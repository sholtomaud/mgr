import Foundation

public enum Restore {
    public static func run(args: [String]) {
        if args.contains("--list") {
            listSnapshots()
        } else if let sourcePath = flagValue(args, flag: "--source") {
            restoreFrom(sourcePath)
        } else {
            fputs("Usage: mgr restore [--list] [--source <snapshot-path>]\n", stderr)
            exit(1)
        }
    }

    // MARK: — List

    private static func listSnapshots() {
        let config = Backup.readConfig()
        let snapshots = Backup.listSnapshots(base: config.snapshotBase)
        if snapshots.isEmpty {
            print("restore: no snapshots found at \(config.snapshotBase)")
            return
        }
        print("Snapshots at \((config.snapshotBase as NSString).expandingTildeInPath):")
        for path in snapshots {
            let name = (path as NSString).lastPathComponent
            // Show source names from manifest if available
            if let manifest = readManifest(snapshotDir: path),
               let sources = manifest["sources"] as? [[String: Any]] {
                let sourceNames = sources.compactMap { $0["path"] as? String }.joined(separator: ", ")
                print("  \(name)  [\(sourceNames)]")
            } else {
                print("  \(name)")
            }
        }
    }

    // MARK: — Restore

    private static func restoreFrom(_ snapshotPath: String) {
        let expandedPath = (snapshotPath as NSString).expandingTildeInPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: expandedPath) else {
            fputs("restore: snapshot not found: \(expandedPath)\n", stderr)
            exit(1)
        }

        let manifest = readManifest(snapshotDir: expandedPath)
        let sources = (manifest?["sources"] as? [[String: Any]] ?? [])
            .compactMap { $0["path"] as? String }

        // Enumerate what's in the snapshot dir
        let entries = (try? fm.contentsOfDirectory(atPath: expandedPath)) ?? []
        let restorableDirs = entries.filter { name in
            guard name != "manifest.json" else { return false }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: expandedPath + "/" + name, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()

        guard !restorableDirs.isEmpty else {
            print("restore: snapshot contains no source directories")
            return
        }

        print("Restore from: \(expandedPath)")
        print("Will restore:")
        for dir in restorableDirs {
            // Try to find original path from manifest
            let originalPath = sources.first { ($0 as NSString).lastPathComponent == dir }
                ?? "~/" + dir
            print("  \(expandedPath)/\(dir)/ → \((originalPath as NSString).expandingTildeInPath)/")
        }

        print("\nType 'yes' to continue, or anything else to abort: ", terminator: "")
        guard let input = readLine(), input.lowercased() == "yes" else {
            print("Aborted.")
            return
        }

        var anyFailure = false
        for dir in restorableDirs {
            let originalPath = sources.first { ($0 as NSString).lastPathComponent == dir }
                ?? "~/" + dir
            let expanded = (originalPath as NSString).expandingTildeInPath
            try? fm.createDirectory(atPath: expanded, withIntermediateDirectories: true)

            let result = Shell.run("/usr/bin/rsync", args: [
                "-a", "--stats",
                expandedPath + "/" + dir + "/",
                expanded + "/"
            ])
            if result.succeeded {
                print("  ✓ \(dir) → \(expanded)")
            } else {
                Logger.error("restore: rsync failed for \(dir): \(result.stderr)")
                anyFailure = true
            }
        }

        Logger.log(
            to: "backup.jsonl",
            level: anyFailure ? "error" : "info",
            message: anyFailure ? "restore partial" : "restore ok",
            extra: ["snapshotDir": expandedPath]
        )
        print(anyFailure ? "restore: completed with errors" : "restore: done")
    }

    // MARK: — Helpers

    private static func readManifest(snapshotDir: String) -> [String: Any]? {
        let path = snapshotDir + "/manifest.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }

    private static func flagValue(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: idx)
        return args.indices.contains(next) ? args[next] : nil
    }
}
