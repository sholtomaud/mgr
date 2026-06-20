import Foundation

public enum Approve {
    public static func run(args: [String]) {
        guard let target = args.first else {
            fputs("mgr approve: requires a pid, path, or name\n", stderr)
            fputs("Usage: mgr approve <pid|path|name>\n", stderr)
            exit(1)
        }
        Logger.info("approve: target=\(target) — not yet implemented")
    }
}
