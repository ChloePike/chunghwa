# 01 · 整体架构

## 进程模型

```
┌──────────────────────────────────────────────────────────────┐
│ ChungHwa.app  (SwiftUI + AppKit, sandboxed=NO)               │
│                                                              │
│  ┌─────────────────┐   ┌──────────────────┐   ┌───────────┐  │
│  │   UI Layer      │   │  Service Layer   │   │  Storage  │  │
│  │  SwiftUI Views  │◄─►│  CoreClient /    │◄─►│  CoreData │  │
│  │  Menu Bar       │   │  SubscriptionMgr │   │  (订阅元数据)│
│  │                 │   │  ProxyManager    │   │  FileSystem│
│  │                 │   │                  │   │  (yaml 配置)│
│  └─────────────────┘   └────────┬─────────┘   └───────────┘  │
│                                 │ HTTP+WS (127.0.0.1:9090)  │
│                                 ▼                            │
│              ┌──────────────────────────────┐                │
│              │  mihomo (child Process)      │                │
│              │  External Controller (REST/WS)│               │
│              │  内嵌于 App Bundle 的 binary  │               │
│              └──────────────────────────────┘                │
│                                 │                            │
│                                 │ XPC                        │
│                                 ▼                            │
│              ┌──────────────────────────────┐                │
│              │  ChungHwaHelper (root daemon)│  ← SMAppService │
│              │  · 系统代理设置（备选）       │                │
│              │  · TUN/路由表写入            │                │
│              │  · 防火墙规则                │                │
│              └──────────────────────────────┘                │
└──────────────────────────────────────────────────────────────┘
```

三个进程：
1. **App 主进程**：UI、状态管理、订阅、与内核通信
2. **mihomo 子进程**：实际的代理内核
3. **特权 Helper**（可选/按需）：仅承担需要 root 的任务，最小权限原则

## 技术选型

| 层 | 选型 | 理由 |
| --- | --- | --- |
| UI 框架 | SwiftUI（macOS 14+，已有项目模板设的是 26.4） | 原生、声明式、AppKit 互操作够用 |
| 系统集成 | AppKit（NSStatusItem、NSWorkspace、SystemConfiguration） | SwiftUI 不覆盖菜单栏与代理设置 API |
| 异步 | Swift Concurrency（async/await + AsyncSequence） | WS 流式推送天然契合 AsyncSequence |
| 本地存储 | CoreData（订阅、配置元信息、用户偏好的复杂部分） + UserDefaults（简单偏好） + 文件系统（mihomo yaml） | CoreData 已在模板中，不重新引入 SQLite/SwiftData |
| 内核通信 | URLSession（REST） + URLSessionWebSocketTask（WS） | 系统库够用，不引第三方 |
| YAML 解析 | [Yams](https://github.com/jpsim/Yams)（SPM） | mihomo 配置是 YAML，需要本地展示/校验 |
| 图表 | Swift Charts | 流量曲线，原生、零依赖 |
| 日志 | OSLog + 写盘文件 | 系统集成、Console.app 可读 |
| 提权 | SMAppService（macOS 13+ daemon） + XPC | 替代已废弃的 SMJobBless |
| 包管理 | Swift Package Manager | 不引 CocoaPods |

## 分层职责

### 1. UI Layer (`Features/`)

按功能聚合的 SwiftUI 视图。每个 feature 独立目录，含 View / ViewModel / 子组件。
ViewModel 是 `@Observable` 类，订阅 Service Layer 的状态流。

### 2. Service Layer (`Core/`)

无 UI 依赖的 Swift 模块，承担：
- 内核生命周期（`KernelController`）
- API 客户端（`MihomoAPIClient` + `MihomoStreamClient`）
- 订阅管理（`SubscriptionManager`）
- 配置管理（`ProfileManager`）
- 系统代理（`SystemProxyController`）
- 偏好（`PreferencesStore`）

它们以 `@Observable` 单例或注入对象的形式给 ViewModel 用。

### 3. Storage Layer (`Storage/`)

- `CoreData` stack：复用模板里已有的 `Persistence.swift`，但替换默认的 `Item` 实体为
  `Subscription`、`Profile`、`RuleSetCache` 等。
- `FileStore`：负责 mihomo 配置目录（`~/Library/Application Support/ChungHwa/mihomo/`）下的
  `config.yaml`、`profiles/*.yaml`、`providers/*.yaml`、`cache.db` 文件读写。

### 4. Helper (`ChungHwaHelper/`)

独立 target，最终打包为 `ChungHwaHelper.app`/`ChungHwaHelper`，注册为 LaunchDaemon。
通过 NSXPCListener 暴露 protocol 给主 App 调用，仅做：
- 启用/关闭 TUN（写路由表）
- 设置/恢复系统级代理（如不通过 networksetup）
- 启动/停止 mihomo（若用户希望开机即代理）

最小化 surface，保持可审计。

## 数据流

### 启动序列

```
App launch
  → PreferencesStore 加载
  → ProfileManager 决定加载哪份 yaml
  → KernelController 拼装启动参数 → spawn mihomo
  → 等待 mihomo External Controller 就绪 (poll /version)
  → MihomoAPIClient 拉取初始 proxies / configs
  → MihomoStreamClient 打开 traffic / logs / connections WS
  → UI 订阅 ViewModel，渲染主窗口 / 菜单栏
```

### 配置切换

```
User picks profile in UI
  → ProfileManager.activate(profile)
  → 写入 mihomo data dir 的 config.yaml
  → MihomoAPIClient.PUT /configs?force=true 触发热重载
  → API 返回成功 → ViewModel 刷新
```

### 节点切换

```
User taps node in group
  → MihomoAPIClient.PUT /proxies/{group} {name: <node>}
  → 服务端持久化由 mihomo 自己管
  → Traffic/Connections WS 自动反映新节点
```

## 关键非功能需求

- **启动到可用 < 1.5 s**（mihomo cold start ≈ 200 ms，UI 优先呈现，待内核就绪再点亮交互）
- **空闲 CPU < 1%**：WS 推送频率高，UI 端要做节流（traffic 1 Hz，connections 增量 diff）
- **崩溃自恢复**：监听子进程 termination，5 秒内重启，3 次失败则降级到 "internal error" 状态并提示用户
- **配置热重载零中断**：节点选择、规则不应在 reload 后丢失
- **可关掉**：用户退出 App 时必须杀掉 mihomo 子进程，恢复系统代理

## 安全 / 权限模型

- 主 App **不开 sandbox**（需要管理子进程、读写任意路径配置、设置网络代理；沙盒会让上述都很别扭）。
  自用阶段不做 hardened runtime + notarize；若将来要分发再补。
- 默认 **不安装 Helper**：只有当用户开启 TUN 模式时按需触发安装并提示授权。
- mihomo External Controller **绑定 127.0.0.1**，secret 启动时随机生成并仅传给本地 UI，
  避免被同机其他进程接管。
