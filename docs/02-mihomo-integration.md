# 02 · mihomo 内核集成

这是项目最关键、最有不确定性的一篇。先列方案对比，再定主路径，再展开细节。

## 集成方式三种候选

### 方案 A：子进程托管 + REST/WS（**主路径**）

把 `mihomo` 预编译二进制随 App 一起打包到 `Contents/MacOS/mihomo`，
App 用 `Process` 启动它，通过 mihomo 自带的 External Controller HTTP/WS 控制。

- ✅ 实现简单、隔离好、内核崩溃不会带垮 UI
- ✅ 可平滑跟进 mihomo 上游版本（替换 binary 即可）
- ✅ 复用社区成熟 API，与 yacd/metacubexd 行为一致
- ✅ 调试期可外挂手动启动的 mihomo，绕开 App
- ⚠️ 需处理代码签名（Hardened Runtime 下嵌入第三方可执行需要签名）
- ⚠️ Universal binary 需自己交叉编译或拼 lipo
- ⚠️ TUN 仍需提权 helper

### 方案 B：cgo 编出 c-archive，静态链接进 App

用 mihomo 上游的 `Constant`/`Hub` 包写一层 Go 导出函数，`go build -buildmode=c-archive`
得到 `.a + .h`，让 Swift 通过 bridging header 调用 `Run/Stop/SetConfig`。

- ✅ 单个进程、无 IPC 开销
- ✅ 不用打包外部 binary，签名简单
- ❌ Go 运行时与 macOS 主线程模型耦合，需仔细设计 goroutine 与主线程
- ❌ 升级 mihomo 必须重编整个 App
- ❌ 内核 panic 会带垮 UI 进程
- ❌ 上游 API 不保证 Go 调用稳定，需要长期维护胶水层
- ❌ External Controller 模型仍然在内核内部跑，不少 endpoint 还是要走 HTTP

判断：**v1 不采用**。可作为 v2/3 的优化方向（性能或单文件分发诉求强烈时）。

### 方案 C：纯 Web 面板（不打内核）

只做面板，让用户自行运行 mihomo。

- ❌ 与定位（"开箱即用的桌面客户端"）矛盾
- 否决

## 子进程方案细节

### 二进制打包

- 在本地脚本中下载 mihomo 上游 release（GitHub Release `mihomo-darwin-arm64-vX.Y.Z` 与 `mihomo-darwin-amd64-vX.Y.Z`）
- 用 `lipo -create` 拼为 universal binary
- 拷贝到 `ChungHwa.app/Contents/MacOS/mihomo`
- Build Phase 中加 ad-hoc 签名步骤：`codesign --force --sign - mihomo`（无开发者账号时够用）
- 在 App 的 entitlements 里启用 `com.apple.security.cs.disable-library-validation = YES`（允许加载非系统签名的子可执行）
- 自用阶段不开 hardened runtime；若将来分发再加 `--options=runtime`

### 启动参数

```
mihomo \
  -d <App Support>/ChungHwa/mihomo \         # data dir：放 cache.db、geoip.dat 等
  -f <App Support>/ChungHwa/mihomo/config.yaml \
  -ext-ctl 127.0.0.1:<random-port> \         # 不用默认 9090，避免与用户已有 mihomo 冲突
  -secret <random-32B-base64>                # 每次启动随机
```

端口：从 47000-47999 范围随机挑一个空闲端口。
secret：用 `SecRandomCopyBytes` 生成，仅保存在内存里传给 `MihomoAPIClient`。

### 配置文件 (`config.yaml`)

App 维护一份**基础模板**（端口、模式、log-level、external-controller、tun 块），
与用户当前 profile 的"上游模板"合并后写入实际启动文件。
合并策略：profile 优先，但端口 / external-controller / secret / tun 等由 App 强制接管。

### 进程生命周期

- 用 `Process` 启动，把 stdout/stderr 接到管道，转写到 OSLog + ringbuffer，
  方便用户在"日志"面板里看历史
- 监听 `terminationHandler`：意外退出 → `KernelController` 进入 restarting 状态，
  指数退避重启（1s, 2s, 4s, max 3 次）
- App 退出时 `terminate()`，等 1 秒未退则 `interrupt()`

### REST API 客户端

mihomo External Controller 端点（与 clash 同源，metacubexd 同样依赖）：

