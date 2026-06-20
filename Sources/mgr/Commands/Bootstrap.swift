import Foundation

enum Bootstrap {
    static func run(args: [String]) {
        let sub = args.first ?? ""
        switch sub {
        case "system":    runSystem()
        case "apps":      runApps()
        case "packages":  runPackages()
        case "dotfiles":  runDotfiles()
        case "agents":    runAgents()
        case "dev":       runDev()
        case "":
            // Run all stages in order
            runSystem()
            runApps()
            runPackages()
            runDotfiles()
            runAgents()
            runDev()
        default:
            fputs("mgr bootstrap: unknown subcommand '\(sub)'\n", stderr)
            fputs("Run 'mgr help bootstrap' for usage.\n", stderr)
            exit(1)
        }
    }

    private static func runSystem() {
        Logger.info("bootstrap/system: not yet implemented")
    }

    private static func runApps() {
        Logger.info("bootstrap/apps: not yet implemented")
    }

    private static func runPackages() {
        Logger.info("bootstrap/packages: not yet implemented")
    }

    private static func runDotfiles() {
        Logger.info("bootstrap/dotfiles: not yet implemented")
    }

    private static func runAgents() {
        Logger.info("bootstrap/agents: not yet implemented")
    }

    private static func runDev() {
        Logger.info("bootstrap/dev: not yet implemented")
    }
}
