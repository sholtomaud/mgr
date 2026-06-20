import Foundation

public enum Doctor {

    public enum FindingStatus: String, Codable {
        case approved = "approved"
        case unknown = "unknown"
        case invalidSignature = "invalid-signature"
    }

    public struct Finding: Codable {
        public let category: String
        public let name: String
        public let path: String
        public let teamID: String?
        public let status: FindingStatus

        public init(category: String, name: String, path: String,
                    teamID: String?, status: FindingStatus) {
            self.category = category; self.name = name; self.path = path
            self.teamID = teamID; self.status = status
        }
    }

    public static func run(args: [String]) {
        let fix  = args.contains("--fix")
        let json = args.contains("--json")

        let approved = ApprovedList.load()
        var findings: [Finding] = []

        let home = FileManager.default.homeDirectoryForCurrentUser.path

        findings += scanLaunchdDir("\(home)/Library/LaunchAgents",
                                   category: "LaunchAgents/user", approved: approved)
        findings += scanLaunchdDir("/Library/LaunchAgents",
                                   category: "LaunchAgents/system", approved: approved)
        findings += scanLaunchdDir("/Library/LaunchDaemons",
                                   category: "LaunchDaemons", approved: approved)
        findings += scanMCPConfigs(home: home, approved: approved)
        findings += scanApplications(approved: approved)

        if fix {
            quarantineUnknown(findings: findings)
        }

        if json {
            printJSON(findings)
        } else {
            printReport(findings)
        }

        let hasIssues = findings.contains { $0.status != .approved }
        if hasIssues { exit(1) }
    }

    // MARK: — Scanners

