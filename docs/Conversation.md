This is a genuine architectural inflection point. Let me give you a structured take on the key decisions, because they're actually interconnected.

The Core Tension
You're describing two separable concerns that have been living in the same repo:

Host OS management layer — bootstrap, backup, PATH, launchd, approved-list monitoring
Dev toolchain — LaTeX, Node/Python AI tools, Go CLIs
The insight you're circling is: these have different threat models and different portability requirements. Splitting them cleanly is the right move.

The Architectural Direction I'd Recommend
Management layer → Single signed Swift CLI
Yes to Swift here. Reasons:

Apple frameworks only (Foundation, System, Security, Virtualization) — no third-party deps, no npm/pip attack surface
Native code signing + notarization from day one, distributed via signed GitHub releases
launchd integration via ServiceManagement.framework (register agents programmatically, no manual plist wrangling)
Can check Keychain, read system state, call codesign/spctl to verify installed software against an approved list — this is the JAMF-lite path, entirely in Apple APIs
GitHub Actions can build, sign, notarize, and publish in one pipeline
Linux portability doesn't matter for the management layer — that's the key insight. If you're on Linux, you're in a container or on a server, and the management problem is different. Don't let the Linux case constrain the macOS solution.

Dev toolchain → Apple Containers / Container Machines
Yes to containers for tools like LaTeX, Node, Python. Your latex-image experiment is exactly right. The philosophy becomes:

Host OS stays pristine: no Homebrew into the host, no global npm, no pip install into system Python
Each tool category is an OCI image you maintain: latex-image, node-ai-image, etc.
The Swift CLI manages these — starts the container, mounts the relevant volume, runs the tool, exits
Commands like buildtex become mgr run latex -- pdflatex thesis.tex rather than a bash script
This is actually more secure than the current approach because the npm/pypi attack surface is contained (literally), and you control what goes into the image.

The chicken-and-egg problem: the container CLI itself is still developer preview and needs to be installed somehow. Short-term: download the Apple-signed binary directly. Long-term: this likely ships with macOS or Xcode.

The Tricky Questions
Should backup also go into the Swift CLI?

