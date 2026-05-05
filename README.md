# 中華 · ChungHwa

A native macOS client for [mihomo](https://github.com/MetaCubeX/mihomo).

> [中文版](./README.zh-CN.md)

![ChungHwa Overview](design/screenshots/overview.png)

## Why

I liked [ClashMac](https://github.com/666OS/ClashMac)'s UI. I wanted
[Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev)'s
performance. After ClashMac decided one Tuesday morning that it would
crash 14 times in an hour, ChungHwa happened.

## Status

Self-use. Apple Silicon, recent macOS. Unsigned, unnotarized — clone,
build, run. If you grabbed a DMG from Releases and Gatekeeper yells:

```sh
xattr -dr com.apple.quarantine /Applications/ChungHwa.app
```

## What's in the box

- **Twelve screens** that you'll mostly never look at because the menu
  bar item knows what you want
- **A theme called "Bone & Brass on Patina"** because every project
  needs a precious name
- **Live everything** — traffic charts, connections, logs, GeoIP flags
  on every row, all streaming
- **TUN that actually works** — one password prompt, then transparent
  routing forever
- **DNS, routes, port, auth — all editable** without leaving the app or
  hand-writing yaml
- **Persistent across kernel restarts** — node delays, GeoIP cache,
  24 h traffic history all live in SQLite
- **Custom rules that don't care which subscription you're on** —
  injected above the source's own rules so they always win
- **Quick toggles in the menu bar** — system proxy, TUN, anonymous
  mode, mode switcher, group → node picker, all one click away
- **`⌘1`–`⌘9`** to flip tabs, `⌘R` to reload config, `⇧⌘R` to restart
  the kernel, `⌘K` to focus search, `⇧⌘K` to nuke logs

## Build

Open `ChungHwa.xcodeproj`, hit `⌘R`. The first build downloads mihomo
into `Vendor/mihomo/` (gitignored) and embeds it into the .app.

For a DMG:

```sh
./scripts/make-dmg.sh           # auto version
./scripts/make-dmg.sh 1.2.3     # override
```

Output lands in `build/`. CI does the same on tag push (see
`.github/workflows/release.yml`).

## First run

1. Launch — kernel starts, menu bar lights up. A working DIRECT-only
   default profile is already loaded so you don't have to do anything.
2. **Profiles** tab — drag a `config.yaml` in or paste a subscription
   URL.
3. **System proxy** chip in the toolbar. Browser flows through mihomo.
4. Want TUN? **Settings → TUN & Privileges → Authorize**. One password
   prompt grants the kernel binary `setuid root`; after that TUN
   transparently captures everything.

## Acknowledgements

- [mihomo](https://github.com/MetaCubeX/mihomo) — the actual proxy
  kernel doing the actual work
- [ClashMac](https://github.com/666OS/ClashMac) — UI inspiration
- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) —
  the performance bar this app is forever trying to clear

## License

GPL v3. See [`LICENSE`](./LICENSE).
