# mgr

Personal macOS management CLI. The open-source, auditable equivalent of Kolide or Kandji for individual use.

**Single signed Swift binary. No third-party dependencies. No Homebrew on the host.**

```
mgr bootstrap   # one-time machine setup
mgr doctor      # on-demand audit (apps, launchd agents, MCP servers)
mgr monitor     # background daemon — detects and alerts on unauthorized processes
mgr backup      # rsync mirror to external SSD
mgr restore     # restore from the backup SSD
mgr approve     # add a process/app to the whitelist
mgr update      # update mgr itself or pinned container image digests
```

## Install

```sh
curl -fsSL https://github.com/sholtomaud/mgr/releases/latest/download/install.sh | sh
```

Requires macOS 14 (Sonoma) or later. The installer downloads the binary, extracts config templates to `~/.config/mgr/`, and runs `mgr bootstrap`.

> **Unsigned releases (pre-Developer ID):** The current release is unsigned. After install, clear the Gatekeeper quarantine flag once:
> ```sh
> xattr -d com.apple.quarantine /usr/local/bin/mgr
> ```
> Signed and notarized releases will lift this requirement.

## Updating

```sh
mgr update --check   # check whether a newer release is available
mgr update --self    # download latest binary from GitHub Releases and replace current install
```

`--self` verifies the code signature before replacing the binary. Run with `sudo` if you get a permission error on `/usr/local/bin`.

## Usage

### `mgr bootstrap [subcommand]`

One-time machine setup. Each subcommand is idempotent.

| Subcommand | What it does |
|---|---|
| `config` | Copies config templates from the release to `~/.config/mgr/` (skips existing files) |
| `system` | Applies macOS defaults from `~/.config/mgr/system.plist` (Dock, Finder, screencapture, keyboard) — prompts before applying |
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

### `mgr backup [--dry-run] [--volume <path>] [<name>]`

Mirrors local directories to an external backup SSD using `rsync -a --delete`. The drive is auto-discovered by scanning `/Volumes/` for a name matching `volumePattern` in `~/.config/mgr/backup.plist` (e.g. `BACKUP`, `BACKUP1`, `BACKUP2`). Exits cleanly if no matching drive is mounted.

- `--dry-run` — prints what would be synced without touching anything
- `--volume <path>` — overrides auto-discovery (e.g. `--volume /Volumes/BACKUP2`)
- `<name>` — run a single named mapping (e.g. `mgr backup Documents`)

Source directories that don't exist on the local machine are skipped without error.

### `mgr restore [--list] [--source <name>]`

- `--list` — shows the configured volume, mount status, and all mappings with resolved paths
- `--source <name>` — restores a single mapping from the backup drive to the local machine (requires typing `yes` to confirm; runs `rsync -a --delete` in reverse)

### `mgr approve <pid|path|name>`

Adds a process, application, or MCP server to the approved whitelist. Verifies the code signature and records a SHA-256 hash, Team ID, and timestamp.

### `mgr update [--check|--self|--containers]`

- `--check` — reports current vs latest version
- `--self` — downloads the latest binary from GitHub Releases, verifies the signature, and replaces the current install
- `--containers` — pulls latest digests for images in `~/.config/mgr/containers.plist` and updates the plist (no floating `latest` tags)

## Configuration

Config files live in `~/.config/mgr/`. The installer populates these from `config.zip` shipped with each release (existing files are never overwritten, so edits survive upgrades). To re-install missing files:

```sh
curl -fsSL https://github.com/sholtomaud/mgr/releases/latest/download/config.zip -o /tmp/config.zip
unzip -n /tmp/config.zip -d ~/.config/mgr/
```

| File | Purpose |
|---|---|
| `approved.plist` | Whitelist and monitor settings |
| `backup.plist` | Volume pattern, source→destination mappings, excludes |
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
swift test              # 56 tests
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
  mgrTests/     # 56 unit tests
config/         # plist templates (shipped as config.zip in each release)
launchd/        # LaunchAgent plist templates
scripts/        # install.sh, release.sh
.github/
  workflows/
    ci.yml                  # build + test on every push/PR (macos-15)
    build-sign-release.yml  # manual workflow_dispatch for signed releases
```

### Releasing

```sh
scripts/release.sh v0.1.3            # signed + notarized (requires Developer ID cert in Keychain)
scripts/release.sh v0.1.3 --unsigned # skip signing (personal use)
```

The script builds a universal binary (arm64 + x86_64), packages `config/` as `config.zip`, and publishes both as assets on a new GitHub release. The `--unsigned` flag is for pre-Developer-ID releases; Gatekeeper will block unsigned binaries on other Macs.

See [docs/spec.md](docs/spec.md) for the full architecture and requirements.

## Philosophy

- macOS-only — full Apple API access (codesign, launchd, Keychain)
- No third-party Swift packages — every line is auditable
- OCI container images for dev toolchains live in separate repos, referenced by digest
- Threat model includes MCP servers and LLM agents, not just traditional software
