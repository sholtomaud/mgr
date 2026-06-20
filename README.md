# mgr

Personal macOS management CLI. The open-source, auditable equivalent of Kolide or Kandji for individual use.

**Single signed Swift binary. No third-party dependencies. No Homebrew on the host.**

```
mgr bootstrap   # one-time machine setup
mgr doctor      # on-demand audit (apps, launchd agents, MCP servers)
mgr monitor     # background daemon — detects and alerts on unauthorized processes
mgr backup      # rsync-based timestamped snapshots
mgr restore     # restore from a snapshot
mgr approve     # add a process/app to the whitelist
mgr update      # update mgr itself or pinned container image digests
```

## Install

```sh
curl -fsSL https://github.com/sholtomaud/mgr/releases/latest/download/install.sh | sh
```

Requires macOS 14 (Sonoma) or later.

> **v0.1.0 note:** The current release is unsigned (Developer ID certificate pending).
> After install, clear the Gatekeeper quarantine flag once:
> ```sh
> xattr -d com.apple.quarantine /usr/local/bin/mgr
> ```
> Signed and notarized releases will lift this requirement.

## Usage

### `mgr bootstrap [subcommand]`

One-time machine setup. Each subcommand is idempotent.

| Subcommand | What it does |
|---|---|
| `system` | Applies macOS defaults from `~/.config/mgr/system.plist` (Dock, Finder, screencapture, keyboard) |
| `dotfiles` | Creates symlinks per `~/.config/mgr/dotfiles.plist`; never overwrites regular files |
| `dev` | Verifies Xcode CLI tools, applies git global config, generates ed25519 SSH key |
| `agents` | Installs and loads `com.mgr.monitor` and `com.mgr.backup` LaunchAgents |
| `apps` | (configurable) Downloads and verifies signed DMGs/PKGs |
| `packages` | (configurable) Runs Brewfile in a container |

Run `mgr bootstrap` (no subcommand) to run all steps in order.

### `mgr doctor [--fix] [--json]`

Audits LaunchAgents, LaunchDaemons, and MCP server configurations against `~/.config/mgr/approved.plist`.

- `--fix` — quarantines unrecognised items to `~/Library/mgr/quarantine/`
- `--json` — machine-readable output

### `mgr monitor [--start|--stop|--status]`

Background daemon that watches for new or changed LaunchAgents and MCP configs. Sends a macOS notification on each new unknown. Optionally auto-quarantines (`autoQuarantine: true` in `approved.plist`).

### `mgr backup [--dry-run] [--destination <path>]`

rsync-based backup. Each run creates a timestamped snapshot directory under `snapshotBase` (configured in `~/.config/mgr/backup.plist`).

- `--dry-run` — prints what would be copied without touching anything
- `--destination` — overrides `snapshotBase` from config

### `mgr restore [--list] [--source <path>]`

- `--list` — shows available snapshots at `snapshotBase`, newest first
- `--source <path>` — restores a snapshot (requires typing `yes` to confirm)

### `mgr approve <pid|path|name>`

Adds a process, application, or MCP server to the approved whitelist. Verifies the code signature and records a SHA-256 hash, Team ID, and timestamp.

### `mgr update [--check|--self|--containers]`

- `--check` — reports current vs latest version
- `--self` — downloads the latest signed binary from GitHub Releases, verifies the signature, and replaces the current install
- `--containers` — pulls latest digests for images in `~/.config/mgr/containers.plist` and updates the plist (no floating `latest` tags)

## Configuration

Config files live in `~/.config/mgr/`. Copy templates from the repo's `config/` directory:

| File | Purpose |
|---|---|
| `approved.plist` | Whitelist and monitor settings |
| `backup.plist` | Snapshot base path, sources, excludes |
| `system.plist` | macOS defaults to apply on `mgr bootstrap system` |
| `dotfiles.plist` | Symlink mappings for `mgr bootstrap dotfiles` |
| `dev.plist` | Git config, SSH key settings |
| `containers.plist` | OCI image digests for dev toolchains |

## Manual steps that cannot be automated

- Full Disk Access (System Settings → Privacy & Security)
- Accessibility permissions
- Apple ID sign-in
- Xcode.app
- Microsoft Office

## Development

Requires Xcode CLI tools (`xcode-select --install`). No Xcode.app needed.

```sh
swift build             # debug build
swift build -c release  # release binary → .build/release/mgr
swift test              # 57 tests
.build/debug/mgr help   # smoke test
```

### Project layout

```
Sources/
  mgr/          # thin entry point (main.swift)
  mgrLib/
    Commands/   # Bootstrap, Doctor, Monitor, Backup, Restore, Approve, Update
    Core/       # Shell, Logger, Plist, Codesign, Notify, ApprovedList
Tests/
  mgrTests/     # 57 unit tests
config/         # plist templates
launchd/        # LaunchAgent plist templates
scripts/        # install.sh
.github/
  workflows/
    ci.yml                  # build + test on every push/PR
    build-sign-release.yml  # sign + notarize on version tags
```

See [docs/spec.md](docs/spec.md) for the full architecture and requirements.

## Philosophy

- macOS-only — full Apple API access (codesign, launchd, Keychain)
- No third-party Swift packages — every line is auditable
- OCI container images for dev toolchains live in separate repos, referenced by digest
- Threat model includes MCP servers and LLM agents, not just traditional software
