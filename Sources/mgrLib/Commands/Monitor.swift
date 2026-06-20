import Foundation

public enum Monitor {

    // Tracks unknowns already notified this session to suppress repeat alerts.
    // Keyed by plist path.
    private static var notifiedPaths = Set<String>()

    // File descriptor handles for DispatchSource watchers — kept alive for daemon lifetime.
    private static var watcherFDs: [Int32] = []
    private static var watcherSources: [DispatchSourceFileSystemObject] = []

    public static func run(args: [String]) {
        if args.contains("--start") {
            start()
        } else if args.contains("--stop") {
            stop()
        } else if args.contains("--status") {
            status()
        } else {
            fputs("Usage: mgr monitor [--start|--stop|--status]\n", stderr)
            exit(1)
        }
    }

    // MARK: — Start (long-running daemon loop)

    private static func start() {
        Logger.info("monitor: starting")

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let watchDirs = [
            "\(home)/Library/LaunchAgents",
            "/Library/LaunchAgents",
        ]

        // File system watchers — fire immediately on directory write (new plist dropped)
        for dir in watchDirs {
            addWatcher(path: dir)
        }

        // Also watch MCP config files for changes
        let mcpPaths = [
            "\(home)/Library/Application Support/Claude/claude_desktop_config.json",
            "\(home)/.cursor/mcp.json",
            "\(home)/.config/claude/claude_desktop_config.json",
        ]
        for path in mcpPaths where FileManager.default.fileExists(atPath: path) {
            addWatcher(path: path)
        }

        // Periodic polling timer — catches changes that DispatchSource may miss
        let settings = loadSettings()
        let interval = settings["monitorInterval"] as? Int ?? 60
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + .seconds(interval), repeating: .seconds(interval))
        timer.setEventHandler { poll() }
        timer.resume()

        // Initial poll on startup
        poll()

        Logger.info("monitor: running (poll interval: \(interval)s)")
        RunLoop.main.run()
    }

    // MARK: — Stop

    private static func stop() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plistPath = "\(home)/Library/LaunchAgents/com.mgr.monitor.plist"

        // Try bootstrap-installed plist first
        if FileManager.default.fileExists(atPath: plistPath) {
            let result = Shell.run("/bin/launchctl", args: ["unload", plistPath])
            if result.succeeded {
                print("Monitor stopped.")
                return
            }
            Logger.error("monitor: launchctl unload failed: \(result.stderr)")
        }

        // Fall back to label-based unload (works if registered via SMAppService or launchctl)
        let result = Shell.run("/bin/launchctl", args: ["remove", "com.mgr.monitor"])
        if result.succeeded {
            print("Monitor stopped.")
        } else {
            fputs("monitor: not running or failed to stop\n", stderr)
            exit(1)
        }
    }

    // MARK: — Status

    private static func status() {
        let result = Shell.run("/bin/launchctl", args: ["list", "com.mgr.monitor"])
        if result.succeeded && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Monitor is running.")
            print(result.stdout)
        } else {
            print("Monitor is not running.")
        }
    }

    // MARK: — Polling

    public static func poll() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let approved = ApprovedList.load()

        let scanDirs: [(path: String, category: String)] = [
            ("\(home)/Library/LaunchAgents", "LaunchAgents/user"),
            ("/Library/LaunchAgents",        "LaunchAgents/system"),
            ("/Library/LaunchDaemons",       "LaunchDaemons"),
        ]

        for (dir, category) in scanDirs {
            let findings = Doctor.scanLaunchdDir(dir, category: category, approved: approved)
            for finding in findings where finding.status != .approved {
                guard !notifiedPaths.contains(finding.path) else { continue }
                notifiedPaths.insert(finding.path)
                handle(finding: finding)
            }
        }
    }

    // MARK: — Finding handler

    private static func handle(finding: Doctor.Finding) {
        let title = "mgr monitor: unrecognized process"
        let body  = "\(finding.name) [\(finding.status.rawValue)]"

        Logger.log(to: "monitor.jsonl", level: "warn", message: body,
                   extra: ["path": finding.path,
                           "category": finding.category,
                           "status": finding.status.rawValue])

        Notify.send(title: title, body: body)

        let settings = loadSettings()
        let autoQuarantine = settings["autoQuarantine"] as? Bool ?? false

        if autoQuarantine && finding.category.hasPrefix("Launch") {
            quarantine(finding: finding)
        } else if autoQuarantine {
            Logger.info("monitor: auto-quarantine skipped for \(finding.category) — manual review required")
        }
    }

    // MARK: — Quarantine

    private static func quarantine(finding: Doctor.Finding) {
        let fm = FileManager.default
        let quarantineDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/mgr/quarantine").path
        try? fm.createDirectory(atPath: quarantineDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = (finding.path as NSString).lastPathComponent
        let dest = "\(quarantineDir)/\(timestamp)_\(filename)"

        Shell.run("/bin/launchctl", args: ["unload", finding.path])

        do {
            try fm.moveItem(atPath: finding.path, toPath: dest)
            Logger.log(to: "monitor.jsonl", level: "info",
                       message: "quarantined \(finding.name)",
                       extra: ["from": finding.path, "to": dest])
            Notify.send(title: "mgr monitor: quarantined",
                        body: "\(finding.name) moved to quarantine")
        } catch {
            Logger.error("monitor: quarantine failed for \(finding.path): \(error.localizedDescription)")
        }
    }

    // MARK: — DispatchSource file watchers

    private static func addWatcher(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Logger.debug("monitor: cannot watch \(path) (fd open failed)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .link],
            queue: DispatchQueue.global()
        )
        source.setEventHandler { poll() }
        source.setCancelHandler { close(fd) }
        source.resume()

        watcherFDs.append(fd)
        watcherSources.append(source)
        Logger.debug("monitor: watching \(path)")
    }

    // MARK: — Helpers

    private static func loadSettings() -> [String: Any] {
        guard let dict = Plist.read(at: ApprovedList.plistPath),
              let settings = dict["settings"] as? [String: Any] else {
            return ["monitorInterval": 60, "autoQuarantine": false]
        }
        return settings
    }
}
