import Foundation

public enum Backup {
    public static func run(args: [String]) {
        let dryRun = args.contains("--dry-run")
        let destOverride = flagValue(args, flag: "--destination")

        let config = readConfig()
        let snapshotBase = destOverride ?? config.snapshotBase

        guard !config.sources.isEmpty else {
            print("backup: no sources configured in config/backup.plist — nothing to do")
            return
        }

        let timestamp = isoTimestamp()
        let snapshotDir = (snapshotBase as NSString).expandingTildeInPath + "/" + timestamp
        let fm = FileManager.default

        if !dryRun {
            do {
                try fm.createDirectory(atPath: snapshotDir, withIntermediateDirectories: true)
            } catch {
                Logger.error("backup: failed to create snapshot dir \(snapshotDir): \(error.localizedDescription)")
                return
            }
        }

        let startDate = Date()
        print("backup: starting snapshot \(timestamp)\(dryRun ? " (dry run)" : "")")

        var anyFailure = false
        var sourceResults: [[String: String]] = []

        for source in config.sources {
            let expanded = (source.path as NSString).expandingTildeInPath
            let basename = (expanded as NSString).lastPathComponent
            let dest = snapshotDir + "/" + basename

            if !dryRun {
                try? fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
            }

            var rsyncArgs = ["-a", "--stats"]
            if dryRun { rsyncArgs.append("--dry-run") }
            for ex in config.globalExcludes + source.excludes {
                rsyncArgs += ["--exclude", ex]
            }
            // Trailing slash on source copies contents, not the dir itself
            rsyncArgs += [expanded + "/", dest + "/"]

            print("  \(expanded) → \(dest)")
            let result = Shell.run("/usr/bin/rsync", args: rsyncArgs)

            if result.succeeded {
                if !result.stdout.isEmpty { print(result.stdout) }
                sourceResults.append(["source": source.path, "dest": dest, "status": "ok"])
            } else {
                Logger.error("backup: rsync failed for \(source.path): \(result.stderr)")
                sourceResults.append(["source": source.path, "dest": dest, "status": "failed"])
                anyFailure = true
            }
        }

        let duration = String(format: "%.1f", Date().timeIntervalSince(startDate))
        let status = anyFailure ? "partial" : "ok"

        if !dryRun {
            writeManifest(snapshotDir: snapshotDir, sources: config.sources, timestamp: timestamp)
            Logger.log(
                to: "backup.jsonl",
                level: anyFailure ? "error" : "info",
                message: "backup \(status)",
                extra: [
                    "snapshotDir": snapshotDir,
                    "duration":    duration + "s",
                    "status":      status,
                    "sources":     String(config.sources.count)
                ]
            )
            Notify.send(
                title: anyFailure ? "Backup partially failed" : "Backup complete",
                body:  "\(config.sources.count) source(s) in \(duration)s → \(snapshotDir)"
            )
        }

        print("backup: \(status) (\(duration)s)")
    }

    // MARK: — Config

    struct BackupConfig {
        let snapshotBase:   String
        let globalExcludes: [String]
        let sources:        [SourceEntry]
    }

    struct SourceEntry {
        let path:     String
        let excludes: [String]
    }

    static func readConfig() -> BackupConfig {
        let paths = [
            "./config/backup.plist",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mgr/backup.plist").path
        ]
        for path in paths {
            guard let dict = Plist.read(at: path) else { continue }
            let snapshotBase   = dict["snapshotBase"]   as? String ?? "~/Backups/mgr"
            let globalExcludes = dict["globalExcludes"] as? [String] ?? []
            let rawSources     = dict["sources"]        as? [[String: Any]] ?? []
            let sources = rawSources.compactMap { entry -> SourceEntry? in
                guard let path = entry["path"] as? String else { return nil }
                let excludes = entry["excludes"] as? [String] ?? []
                return SourceEntry(path: path, excludes: excludes)
            }
            return BackupConfig(snapshotBase: snapshotBase, globalExcludes: globalExcludes, sources: sources)
        }
        return BackupConfig(snapshotBase: "~/Backups/mgr", globalExcludes: [], sources: [])
    }

    // MARK: — Manifest

    private static func writeManifest(snapshotDir: String, sources: [SourceEntry], timestamp: String) {
        let entries = sources.map { ["path": $0.path, "excludes": $0.excludes] }
        let manifest: [String: Any] = [
            "timestamp": timestamp,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "sources":   entries
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) else { return }
        let path = snapshotDir + "/manifest.json"
        try? data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: — Helpers

    public static func listSnapshots(base: String) -> [String] {
        let expanded = (base as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: expanded) else { return [] }
        return entries
            .filter { name in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: expanded + "/" + name, isDirectory: &isDir)
                return isDir.boolValue && name != ".DS_Store"
            }
            .sorted()
            .reversed()
            .map { expanded + "/" + $0 }
    }

    private static func isoTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: Date())
    }

    private static func flagValue(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: idx)
        return args.indices.contains(next) ? args[next] : nil
    }
}
