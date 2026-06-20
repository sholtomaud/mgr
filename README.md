# mgr

Personal macOS management CLI. The open-source, auditable equivalent of Kolide or Kandji for individual use.

**Single signed Swift binary. No third-party dependencies. No Homebrew on the host.**

```
mgr bootstrap   # one-time machine setup
mgr doctor      # on-demand audit (apps, launchd agents, MCP servers)
mgr monitor     # background daemon — detects and alerts on unauthorized processes
mgr backup      # rsync-based backup
mgr restore     # restore from backup
mgr approve     # add a process/app to the whitelist
mgr update      # update mgr itself or pinned container image digests
```

## Quick start (once a signed release exists)

```sh
curl -fsSL https://github.com/sholtomaud/mgr/releases/latest/download/install.sh | sh
```

`install.sh` verifies the code signature before executing anything, then hands off to `mgr bootstrap`.

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
swift test
```

See [docs/spec.md](docs/spec.md) for the full architecture and functional requirements.

## Philosophy

- macOS-only — full Apple API access (codesign, launchd, SMAppService, Keychain)
- No third-party Swift packages — every line is auditable
- OCI container images for dev toolchains live in separate repos, referenced by digest
- Threat model includes MCP servers and LLM agents, not just traditional software
