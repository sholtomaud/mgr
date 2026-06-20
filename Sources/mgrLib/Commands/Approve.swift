import Foundation

public enum Approve {
    public static func run(args: [String]) {
        guard let target = args.first else {
            fputs("mgr approve: requires a pid, path, or name\n", stderr)
            fputs("Usage: mgr approve <pid|path|name>\n", stderr)
            exit(1)
        }

        let resolvedPath = resolve(target: target)

        // Verify the binary exists and is reachable
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            fputs("mgr approve: path not found: \(resolvedPath)\n", stderr)
            exit(1)
        }

        let info = Codesign.verify(path: resolvedPath)
        if !info.isValid {
            fputs("mgr approve: warning — \(resolvedPath) has an invalid or missing code signature\n", stderr)
        }

        let sha256 = ApprovedList.sha256(of: resolvedPath) ?? ""
        let name = (resolvedPath as NSString).lastPathComponent
        let entry = ApprovedEntry(
            name: name,
            path: resolvedPath,
            teamID: info.teamID ?? "",
            sha256: sha256,
            approvedBy: NSUserName(),
            approvedAt: ISO8601DateFormatter().string(from: Date())
        )

        do {
            try ApprovedList.append(entry)
            print("Approved: \(name)")
            print("  path:       \(resolvedPath)")
            print("  teamID:     \(info.teamID ?? "(none)")")
            print("  sha256:     \(sha256)")
            print("  approvedBy: \(entry.approvedBy)")
            print("  approvedAt: \(entry.approvedAt)")
            print("  written to: \(ApprovedList.plistPath)")
        } catch {
            fputs("mgr approve: failed to write approved.plist: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // Resolve a pid, path, or name to an absolute path
    private static func resolve(target: String) -> String {
        // Absolute path — use directly
        if target.hasPrefix("/") { return target }

        // Numeric — treat as PID, look up the binary via `ps`
        if let pid = Int(target) {
            let result = Shell.run("/bin/ps", args: ["-p", String(pid), "-o", "comm="])
            let comm = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !comm.isEmpty { return comm }
            fputs("mgr approve: no process found with PID \(pid)\n", stderr)
            exit(1)
        }

        // Name — try `which` to find it on PATH
        let result = Shell.run("/usr/bin/which", args: [target])
        let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty { return resolved }

        // Last resort — treat as a relative path from CWD
        return FileManager.default.currentDirectoryPath + "/" + target
    }
}