| 用途 | 方法 | 路径 |
| --- | --- | --- |
| 健康检查 | GET | `/version` |
| 拉取代理组与节点 | GET | `/proxies` |
| 切换节点 | PUT | `/proxies/{name}` (`{"name": "<node>"}`) |
| 测延迟 | GET | `/proxies/{name}/delay?url=...&timeout=2000` |
| 拉取规则 | GET | `/rules` |
| 拉取/更新配置 | GET / PUT | `/configs` |
| 重载配置 | PUT | `/configs?force=true` |
| 关闭单个连接 | DELETE | `/connections/{id}` |
| 关闭全部连接 | DELETE | `/connections` |
| 拉取/更新 provider | GET / PUT | `/providers/proxies/{name}` |

`MihomoAPIClient`：
- 一个 actor 持有 `URLSession`、baseURL、bearer token (=secret)
- 方法全部 `async throws`
- 错误用 `MihomoAPIError` 区分 transport / decoding / status code

### WebSocket 流式 API

| 流 | 路径 | 频率 |
| --- | --- | --- |
| 实时流量 | `GET /traffic` | 1 Hz |
| 实时日志 | `GET /logs?level=info` | 事件驱动 |
| 连接快照 | `GET /connections` | 1 Hz（含全量增量） |
| 内存使用 | `GET /memory` | 1 Hz |

`MihomoStreamClient` 用 `URLSessionWebSocketTask` 暴露为 `AsyncStream<TrafficSample>` 等。
断线后自动重连（同一 backoff 策略）。

## TUN 模式与提权

### 需要提权的事

1. 创建 utun 设备：mihomo 自己用 `socket(AF_SYSTEM, ...)`，不需要 root（macOS 上 utun 默认允许任意用户创建）
2. 改默认路由 / 添加 IP 规则：**需要 root**
3. 修改 `/etc/resolver/*` 注入 DNS：**需要 root**

### 设计

- TUN 默认 **关闭**。在设置里第一次开启时，触发 helper 安装流程：
  - 用 `SMAppService.daemon(plistName:).register()` 注册 LaunchDaemon
  - 弹出 macOS 系统授权 sheet（用户输管理员密码）
  - 安装成功后 helper 在后台常驻
- App 与 helper 通过 NSXPC：
  ```swift
  protocol HelperProtocol {
    func enableTunRouting(interface: String, reply: @escaping (Bool, String?) -> Void)
    func disableTunRouting(reply: @escaping (Bool, String?) -> Void)
    func setSystemProxy(host: String, port: Int, reply: @escaping (Bool, String?) -> Void)
    func clearSystemProxy(reply: @escaping (Bool, String?) -> Void)
  }
  ```
- helper 自身 **不直接调用 mihomo**，只动路由 / 代理设置；mihomo 仍在用户域跑

### 系统代理（不开 TUN 的常规模式）

不需要 helper：直接用 `SCNetworkProxiesSetByteArray` 或 fork `networksetup -setwebproxy`。
ClashX 走的就是后者；本项目用 SystemConfiguration framework 更原生。

退出 App 时务必清空（在 `applicationWillTerminate` 与 `SIGTERM`/`SIGINT` 处理里都要做）。

## 失败模式与回退

| 场景 | 检测 | 回退 |
| --- | --- | --- |
| binary 找不到 / 不可执行 | spawn 失败 | 弹错对话框，禁用所有"代理"功能 |
| 端口被占用 | mihomo 退出码 + stderr | 重选端口重试 3 次 |
| External Controller 不响应 | `/version` poll 5 s 超时 | 重启子进程 1 次 |
| 配置非法 | reload 返回 4xx，body 含原因 | 不替换当前活动 yaml，回滚 + 红条提示 |
| Helper 通信失败 | XPC error | 自动降级到非 TUN 模式 + 红条提示 |
| 用户拔网 / 系统休眠 | NWPathMonitor + NSWorkspace.willSleepNotification | 暂停 WS 重连，唤醒后恢复 |

## 与上游版本的兼容策略

- 锁定一个最低支持的 mihomo 版本（建议 ≥ v1.18.x，写入 `Resources/mihomo-version.txt`）
- 启动后调用 `/version` 校验，低于最低版本提示但允许运行
- `MihomoAPIClient` 对未知字段使用宽松解码（`decoder.allowsUnknownKeys`），降低升级摩擦
