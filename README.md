# ChungHwa · macOS native client for mihomo

A SwiftUI desktop client that runs [mihomo](https://github.com/MetaCubeX/mihomo) as a managed
child process and drives it through its External Controller HTTP + WebSocket API.

## Status

Self-use, in active development. Built for Apple Silicon Macs on a recent macOS
(deployment target lives in `ChungHwa.xcodeproj`; the project tracks the latest
SDK rather than pinning a Sonoma-era floor). Not signed, not notarized, not
distributed — clone, build, run.

## Highlights

- **12-screen SwiftUI UI** — Overview, Traffic Stats, Connections, Logs, Topology,
  Route Map, Proxies, Rules, Providers, Profiles, Advanced, Settings.
- **Custom Bone & Brass theme** — typography, color tokens and reusable card
  components live in `Core/Design/`.
- **Menubar app + main window** — close the window and the app keeps living in
  the menubar; quitting cleans up the kernel and system proxy.
- **Full mihomo lifecycle** — start, stop, reload, crash-recovery, hot config
  swap. Kernel state machine is in `Core/Kernel/KernelController.swift`.
- **Live `/configs` wiring** — mode, log level, allow-LAN, IPv6, tcp-concurrent
  flip on the running kernel without restart.
- **Persistent 24 h traffic history** — survives kernel restarts and app relaunch.
- **Profiles** — drag-drop YAML import, paste-a-URL subscriptions with automatic
  periodic refresh, in-app YAML viewer/editor.
- **System integration** — one-click system proxy on/off, launch-at-login,
  hide-Dock-icon, close-window-keeps-menubar-running.
- **Global shortcuts** — `⌘1`–`⌘9` jump between tabs, `⌘R` reload config,
  `⌘K` focus filter, `⌘⇧K` clear logs.

## Architecture

```
ChungHwa.app  ──spawns──▶  mihomo child process
      │                          │
      └──── HTTP + WS  ──────────▶
            127.0.0.1:47913
```

The app is a single non-sandboxed process that owns the mihomo binary's
lifecycle and talks to it over loopback. Layout:

- `Core/` — non-UI logic. Stores: `KernelController`, `ConfigStore`,
  `ProxyStore`, `RuleStore`, `ConnectionsStore`, `TrafficStore`,
  `TrafficHistoryStore`, `NotificationCenterStore`, `ProfileStore`,
  `SystemProxyController`, `AnonymousMode`, `LoginItemController`.
- `Features/<Tab>/` — one folder per SwiftUI screen.
- `App/` — top-level wiring (entry point, scenes, environment injection).
- `Core/Design/` — design tokens, shared components, theme.

Stores are `@Observable` singletons fed by `MihomoAPIClient` (REST) and
`MihomoStreamClient` (WebSocket streams: traffic, memory, logs, connections).
ViewModels in `Features/` subscribe to stores; views stay declarative.

See `docs/01-architecture.md` for the long version.

## Building from source

1. Open `ChungHwa.xcodeproj` in Xcode.
2. Apple Silicon Mac required (mihomo is fetched per-host arch by the build
   phase).
3. Hit `⌘R`.

The first build runs `scripts/fetch-mihomo.sh` as a pre-build phase. It
downloads a mihomo release binary into `Vendor/mihomo/` (gitignored) and
embeds it into `ChungHwa.app/Contents/Resources/mihomo`.

For headless builds and the os_log reading recipe, see `CLAUDE.md`.

## First run

1. Launch the app — kernel starts, menubar icon appears.
2. Open the **Profiles** tab and either drag a `config.yaml` into the window
   or paste a subscription URL.
3. Flip **System Proxy** on from the toolbar. Browser traffic now flows through
   mihomo.

## Mihomo binary management

`Core/Kernel/KernelBinaryResolver.swift` picks a binary in this order:

1. **Custom** — a path the user picked in Settings
   (UserDefaults key `KernelCustomBinaryPath`).
2. **Managed** — downloaded by the in-app *Update kernel* action to
   `~/Library/Application Support/ChungHwa/kernel/mihomo`.
3. **Bundled** — fetched at build time by `scripts/fetch-mihomo.sh` and
   shipped inside `ChungHwa.app/Contents/Resources/mihomo`.

This means you can develop without ever touching mihomo manually, but you can
also point the app at your own build during kernel work.

## Project layout

```
ChungHwa/
├── ChungHwa/          App source (Core/, Features/, App/, Core/Design/)
├── ChungHwa.xcodeproj
├── ChungHwaTests/     Unit tests
├── ChungHwaUITests/   UI tests
├── docs/              Architecture, mihomo integration, modules, roadmap
├── design/            UI mockups (HTML + JSX reference)
├── scripts/           Build-phase scripts (fetch-mihomo.sh)
└── Vendor/mihomo/     Gitignored — populated at build time
```

## Roadmap

Tracked in `docs/05-roadmap.md`.

- **M0 · Skeleton** — kernel lifecycle, API smoke test. Done.
- **M1 · MVP main window** — proxies, logs, settings, system proxy, menubar. Done.
- **M2 · Live streams** — connections, traffic chart, log stream, rules. Done.
- **M3 · Subscriptions & profiles** — URL subscriptions, auto-refresh,
  CoreData-backed profile store, login item. Done.
- **M4 · Polish** — design system rebuild, theming, YAML editor, app icon.
  In progress.
- **M5+** — TUN mode via privileged helper, real GeoIP, per-process
  attribution, iOS exploration.

## Acknowledgements

Built on top of [mihomo](https://github.com/MetaCubeX/mihomo) — all of the
actual proxying happens there.
