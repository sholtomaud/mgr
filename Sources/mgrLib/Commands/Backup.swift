import Foundation

public enum Backup {
    public static func run(args: [String]) {
        let dryRun      = args.contains("--dry-run")
        let volumeOverride = flagValue(args, flag: "--volume")
        let nameFilter  = args.first(where: { !$0.hasPrefix("-") })

        let config = readConfig()

        guard !config.mappings.isEmpty else {
            print("backup: no mappings configured in config/backup.plist — nothing to do")
            print("  Uncomment and edit the example entries to get started.")
            return
        }

        // Find which backup drive is mounted
        let volumePath: String
        if let override = volumeOverride {
            volumePath = override
        } else if let found = findVolume(pattern: config.volumePattern) {
            volumePath = found
        } else {
            print("backup: no backup drive mounted (looking for /Volumes/\(config.volumePattern)*)")
            print("  Plug in one of your backup drives and try again.")
            return
        }
        print("backup: using drive \(volumePath)\(dryRun ? " (dry run)" : "")")

        let targets = nameFilter != nil
            ? config.mappings.filter { $0.name == nameFilter }
            : config.mappings

        if targets.isEmpty {
            Logger.error("backup: no mapping named '\(nameFilter!)' — run 'mgr restore --list' to see all")
            exit(1)
        }

        let startDate = Date()
        var anyFailure = false

        for mapping in targets {
            let src = (mapping.source as NSString).expandingTildeInPath
            let dst = volumePath + "/" + mapping.destination

            guard FileManager.default.fileExists(atPath: src) else {
                print("  [skip] \(mapping.name): \(src) does not exist")
                continue
            }

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

            if result.succeeded || result.exitCode == 23 {
                // exit code 23 = partial transfer due to unreadable files (e.g. Apple-managed
                // dirs like Music/Music, Movies/TV that need Full Disk Access)
                let summary = result.stdout.components(separatedBy: "\n")
                    .filter { $0.hasPrefix("Number of") || $0.hasPrefix("Total") || $0.hasPrefix("Sent") }
                    .joined(separator: "\n")
                if !summary.isEmpty { print(summary) }
                if result.exitCode == 23 {
                    let skipped = result.stderr.components(separatedBy: "\n")
                        .filter { $0.contains("unreadable") || $0.contains("Operation not permitted") }
                        .joined(separator: "\n")
                    if !skipped.isEmpty {
                        print("  [warn] some files skipped (Full Disk Access required):\n\(skipped)")
                    }
                }
                print("  ✓ \(mapping.name)")
            } else {
                Logger.error("backup: [\(mapping.name)] rsync failed: \(result.stderr)")
                anyFailure = true
            }
        }

        let duration = String(format: "%.1f", Date().timeIntervalSince(startDate))
        let status   = anyFailure ? "partial" : "ok"

        if !dryRun {
            Logger.log(
                to: "backup.jsonl",
                level: anyFailure ? "error" : "info",
                message: "backup \(status)",
                extra: [
                    "volume":   volumePath,
                    "mappings": String(targets.count),
                    "duration": duration + "s",
                    "status":   status
                ]
            )
            Notify.send(
                title: anyFailure ? "Backup partially failed" : "Backup complete",
                body:  "\(targets.count) mapping(s) → \(volumePath) in \(duration)s"
            )
        }

        print("backup: \(status) (\(duration)s)")
    }

    // MARK: — Volume discovery

    public static func findVolume(pattern: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return nil }
        return entries
            .filter { $0.hasPrefix(pattern) }
            .sorted()                          // deterministic: BACKUP1 before BACKUP2
            .first
            .map { "/Volumes/" + $0 }
    }

    // MARK: — Config

    public struct Config {
        public let volumePattern: String
        public let mappings:      [Mapping]
    }

    public struct Mapping {
        public let name:        String
        public let source:      String
        public let destination: String   // relative to volume root
        public let excludes:    [String]
    }

    public static func readConfig() -> Config {
        let paths = [
            "./config/backup.plist",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mgr/backup.plist").path
        ]
        for path in paths {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let obj  = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = obj as? [String: Any] else { continue }

            let pattern        = dict["volumePattern"]  as? String   ?? "BACKUP"
            let globalExcludes = dict["globalExcludes"] as? [String] ?? []
            let rawArr         = dict["mappings"]       as? [[String: Any]] ?? []
            let mappings = rawArr.compactMap { entry -> Mapping? in
                guard let name = entry["name"]        as? String,
                      let src  = entry["source"]      as? String,
                      let dst  = entry["destination"] as? String else { return nil }
                let perMapping = entry["excludes"] as? [String] ?? []
                return Mapping(name: name, source: src, destination: dst,
                               excludes: globalExcludes + perMapping)
            }
            return Config(volumePattern: pattern, mappings: mappings)
        }
        return Config(volumePattern: "BACKUP", mappings: [])
    }

    // MARK: — Helpers

    private static func flagValue(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: idx)
        return args.indices.contains(next) ? args[next] : nil
    }
}
