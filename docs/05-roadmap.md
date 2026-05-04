# 05 · 路线图

> 状态截至当前：M0–M4 全部落地，自用 v1 可日常使用。M5+ 大半也已完成。
> 本文档逐条 mark done 而不是另起一份「已完成清单」，保留原始里程碑结构方便对照决策。

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
- [x] Traffic 上下行曲线（Swift Charts，1/5/15min 范围切换）
- [x] Logs WS 替换 ringbuffer
- [x] Rules 列表 + provider 标识
- [x] 出站模式切换（Rule / Global / Direct）
- [x] 单组 / 全部 测速

## M3 · 订阅与 Profile ✅

- [x] Profile / Subscription 模型 + JSON 元数据
- [x] URL 订阅 add / refresh / delete
- [x] `subscription-userinfo` header 解析（流量、过期信息）
- [x] Profiles Tab 卡片 + 一键更新
- [x] 自动定时更新（默认 24h，UserDefaults 可调）
- [x] 启动项 `LoginItemController`（SMAppService）
- [x] 默认配置兜底：首次启动 `ProfileStore` 写一份 rule + DIRECT 的最小 yaml

## M4 · 抛光 ✅（自用 v1）

- [x] DesignSystem：Bone & Brass on Patina（Newsreader serif + 深 teal / brass / bone 配色，`Core/Design/`）
- [x] 跟随系统的 light / dark adaptive 调色板
- [x] 自定义 yaml 编辑器（CodeEdit-style + 异步加载缓存）
- [x] Icon Composer 应用图标 (`ChungHwa/AppIcon.icon`)，菜单栏 PNG (`Assets.xcassets/MenubarIcon.imageset`)
- [x] 关于卡 / 入站端口 / 在 Finder 中打开等设置项
- [x] 性能调优：`ChDot` 走 CoreAnimation 不再用 `TimelineView(.animation)`，所有 1Hz 数据在叶子子视图订阅，待机 CPU 从 23% 砍到 ~12%

## M5+ · 进阶 / 已完成

- [x] **TUN 模式**：`tun: enable: true / stack: gvisor / auto-route` 由 ConfigComposer 注入；
  `KernelPrivilegeHelper` 走 `osascript with administrator privileges` 一键 setuid root
- [x] **DNS 设置 UI**：`DNSEditorSheet` 编辑主上游 + 兜底，支持 DoH / DoT / DoQ / UDP；
  `enhanced-mode` (smart / system / fake-ip) + 53 端口劫持开关
- [x] **自定义路由**：`RoutingEditor` 编辑 `[CustomRule]`（DOMAIN-* / IP-CIDR / GEOIP / PROCESS-NAME → DIRECT/PROXY/REJECT/groupName），
  目前仅在使用默认配置时由 ConfigComposer 注入（带 `MATCH,DIRECT` 兜底）
- [x] **节点延迟持久化**：`ProxyStore` 写到 `~/Library/Application Support/ChungHwa/proxy-delays.json`，
  内核重启后仍保留上次测速结果直到下一次 testGroup 覆盖
- [x] **GeoIP 国旗**：连接表的 region 列 + 概览的「直连 IP」「代理 IP」走 `GeoIPStore`（HTTPS via ipwho.is，本地 JSON 缓存）
- [x] **入站端口可配置**：mixed-port 持久化到 UserDefaults，应用按钮触发 kernel restart + 系统代理重新启用
- [x] **网络状态卡**：互联网 / DNS / 路由 / 直连 IP / 代理 IP（带国旗）

## 没做 / 待定

- [ ] iOS 探索（要 NetworkExtension，性质上是另一个项目）
- [ ] Web Dashboard 内嵌（用户自己开 yacd / metacubexd 即可）
- [ ] 商业化 / 节点市场 / 自研协议 — 永久 non-goal
- [ ] 公证 + DMG 打包 — 自用版本不需要

## 节奏建议（保留原文供未来参考）

- 每周一次可演示构建
- 不并行做超过两个 milestone 的事
- 每个 PR / 分支聚焦单一 feature
- 不确定的技术点先在 `06-open-questions.md` 起条目
