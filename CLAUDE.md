# ChungHwa — Notes for Claude

## Workflow

- **每一次变更都需要 commit + push，不必再问**。完成一组连贯改动后立即 `git add` → commit → `git push origin main`。
- 沟通用中文；代码、commit message、文件名用英文。
- 不在 `main` 上做 force push 或 reset --hard。
- 用 conventional-style 简短 commit title（< 70 字符），正文写「为什么」。

## 项目概览

macOS SwiftUI 客户端，mihomo 作为子进程通过 External Controller (HTTP+WebSocket) 控制。
详细设计 / 路线图见 `docs/`，UI 设计原型见 `design/`（React JSX 参考）。

## 内核二进制

三层优先级（见 `Core/Kernel/KernelBinaryResolver.swift`）：

1. **custom** — 用户在设置里手选的路径（UserDefaults：`KernelCustomBinaryPath`）
2. **managed** — 应用内 "Update kernel" 下载到 `~/Library/Application Support/ChungHwa/kernel/mihomo`
3. **bundled** — Pre-build phase `Embed mihomo` 拉取并嵌入 `.app/Contents/Resources/mihomo`，由 `scripts/fetch-mihomo.sh` 写到 `Vendor/mihomo/`（gitignored）

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
