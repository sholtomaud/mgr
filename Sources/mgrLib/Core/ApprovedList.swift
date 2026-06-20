import Foundation
import CryptoKit

public struct ApprovedEntry {
    public let name: String
    public let path: String
    public let teamID: String
    public let sha256: String
    public let approvedBy: String
    public let approvedAt: String

    public init(name: String, path: String, teamID: String, sha256: String,
                approvedBy: String, approvedAt: String) {
        self.name = name; self.path = path; self.teamID = teamID
        self.sha256 = sha256; self.approvedBy = approvedBy; self.approvedAt = approvedAt
    }

    public func asDictionary() -> [String: Any] {
        ["name": name, "path": path, "teamID": teamID,
         "sha256": sha256, "approvedBy": approvedBy, "approvedAt": approvedAt]
    }
}

public enum ApprovedList {
    // Override for tests. When set, all other resolution is skipped.
    nonisolated(unsafe) public static var testPlistPathOverride: String? = nil

    // Resolution order:
    // 1. testPlistPathOverride (set in test setUp/tearDown)
    // 2. ~/.config/mgr/approved.plist (runtime)
    // 3. ./config/approved.plist (dev fallback, relative to CWD)
    public static var plistPath: String {
        if let override = testPlistPathOverride { return override }
        let runtime = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mgr/approved.plist").path
        if FileManager.default.fileExists(atPath: runtime) { return runtime }
        return "./config/approved.plist"
    }

    public static func load() -> [ApprovedEntry] {
        guard let dict = Plist.read(at: plistPath),
              let array = dict["approved"] as? [[String: Any]] else { return [] }
        return array.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let path = entry["path"] as? String else { return nil }
            return ApprovedEntry(
                name: name,
                path: path,
                teamID: entry["teamID"] as? String ?? "",
                sha256: entry["sha256"] as? String ?? "",
                approvedBy: entry["approvedBy"] as? String ?? "",
                approvedAt: entry["approvedAt"] as? String ?? ""
            )
        }
    }

    public static func append(_ entry: ApprovedEntry) throws {
        var dict = Plist.read(at: plistPath) ?? defaultPlist()
        var array = dict["approved"] as? [[String: Any]] ?? []
        array.append(entry.asDictionary())
        dict["approved"] = array
        // Ensure the config dir exists
        let dir = (plistPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir,
            withIntermediateDirectories: true)
        try Plist.write(dict, to: plistPath)
    }

    // Returns true if path or (non-empty) teamID matches any approved entry
    public static func isApproved(path: String, teamID: String?) -> Bool {
        load().contains { entry in
            entry.path == path ||
            (!entry.teamID.isEmpty && entry.teamID == teamID)
        }
    }

    public static func sha256(of path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let digest = SHA256.hash(data: data)
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "sha256:" + hex
    }

    private static func defaultPlist() -> [String: Any] {
        ["settings": ["monitorInterval": 60, "autoQuarantine": false,
                      "logPath": "~/Library/Logs/mgr/monitor.jsonl"],
         "approved": [] as [[String: Any]]]
    }
}
