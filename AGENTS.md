# AGENTS.md — mgr

Instructions for AI agents and coding assistants working in this repository.

## Project overview

`mgr` is a personal macOS management CLI written in Swift. It is the open-source equivalent of Kolide/Kandji for individual use. The binary is code-signed and notarized; no third-party Swift packages are permitted.

See [docs/spec.md](docs/spec.md) for the full architecture and functional requirements.

## Hard constraints

1. **macOS-only.** Do not add Linux compatibility shims or conditional compilation for non-Apple platforms. The Apple API surface is the point.
2. **No third-party Swift packages.** `Package.swift` must only declare targets; no external `.package(url:...)` dependencies. Use Apple frameworks only: Foundation, Security, ServiceManagement, UserNotifications.
3. **No new files without a home.** Follow the established structure:
   - `Sources/mgr/Commands/` — one file per subcommand
   - `Sources/mgr/Core/` — shared helpers (Logger, Plist, Process/Shell, Codesign, Notify)
   - `config/` — plist configuration files
   - `launchd/` — launchd agent plist templates
   - `scripts/` — shell scripts (keep minimal; logic belongs in Swift)
   - `Tests/mgrTests/` — XCTest cases
4. **No comments explaining what code does.** Only add a comment when the WHY is non-obvious: a hidden constraint, a workaround for a specific macOS API quirk, or an invariant that would surprise a reader.
5. **Idempotent operations.** Every `mgr` subcommand must be safely re-runnable. Operations that have already completed should report "already done" rather than failing or duplicating work.

## Code style

- Swift 5.9+ with `async/await` where appropriate (prefer sync for CLI commands unless I/O blocks)
- Use `enum` with static methods for command namespaces (matches existing `Bootstrap`, `Doctor`, etc.)
- Error output goes to `stderr` via `fputs(..., stderr)`, not `print`
- Exit with non-zero on failure: `exit(1)`
- All structured log output goes through `Logger` — do not use bare `print` in command implementations

## Security rules

- Never call `Shell.run` with user-supplied strings interpolated directly into arguments. Pass arguments as a `[String]` array.
- Verify codesign before executing any downloaded binary (see `Codesign.swift`).
- Do not write secrets, tokens, or credentials into config plist files.
- `approved.plist` must never be written without going through the `Approve` command (which logs approval with a timestamp).

## Threat model context

MCP servers and LLM agents are first-class threat actors. Any persistent process installed via npm, pip, or an agent action must be treated as unverified until it appears in `config/approved.plist`. The `doctor` and `monitor` commands exist specifically to surface these.

## Working with GitHub Issues

Issues are organized by implementation phase (see [docs/spec.md](docs/spec.md) Phase 1–6). Each phase has a parent issue; tasks within a phase are sub-issues or checklist items. When implementing a feature:

1. Reference the relevant issue in commit messages: `refs #<n>`
2. Close issues with `closes #<n>` in the PR description
3. Do not open new issues for work already covered by existing phase issues — add a checklist item instead

## Building and testing

```sh
swift build             # debug
swift build -c release  # release binary
swift test              # run XCTest suite
.build/debug/mgr help   # smoke test the CLI
```

No Xcode.app required. Xcode CLI tools (`xcode-select --install`) are sufficient.

## What NOT to do

- Do not add a `README.md` to subdirectories — the top-level README and spec.md are the docs
- Do not add logging to every function — only log at command entry points and significant state changes
- Do not use `Process` directly — use the `Shell.run` wrapper in `Core/Process.swift`
- Do not use `FileManager` for process inspection — use `Shell.run("/usr/bin/launchctl", ...)` and parse output
