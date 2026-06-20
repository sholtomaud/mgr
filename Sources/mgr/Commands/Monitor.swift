import Foundation

enum Monitor {
    static func run(args: [String]) {
        if args.contains("--start") {
            Logger.info("monitor: start — not yet implemented")
        } else if args.contains("--stop") {
            Logger.info("monitor: stop — not yet implemented")
        } else if args.contains("--status") {
            Logger.info("monitor: status — not yet implemented")
        } else {
            Logger.info("monitor: run 'mgr monitor --start|--stop|--status'")
        }
    }
}
