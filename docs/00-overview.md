# 00 · 项目概览

## 一句话定位

ChungHwa 是一款运行在 macOS 上、以 mihomo 为代理内核的图形化客户端，
为用户提供订阅管理、节点切换、规则查看、连接监控、流量统计等可视化能力，
并以菜单栏常驻 + 主窗口面板的形式融入 macOS 桌面工作流。

## 目标 (Goals)

1. **可用的 Clash 面板**：完整覆盖 mihomo External Controller API 暴露的能力（proxies / rules / connections / logs / traffic / configs / providers）。
2. **原生体验**：使用 SwiftUI 构建，遵循 macOS 的视觉、交互与系统集成约定（菜单栏、Sheet、Settings Scene、Notification、SF Symbols）。
3. **稳定的内核托管**：内核进程的启动、停止、崩溃自恢复、配置热重载、日志收集都由 App 主控，用户无需感知。
4. **订阅与配置管理**：订阅 URL 拉取、定时更新、流量信息解析、多配置切换、本地编辑兜底。
5. **系统代理 / TUN 模式**：一键开关系统代理；TUN 模式通过 PrivilegedHelper 提权以在不依赖 sudo 的前提下接管路由。
6. **可观测**：流量曲线、连接表、日志窗口实时刷新，性能开销可控。

## 非目标 (Non-Goals，至少 v1 不做)

- iOS / iPadOS 客户端（受限于 NetworkExtension 沙盒，需另起方案，留作 v2）
- 自研代理协议或自带规则集生态（直接复用 mihomo 与社区规则集）
- Web 端面板（如需远程控制，引导用户使用 yacd / metacubexd 接到同一 External Controller 即可）
- 商业化订阅商店、节点市场
- Windows / Linux 版本

## 参考产品与差异

| 产品 | 内核 | 平台 | 我们参考什么 | 与之差异 |
| --- | --- | --- | --- | --- |
| ClashX Pro | clash premium | macOS | 菜单栏交互、系统代理切换、轻量心智 | 内核切到 mihomo，UI 更现代化（SwiftUI / 卡片化） |
| Clash Verge Rev | mihomo / clash | 跨平台 (Tauri) | 功能完备度（profiles、rules、connections） | 原生 SwiftUI，避免 webview 性能与观感损失 |
| Stash | sing-box / 自研 | macOS / iOS | 视觉设计、节点卡片 | 开源 + 社区内核，无订阅成本 |
| metacubexd / yacd | — | Web 面板 | API 调用模式、视图组织 | 桌面应用、负责内核生命周期 |

## 用户画像

- **P0 主用户**：熟悉 Clash 生态、有订阅链接、追求 macOS 原生体验的开发者 / 极客。
- **P1 用户**：从 ClashX 等老客户端迁移过来、想要更现代界面的存量用户。
- **P2 用户**：完全不懂 Clash 的新手 —— v1 不做引导，但 UI 措辞尽量保留可理解性。

## 命名

- 项目代号 / 应用名：**ChungHwa**（中華）— 已确认
- Bundle ID：`com.tzaigroup.chunghwa`（基于现有邮箱默认；自用，无外部分发顾虑）
- 内核可执行：随发行版打包的 `mihomo` binary（位于 App Bundle `Contents/MacOS/mihomo`）

## 分发模型

**自用为主，不发行商店、不公证。** 决策来自：作者暂无 Apple Developer Program 账号。
具体影响：
- Xcode 用 Personal Team 自动签名即可
- mihomo 子 binary 用 ad-hoc (`codesign -s -`) 签
- 不开 Sandbox，不做 notarization，不做 DMG 打包流水线
- 用户首次启动若被 Gatekeeper 拦，自己 `xattr -dr com.apple.quarantine` 解决
- 后续若有发行需求，再补回签名 / 公证脚本（保留在 `scripts/` 但默认不挂入 build）
