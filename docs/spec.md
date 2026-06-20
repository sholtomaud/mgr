# mgr — Overview and Functional Requirements

## 1. Project Philosophy and Constraints

**mgr** is a personal macOS management CLI equivalent in scope to what Kolide or Kandji provide commercially, built as an open-source, auditable, single-binary tool for individual and small-team use.

### Core principles

1. **Apple-only dependencies.** The binary uses only Swift stdlib and Apple frameworks (Foundation, System, Security, ServiceManagement). No npm, no pip, no Homebrew packages installed to the host OS.
2. **Signed and notarized.** Every release binary is code-signed and notarized. The install script verifies the signature before executing anything.
3. **macOS-only.** Linux portability is not a goal. Accepting that constraint unlocks the full Apple API surface (codesign, launchd, Keychain, SMAppService).
4. **Idempotent operations.** Every subcommand can be re-run on an existing machine and reports "already done" rather than failing or duplicating work.
5. **No third-party Swift packages.** Every line is auditable. External dependencies are managed as OCI images in separate repos with digest pinning, not as host-installed packages.
6. **Minimal bash surface.** A tiny `install.sh` (Stage 0) is the only bash that runs before the signed binary takes over. Thin glue scripts that call `mgr` subcommands are acceptable; complex logic lives in Swift.
7. **Threat model includes LLMs and MCP servers.** MCP servers are persistent processes with filesystem/network access installed via npm or configured in dotfiles. `mgr` treats them as first-class monitored entities.

### What mgr is NOT

- Not a cross-platform tool
- Not a replacement for MDM (it cannot burn profiles into the OS layer)
- Not an endpoint security product requiring System Extensions or kernel access
- Not a package manager (Homebrew is used inside containers, not on the host)

---

## 2. Repository Structure

```
mgr/
├── Sources/mgr/
│   ├── main.swift
│   ├── Commands/
│   │   ├── Bootstrap.swift
│   │   ├── Doctor.swift
│   │   ├── Monitor.swift
│   │   ├── Backup.swift
│   │   ├── Restore.swift
│   │   ├── Approve.swift
│   │   └── Update.swift
│   ├── Core/
│   │   ├── Plist.swift          # read/write plist helpers
│   │   ├── Process.swift        # Process wrapper (replaces shell exec)
│   │   ├── Codesign.swift       # codesign/spctl verification
│   │   ├── Notify.swift         # macOS UserNotifications
│   │   └── Logger.swift         # structured JSON log writer
├── Package.swift
├── config/
│   ├── approved.plist           # whitelist of approved processes, apps, MCP servers
│   ├── backup.plist             # source/destination drive mappings
│   └── containers.plist         # OCI image digests for container tools
├── launchd/
│   ├── com.mgr.monitor.plist    # background monitor agent
│   └── com.mgr.backup.plist     # scheduled backup agent
├── scripts/
│   └── install.sh               # Stage 0 bootstrap (download + verify binary)
├── docs/
│   ├── spec.md                  # this file
│   └── Conversation.md          # design conversation archive
└── .github/
    └── workflows/
        ├── build-sign-release.yml
        └── container-images.yml
```

### Development toolchain

- **Swift:** Xcode CLI tools (`xcode-select --install`) — no Xcode.app required
- **Editor:** VSCode with the Swift extension
- **Build:** `swift build -c release` from the repo root
- **Test:** `swift test`
- **CI:** GitHub Actions (macOS runner) for build, sign, notarize, release

---

## 3. Binary Architecture — Subcommand Tree

```
mgr <command> [subcommand] [flags]

mgr bootstrap [system|apps|packages|dotfiles|agents|dev]
mgr doctor    [--fix] [--json]
mgr monitor   [--start|--stop|--status]
mgr backup    [--destination <path>] [--dry-run]
mgr restore   [--source <path>] [--list]
mgr approve   <pid|path|name>
mgr update    [--check|--containers|--self]
mgr version
mgr help [command]
```

All commands respect `--json` for machine-readable output and `--verbose` for debug logging.

---

## 4. Bootstrap Sequence

### Stage 0 — install.sh (bash, ~50 lines)

Located at `scripts/install.sh`, vendored into each GitHub release.

Responsibilities:
1. Verify macOS version (≥ 14 Sonoma) and architecture (arm64 / x86_64)
2. Install Xcode CLI tools if absent (`xcode-select --install` + poll loop)
3. Download `mgr` binary from `https://github.com/sholtomaud/mgr/releases/latest/download/mgr-<arch>`
4. Verify code signature: `codesign --verify --deep --strict mgr` — abort if it fails
5. Move to `/usr/local/bin/mgr` and `chmod +x`
6. Hand off: `mgr bootstrap`

The script downloads nothing else. The signed binary drives all subsequent steps.

### Stage 1 — `mgr bootstrap`

Runs subcommands in order. Each subcommand is independently re-runnable.

