# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-05-05

First public release. Self-use, unsigned ad-hoc build, three DMGs
(universal / arm64 / x86_64).

### Added

- Twelve-screen SwiftUI window — Overview, Connections, Logs, Topology,
  Proxies, Rules, Profiles, Advanced, Settings.
- Menu-bar item — quick toggles (system proxy / TUN / anonymous),
  mode picker, group → node picker (left-side popover), profile
  switcher, live ↑/↓ rate readout.
- Full mihomo lifecycle — spawn / hot-reload / cold restart / crash
  recovery / orphan cleanup.
- TUN mode — one-shot setuid-root via `osascript with administrator
  privileges`; gvisor stack with `auto-route` + `auto-detect-interface`.
- Custom DNS editor (DoH / DoT / DoQ / UDP), `enhanced-mode` picker,
  port-53 hijack toggle. Editor is effective on the default profile
  and any user yaml without a `dns:` block.
- Custom routing rules — DOMAIN-* / IP-CIDR / GEOIP / PROCESS-NAME →
  DIRECT / PROXY / REJECT / group. Spliced above the subscription's
  own rules so they always win.
- Configurable mixed-port (HTTP + SOCKS5) — kernel restarts and the
  system proxy re-applies at the new port.
- Inbound proxy authentication and a system-proxy bypass list.
- Profile management — file / drag-and-drop / URL subscription with
  periodic refresh / in-app YAML editor / a working DIRECT-only
  default that ships on first launch.
- GeoIP — region column on the connections grid + flag emoji on
  direct / proxy IPs in Overview, via `api.country.is`.
- Live traffic chart (1 / 5 / 15 min) with session totals + today's
  cumulative.
- Per-connection live up/down rate (derived from successive snapshots).
- Persistent node delays — `testGroup` results survive kernel restarts.
- 24 h traffic history, persistent across kernel + app restarts.
- macOS Notification Center for warning / error events.
- Login item, hide-Dock-icon, close-window-keeps-running options.
- Shortcuts — `⌘1`–`⌘9` switch tabs, `⌘R` reload, `⇧⌘R` restart
  kernel, `⌘K` focus search, `⇧⌘K` clear logs.
- GitHub Actions release workflow — tag push produces three DMGs
  (universal / arm64 / x86_64) and a `SHA256SUMS.txt`.

### Storage

- SQLite at `~/Library/Application Support/ChungHwa/data.sqlite`
  (WAL, `synchronous=NORMAL`) for proxy delays, GeoIP cache, and
  per-minute traffic history. Old per-store JSON files import once
  on first launch with the new build, then get deleted.
- UserDefaults under `ChungHwa.*` is the single source of truth for
  mixed-port / TUN / DNS / custom-rules / proxy-auth / bypass list.
  Composer, system-proxy applier, and network probes all read the
  same keys.

### Performance

- ChDot pulse moved off `TimelineView(.animation)` onto Core Animation
  — idle CPU 23 % → ~5 %.
- Status bar / Overview / Menubar split into per-store leaf subviews
  so 1 Hz traffic samples don't re-render whole screens.
- `KernelController.terminationHandler` filters stale exit callbacks
  (`process === proc`) — fixes the "kernel reported dead after restart"
  bug on TUN toggle.
- `KernelPrivilegeHelper.grantPrivileges` runs off-main so
  `Process.waitUntilExit()` doesn't freeze the UI during the password
  prompt.
- 250 ms `ConnectionsStore` coalescing; 500 ms `TrafficStore` totals
  flush.

### Distribution notes

- Unsigned, unnotarized. Gatekeeper will quarantine the `.app` on
  first download. Right-click → Open, or
  `xattr -dr com.apple.quarantine /Applications/ChungHwa.app`.
- TUN needs the kernel binary to run as root. **Settings → TUN &
  Privileges → Authorize** does this once via `osascript`.

[Unreleased]: https://github.com/ChloePike/chunghwa/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ChloePike/chunghwa/releases/tag/v0.1.0
