import Foundation

public enum Restore {
    public static func run(args: [String]) {
        if args.contains("--list") {
            listMappings()
        } else if let name = flagValue(args, flag: "--source") {
            restoreFrom(name: name)
        } else {
            fputs("Usage: mgr restore [--list] [--source <name>]\n", stderr)
            fputs("  --list           Show configured mappings and which drive is mounted\n", stderr)
            fputs("  --source <name>  Restore a named mapping: backup drive → source\n", stderr)
            exit(1)
        }
    }

    // MARK: — List

    private static func listMappings() {
        let config = Backup.readConfig()

        let volumePath = Backup.findVolume(pattern: config.volumePattern)
        if let v = volumePath {
            print("Backup drive: \(v)  ✓ mounted")
        } else {
            print("Backup drive: /Volumes/\(config.volumePattern)*  ✗ not mounted")
        }
        print("")

        guard !config.mappings.isEmpty else {
            print("No mappings configured in config/backup.plist")
            return
        }

        print("Mappings:")
        for m in config.mappings {
            let resolvedDst = volumePath.map { $0 + "/" + m.destination } ?? "(drive not mounted)"
            print("  \(m.name)")
            print("    source:      \(m.source)")
            print("    destination: \(resolvedDst)")
            if !m.excludes.isEmpty {
                print("    excludes:    \(m.excludes.joined(separator: ", "))")
            }
        }
    }

    // MARK: — Restore

    private static func restoreFrom(name: String) {
        let config = Backup.readConfig()

        guard let mapping = config.mappings.first(where: { $0.name == name }) else {
            fputs("restore: no mapping named '\(name)'\n", stderr)
            fputs("  Run 'mgr restore --list' to see configured mappings.\n", stderr)
            exit(1)
        }

        guard let volumePath = Backup.findVolume(pattern: config.volumePattern) else {
            fputs("restore: no backup drive mounted (looking for /Volumes/\(config.volumePattern)*)\n", stderr)
            fputs("  Plug in one of your backup drives and try again.\n", stderr)
            exit(1)
        }

        let src = (mapping.source as NSString).expandingTildeInPath
        let dst = volumePath + "/" + mapping.destination

        guard FileManager.default.fileExists(atPath: dst) else {
            fputs("restore: backup directory not found: \(dst)\n", stderr)
            fputs("  Has '\(name)' been backed up yet? Run: mgr backup \(name)\n", stderr)
            exit(1)
        }

        print("Restore '\(name)':")
        print("  from: \(dst)/")
        print("  to:   \(src)/")
        print("")
        print("WARNING: This will overwrite \(src) with the contents of the backup.")
        print("         Files on your Mac not in the backup will be DELETED (rsync --delete).")
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
                       extra: ["mapping": name, "volume": volumePath])
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
