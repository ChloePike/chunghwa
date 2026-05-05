# 05 · 路线图

> 状态：v0.1.0 已发布，自用版本日常可用。M0–M5 全部落地，M6 也已完成。

## M0 · 骨架与冒烟 ✅

- [x] Xcode 项目结构 + asset catalog
- [x] `scripts/fetch-mihomo.sh`：从 GitHub release 拉两架构 binary 并 lipo
- [x] Build Phase：在 Copy Bundle Resources 之前下载 + 拷贝 + 签名 mihomo
- [x] `KernelController` 状态机
- [x] `MihomoAPIClient.version()` 跑通

## M1 · MVP 主窗口 ✅

- [x] NavigationSplitView 主框架（Overview / Connections / Logs / Topology / Proxies / Rules / Profiles / Advanced / Settings）
- [x] Profiles：本地 yaml + URL 订阅 + iCloud Drive 三种存储
- [x] Proxies：组列表 + 节点列表 + 单击切换 + 一键测速
- [x] 日志窗口（`/logs` WS）
- [x] 菜单栏 SwiftUI 弹窗（`MenuBarExtra(.window)`）
- [x] `SystemProxyController` 走 `SCPreferences` + AuthorizationCreate
- [x] 退出钩子杀子进程 + 清系统代理

## M2 · 流式可视化 ✅

- [x] `MihomoStreamClient`（traffic / memory / connections / logs 全部 WebSocket）
- [x] Connections 表格 + 过滤 + 关闭 + per-conn 实时速率（store 端 diff）
- [x] Traffic 上下行曲线（Swift Charts，1/5/15 min 范围切换）
- [x] Logs WS 替换 ringbuffer
- [x] Rules 列表 + provider 标识
- [x] 出站模式切换（Rule / Global / Direct）
- [x] 单组 / 全部 测速

## M3 · 订阅与 Profile ✅

- [x] Profile / Subscription 模型 + JSON 元数据
- [x] URL 订阅 add / refresh / delete
- [x] `subscription-userinfo` header 解析
- [x] Profiles Tab 卡片 + 一键更新
- [x] 自动定时更新（默认 24h，UserDefaults 可调）
- [x] 启动项 `LoginItemController`（SMAppService）
- [x] 默认配置兜底：首次启动写一份 rule + DIRECT 最小 yaml
- [x] iCloud Drive 存储模式

## M4 · 抛光 ✅

- [x] DesignSystem：Bone & Brass on Patina
- [x] light / dark adaptive 调色板
- [x] yaml 编辑器（CodeEdit-style + 异步缓存）
- [x] AppIcon（`AppIcon.appiconset` PNG 全套）+ 菜单栏 PNG
- [x] 关于卡 / 入站端口 / 在 Finder 中打开等设置项
- [x] 性能：`ChDot` 改 CoreAnimation、所有 1Hz 数据走叶子订阅、StatusBar / Overview / Menubar 全拆叶子；待机 CPU 23% → ~5%
- [x] 文案全局清洗（去 AI 味）
- [x] 视图拆分：四个超长 view 文件拆成 14 个单一职责文件

## M5 · 进阶 ✅

- [x] **TUN 模式**：`KernelPrivilegeHelper` 一次 setuid root，gvisor 栈 + auto-route + auto-detect-interface
- [x] **DNS 设置 UI**：`DNSEditorSheet` 主上游 + 兜底（DoH / DoT / DoQ / UDP），enhanced-mode (system / smart / fake-ip)，53 端口劫持开关真接到 yaml
- [x] **自定义路由**：`RoutingEditor` 跨 profile 通用——splice 在 user yaml 的 `rules:` 之前永远先匹配
- [x] **GeoIP 国旗**：Connections 地区列 + Overview 直连 IP / 代理 IP 都带国旗（`api.country.is` HTTPS）
- [x] **入站端口可配置**：mixed-port 持久化，应用按钮链 `kernel.restart` + 系统代理重新启用
- [x] **网络状态卡**：互联网 / DNS / 路由 + 直连 IP / 代理 IP
- [x] **代理认证 + 系统代理 bypass list**：UI 接 ConfigComposer + SystemProxyController
- [x] **`unified-delay` 真接通**：从死 UI 改成 yaml 注入 + restart
- [x] **macOS 系统通知**：warning / error 级别同步给 `UNUserNotificationCenter`
- [x] **系统代理一次提权**：`AuthorizationRef` 缓存到 controller 生命周期，不再每次切换都弹窗
- [x] **kernel termination race fix**：`process === proc` 守卫——治了 TUN 重启后内核被误判崩溃的 bug

## M6 · 自我托管 + 分发 ✅

- [x] SQLite 数据层（`Core/Storage/Database.swift`，WAL + `synchronous=NORMAL`）替代 proxy-delays.json / geoip-cache.json / traffic-history.json，首次启动一次性导入旧 JSON 再删
- [x] UserDefaults 单一事实源（`ChungHwa.MixedPort` / `ChungHwa.TunEnabled` / `ChungHwa.DNS.*` / `ChungHwa.CustomRules` / `ChungHwa.Advanced.*`），composer + 探针 + UI 都从同一处读
- [x] 身份脱敏：log subsystem 改成中性 `org.clash.ChungHwa`，删 `DEVELOPMENT_TEAM`，git 历史 author 全部改 Claude
- [x] DMG 打包脚本 `scripts/make-dmg.sh`（ad-hoc 签名、UDZO 压缩、`/Applications` 拖装符号链接）
- [x] GitHub Actions release workflow：tag push (`v*`) → 三 DMG (universal / arm64 / x86_64) + SHA256SUMS 自动挂到 Release
- [x] CHANGELOG.md（Keep a Changelog 格式）
- [x] `.github/PULL_REQUEST_TEMPLATE.md` + `ISSUE_TEMPLATE/{bug_report, feature_request, question, config}.yml`
- [x] Repo label 集（type / status / area / subsystem 四类共 35 个）
- [x] 双语 README：默认英文，`README.zh-CN.md` 中文，README 顶部互相引用
- [x] GPL v3 LICENSE
- [x] 单元测试：ConfigComposer / ConfigStore / ConnectionsStore / GeoIPStore / ProxyStore / TrafficStore / TrafficHistoryStore（部分基于 Database 注入路径）

## 没做 / 不打算做

- [ ] **iOS 探索**——要 NetworkExtension，本质上是另一个项目
- [ ] **Web Dashboard 内嵌**——用户自己开 yacd / metacubexd 接同一个 External Controller 即可
- [ ] **公证**——自用版本不上架 / 不发行，不付 $99/yr Apple Developer Program；下载者第一次开需要 `xattr -dr com.apple.quarantine`
- [ ] **沙盒化**——要把 mihomo 拆成 SMAppService daemon 跑，整个生命周期模型重写，自用版本不值
- [ ] **TUN 二进制挪到 `/Library/PrivilegedHelperTools/`**——目前 setuid 直接打在当前 active mihomo 上够用；未来要做发行版可以补
- [ ] **商业化 / 节点市场 / 自研协议**——永久 non-goal

## 还可以做的（feature 请求池，未排期）

- [ ] 流量图缩放 / 长按 reveal 数值
- [ ] 节点延迟历史曲线（不光是当前那个数）
- [ ] PROCESS-NAME 规则的进程列表自动补全
- [ ] yaml 编辑器加 mihomo 校验器（解析 + 高亮错误）
- [ ] Trick：「直连公网 IP / 代理公网 IP 一致时」高亮提示用户代理可能没工作
- [ ] 全局快捷键 / URL Scheme（`chunghwa://import?url=...`）
