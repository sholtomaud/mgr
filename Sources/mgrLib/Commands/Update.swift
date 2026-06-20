import Foundation

public enum Update {
    static let repo = "sholtomaud/mgr"
    static let apiBase = "https://api.github.com"
    static let releaseBase = "https://github.com/\(repo)/releases/download"

    public static func run(args: [String]) {
        if args.contains("--check") {
            checkForUpdate()
        } else if args.contains("--containers") {
            updateContainers()
        } else if args.contains("--self") {
            selfUpdate()
        } else {
            fputs("Usage: mgr update [--check|--containers|--self]\n", stderr)
            exit(1)
        }
    }

    // MARK: — --check

    static func checkForUpdate() {
        let currentVersion = currentVersionString()
        print("update: current version: \(currentVersion)")
        guard let latest = fetchLatestTag() else {
            Logger.error("update: could not reach GitHub API")
            return
        }
        print("update: latest version:  \(latest)")
        if latest == currentVersion || latest == "v\(currentVersion)" {
            print("update: up to date")
        } else {
            print("update: new version available — run: mgr update --self")
        }
    }

    // MARK: — --self

    static func selfUpdate() {
        guard let latestTag = fetchLatestTag() else {
            Logger.error("update: could not reach GitHub releases API")
            exit(1)
        }

        let currentVersion = currentVersionString()
        let normalised = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag
        if normalised == currentVersion {
            print("update: already at \(latestTag)")
            return
        }
        print("update: \(currentVersion) → \(latestTag)")

        let arch = machineArch()
        let assetName = "mgr-\(arch)"
        // Try arch-specific asset first, fall back to universal binary name "mgr"
        let url = "\(releaseBase)/\(latestTag)/\(assetName)"

        print("update: downloading \(url) ...")
        guard let tmp = downloadToTemp(url: url) else {
            Logger.error("update: download failed")
            exit(1)
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Codesign verification — mandatory before installing
        let sig = Codesign.verify(path: tmp)
        guard sig.isValid else {
            Logger.error("update: code signature invalid — aborting")
            exit(1)
        }
        print("update: signature valid (Team ID: \(sig.teamID ?? "unknown"))")

        let installPath = "/usr/local/bin/mgr"
        let result = Shell.run("/usr/bin/install", args: ["-m", "755", tmp, installPath])
        if result.succeeded {
            print("update: installed \(latestTag) to \(installPath)")
            Logger.log(to: "update.jsonl", message: "self-update ok",
                       extra: ["from": currentVersion, "to": latestTag])
        } else {
            // install(1) may fail if /usr/local/bin is owned by root
            Logger.error("update: install failed — try: sudo mgr update --self\n\(result.stderr)")
            exit(1)
        }
    }

    // MARK: — --containers

    static func updateContainers() {
        let plistPath = containersPlistPath()
        guard let raw = Plist.read(at: plistPath) else {
            print("update: no containers configured in \(plistPath)")
            return
        }

        var updated = raw
        var anyChange = false

        for (name, value) in raw {
            guard let entry = value as? [String: Any],
                  let image = entry["image"] as? String else { continue }
            let currentDigest = entry["digest"] as? String ?? ""

            print("update/containers: checking \(name) (\(image))...")
            guard let digest = fetchContainerDigest(image: image) else {
                Logger.error("update/containers: could not fetch digest for \(image)")
                continue
            }

            if digest == currentDigest {
                print("  \(name): up to date (\(shortDigest(digest)))")
            } else {
                print("  \(name): \(shortDigest(currentDigest)) → \(shortDigest(digest))")
                var newEntry = entry
                newEntry["digest"] = digest
                updated[name] = newEntry
                anyChange = true
            }
        }

        if anyChange {
            do {
                try Plist.write(updated, to: plistPath)
                print("update/containers: plist updated")
                Logger.log(to: "update.jsonl", message: "containers updated")
            } catch {
                Logger.error("update/containers: failed to write plist: \(error.localizedDescription)")
            }
        } else {
            print("update/containers: all images up to date")
        }
    }

    // MARK: — GitHub API helpers

    public static func fetchLatestTag() -> String? {
        let url = "\(apiBase)/repos/\(repo)/releases/latest"
        let result = Shell.run("/usr/bin/curl", args: [
            "-fsSL",
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            "--max-time", "15",
            url
        ])
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        return tag
    }

    private static func downloadToTemp(url: String) -> String? {
        let tmp = NSTemporaryDirectory() + "mgr-update-\(UUID().uuidString)"
        let result = Shell.run("/usr/bin/curl", args: [
            "-fsSL",
            "--max-time", "120",
            "-o", tmp,
            url
        ])
        guard result.succeeded else {
            Logger.error("update: curl failed: \(result.stderr)")
            return nil
        }
        Shell.run("/bin/chmod", args: ["+x", tmp])
        return tmp
    }

    // MARK: — Container registry helpers

    private static func fetchContainerDigest(image: String) -> String? {
        // docker must be installed; crane or skopeo are alternatives
        let dockerPath = "/usr/local/bin/docker"
        let dockerExists = FileManager.default.fileExists(atPath: dockerPath)
        guard dockerExists else {
            Logger.error("update/containers: docker not found at \(dockerPath) — install Docker Desktop")
            return nil
        }

        // Pull latest to refresh the digest
        let pull = Shell.run(dockerPath, args: ["pull", image + ":latest"])
        guard pull.succeeded else {
            Logger.error("update/containers: docker pull failed: \(pull.stderr)")
            return nil
        }

        // Extract the repo digest (sha256:...)
        let inspect = Shell.run(dockerPath, args: [
            "inspect", "--format", "{{index .RepoDigests 0}}", image + ":latest"
        ])
        guard inspect.succeeded else { return nil }
        let raw = inspect.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Format: image@sha256:abc123 — extract the sha256:... part
        if let atRange = raw.range(of: "@") {
            return String(raw[atRange.upperBound...])
        }
        return raw.isEmpty ? nil : raw
    }

    // MARK: — Miscellaneous helpers

    private static func currentVersionString() -> String {
        // Run our own binary with `version` to get the embedded version string
        let result = Shell.run(CommandLine.arguments[0], args: ["version"])
        if result.succeeded {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "mgr ", with: "")
        }
        return "unknown"
    }

    private static func machineArch() -> String {
        let result = Shell.run("/usr/bin/uname", args: ["-m"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containersPlistPath() -> String {
        let cwdPath = "./config/containers.plist"
        if FileManager.default.fileExists(atPath: cwdPath) { return cwdPath }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mgr/containers.plist").path
    }

    private static func shortDigest(_ digest: String) -> String {
        guard digest.hasPrefix("sha256:"), digest.count > 19 else { return digest }
        return "sha256:" + digest.dropFirst(7).prefix(12)
    }
}
