import Foundation

public enum Backup {
    public static func run(args: [String]) {
        let dryRun = args.contains("--dry-run")
        let destOverride = flagValue(args, flag: "--destination")
        let nameFilter = args.first(where: { !$0.hasPrefix("-") })

        let mappings = readConfig()

        guard !mappings.isEmpty else {
            print("backup: no mappings configured in config/backup.plist — nothing to do")
            print("  Add source/destination pairs to config/backup.plist to get started.")
            return
        }

        let targets = nameFilter != nil
            ? mappings.filter { $0.name == nameFilter }
            : mappings

        if targets.isEmpty {
            Logger.error("backup: no mapping named '\(nameFilter!)' — run 'mgr backup' to see all")
            exit(1)
        }

        let startDate = Date()
        print("backup: starting\(dryRun ? " (dry run)" : "")")

        var anyFailure = false

        for mapping in targets {
            let src = (mapping.source as NSString).expandingTildeInPath
            let dst = destOverride ?? mapping.destination

            // Warn clearly if the destination drive isn't mounted
            guard FileManager.default.fileExists(atPath: dst) ||
                  FileManager.default.fileExists(atPath: (dst as NSString).deletingLastPathComponent) else {
                Logger.error("backup: destination not reachable: \(dst)")
                Logger.error("  Is the external drive mounted?")
                anyFailure = true
                continue
            }

            // Ensure destination directory exists
            if !dryRun {
                try? FileManager.default.createDirectory(
                    atPath: dst, withIntermediateDirectories: true)
            }

            var rsyncArgs = ["-a", "--delete", "--stats"]
            if dryRun { rsyncArgs.append("--dry-run") }
            for ex in mapping.excludes {
                rsyncArgs += ["--exclude", ex]
            }
            rsyncArgs += [src + "/", dst + "/"]

            print("  [\(mapping.name)] \(mapping.source) → \(dst)")
            let result = Shell.run("/usr/bin/rsync", args: rsyncArgs)

            if result.succeeded {
                // Print the summary lines rsync produces (transferred, size, etc.)
                let summary = result.stdout.components(separatedBy: "\n")
                    .filter { $0.hasPrefix("Number of") || $0.hasPrefix("Total") || $0.hasPrefix("Sent") }
                    .joined(separator: "\n")
                if !summary.isEmpty { print(summary) }
                print("  ✓ \(mapping.name)")
            } else {
                Logger.error("backup: [\(mapping.name)] rsync failed: \(result.stderr)")
                anyFailure = true
            }
        }

        let duration = String(format: "%.1f", Date().timeIntervalSince(startDate))
        let status = anyFailure ? "partial" : "ok"

        if !dryRun {
            Logger.log(
                to: "backup.jsonl",
                level: anyFailure ? "error" : "info",
                message: "backup \(status)",
                extra: [
                    "mappings": String(targets.count),
                    "duration": duration + "s",
                    "status":   status
                ]
            )
            Notify.send(
                title: anyFailure ? "Backup partially failed" : "Backup complete",
                body:  "\(targets.count) mapping(s) in \(duration)s"
            )
        }

        print("backup: \(status) (\(duration)s)")
    }

    // MARK: — Config

    public struct Mapping {
        public let name:        String
        public let source:      String
        public let destination: String
        public let excludes:    [String]
    }

    public static func readConfig() -> [Mapping] {
        let paths = [
            "./config/backup.plist",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mgr/backup.plist").path
        ]
        for path in paths {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let obj  = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let arr  = obj as? [[String: Any]] else { continue }
            return arr.compactMap { entry -> Mapping? in
                guard let name = entry["name"]        as? String,
                      let src  = entry["source"]      as? String,
                      let dst  = entry["destination"] as? String else { return nil }
                let excludes = entry["excludes"] as? [String] ?? []
                return Mapping(name: name, source: src, destination: dst, excludes: excludes)
            }
        }
        return []
    }

    // MARK: — Helpers

    private static func flagValue(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: idx)
        return args.indices.contains(next) ? args[next] : nil
    }
}
