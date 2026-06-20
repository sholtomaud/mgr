import Foundation

public enum Restore {
    public static func run(args: [String]) {
        if args.contains("--list") {
            listMappings()
        } else if let name = flagValue(args, flag: "--source") {
            restoreFrom(name: name)
        } else {
            fputs("Usage: mgr restore [--list] [--source <name>]\n", stderr)
            fputs("  --list           Show configured backup mappings and drive status\n", stderr)
            fputs("  --source <name>  Restore a named mapping from destination → source\n", stderr)
            exit(1)
        }
    }

    // MARK: — List

    private static func listMappings() {
        let mappings = Backup.readConfig()
        guard !mappings.isEmpty else {
            print("restore: no mappings configured in config/backup.plist")
            return
        }
        print("Backup mappings:")
        for m in mappings {
            let mounted = FileManager.default.fileExists(atPath: m.destination)
            let status  = mounted ? "✓ mounted" : "✗ not mounted"
            print("  \(m.name)")
            print("    source:      \(m.source)")
            print("    destination: \(m.destination)  [\(status)]")
            if !m.excludes.isEmpty {
                print("    excludes:    \(m.excludes.joined(separator: ", "))")
            }
        }
    }

    // MARK: — Restore

    private static func restoreFrom(name: String) {
        let mappings = Backup.readConfig()
        guard let mapping = mappings.first(where: { $0.name == name }) else {
            fputs("restore: no mapping named '\(name)'\n", stderr)
            fputs("  Run 'mgr restore --list' to see configured mappings.\n", stderr)
            exit(1)
        }

        let src = (mapping.source as NSString).expandingTildeInPath
        let dst = mapping.destination

        guard FileManager.default.fileExists(atPath: dst) else {
            fputs("restore: destination not found: \(dst)\n", stderr)
            fputs("  Is the external drive mounted?\n", stderr)
            exit(1)
        }

        print("Restore '\(name)':")
        print("  from: \(dst)/")
        print("  to:   \(src)/")
        print("")
        print("WARNING: This will overwrite \(src) with the contents of the backup.")
        print("Files on your Mac that don't exist in the backup will be DELETED (rsync --delete).")
        print("")
        print("Type 'yes' to continue, or anything else to abort: ", terminator: "")

        guard let input = readLine(), input.lowercased() == "yes" else {
            print("Aborted.")
            return
        }

        try? FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)

        let result = Shell.run("/usr/bin/rsync", args: [
            "-a", "--delete", "--stats",
            dst + "/", src + "/"
        ])

        if result.succeeded {
            let summary = result.stdout.components(separatedBy: "\n")
                .filter { $0.hasPrefix("Number of") || $0.hasPrefix("Total") }
                .joined(separator: "\n")
            if !summary.isEmpty { print(summary) }
            print("restore: done")
            Logger.log(to: "backup.jsonl", message: "restore ok",
                       extra: ["mapping": name, "from": dst, "to": src])
        } else {
            Logger.error("restore: rsync failed: \(result.stderr)")
            Logger.log(to: "backup.jsonl", level: "error", message: "restore failed",
                       extra: ["mapping": name])
            exit(1)
        }
    }

    // MARK: — Helpers

    private static func flagValue(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: idx)
        return args.indices.contains(next) ? args[next] : nil
    }
}