| Subcommand | Responsibility |
|---|---|
| `mgr bootstrap system` | hostname, defaults write (dock, finder, sleep settings), timezone |
| `mgr bootstrap apps` | download + verify DMGs/PKGs from approved sources (no App Store automation) |
| `mgr bootstrap packages` | Brewfile evaluation inside container, OR direct binary downloads |
| `mgr bootstrap dotfiles` | symlink shell config, git config, SSH key generation |
| `mgr bootstrap agents` | register `com.mgr.monitor` and `com.mgr.backup` via SMAppService |
| `mgr bootstrap dev` | `xcode-select` path, git global config, SSH key upload prompt |

#### What cannot be automated (documented as manual steps in README)

- Full Disk Access grants (System Settings → Privacy & Security)
- Accessibility permissions for any assistive tools
- Apple ID sign-in
- Xcode.app (too large; `mas install 497799835` or manual)
- Microsoft Office (requires Apple ID or volume license)

---

## 5. Monitoring Subsystem

### Threat model

- MCP servers: persistent processes installed via npm/pip, configured in `~/.claude/settings.json`, `~/.cursor/`, `~/.config/`
- Prompt injection can cause an agent to install persistent software
- Processes look legitimate (node, python) but payloads may not be
- launchd agents/daemons: new entries may appear between audits

### `mgr doctor` — on-demand audit

Scans:
- `~/Library/LaunchAgents` and `/Library/LaunchAgents`
- `/Library/LaunchDaemons`
- `~/Library/Application Support/Claude/`
- `~/.cursor/`
- `~/.config/` (for MCP server configs)
- `/Applications` (app bundle codesign validity + team ID)

For each item found:
1. Run `codesign --verify --deep --strict <path>`
2. Extract Team ID from signature
3. Compare against `config/approved.plist`
4. Report drift: new / changed / unrecognized entries

Output is a diff-style report. `mgr doctor` does NOT auto-terminate — human confirmation is required for first-pass audits. Use `mgr doctor --fix` to quarantine unrecognized items after review.

### `mgr monitor` — background daemon

Installed via `mgr bootstrap agents` using `SMAppService`. Registered as `com.mgr.monitor`.

Behavior:
- Polls every 60 seconds (low overhead, no EndpointSecurity.framework required)
- Uses `DispatchSource.makeFileSystemObjectSource` to watch LaunchAgents dirs and MCP config files for changes
- On new/changed entry detected:
  1. Send macOS UserNotification: "Unrecognized process detected: <name>"
  2. Append structured entry to `~/Library/Logs/mgr/monitor.jsonl`
  3. If `autoQuarantine: true` in `approved.plist`: move plist to quarantine dir, run `launchctl unload`
- Poll interval is configurable in `approved.plist`

### `mgr approve <pid|path|name>` — whitelist management

Adds an entry to `config/approved.plist`:

```xml
<dict>
  <key>name</key>        <string>filesystem-mcp</string>
  <key>path</key>        <string>/usr/local/bin/filesystem-mcp</string>
  <key>teamID</key>      <string>XXXXXXXXXX</string>
  <key>sha256</key>      <string>abc123...</string>
  <key>approvedBy</key>  <string>sholto</string>
  <key>approvedAt</key>  <string>2026-06-20T10:00:00Z</string>
</dict>
```

Approval is logged. Removing an entry requires editing `approved.plist` directly (intentional friction).

---

## 6. Backup / Restore

### `mgr backup`

Replaces the existing bash backup scripts. Uses `rsync` (Apple-supplied binary) called via Swift `Process`.

Config in `config/backup.plist`:
```xml
<array>
  <dict>
    <key>name</key>        <string>home</string>
    <key>source</key>      <string>/Users/sholto</string>
    <key>destination</key> <string>/Volumes/Backup/home</string>
    <key>excludes</key>    <array><string>.Trash</string><string>Library/Caches</string></array>
  </dict>
</array>
```

Features:
- `--dry-run` outputs rsync `--dry-run` output without copying
- Logs start/end/size/duration to `~/Library/Logs/mgr/backup.jsonl`
- Sends macOS notification on completion or failure
- Scheduled via `com.mgr.backup.plist` launchd agent (configurable interval)

### `mgr restore`

- `mgr restore --list` shows available snapshots (timestamped dirs or rsync hardlink trees)
- `mgr restore --source <path>` runs rsync in reverse (destination → source) with confirmation prompt

---

## 7. Container Image Reference Model

OCI images for dev toolchains live in separate repos, each with its own release cycle:

| Image | Repo | Purpose |
|---|---|---|
| `ghcr.io/sholtomaud/container-latex` | github.com/sholtomaud/container-latex | Academic LaTeX toolchain |
| `ghcr.io/sholtomaud/container-node-ai` | github.com/sholtomaud/container-node-ai | AI/LLM tooling (node, etc.) |
| `ghcr.io/sholtomaud/container-python` | github.com/sholtomaud/container-python | docling, md2docx, python tools |