    public static func scanLaunchdDir(_ dirPath: String, category: String,
                                approved: [ApprovedEntry]) -> [Finding] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }

        return items
            .filter { $0.hasSuffix(".plist") }
            .compactMap { filename -> Finding? in
                let plistPath = "\(dirPath)/\(filename)"
                let binaryPath = extractBinaryPath(fromPlist: plistPath)
                let target = binaryPath ?? plistPath
                let name = (filename as NSString).deletingPathExtension
                let info = Codesign.verify(path: target)

                guard info.isValid else {
                    // Skip Apple system plists that reference protected binaries we can't read
                    if target.hasPrefix("/System/") || target.hasPrefix("/usr/libexec/") {
                        return nil
                    }
                    return Finding(category: category, name: name,
                                   path: plistPath, teamID: nil,
                                   status: .invalidSignature)
                }

                let status: FindingStatus = ApprovedList.isApproved(path: target,
                                                                     teamID: info.teamID)
                    ? .approved : .unknown
                return Finding(category: category, name: name,
                               path: plistPath, teamID: info.teamID, status: status)
            }
    }

    static func scanMCPConfigs(home: String, approved: [ApprovedEntry]) -> [Finding] {
        let candidates: [(path: String, parser: (String) -> [Finding])] = [
            ("\(home)/Library/Application Support/Claude/claude_desktop_config.json",
             parseClaudeMCPConfig),
            ("\(home)/.cursor/mcp.json",                parseGenericMCPConfig),
            ("\(home)/.config/claude/claude_desktop_config.json", parseClaudeMCPConfig),
            ("\(home)/.config/mcp/servers.json",         parseGenericMCPConfig),
        ]

        return candidates.flatMap { (path, parser) -> [Finding] in
            guard FileManager.default.fileExists(atPath: path) else { return [] }
            return parser(path)
        }
    }

    static func scanApplications(approved: [ApprovedEntry]) -> [Finding] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: "/Applications") else { return [] }

        return items
            .filter { $0.hasSuffix(".app") }
            .compactMap { appName -> Finding? in
                let appPath = "/Applications/\(appName)"
                let info = Codesign.verify(path: appPath)
                let name = (appName as NSString).deletingPathExtension

                guard info.isValid else {
                    return Finding(category: "Applications", name: name,
                                   path: appPath, teamID: nil,
                                   status: .invalidSignature)
                }

                let status: FindingStatus = ApprovedList.isApproved(path: appPath,
                                                                     teamID: info.teamID)
                    ? .approved : .unknown
                return Finding(category: "Applications", name: name,
                               path: appPath, teamID: info.teamID, status: status)
            }
    }

    // MARK: — MCP config parsers

    private static func parseClaudeMCPConfig(_ path: String) -> [Finding] {
        parseMCPServersJSON(path: path, serversKey: "mcpServers", commandKey: "command")
    }

    private static func parseGenericMCPConfig(_ path: String) -> [Finding] {
        parseMCPServersJSON(path: path, serversKey: "mcpServers", commandKey: "command")
    }

    private static func parseMCPServersJSON(path: String, serversKey: String,
                                             commandKey: String) -> [Finding] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json[serversKey] as? [String: Any] else { return [] }

        return servers.compactMap { (name, value) -> Finding? in
            guard let server = value as? [String: Any],
                  let command = server[commandKey] as? String else { return nil }

            // Resolve the command to an absolute path
            let resolvedPath = resolveCommandPath(command)
            let info = Codesign.verify(path: resolvedPath)
            let status: FindingStatus = ApprovedList.isApproved(path: resolvedPath,
                                                                  teamID: info.teamID)
                ? .approved : .unknown

            return Finding(category: "MCP/\((path as NSString).lastPathComponent)",
                           name: name, path: resolvedPath,
                           teamID: info.teamID, status: status)
        }
    }

    // MARK: — Fix / quarantine

    private static func quarantineUnknown(findings: [Finding]) {
        let fm = FileManager.default
        let quarantineDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/mgr/quarantine").path
        try? fm.createDirectory(atPath: quarantineDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        for finding in findings where finding.status == .unknown {
            // Only quarantine launchd plists — apps and MCP configs need explicit user action
            guard finding.category.hasPrefix("Launch") else {
                Logger.info("doctor: \(finding.name) is unknown — manual review required (not auto-quarantined)")
                continue
            }

            let filename = (finding.path as NSString).lastPathComponent
            let dest = "\(quarantineDir)/\(timestamp)_\(filename)"

            // Unload before moving
            Shell.run("/bin/launchctl", args: ["unload", finding.path])

            do {
                try fm.moveItem(atPath: finding.path, toPath: dest)
                Logger.info("doctor: quarantined \(finding.name) → \(dest)")
            } catch {
                Logger.error("doctor: failed to quarantine \(finding.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: — Output

    private static func printReport(_ findings: [Finding]) {
        let byCategory = Dictionary(grouping: findings, by: { $0.category })

        for category in byCategory.keys.sorted() {
            print("\n\(category)")
            for f in byCategory[category]! {
                let icon: String
                switch f.status {
                case .approved:          icon = "✓"
                case .unknown:           icon = "?"
                case .invalidSignature:  icon = "✗"
                }
                let team = f.teamID.map { " (team: \($0))" } ?? ""
                print("  \(icon) \(f.name)\(team)")
                if f.status != .approved {
                    print("    path: \(f.path)")
                }
            }
        }

        let approved = findings.filter { $0.status == .approved }.count
        let unknown  = findings.filter { $0.status == .unknown }.count
        let invalid  = findings.filter { $0.status == .invalidSignature }.count
        print("\nSummary: \(approved) approved, \(unknown) unknown, \(invalid) invalid-signature")

        if unknown > 0 || invalid > 0 {
            print("Run 'mgr approve <path>' to whitelist an item, or 'mgr doctor --fix' to quarantine unknowns.")
        }
    }

    private static func printJSON(_ findings: [Finding]) {
        guard let data = try? JSONEncoder().encode(findings),
              let str = String(data: data, encoding: .utf8) else { return }
        print(str)
    }

    // MARK: — Helpers

    private static func extractBinaryPath(fromPlist plistPath: String) -> String? {
        guard let dict = Plist.read(at: plistPath) else { return nil }
        if let program = dict["Program"] as? String { return program }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            return first
        }
        return nil
    }

    private static func resolveCommandPath(_ command: String) -> String {
        if command.hasPrefix("/") { return command }
        let result = Shell.run("/usr/bin/which", args: [command])
        let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? command : resolved
    }
}
