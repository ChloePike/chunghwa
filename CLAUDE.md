# ChungHwa — Notes for Claude

## Workflow

- **每一次变更都需要 commit + push，不必再问**。完成一组连贯改动后立即 `git add` → commit → `git push origin main`。
- 沟通用中文；代码、commit message、文件名用英文。
- 不在 `main` 上做 force push 或 reset --hard。
- 用 conventional-style 简短 commit title（< 70 字符），正文写「为什么」。
- **不要 `pkill` ChungHwa**。mihomo 是 ChungHwa 的子进程，杀父进程会
  连带杀掉 mihomo + 当前所有 connections。改动只 build，不重启 app；
  让用户自己手动 quit + 重开。如果一定要重启进程，用 app 内的
  「重启内核」（⇧⌘R）只重启 mihomo。

## 项目概览

macOS SwiftUI 客户端，mihomo 作为子进程通过 External Controller (HTTP+WebSocket) 控制。
详细设计 / 路线图见 `docs/`，UI 设计原型见 `design/`（React JSX 参考），
图标 / 品牌素材源文件在 `design/icons/`。

## 内核二进制

三层优先级（见 `Core/Kernel/KernelBinaryResolver.swift`）：

1. **custom** — 用户在设置里手选的路径（UserDefaults：`KernelCustomBinaryPath`）
2. **managed** — 应用内 "Update kernel" 下载到 `~/Library/Application Support/ChungHwa/kernel/mihomo`
3. **bundled** — Pre-build phase `Embed mihomo` 拉取并嵌入 `.app/Contents/Resources/mihomo`，由 `scripts/fetch-mihomo.sh` 写到 `Vendor/mihomo/`（gitignored）

## TUN 提权

TUN 模式需要 mihomo 进程 euid=0 才能创建 utun。`KernelPrivilegeHelper`
通过 `osascript ... with administrator privileges` 直接 `chown root:wheel`
+ `chmod u+s` 当前 active 二进制（一次授权终身有效，可 `chmod u-s` 撤销）。
设置 → TUN 与权限 暴露这个动作。

## YAML 合成

`Core/Profiles/ConfigComposer.swift` 把用户 yaml 跟 App 持久化的设置
（mixed-port / TUN / DNS / 自定义规则）合并成最终 yaml 喂给内核。
策略是「撕掉用户冲突 key 再追加我们的」——mihomo 严格不允许重复 key。

UserDefaults 单一事实源：

- `ChungHwa.MixedPort`（Int）
- `ChungHwa.TunEnabled`（Bool）
- `ChungHwa.DNS.Nameservers` / `ChungHwa.DNS.Fallback`（[String]）
- `ChungHwa.Advanced.DNSMode` / `ChungHwa.Advanced.DNSHijack`
- `ChungHwa.CustomRules`（JSON-encoded `[CustomRule]`）

`ConfigStore` 提供 `static currentMixedPort` / `currentDNS()` /
`currentCustomRules()` 静态访问器，composer + 探针 + UI 共用同一份。

## 常用命令

构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ChungHwa.xcodeproj -scheme ChungHwa \
  -configuration Debug -destination 'platform=macOS' build
```

跑（命令行 launch，不弹 Dock）：

```sh
"$(DerivedData)/Build/Products/Debug/ChungHwa.app/Contents/MacOS/ChungHwa"
```

读 os_log（kernel / binary / downloader）：

```sh
log show --predicate 'subsystem == "com.tzaigroup.chunghwa"' --last 5m --info --debug --style compact
```
