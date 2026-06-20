import Foundation

public enum Restore {
    public static func run(args: [String]) {
        if args.contains("--list") {
            Logger.info("restore: list snapshots — not yet implemented")
        } else {
            let srcIdx = args.firstIndex(of: "--source").map { args.index(after: $0) }
            let source = srcIdx.flatMap { args.indices.contains($0) ? args[$0] : nil }
            Logger.info("restore: source=\(source ?? "none") — not yet implemented")
        }
    }
}
