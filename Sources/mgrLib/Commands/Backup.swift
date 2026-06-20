import Foundation

public enum Backup {
    public static func run(args: [String]) {
        let dryRun = args.contains("--dry-run")
        let destIdx = args.firstIndex(of: "--destination").map { args.index(after: $0) }
        let destination = destIdx.flatMap { args.indices.contains($0) ? args[$0] : nil }
        Logger.info("backup: dryRun=\(dryRun) destination=\(destination ?? "config/backup.plist") — not yet implemented")
    }
}
