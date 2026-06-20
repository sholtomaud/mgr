import Foundation

public enum Bootstrap {
    public static func run(args: [String]) {
        let sub = args.first ?? ""
        switch sub {
        case "config":    runConfig()
        case "system":    runSystem()
        case "apps":      runApps()
        case "packages":  runPackages()
        case "dotfiles":  runDotfiles()
        case "agents":    runAgents()
        case "dev":       runDev()
        case "":
            runConfig()
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

    // MARK: — config

    static func runConfig() {
        let fm = FileManager.default
        let configDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mgr")

        let templates = ["approved.plist", "backup.plist", "system.plist",
                         "dotfiles.plist", "dev.plist", "containers.plist"]

        // If running from the repo root (dev), copy missing templates now
        let repoConfig = "./config"
        let runningFromRepo = fm.fileExists(atPath: repoConfig + "/backup.plist")

        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        var missing: [String] = []
        for name in templates {
            let dest = configDir.appendingPathComponent(name).path
            if fm.fileExists(atPath: dest) {
                print("  ✓ ~/.config/mgr/\(name)")
            } else if runningFromRepo,
                      let src = Optional(repoConfig + "/" + name),
                      fm.fileExists(atPath: src) {
                do {
                    try fm.copyItem(atPath: src, toPath: dest)
                    print("  ✓ ~/.config/mgr/\(name) (copied from repo)")
                } catch {
                    Logger.error("bootstrap/config: \(name): \(error.localizedDescription)")
                }
            } else {
                print("  ✗ ~/.config/mgr/\(name) (missing)")
                missing.append(name)
            }
        }

        if !missing.isEmpty {
            print("")
            print("Some config files are missing. They ship with the release as config.zip.")
            print("Re-run the installer or download manually:")
            print("  curl -fsSL https://github.com/sholtomaud/mgr/releases/latest/download/config.zip -o /tmp/config.zip")
            print("  unzip -n /tmp/config.zip -d ~/.config/mgr/")
        } else {
            print("bootstrap/config: all present — edit ~/.config/mgr/ to customise")
        }
    }

    // MARK: — system

    static func runSystem() {
        let config = configDict("system.plist")
        let defaults = config["defaults"] as? [String: Any] ?? [:]
        let hostname = config["hostname"] as? String ?? ""
        let timezone = config["timezone"] as? String ?? ""

        // Build a flat list of pending changes so the user can review before applying
        var pending: [(domain: String, key: String, value: Any)] = []
        for (domain, rawKeys) in defaults {
            guard let keys = rawKeys as? [String: Any] else { continue }
            for (key, value) in keys {
                pending.append((domain, key, value))
            }
        }

        if pending.isEmpty && hostname.isEmpty && timezone.isEmpty {
            print("bootstrap/system: nothing configured in config/system.plist — skipping")
            return
        }

        // Preview
        print("bootstrap/system: the following defaults will be written:")
        for p in pending.sorted(by: { "\($0.domain) \($0.key)" < "\($1.domain) \($1.key)" }) {
            print("  defaults write \(p.domain) \(p.key) \(p.value)")
        }
        if !hostname.isEmpty { print("  scutil --set HostName \(hostname)  (requires sudo)") }
        if !timezone.isEmpty { print("  systemsetup -settimezone \(timezone)  (requires sudo)") }

        print("")
        print("Apply these settings? [y/N]: ", terminator: "")
        guard let input = readLine(), input.lowercased() == "y" else {
            print("Skipped.")
            return
        }

        var didChangeDock   = false
        var didChangeFinder = false

        for p in pending {
            let args = defaultsWriteArgs(domain: p.domain, key: p.key, value: p.value)
            let result = Shell.run("/usr/bin/defaults", args: args)
            if result.succeeded {
                print("  ✓ \(p.domain) \(p.key)")
                if p.domain == "com.apple.dock"   { didChangeDock   = true }
                if p.domain == "com.apple.finder" { didChangeFinder = true }
            } else {
                Logger.error("bootstrap/system: defaults write \(p.domain) \(p.key): \(result.stderr)")
            }
        }

        // Restart affected apps to apply changes
        if didChangeDock   { Shell.run("/usr/bin/killall", args: ["Dock"])   }
        if didChangeFinder { Shell.run("/usr/bin/killall", args: ["Finder"]) }

        if !hostname.isEmpty {
            let r = Shell.run("/usr/sbin/scutil", args: ["--set", "HostName", hostname])
            if r.succeeded {
                print("  ✓ hostname → \(hostname)")
            } else {
                Logger.error("bootstrap/system: hostname requires sudo — run: sudo scutil --set HostName \(hostname)")
            }
        }

        if !timezone.isEmpty {
            let r = Shell.run("/usr/sbin/systemsetup", args: ["-settimezone", timezone])
            if r.succeeded {
                print("  ✓ timezone → \(timezone)")
            } else {
                Logger.error("bootstrap/system: timezone requires sudo — run: sudo systemsetup -settimezone \(timezone)")
            }
        }

        print("bootstrap/system: done")
    }

    // MARK: — dotfiles

    static func runDotfiles() {
        print("bootstrap/dotfiles: linking dotfiles...")
        guard let entries = configArray("dotfiles.plist") else {
            print("bootstrap/dotfiles: no entries in config/dotfiles.plist — nothing to do")
            return
        }

        // Resolve the repo root (where the config/ dir lives)
        let repoRoot = resolveRepoRoot()
        let fm = FileManager.default

        for entry in entries {
            guard let source = entry["source"] as? String,
                  let target = entry["target"] as? String else { continue }

            let sourcePath = "\(repoRoot)/\(source)"
            let targetPath = (target as NSString).expandingTildeInPath

            guard fm.fileExists(atPath: sourcePath) else {
                Logger.error("bootstrap/dotfiles: source not found: \(sourcePath)")
                continue
            }

            _createSymlink(source: sourcePath, target: targetPath)
        }

        print("bootstrap/dotfiles: done")
    }

    // MARK: — dev

    static func runDev() {
        print("bootstrap/dev: configuring dev environment...")

        // Xcode CLI tools
        let xcodeResult = Shell.run("/usr/bin/xcode-select", args: ["-p"])
        if xcodeResult.succeeded {
            print("  ✓ Xcode CLI tools: \(xcodeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        } else {
            Logger.error("bootstrap/dev: Xcode CLI tools not installed — run: xcode-select --install")
        }

        // Git global config
        let devConfig = configDict("dev.plist")
        if let git = devConfig["git"] as? [String: Any] {
            setGitConfig(git)
        }

        // SSH key
        if let ssh = devConfig["ssh"] as? [String: Any] {
            generateSSHKey(ssh)
        }

        print("bootstrap/dev: done")
    }

    // MARK: — apps

    static func runApps() {
        print("bootstrap/apps: not yet configured")
        print("  Add app entries to config/approved.plist with download URLs to enable this step.")
    }

    // MARK: — packages

    static func runPackages() {
        print("bootstrap/packages: not yet configured")
        print("  Add a Brewfile to the repo and configure a container to run `brew bundle` in.")
    }

    // MARK: — agents (implemented in Phase 3, kept here for the full bootstrap sequence)

    // SMAppService requires an app bundle; for a developer-installed CLI we use launchctl
    // directly — correct for /usr/local/bin installs.
    static func runAgents() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let launchAgentsDir = "\(home)/Library/LaunchAgents"
        try? fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)

        installAgent(name: "com.mgr.monitor", dest: "\(launchAgentsDir)/com.mgr.monitor.plist")

        // Only install the backup agent if at least one source is configured
        let backupConfig = Backup.readConfig()
        if backupConfig.mappings.isEmpty {
            print("bootstrap/agents: com.mgr.backup skipped — no mappings in config/backup.plist")
        } else {
            installAgent(name: "com.mgr.backup", dest: "\(launchAgentsDir)/com.mgr.backup.plist")
        }
    }

    // MARK: — Private helpers

    private static func setGitConfig(_ git: [String: Any]) {
        let fields: [(key: String, configKey: String)] = [
            ("name",       "user.name"),
            ("email",      "user.email"),
            ("signingKey", "user.signingkey"),
        ]
        for (plistKey, gitKey) in fields {
            guard let value = git[plistKey] as? String, !value.isEmpty else { continue }
            let current = Shell.run("/usr/bin/git", args: ["config", "--global", gitKey])
            if current.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == value {
                print("  ✓ git \(gitKey) (already set)")
                continue
            }
            let result = Shell.run("/usr/bin/git", args: ["config", "--global", gitKey, value])
            if result.succeeded {
                print("  ✓ git \(gitKey) → \(value)")
            } else {
                Logger.error("bootstrap/dev: git config \(gitKey): \(result.stderr)")
            }
        }
    }

    private static func generateSSHKey(_ ssh: [String: Any]) {
        let keyPath = ((ssh["keyPath"] as? String) ?? "~/.ssh/id_ed25519")
        let expandedPath = (keyPath as NSString).expandingTildeInPath
        let keyType = (ssh["keyType"] as? String) ?? "ed25519"
        let comment = (ssh["comment"] as? String) ?? ""

        if FileManager.default.fileExists(atPath: expandedPath) {
            print("  ✓ SSH key exists: \(expandedPath)")
            printPublicKey(expandedPath)
            return
        }

        // Ensure ~/.ssh exists with correct permissions
        let sshDir = (expandedPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
        Shell.run("/bin/chmod", args: ["700", sshDir])

        var args = ["-t", keyType, "-f", expandedPath, "-N", ""]
        if !comment.isEmpty { args += ["-C", comment] }

        let result = Shell.run("/usr/bin/ssh-keygen", args: args)
        if result.succeeded {
            print("  ✓ SSH key generated: \(expandedPath)")
            printPublicKey(expandedPath)
        } else {
            Logger.error("bootstrap/dev: ssh-keygen failed: \(result.stderr)")
        }
    }

    private static func printPublicKey(_ privatePath: String) {
        let pubPath = privatePath + ".pub"
        if let pub = try? String(contentsOfFile: pubPath, encoding: .utf8) {
            print("  Public key (add to GitHub/GitLab):")
            print("  \(pub.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private static func installAgent(name: String, dest: String) {
        let listResult = Shell.run("/bin/launchctl", args: ["list", name])
        if listResult.succeeded {
            print("bootstrap/agents: \(name) already loaded — skipping")
            return
        }
        guard let templatePath = findTemplate(named: "\(name).plist") else {
            Logger.error("bootstrap/agents: template for \(name).plist not found")
            return
        }
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
            Logger.error("bootstrap/agents: launchctl load failed: \(loadResult.stderr)")
        }
    }

    private static func _createSymlink(source: String, target: String) {
        let fm = FileManager.default
        let parentDir = (target as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        var isSymlink = false
        if let attrs = try? fm.attributesOfItem(atPath: target) {
            isSymlink = (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
        }

        if isSymlink {
            let existing = (try? fm.destinationOfSymbolicLink(atPath: target)) ?? ""
            if existing == source {
                print("  ✓ \(target) (already linked)")
                return
            }
            try? fm.removeItem(atPath: target)
        } else if fm.fileExists(atPath: target) {
            Logger.error("bootstrap/dotfiles: \(target) exists as a regular file — skipping (back it up manually first)")
            return
        }

        do {
            try fm.createSymbolicLink(atPath: target, withDestinationPath: source)
            print("  ✓ \(target) → \(source)")
        } catch {
            Logger.error("bootstrap/dotfiles: failed to link \(target): \(error.localizedDescription)")
        }
    }

    private static func findTemplate(named filename: String) -> String? {
        let binaryDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
        let shareCandidate = "\(binaryDir)/../share/mgr/launchd/\(filename)"
        if FileManager.default.fileExists(atPath: shareCandidate) { return shareCandidate }
        let cwdCandidate = "./launchd/\(filename)"
        if FileManager.default.fileExists(atPath: cwdCandidate) { return cwdCandidate }
        return nil
    }

    // Returns the repo root by walking up from the binary until config/ is found
    private static func resolveRepoRoot() -> String {
        // Dev: CWD is the repo root
        if FileManager.default.fileExists(atPath: "./config/dotfiles.plist") {
            return FileManager.default.currentDirectoryPath
        }
        // Installed: look next to binary
        let binaryDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
        let candidate = "\(binaryDir)/../share/mgr"
        if FileManager.default.fileExists(atPath: "\(candidate)/config/dotfiles.plist") {
            return candidate
        }
        return FileManager.default.currentDirectoryPath
    }

    // Reads a config plist from config/ dir (dev CWD first, then ~/.config/mgr/)
    private static func configDict(_ filename: String) -> [String: Any] {
        let paths = [
            "./config/\(filename)",
            (FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mgr/\(filename)").path)
        ]
        for path in paths {
            if let dict = Plist.read(at: path) { return dict }
        }
        return [:]
    }

    private static func configArray(_ filename: String) -> [[String: Any]]? {
        let paths = [
            "./config/\(filename)",
            (FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mgr/\(filename)").path)
        ]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url),
                  let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let array = obj as? [[String: Any]] else { continue }
            return array
        }
        return nil
    }

    // Test hooks (public so BootstrapTests can call them without going through the full command)
    public static func testDefaultsWriteArgs(domain: String, key: String, value: Any) -> [String] {
        defaultsWriteArgs(domain: domain, key: key, value: value)
    }
    public static func testCreateSymlink(source: String, target: String) {
        _createSymlink(source: source, target: target)
    }
    public static func testGenerateSSHKey(keyType: String, keyPath: String, comment: String) {
        generateSSHKey(["keyType": keyType, "keyPath": keyPath, "comment": comment])
    }

    // Translates a plist value to `defaults write` arguments
    private static func defaultsWriteArgs(domain: String, key: String, value: Any) -> [String] {
        switch value {
        case let b as Bool:
            return ["write", domain, key, "-bool", b ? "true" : "false"]
        case let i as Int:
            return ["write", domain, key, "-int", String(i)]
        case let f as Float:
            return ["write", domain, key, "-float", String(f)]
        case let d as Double:
            return ["write", domain, key, "-float", String(d)]
        case let s as String:
            return ["write", domain, key, "-string", s]
        default:
            return ["write", domain, key, String(describing: value)]
        }
    }
}
