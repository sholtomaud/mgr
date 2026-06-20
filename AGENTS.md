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

## Autonomous workflow — how to work through issues

Follow this loop exactly. Do not skip steps. Do not start a new issue until the previous one is merged and CI is green.

### Step 1 — Pick the next issue

```sh
gh issue list --repo sholtomaud/mgr --state open --label "phase:1" --json number,title,labels | head -1
# If phase:1 is empty, move to phase:2, phase:3, etc. in order.
```

Work issues in ascending phase order (phase:1 before phase:2, etc.) and ascending issue number within a phase. Never pick an issue whose phase depends on an incomplete earlier phase (e.g. don't start phase:3 if open phase:2 issues remain).

### Step 2 — Read the issue fully

```sh
gh issue view <number> --repo sholtomaud/mgr
```

Read every checklist item and acceptance criterion before writing any code. If the issue references other issues (`refs #n`), read those too.

### Step 3 — Checkout a branch

Branch name format: `issue/<number>-<short-slug>`

```sh
git checkout main && git pull origin main
git checkout -b issue/<number>-<short-slug>
```

### Step 4 — Implement

Work through every unchecked task in the issue's checklist. Follow all constraints in this file (hard constraints, code style, security rules). Do not implement anything not in the checklist — scope creep will cause issues to drift.

After each logical unit of work:
- `swift build` — must be clean (zero errors, zero warnings)
- `swift test` — must pass
- `.build/debug/mgr <subcommand> help` — smoke test the relevant subcommand

### Step 5 — Commit

```sh
git add <specific files>   # never `git add -A` or `git add .`
git commit -m "feat(<subcommand>): <what changed>

refs #<number>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

Reference the issue number in every commit. Group related changes into a single commit; do not make one commit per file.

### Step 6 — Push and open a PR

```sh
git push -u origin issue/<number>-<short-slug>

gh pr create --repo sholtomaud/mgr \
  --title "<short description>" \
  --body "$(cat <<'EOF'
## Summary
- <bullet 1>
- <bullet 2>

## Checklist
- [ ] `swift build` passes (zero warnings)
- [ ] `swift test` passes
- [ ] Smoke-tested: `mgr <subcommand> --help`

closes #<number>

🤖 Generated with Claude Code
EOF
)"
```

### Step 7 — Wait for CI and verify

```sh
gh run list --repo sholtomaud/mgr --branch issue/<number>-<short-slug> --limit 5
gh run watch <run-id>   # block until complete
```

If CI fails:
1. `gh run view <run-id> --log-failed` — read the failure output
2. Fix the root cause locally (`swift build`, `swift test`)
3. Commit the fix with `fix: <description> refs #<number>`
4. Push — CI re-triggers automatically
5. Return to Step 7

Do NOT merge a PR with a failing CI run.

### Step 8 — Merge

Once CI is green:

```sh
gh pr merge <pr-number> --repo sholtomaud/mgr --squash --delete-branch
```

Use `--squash` to keep `main` history clean. The squash commit message should be the PR title + `closes #<number>`.

### Step 9 — Update the issue checklist

After merging, verify the issue was auto-closed by the `closes #<n>` in the PR. If not:

```sh
gh issue close <number> --repo sholtomaud/mgr --comment "Completed in PR #<pr-number>."
```

### Step 10 — Return to Step 1

Pull `main` and pick the next open issue.

```sh
git checkout main && git pull origin main
```

---

## Working with GitHub Issues — general rules

Issues are organized by implementation phase (see [docs/spec.md](docs/spec.md) Phase 1–6). Each phase has a parent issue; tasks within a phase are checklist items.

- Reference issues in commit messages: `refs #<n>`
- Close issues via PR description: `closes #<n>`
- Do not open new issues for work already covered by existing phase issues — tick the checklist item instead
- Do not modify the issue title or labels — they drive the phase ordering

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
