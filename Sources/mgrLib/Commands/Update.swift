import Foundation

public enum Update {
    public static func run(args: [String]) {
        if args.contains("--check") {
            Logger.info("update: check — not yet implemented")
        } else if args.contains("--containers") {
            Logger.info("update: containers — not yet implemented")
        } else if args.contains("--self") {
            Logger.info("update: self — not yet implemented")
        } else {
            Logger.info("update: run 'mgr update --check|--containers|--self'")
        }
    }
}