Yes. The Go backup port you started is evidence you already felt the bash version was reaching its limits. Swift gives you FileManager, URLSession for remote backup, and direct access to the Security framework for verifying backup integrity. The rsync dependency can stay (it's an Apple-supplied binary), called via Process.

Should there be a GitHub Actions CI pipeline?

Yes, for two things:

Build + notarize the Swift CLI and publish a signed release binary
Validate container image builds on push (so your latex-image is always in a known-good state)
JAMF-lite / approved list monitoring?

A mgr doctor subcommand that:

Reads a approved.plist from the repo
Walks /Applications, checks codesign validity and team IDs
Checks running launchd agents against your declared set
Reports drift
This is maybe 200 lines of Swift using FileManager + a Process wrapper around codesign. No third-party deps needed.

What I'd NOT Do
Don't make the Swift CLI cross-platform — you'll compromise the Apple API access that makes it powerful
Don't eliminate Bash entirely — thin glue scripts calling the Swift CLI are fine and easier to read/audit than building a full TUI in Swift
Don't rush to rewrite everything at once — the Swift CLI can start as a wrapper around the existing bash scripts and absorb them one subcommand at a time
Proposed Structure

utilities/
├── Sources/mgr/          # Swift CLI (the new core)
│   ├── Commands/
│   │   ├── Bootstrap.swift    # install, linklocal, launchd agents
│   │   ├── Backup.swift       # replaces scripts/backup
│   │   ├── Doctor.swift       # drift / approved-list checks
│   │   └── Container.swift    # manages Apple container images
│   └── main.swift
├── Package.swift
├── containers/           # OCI image definitions
│   ├── latex/
│   └── node-ai/
├── config/
│   ├── approved.plist    # approved apps + team IDs
│   ├── backup.plist      # drive mappings
│   └── packages.plist    # brew packages (or Brewfile)
├── launchd/              # single consolidated plist dir
└── .github/workflows/
    ├── build-sign-release.yml
    └── container-images.yml
The One Thing to Decide First
What's the bootstrap story? If the Swift CLI is the management layer, something has to install it before it can install everything else. Options:

A single curl | sh bootstrap that downloads the signed binary from GitHub releases and verifies the signature before running
A minimal bash bootstrap (setup.sh) that only does one thing: download and install the Swift CLI, then hand off
Option 2 is safer — the bash surface is tiny and auditable, and everything after that is the signed binary.

Want me to sketch out the Swift CLI structure in more detail, or start with the GitHub Actions pipeline for build/sign/notarize? The Package.swift + argument parser setup (using only Swift stdlib, no ArgumentParser library) would be a natural first step.

There is another thing to consider now, LLMs+Agents. MCP is a thing which needs to be monitored, and I wonder whehter something like `mgr doctor` needs to monitor the running processes and reports anything not approved and terminates it and puts the process on a whitelist. 

I don't think these oci images should be stored in the repo. the deserve their own repos and update/patching schedules right? 
├── containers/           # OCI image definitions
│   ├── latex/
│   └── node-ai/

---
Hmmm, so what's best in class for macos laptop initial setup when you can't burn a jamf-lite agent into the os layer? A README.md documeninting a `single curl | sh bootstrap` that downloads the signed binary from GitHub releases and verifies the signature before running the laptop setup? which installs apps like vscode/antigravity, vscode extensions, MSword documents, other things like xcode cli tools, mgr/monitoring agent.
These are three distinct but connected decisions. Let me address each directly.

1. LLMs + Agents + MCP Monitoring
This is actually one of the most important additions to the threat model. The attack surface has shifted:

MCP servers are persistent processes with filesystem/network access, typically installed via npm (attack vector) or configured in ~/.claude/settings.json, ~/.cursor/, etc.
An agent can be prompt-injected into installing something that persists
The process looks legitimate (it's node, it's python) but the payload is not
So mgr needs two modes here:

mgr doctor — on-demand audit

Walks ~/Library/LaunchAgents, /Library/LaunchDaemons, ~/Library/Application Support/Claude/, ~/.cursor/, ~/.config/ etc.
For every process/agent found: codesign --verify + check team ID against approved.plist
Reports drift as a diff: what's new, what's changed, what's unrecognized
Does NOT auto-terminate — you want human confirmation for a first-pass audit
mgr monitor — background launchd agent

Polls on an interval (every 60s, low overhead)
Detects new entries in LaunchAgents dirs and MCP config files
On detection: sends a macOS notification, logs to a structured file, optionally terminates the process and quarantines the plist
Whitelist is a signed approved.plist — adding to it requires running mgr approve <process> which logs the approval with a timestamp
The whitelist model for MCP specifically:


# approved.plist entry for an MCP server
{
  "name": "filesystem-mcp",
  "path": "/usr/local/bin/filesystem-mcp",
  "teamID": "APPLE_TEAM_ID",
  "sha256": "abc123...",
  "approvedBy": "sholto",
  "approvedAt": "2026-06-20T10:00:00Z"
}
This is doable with Foundation + Process without EndpointSecurity.framework (which requires a System Extension entitlement and user approval pop-ups). Polling via launchctl list + ps + file system watchers (DispatchSource.makeFileSystemObjectSource) is sufficient for a personal tool.

2. OCI Images → Separate Repos
Correct. Each image is its own concern:


github.com/sholtomaud/container-latex     # academic LaTeX toolchain
github.com/sholtomaud/container-node-ai   # AI/LLM tooling (node, coedit etc.)
github.com/sholtomaud/container-python    # docling, md2docx
Each gets:

Its own GitHub Actions: build → scan (Trivy) → publish to GHCR → tag with digest
Its own semver + changelog
Security scanning on a schedule, not just on push
The main utilities repo references them pinned by digest in a containers.plist:


<key>latex</key>
<dict>
  <key>image</key>
  <string>ghcr.io/sholtomaud/container-latex</string>
  <key>digest</key>
  <string>sha256:abc123...</string>
</dict>
mgr update containers pulls the latest approved digest and updates this file. No floating latest tags.

3. Best-in-Class macOS Bootstrap Without MDM
The honest answer: without burning an MDM profile into the OS layer, you can't fully automate everything. Some things (system extensions, kernel extensions, full-disk access grants) require human clicks. The best you can do is make those steps explicit and minimal.

The gold standard pattern for personal/team use is:

Stage 0 — The single URL in the README

curl -fsSL https://github.com/sholtomaud/utilities/releases/latest/download/install.sh | sh
install.sh is tiny, vendored into the release, and does only three things:

Verifies macOS version + architecture
Installs Xcode CLI tools (xcode-select --install + wait loop)
Downloads the signed+notarized mgr binary, verifies with codesign --verify --deep before executing anything
Stage 1 — mgr bootstrap
The signed binary takes over. Subcommands run in order:


mgr bootstrap
  └── mgr bootstrap system      # defaults write, hostname, etc.
  └── mgr bootstrap apps        # download + verify DMGs/PKGs from approved sources
  └── mgr bootstrap packages    # Brewfile OR container-based installs
  └── mgr bootstrap dotfiles    # symlinks, shell config
  └── mgr bootstrap agents      # install launchd agents (backup, monitor)
  └── mgr bootstrap dev         # xcode-select, SSH key, git config
Each step is idempotent and reports status — so re-running on an existing machine just shows "already done" for completed steps.

What can't be automated (document these as manual steps in README)
Full Disk Access grants (System Settings > Privacy)
Accessibility permissions
Microsoft Word / Office (requires Apple ID or volume license — open a downloaded PKG is the best you can do)
Xcode (too large; mas install 497799835 via MAS or manual)
Apple ID sign-in
The monitoring agent installs itself
mgr bootstrap agents registers com.mgr.monitor.plist via SMAppService (Swift, no manual launchctl load), so monitoring starts immediately after bootstrap and survives reboots.

The Full Picture

README.md
  └── curl install.sh
        └── mgr (signed binary, GitHub release)
              ├── mgr bootstrap      # one-time machine setup
              ├── mgr doctor         # on-demand audit
              ├── mgr monitor        # background daemon (self-installs)
              ├── mgr backup         # replaces scripts/backup
              ├── mgr restore
              ├── mgr approve <pid>  # add to whitelist
              └── mgr update         # update mgr itself + container digests

Separate repos:
  container-latex / container-node-ai / container-python
  (referenced by digest in config/containers.plist)
The thing worth noting: this is now closer to what Kolide or Kandji sell as a product. You'd be building the personal/open-source equivalent — which is actually more appropriate given the no-third-party-libs constraint means you can audit every line.

Want to start with the Package.swift + CLI skeleton for mgr, or the install.sh bootstrap script + GitHub Actions release pipeline first? The release pipeline is probably the right foundation since everything else depends on being able to ship a signed binary.

I think we should start this project in a fresh repo and archive the utilities repo. If you agree with this please suggest a name for the repo, I will create a new folder and then generate the full overview and functional requirements for the swift cli & bash scripting for the best in class personal/open-source equivalent to Kolide or Kandji. we will be using vscode as our coding interface (not xcode) so we will need to use the xcode cli tools to build and test our swift cli code.
Agreed — clean break is the right call. The utilities repo becomes a historical archive; the new repo starts with intent baked in from day one.

Name Suggestions
keel — my top pick.

The keel is the structural backbone of a ship: it keeps the vessel stable, properly oriented, and on course. Metaphorically exact — it's what keeps your Mac stable after bootstrap, monitored, and recoverable. The subcommands read naturally:


keel bootstrap
keel doctor
keel monitor
keel backup
keel restore
keel approve
keel update
Single word, no conflicts with major projects, domain available, not OS-specific in its meaning (though the implementation is).

Alternatives if keel doesn't land:

Name	Rationale
vigil	Watchfulness — leans into the monitoring angle
aegis	Shield/protection — strong security connotation
bulwark	Defense + stability, slightly more dramatic
steward	Manages resources on behalf of the owner — accurate but softer
keel is my recommendation. Once you've created the folder and initialized the repo, I'll generate the full overview and functional requirements document covering:

Project philosophy + constraints
Binary architecture (keel CLI subcommand tree)
Bootstrap sequence + install.sh design
Monitoring subsystem (process whitelist, MCP/agent detection, launchd scanning)
Backup/restore spec
Container image reference model (separate repos, digest pinning)
GitHub Actions pipeline (build, sign, notarize, release)
VSCode + Xcode CLI toolchain setup
Configuration schema (approved.plist, backup.plist, containers.plist)
What's the name — keel, or one of the others?

what about `captain|capt` or `mgr|manager`? your choice, shorter the better.
capt.

3 reasons:

Shortest usable form (4 chars vs mgr's 3, but mgr has no identity)
Captain implies authority and command — accurate for a tool that controls, monitors, and approves what runs on your machine
Pairs cleanly with keel as the repo name if you want to keep that: the keel is the structure, the captain commands it
Subcommands read naturally:


capt bootstrap
capt doctor
capt monitor
capt backup
capt restore
capt approve
capt update
Repo: keel, binary: capt.

Create the folder whenever you're ready and I'll generate the full spec.

lets use `mgr`.
mgr it is — short, unambiguous, no metaphor baggage.

Repo: mgr, binary: mgr.


mgr bootstrap
mgr doctor
mgr monitor
mgr backup
mgr restore
mgr approve
mgr update
Create the folder and repo when ready and I'll generate the full overview and functional requirements.

> ok I've created the ~/Development/mgr folder.