Each image repo has:
- GitHub Actions: build → Trivy scan → publish to GHCR → tag with digest
- Semver + changelog
- Scheduled security scan (not just on push)

The main `mgr` repo references images pinned by digest in `config/containers.plist`. No floating `latest` tags.

```xml
<dict>
  <key>latex</key>
  <dict>
    <key>image</key>  <string>ghcr.io/sholtomaud/container-latex</string>
    <key>digest</key> <string>sha256:abc123...</string>
  </dict>
</dict>
```

### `mgr update --containers`

Pulls latest digest for each image and updates `containers.plist`. Requires explicit invocation — no automatic updates.

### `mgr update --self`

Downloads the latest signed `mgr` binary from GitHub releases, verifies codesign, replaces `/usr/local/bin/mgr`.

---

## 8. Configuration Schema

### config/approved.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
  <key>settings</key>
  <dict>
    <key>monitorInterval</key> <integer>60</integer>
    <key>autoQuarantine</key>  <false/>
    <key>logPath</key>         <string>~/Library/Logs/mgr/monitor.jsonl</string>
  </dict>
  <key>approved</key>
  <array>
    <!-- entries written by `mgr approve` -->
  </array>
</dict>
</plist>
```

### config/backup.plist

Array of source/destination mappings with per-entry excludes and schedule overrides.

### config/containers.plist

Dict of image name → `{image, digest}` pairs. Updated by `mgr update --containers`.

---

## 9. GitHub Actions Pipelines

### build-sign-release.yml

Triggers: push to `main`, version tag (`v*`)

Steps:
1. `swift build -c release` on `macos-latest` runner (arm64 + x86_64, lipo into universal)
2. Code sign with Developer ID Application certificate (stored in Actions secret)
3. Notarize with `xcrun notarytool submit`
4. Staple: `xcrun stapler staple`
5. Create GitHub release with signed binary + `install.sh` as release assets

### container-images.yml

Per-image repo pipeline (template, applied to container-latex etc.):
1. Build OCI image
2. Trivy vulnerability scan (fail on CRITICAL)
3. Push to GHCR with digest tag
4. Output digest — used to open a PR updating `containers.plist` in the `mgr` repo

---

## 10. VSCode + Xcode CLI Development Setup

### Prerequisites

```sh
xcode-select --install          # Xcode CLI tools
swift --version                 # verify Swift toolchain
```

### VSCode extensions

- `sswg.swift-lang` — Swift language support, SourceKit-LSP
- `vadimcn.vscode-lldb` — LLDB debugger integration

### Building

```sh
swift build                     # debug
swift build -c release          # release binary at .build/release/mgr
swift test                      # run test suite
```

### Running locally

```sh
.build/debug/mgr doctor         # test doctor subcommand
.build/debug/mgr bootstrap --dry-run  # if implemented
```

### launch.json (VSCode debugger)

```json
{
  "version": "0.2.0",
  "configurations": [{
    "type": "lldb",
    "request": "launch",
    "name": "Debug mgr",
    "program": "${workspaceFolder}/.build/debug/mgr",
    "args": ["doctor"],
    "cwd": "${workspaceFolder}"
  }]
}
```

---

## 11. Phased Implementation Plan

### Phase 1 — Foundation (current)
- [ ] `Package.swift` + argument dispatch in `main.swift`
- [ ] `mgr version` and `mgr help`
- [ ] `Logger.swift` — structured JSON log writer
- [ ] `Plist.swift` — read/write helpers for config files
- [ ] GitHub Actions: build pipeline (no signing yet)

### Phase 2 — Doctor
- [ ] `Codesign.swift` — wrap `codesign --verify`, extract team ID
- [ ] `mgr doctor` — scan LaunchAgents, /Applications, MCP config dirs
- [ ] `approved.plist` schema + `mgr approve`

### Phase 3 — Monitor
- [ ] `mgr monitor` background daemon
- [ ] `com.mgr.monitor.plist` launchd agent
- [ ] `Notify.swift` — UserNotifications wrapper
- [ ] `mgr bootstrap agents` via SMAppService

### Phase 4 — Bootstrap
- [ ] `mgr bootstrap system` — defaults write, hostname
- [ ] `mgr bootstrap dotfiles` — symlinks
- [ ] `mgr bootstrap dev` — git config, SSH key
- [ ] `scripts/install.sh`

### Phase 5 — Backup
- [ ] `Process.swift` — rsync wrapper
- [ ] `mgr backup` + `mgr restore`
- [ ] `com.mgr.backup.plist` scheduled agent

### Phase 6 — Release
- [ ] Code signing + notarization in GitHub Actions
- [ ] `mgr update --self`
- [ ] `mgr update --containers`
- [ ] Public release + README bootstrap instruction
