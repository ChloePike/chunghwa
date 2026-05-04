# 中華 · ChungHwa — macOS 上的 mihomo 原生客户端

一款 SwiftUI 桌面客户端，把 [mihomo](https://github.com/MetaCubeX/mihomo)
作为受管子进程拉起，并通过其 External Controller 的 HTTP + WebSocket API
驱动它。

![ChungHwa 概览](design/screenshots/overview.png)

## 缘起

我喜欢 [ClashMac](https://github.com/666OS/ClashMac) 的 UI，又想要
[Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) 的性能。
某个上午我的 ClashMac 崩溃了无数次后，ChungHwa 诞生了。

## 状态

自用为主，持续开发中。面向 Apple Silicon Mac + 较新 macOS（部署目标在
`ChungHwa.xcodeproj` 里跟最新 SDK 走，不锁 Sonoma 这种老底线）。
未签名、未公证、未发行——克隆、编译、运行。

## 亮点

- **十二屏 SwiftUI 主窗口**：概览 / 流量 / 连接 / 日志 / 拓扑 / 路由图 /
  代理 / 规则 / 提供方 / 配置 / 高级 / 设置
- **Bone & Brass 自定义主题**：字号、配色、卡片基元都在 `Core/Design/`，
  深 teal + brass + bone 调色板，跟随系统 light / dark 自适应
- **菜单栏 + 主窗口双形态**：关窗保留菜单栏常驻，退出才清内核 + 系统代理
- **完整的 mihomo 生命周期**：启动、停止、热重载、重启、子进程崩溃自恢复，
  状态机集中在 `Core/Kernel/KernelController.swift`
- **`/configs` 直连**：模式 / 日志级别 / allow-LAN / IPv6 / TCP 并发都
  PATCH 即生效，不重启内核
- **24 小时持久化流量历史**：内核重启 / app 重启都不丢
- **配置管理**：拖拽 yaml / 粘贴订阅 URL / 周期自动刷新 / 应用内 yaml
  编辑器；首次启动写一份 rule + DIRECT 兜底默认配置
- **TUN 模式**：`KernelPrivilegeHelper` 走 `osascript with administrator
  privileges` 一次 setuid root，gvisor 栈接管路由
- **自定义 DNS**：DoH / DoT / DoQ / UDP 自由组合，53 端口劫持开关，
  smart / system / fake-ip 三种 enhanced-mode
- **自定义路由**：DOMAIN-* / IP-CIDR / GEOIP / PROCESS-NAME → DIRECT /
  PROXY / REJECT / 任意组名（默认配置生效）
- **GeoIP 国旗**：连接表 region 列 + 概览的「直连 IP」「代理 IP」都带国旗，
  HTTPS 向 `ipwho.is` 查询，本地 JSON 缓存
- **节点延迟持久化**：写到 `~/Library/Application Support/ChungHwa/proxy-delays.json`，
  内核重启不丢测速结果
- **入站端口可改**：mixed-port 持久化，应用按钮一键 kernel restart +
  系统代理重新启用
- **系统集成**：一键系统代理、登录启动、隐藏 Dock 图标、关窗保持菜单栏
- **全局快捷键**：`⌘1`–`⌘9` 切 tab、`⌘R` 重载、`⇧⌘R` 重启内核、
  `⌘K` 聚焦搜索、`⇧⌘K` 清空日志

## 架构

```
ChungHwa.app  ──spawns──▶  mihomo 子进程
      │                          │
      └──── HTTP + WS  ──────────▶
            127.0.0.1:47913
```

App 是单进程、未沙盒化，独占 mihomo 的生命周期，通过 loopback 通讯。
目录划分：

- `Core/` — 非 UI 逻辑。Stores：`KernelController` / `ConfigStore` /
  `ProxyStore` / `RuleStore` / `ConnectionsStore` / `TrafficStore` /
  `TrafficHistoryStore` / `ProfileStore` / `SystemProxyController` /
  `NetworkStatusStore` / `GeoIPStore` / `NotificationCenterStore` /
  `AnonymousMode` / `LoginItemController`
- `Features/<Tab>/` — 每个 SwiftUI 屏一个目录
- `App/` — 顶层接线（入口、scenes、environment 注入）
- `Core/Design/` — 设计 token、共享组件、主题

Stores 都是 `@Observable` 单例，由 `MihomoAPIClient`（REST）+
`MihomoStreamClient`（traffic / memory / logs / connections 四路 WebSocket）
喂数据。`Features/` 里的 view 订阅 stores 保持声明式。

详细架构见 `docs/01-architecture.md`。

## 编译

1. 用 Xcode 打开 `ChungHwa.xcodeproj`
2. Apple Silicon Mac 必须（mihomo 按主机架构 fetch）
3. `⌘R`

第一次编译会跑 `scripts/fetch-mihomo.sh` 作为 pre-build phase，下载 mihomo
release 到 `Vendor/mihomo/`（gitignored）并嵌入
`ChungHwa.app/Contents/Resources/mihomo`。

命令行 build / 读 os_log 的姿势见 `CLAUDE.md`。

## 首次运行

1. 启动 app，内核自动跑起来，菜单栏图标出现
2. 打开 **配置** tab，拖一个 `config.yaml` 进来或粘贴订阅 URL（或者用
   首次启动自动生成的「默认配置」）
3. toolbar 翻 **系统代理** 开关，浏览器流量进 mihomo
4. 想用 TUN：**设置 → TUN 与权限 → 授权**，输入一次密码后内核以 root
   重启，TUN 即可工作

## mihomo 二进制管理

`Core/Kernel/KernelBinaryResolver.swift` 三层优先级挑：

1. **Custom**：用户在设置里手选的路径（UserDefaults `KernelCustomBinaryPath`）
2. **Managed**：应用内 *更新内核* 下载到
   `~/Library/Application Support/ChungHwa/kernel/mihomo`
3. **Bundled**：build 阶段由 `scripts/fetch-mihomo.sh` 拉好嵌入
   `ChungHwa.app/Contents/Resources/mihomo`

平时不用碰 mihomo；做内核调试时可以指向自己 build 的版本。

## 目录布局

```
ChungHwa/
├── ChungHwa/          App 源代码（Core/、Features/、App/、Core/Design/）
├── ChungHwa.xcodeproj
├── ChungHwaTests/     单元测试
├── ChungHwaUITests/   UI 测试
├── docs/              架构、mihomo 集成、模块、路线图
├── design/            UI 设计稿（HTML + JSX 参考）+ icons + screenshots
├── scripts/           Build phase 脚本（fetch-mihomo.sh）
└── Vendor/mihomo/     Gitignored，build 时填充
```

## 路线图

跟踪在 `docs/05-roadmap.md`。M0–M4 + M5+ 大半已完成。

## 致谢

- [mihomo](https://github.com/MetaCubeX/mihomo) — 真正的代理内核，
  所有路由 / 规则 / 协议都在那里发生
- [ClashMac](https://github.com/666OS/ClashMac) — UI 灵感来源，
  这个 app 一半的视觉决策都在有意呼应它的菜单栏 / 面板节奏
- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) —
  性能基准。哪里手感卡了，那就是没追上的那条线

## 许可证

GNU General Public License v3.0。完整文本见 [`LICENSE`](./LICENSE)。

ChungHwa 是自由软件：你可以在自由软件基金会发布的 GNU GPL v3 条款下
重新分发或修改它。本程序不附带任何担保，包括对适销性或针对特定用途
适用性的隐含担保。
