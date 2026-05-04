# 05 · 路线图

时间是估算（个人 / 兼职节奏，按周计）。每个里程碑结尾都有可演示版本。

## M0 · 骨架与冒烟（约 1 周）

目标：项目结构搭起来、能启停 mihomo、API 通了。

- [ ] 清空 Xcode 模板里的 `Item` CoreData 实体，建 `Subscription` / `Profile` / `RuleSetCache` 三个空壳实体
- [ ] 接入 SPM 依赖：Yams
- [ ] `scripts/fetch-mihomo.sh`：从 GitHub release 拉两架构 binary 并 lipo
- [ ] Build Phase：在 Copy Bundle Resources 之前下载 + 拷贝 + 签名 mihomo
- [ ] `KernelController` 状态机最小实现
- [ ] `MihomoAPIClient.version()` 跑通
- [ ] App 启动后控制台打印出 mihomo 版本号

**Demo**：命令行 build & run，控制台输出 `mihomo running v1.18.x`。

## M1 · MVP 主窗口（约 2 周）

目标：能配置、能切代理、能开系统代理。

- [ ] 主窗口 Tab 框架（Proxies / Logs / Settings）
- [ ] Settings：选本地 yaml → 写入 App Support → reload → 状态反馈
- [ ] Proxies：组列表 + 节点列表 + 单击切换
- [ ] 日志窗口（先只展示 stderr ringbuffer）
- [ ] 菜单栏图标 + 「启动/停止内核」「打开/关闭系统代理」「显示主窗口」「退出」
- [ ] `SystemProxyController` 跑通（先用 SystemConfiguration framework）
- [ ] 应用退出钩子：杀子进程 + 清系统代理

**Demo**：拖一份 yaml 进 Settings，浏览器能科学上网。

## M2 · 流式可视化（约 2 周）

目标：实时观感到位。

- [ ] `MihomoStreamClient` 全部四个流跑通
- [ ] Connections Tab：表格 + 过滤 + 关闭
- [ ] Traffic 上下行曲线（Swift Charts）
- [ ] Logs Tab：替换 ringbuffer，使用 `/logs` WS
- [ ] Rules Tab：列表 + 来源 provider 标识
- [ ] Mode 切换 (Rule / Global / Direct)
- [ ] 节点延迟测试（单组 + 全部）

**Demo**：刷视频时主窗口能看到流量曲线，连接表实时增长，logs 有规则命中行。

## M3 · 订阅与 Profile（约 2 周）

目标：脱离手工拷贝 yaml，正式可日常使用。

- [ ] CoreData：补完 Subscription / Profile schema
- [ ] `SubscriptionManager` add / refresh / delete
- [ ] 解析 `subscription-userinfo` header（流量、过期）
- [ ] Subscriptions Tab：卡片列表 + 流量进度条 + 一键更新
- [ ] Profile 切换（含模板合并器）
- [ ] 自动更新：启动时 + 周期（默认 24h）
- [ ] 启动项（SMAppService.loginItem）

**Demo**：粘订阅 URL → 自动拉取 → 选默认 profile → 重启后自动恢复运行。

## M4 · 抛光（约 1–2 周，自用版）

- [ ] DesignSystem 重构（Color / Typography / Card 组件复用）
- [ ] 主题（跟随系统）
- [ ] yaml 编辑器（高亮 + 保存前 mihomo 校验）
- [ ] 应用图标
- [ ] README 与简易使用说明

**v1.0 Self-use Release**：自用版本完成。
公证 / DMG 打包 / 多语言 / 商店分发 等延后到有外部发行需求时再做。

## M5+ · TUN 与生态（开放节奏）

- [ ] PrivilegedHelper 安装与 XPC 协议
- [ ] TUN 模式开关
- [ ] DNS 设置 UI
- [ ] Providers Tab
- [ ] 节点延迟历史
- [ ] 全局快捷键 / URL Scheme
- [ ] iOS 探索（独立分支）

## 节奏建议

- **每周一次可演示构建**：哪怕只是 menubar 多了一个开关
- **不要并行做超过两个 milestone 的事**
- **每个 PR/分支聚焦单一 feature**
- **遇到不确定的技术点，先在 `docs/06-open-questions.md` 起一个条目，再决定要不要写代码**
