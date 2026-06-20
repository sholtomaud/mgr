import Foundation

public enum Bootstrap {
    public static func run(args: [String]) {
        let sub = args.first ?? ""
        switch sub {
        case "system":    runSystem()
        case "apps":      runApps()
        case "packages":  runPackages()
        case "dotfiles":  runDotfiles()
        case "agents":    runAgents()
        case "dev":       runDev()
        case "":
            runSystem()
            runApps()
            runPackages()
            runDotfiles()
            runAgents()
            runDev()
        default:
            fputs("mgr bootstrap: unknown subcommand '\(sub)'\n", stderr)
            fputs("Run 'mgr help bootstrap' for usage.\n", stderr)
            exit(1)
        }
    }

    private static func runSystem() {
        Logger.info("bootstrap/system: not yet implemented")
    }

    private static func runApps() {
        Logger.info("bootstrap/apps: not yet implemented")
    }

    private static func runPackages() {
        Logger.info("bootstrap/packages: not yet implemented")
    }

    private static func runDotfiles() {
        Logger.info("bootstrap/dotfiles: not yet implemented")
    }

    // Installs com.mgr.monitor and com.mgr.backup launchd agents.
    // SMAppService requires an app bundle; for a developer-installed CLI we use launchctl
    // directly, which is the correct path for /usr/local/bin installs.
    static func runAgents() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let launchAgentsDir = "\(home)/Library/LaunchAgents"

        // Ensure ~/Library/LaunchAgents exists
        try? fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)

        installAgent(name: "com.mgr.monitor", dest: "\(launchAgentsDir)/com.mgr.monitor.plist")
        installAgent(name: "com.mgr.backup",  dest: "\(launchAgentsDir)/com.mgr.backup.plist")
    }

    private static func installAgent(name: String, dest: String) {
        // Check if already loaded
        let listResult = Shell.run("/bin/launchctl", args: ["list", name])
        if listResult.succeeded {
            print("bootstrap/agents: \(name) already loaded — skipping")
            return
        }

        // Find the plist template: look next to the binary, then next to CWD/launchd/
        guard let templatePath = findTemplate(named: "\(name).plist") else {
            Logger.error("bootstrap/agents: template for \(name).plist not found")
            return
        }

        // Read template, replace binary path placeholder with actual binary path
        let binaryPath = CommandLine.arguments[0]
        guard var content = try? String(contentsOfFile: templatePath, encoding: .utf8) else {
            Logger.error("bootstrap/agents: cannot read template \(templatePath)")
            return
        }
        content = content.replacingOccurrences(of: "/usr/local/bin/mgr", with: binaryPath)

        do {
            try content.write(toFile: dest, atomically: true, encoding: .utf8)
        } catch {
            Logger.error("bootstrap/agents: failed to write \(dest): \(error.localizedDescription)")
            return
        }

        let loadResult = Shell.run("/bin/launchctl", args: ["load", dest])
        if loadResult.succeeded {
            print("bootstrap/agents: \(name) installed and loaded")
        } else {
            Logger.error("bootstrap/agents: launchctl load failed for \(name): \(loadResult.stderr)")
        }
    }

    private static func findTemplate(named filename: String) -> String? {
        // 1. Next to the binary (installed: /usr/local/bin/../share/mgr/launchd/)
        let binaryDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
        let shareCandidate = "\(binaryDir)/../share/mgr/launchd/\(filename)"
        if FileManager.default.fileExists(atPath: shareCandidate) { return shareCandidate }

        // 2. Relative to CWD (dev: ./launchd/)
        let cwdCandidate = "./launchd/\(filename)"
        if FileManager.default.fileExists(atPath: cwdCandidate) { return cwdCandidate }

        return nil
    }

    private static func runDev() {
        Logger.info("bootstrap/dev: not yet implemented")
    }
}
