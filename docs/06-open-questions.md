# 06 · 未决问题与风险

文档完成后立刻能看见的"还要拍板"清单。每条都需要在动工之前给个临时答案，正式答案随项目演进确定。

## 必须先拍板的（影响 M0 立刻能不能开工）

### Q1 · App 命名与 Bundle ID — ✅ 已定
- 名字：**ChungHwa**
- Bundle ID：`com.tzaigroup.chunghwa`

### Q2 · 是否真的要用 CoreData
- 模板默认带，但 SwiftData / GRDB / 纯 JSON 文件都行
- 订阅 / Profile 数据量很小，CoreData 偏重
- **临时**：保留 CoreData（少改一处）；若 M3 之前发现 SwiftData 更顺，再迁移
- **决策时机**：M3 开工前

### Q3 · 最低 macOS 版本 — ✅ 已定（搁置）
- 不主动指定，沿用 Xcode 模板默认（当前 `MACOSX_DEPLOYMENT_TARGET = 26.4`）
- 自用，不需考虑覆盖面

### Q4 · 开发者签名 / 公证身份 — ✅ 已定
- 暂无 Apple Developer Program 账号，自用
- 走 Personal Team 自动签名 + mihomo binary 用 `codesign -s -` ad-hoc 签
- 不开 Sandbox，不做 hardened runtime / notarization
- 后续如需分发再补

## 影响架构的

### Q5 · 是否要支持外部 mihomo 实例
- 场景：高级用户已经在 server / NAS 上跑了 mihomo，希望用 ChungHwa 作为面板远程接入
- 实现：`KernelController` 增加一种 `external` 模式，跳过 spawn，仅持有远端 baseURL + secret
- 工作量：不大，但要梳理 UI 上"内核是我托管 vs 远端"的状态展示
- **临时**：v1 不做，v1.x 加
- **决策时机**：v1 发布前确认是否提前

### Q6 · 内核与 UI 的版本耦合
- 每次 mihomo 上游更新，是发新 App 版本还是支持热更换 binary？
- 候选 A（推荐）：每个 App 版本绑定一个 mihomo 版本，发布即整体
- 候选 B：App 启动时检查更新，下载新 binary 替换
- **临时**：A。简单且签名链路完整
- **决策时机**：CI 脚本动手前

### Q7 · TUN 模式实现路径
- 路径 1：mihomo 自己开 TUN（macOS 上要 root 来改路由），App 装 helper 改路由
- 路径 2：用 Apple 的 NETransparentProxyProvider / NEPacketTunnelProvider（System Extension）
- 路径 1 简单但需要 helper；路径 2 沙盒友好但调试痛苦
- **临时**：路径 1。和 ClashX Pro 路线一致，社区案例多
- **决策时机**：M5 开工前

### Q8 · App 是否开 Sandbox — ✅ 已定
- 不开 Sandbox（自用 + 子进程托管 + 系统代理设置都需要不沙盒）
- entitlements 仅保留 `com.apple.security.cs.disable-library-validation`

## 影响产品形态的

### Q9 · UI 视觉走向 — 🟡 待定（用户在设计中）
- 风格 A：Stash 风（卡片化、彩色 chip、视觉重）
- 风格 B：ClashX Pro 风（系统原生、克制、像 Finder）
- 风格 C：metacubexd 风（数据密度高、表格为主）
- **当前**：用户自行设计中
- **影响**：M0–M2 用素颜布局（List + Form + 默认控件），等设计稿出来再统一抛光
- **决策时机**：M3/M4 视觉抛光前必须有方向

### Q10 · 是否需要"小白引导"
- 第一次启动是不是要问一遍订阅 URL、引导开系统代理？
- **临时**：v1 不做，v1.x 加
- **决策时机**：v1 发布后再说

### Q11 · 隐私与数据上报
- 是否做匿名 telemetry（崩溃、启动统计）？
- **临时**：不做。任何数据上报都要先有清晰的隐私策略
- **决策时机**：长期不做即可

## 风险登记

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| mihomo 上游 External Controller 不兼容变更 | API 客户端失效 | 锁版本 + 宽松解码 + 升级前回归测试 |
| Apple 公证策略变化导致内嵌 binary 被拒 | 无法分发 | 关注 hardened runtime 文档；备方案 B |
| 用户系统已运行其他 Clash 端口冲突 | 启动失败 | 启动前端口 probe + 自动改端口 |
| Helper 提权流程被新版 macOS 改动 | TUN 不可用 | 用 SMAppService 而非 SMJobBless（更前向兼容） |
| 长时间 WS 连接耗电 | 后台续航差 | 失焦时降频；接 NWPathMonitor |
| 用户拷贝异常 yaml 导致内核反复崩溃 | 体验差 | 启动前预校验 + 失败回滚到上一份可用 yaml |

## 决策汇总（2026-05-04）

| 项 | 结论 |
| --- | --- |
| Q1 命名 / Bundle ID | ✅ ChungHwa / `com.tzaigroup.chunghwa` |
| Q3 最低 macOS | ✅ 不指定，沿用模板 |
| Q4 签名 / 分发 | ✅ 自用，无开发者账号，ad-hoc 签名 |
| Q5 内核集成主路径 | ✅ 子进程托管 mihomo binary |
| Q8 Sandbox | ✅ 不开 |
| Q9 UI 风格 | 🟡 用户设计中，M0–M2 用素颜布局 |

剩余 Q2 / Q6 / Q7 / Q10 / Q11 与时间相关，到时再决定。
