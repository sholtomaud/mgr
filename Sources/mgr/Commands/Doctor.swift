import Foundation

enum Doctor {
    static func run(args: [String]) {
        let fix = args.contains("--fix")
        let json = args.contains("--json")
        Logger.info("doctor: scanning (fix=\(fix), json=\(json)) — not yet implemented")
    }
}
