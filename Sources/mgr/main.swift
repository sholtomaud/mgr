import Foundation

// mgr — personal macOS management CLI
// Usage: mgr <command> [subcommand] [flags]

let version = "0.1.0"

guard CommandLine.arguments.count > 1 else {
    printHelp()
    exit(0)
}

let command = CommandLine.arguments[1]
let args = Array(CommandLine.arguments.dropFirst(2))

switch command {
case "version", "--version", "-v":
    print("mgr \(version)")
case "help", "--help", "-h":
    if let sub = args.first {
        printHelp(for: sub)
    } else {
        printHelp()
    }
case "bootstrap":
    Bootstrap.run(args: args)
case "doctor":
    Doctor.run(args: args)
case "monitor":
    Monitor.run(args: args)
case "backup":
    Backup.run(args: args)
case "restore":
    Restore.run(args: args)
case "approve":
    Approve.run(args: args)
case "update":
    Update.run(args: args)
default:
    fputs("mgr: unknown command '\(command)'\n", stderr)
    fputs("Run 'mgr help' for usage.\n", stderr)
    exit(1)
}

func printHelp(for command: String? = nil) {
    if let command {
        switch command {
        case "bootstrap":
            print("""
            Usage: mgr bootstrap [system|apps|packages|dotfiles|agents|dev]

            One-time machine setup. Each subcommand is idempotent.

              system    Write macOS defaults, set hostname
              apps      Download and verify DMGs/PKGs from approved sources
              packages  Evaluate Brewfile inside container
              dotfiles  Symlink shell config, git config
              agents    Register com.mgr.monitor and com.mgr.backup via SMAppService
              dev       Xcode CLI path, git config, SSH key generation
            """)
        case "doctor":
            print("""
            Usage: mgr doctor [--fix] [--json]

            Audit running processes, launchd agents, and MCP server configurations
            against the approved whitelist in config/approved.plist.

              --fix     Quarantine unrecognized items (after review)
              --json    Machine-readable JSON output
            """)
        case "monitor":
            print("""
            Usage: mgr monitor [--start|--stop|--status]

            Manage the background monitoring daemon.

              --start   Start the monitor agent
              --stop    Stop the monitor agent
              --status  Show daemon status
            """)
        case "backup":
            print("""
            Usage: mgr backup [--destination <path>] [--dry-run]

            Run rsync backup using mappings in config/backup.plist.

              --destination  Override destination path
              --dry-run      Show what would be copied without copying
            """)
        case "restore":
            print("""
            Usage: mgr restore [--source <path>] [--list]

            Restore from a backup snapshot.

              --list    List available snapshots
              --source  Path to snapshot to restore from
            """)
        case "approve":
            print("""
            Usage: mgr approve <pid|path|name>

            Add a process, application, or MCP server to the whitelist.
            Writes a timestamped entry to config/approved.plist.
            """)
        case "update":
            print("""
            Usage: mgr update [--check|--containers|--self]

              --check       Report available updates without installing
              --containers  Pull latest approved container image digests
              --self        Download and install the latest signed mgr binary
            """)
        default:
            print("No help available for '\(command)'.")
        }
    } else {
        print("""
        mgr \(version) — personal macOS management CLI

        Usage: mgr <command> [subcommand] [flags]

        Commands:
          bootstrap   One-time machine setup
          doctor      On-demand audit of processes, agents, and MCP servers
          monitor     Background daemon — detect and alert on unauthorized processes
          backup      rsync-based backup
          restore     Restore from backup snapshot
          approve     Add a process or app to the whitelist
          update      Update mgr itself or pinned container image digests

        Run 'mgr help <command>' for command-specific usage.
        """)
    }
}
