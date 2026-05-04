# 04 · 模块划分与目录结构

## 目录结构（建议）

```
ChungHwa/
├── ChungHwa.xcodeproj
├── ChungHwa/                       # 主 App target
│   ├── App/
│   │   ├── ChungHwaApp.swift       # @main, Scene 组装
│   │   ├── AppDelegate.swift       # NSApplicationDelegate, lifecycle 钩子
│   │   ├── MenuBar/
│   │   │   ├── MenuBarController.swift
│   │   │   └── MenuBarMenu.swift
│   │   └── DI.swift                # 依赖装配
│   │
│   ├── Core/                       # 与 UI 无关的服务层（可单元测试）
│   │   ├── Kernel/
│   │   │   ├── KernelController.swift
│   │   │   ├── KernelLaunchPlan.swift
│   │   │   └── KernelStatus.swift
│   │   ├── API/
│   │   │   ├── MihomoAPIClient.swift
│   │   │   ├── MihomoStreamClient.swift
│   │   │   ├── Models/
│   │   │   │   ├── ProxyGroup.swift
│   │   │   │   ├── Proxy.swift
│   │   │   │   ├── Connection.swift
│   │   │   │   ├── TrafficSample.swift
│   │   │   │   ├── LogLine.swift
│   │   │   │   └── ConfigSnapshot.swift
│   │   │   └── Errors.swift
│   │   ├── Profiles/
│   │   │   ├── ProfileManager.swift
│   │   │   ├── ProfileTemplateMerger.swift
│   │   │   └── YAMLValidator.swift
│   │   ├── Subscriptions/
│   │   │   ├── SubscriptionManager.swift
│   │   │   ├── SubscriptionFetcher.swift
│   │   │   └── SubscriptionUserInfo.swift
│   │   ├── SystemProxy/
│   │   │   └── SystemProxyController.swift
│   │   ├── Helper/
│   │   │   ├── HelperInstaller.swift
│   │   │   └── HelperClient.swift   # XPC proxy 包装
│   │   └── Preferences/
│   │       └── PreferencesStore.swift
│   │
│   ├── Storage/
│   │   ├── Persistence.swift                # 复用模板，重命名实体
│   │   ├── ChungHwa.xcdatamodeld/
│   │   └── FileStore.swift                   # App Support 目录读写
│   │
│   ├── Features/                   # 每个 feature 一个目录，内含 View + ViewModel
│   │   ├── Proxies/
│   │   │   ├── ProxiesView.swift
│   │   │   ├── ProxiesViewModel.swift
│   │   │   ├── ProxyGroupCard.swift
│   │   │   └── NodeRow.swift
│   │   ├── Connections/
│   │   ├── Logs/
│   │   ├── Rules/
│   │   ├── Profiles/
│   │   ├── Subscriptions/
│   │   ├── Traffic/
│   │   └── Settings/
│   │
│   ├── DesignSystem/
│   │   ├── Colors.swift
│   │   ├── Typography.swift
│   │   ├── Components/             # Button、Card、StatusDot、SegmentedControl…
│   │   └── Icons.swift
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── mihomo-version.txt
│   │   └── Templates/
│   │       └── base-config.yaml
│   │
│   └── Supporting/
│       ├── Info.plist
│       └── ChungHwa.entitlements
│
├── ChungHwaHelper/                 # 独立 target，root daemon
│   ├── main.swift
│   ├── HelperListener.swift
│   ├── HelperProtocol.swift        # 与主 App 共享
│   ├── RoutingOps.swift
│   ├── SystemProxyOps.swift
│   └── ChungHwaHelper.entitlements
│
├── ChungHwaShared/                 # 主 App 与 Helper 共用代码（XPC 协议、共享类型）
│   └── HelperProtocol.swift        # symlink 或 SPM 本地包
│
├── ChungHwaTests/                  # 单元测试，重点测 Core/
├── ChungHwaUITests/                # 关键流程 UI 测试
│
├── docs/                           # 本规划文档
├── scripts/
│   ├── fetch-mihomo.sh             # 下载并 lipo 拼 universal binary
│   ├── codesign-helper.sh
│   └── notarize.sh
└── README.md
```

## 模块依赖（单向，自上而下）

```
Features  ──►  Core  ──►  Storage
   │            │
   └──────►  DesignSystem
   │
App ──► Features, Core
Helper ── 独立，仅依赖 ChungHwaShared
```

`Core` 不依赖 SwiftUI、不 import AppKit；
`Features` 不直接读写文件系统；
`Storage` 不持有业务逻辑。

## 关键类型契约（先用文字描述，落地时翻译成 Swift）

### `KernelController`
```
state: @Observable  enum { idle, starting, running(version), restarting(attempt), failed(reason) }
async func start() throws
async func stop()
async func reload(profile: ProfileID) throws
var apiClient: MihomoAPIClient { get }      // running 状态下非空
var streamClient: MihomoStreamClient { get }
```

### `MihomoAPIClient` (actor)
```
init(baseURL: URL, secret: String)
func version() async throws -> Version
func proxies() async throws -> ProxiesSnapshot
func selectProxy(group: String, node: String) async throws
func delay(node: String, testURL: URL, timeoutMs: Int) async throws -> Int
func rules() async throws -> [Rule]
func reloadConfig(force: Bool) async throws
func closeConnection(id: String) async throws
func closeAllConnections() async throws
```

### `MihomoStreamClient`
```
func traffic() -> AsyncThrowingStream<TrafficSample, Error>
func logs(level: LogLevel) -> AsyncThrowingStream<LogLine, Error>
func connections() -> AsyncThrowingStream<ConnectionsSnapshot, Error>
func memory() -> AsyncThrowingStream<MemorySample, Error>
```

### `SubscriptionManager`
```
@Observable var subscriptions: [Subscription]   // 来自 CoreData
func add(url: URL, name: String) async throws -> Subscription
func refresh(_ id: SubscriptionID) async throws
func refreshAll() async
func remove(_ id: SubscriptionID) throws
func userInfo(for: SubscriptionID) -> SubscriptionUserInfo?  // 上下行 / 到期
```

### `ProfileManager`
```
@Observable var profiles: [Profile]            // 订阅型 + 本地型
@Observable var activeProfileID: ProfileID?
func activate(_ id: ProfileID) async throws
func mergedYAML(for id: ProfileID) throws -> String
```

### `SystemProxyController`
```
@Observable var isEnabled: Bool
func enable(host: String, httpPort: Int, socksPort: Int) throws
func disable() throws
```

## 测试边界

- `Core/` 全部覆盖单元测试，通过 mock 的 `URLProtocol` 喂假响应
- `MihomoStreamClient` 用本地 WebSocket server fixture（XCTNetwork 或者自起一个）
- `Features/` 关键 ViewModel 单测；UI 测试只覆盖菜单栏开关代理 + 切节点
- Helper 用 XPC mock 协议测 protocol 一致性，不真起 daemon

## 不要做的事

- 不要把 mihomo 配置直接 binding 到 SwiftUI Form 控件 → 用 ViewModel 中间层
- 不要在 View 里直接 `Process()` → 必须经 `KernelController`
- 不要把 secret / API token 存进 UserDefaults → 只放内存 + Keychain（如有持久化需要）
- 不要在 Helper 里做任何网络请求 → 它只摸路由表和系统代理
