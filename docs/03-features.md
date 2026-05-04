# 03 · 功能清单

按 **MVP（M0）→ v1.0 → v1.x → v2** 四档分级。每个功能标注：

- **难度**：低 / 中 / 高
- **依赖**：必须先有的能力

---

## M0 · MVP（"能跑起来代理就行"）

目标：本机能拉起 mihomo、看到节点、切节点、看流量、开关系统代理。
不追求美观，不做提权 / TUN，不做订阅自动更新。

| # | 功能 | 难度 | 依赖 |
| --- | --- | --- | --- |
| 1 | 打包 mihomo 二进制并能启动 | 中 | CI 脚本、签名 |
| 2 | `KernelController` 启停、状态机 | 中 | #1 |
| 3 | `MihomoAPIClient` 拉 `/version` `/proxies` `/configs` | 低 | #2 |
| 4 | 主窗口 Tab 框架（Proxies / Connections / Logs / Settings） | 低 | — |
| 5 | Proxies Tab：列出代理组与节点、点击切换 | 中 | #3 |
| 6 | Settings Tab：选本地 yaml 文件作为配置 | 低 | — |
| 7 | 一键开关系统代理 (HTTP/HTTPS/SOCKS) | 中 | SystemConfiguration |
| 8 | 菜单栏图标 + 简易菜单（开关代理、退出） | 低 | — |
| 9 | 日志窗口（最近 1000 行，stderr ringbuffer） | 低 | #2 |

**Definition of Done**：用户在 Settings 里选一份手动放进去的 mihomo yaml，
点"启动" → 选节点 → 打开系统代理 → 浏览器能科学上网。

---

## v1.0 · 公测版

| # | 功能 | 难度 | 依赖 |
| --- | --- | --- | --- |
| 10 | 订阅管理：添加 URL、手动更新、删除 | 中 | — |
| 11 | 订阅自动更新（按周期 / 启动时） | 低 | #10 |
| 12 | 订阅流量信息（解析 `subscription-userinfo` header） | 低 | #10 |
| 13 | 多 Profile 切换（订阅 + 本地文件混合） | 中 | #10 |
| 14 | Proxies：节点延迟测试（单组 / 全部） | 低 | #5 |
| 15 | Connections Tab：实时连接表、过滤、关闭 | 中 | WS |
| 16 | Traffic：上行/下行实时曲线（Swift Charts） | 低 | WS |
| 17 | Rules Tab：当前规则列表、来源 provider 标识 | 低 | API |
| 18 | Mode 切换（Rule / Global / Direct） | 低 | API |
| 19 | 启动项 / 开机自启（SMAppService.loginItem） | 低 | — |
| 20 | 配置文件本地编辑（YAML 高亮 + 校验） | 中 | Yams |

**Definition of Done**：完成订阅 → 切节点 → 看连接 → 切配置整套循环，
体验对齐 ClashX Pro 的核心场景。

---

## v1.x · 增强版

| # | 功能 | 难度 |
| --- | --- | --- |
| 21 | TUN 模式 + Helper 安装流程 | 高 |
| 22 | Providers Tab：proxy-providers / rule-providers 状态、手动刷新 | 中 |
| 23 | DNS 设置 UI（fake-ip / redir-host / 自定义 nameserver） | 中 |
| 24 | 节点分组的自定义排序与收藏 | 低 |
| 25 | 节点延迟历史折线（每节点 24h） | 中 |
| 26 | 全局快捷键（切代理模式、切系统代理） | 低 |
| 27 | 通知中心提醒（订阅过期、流量超限、内核崩溃） | 低 |
| 28 | URL Scheme：`chunghwa://import?url=...` 一键导入订阅 | 低 |
| 29 | 多语言（简中 / 英文 / 繁中 / 日文） | 中 |
| 30 | 主题（Light / Dark / 跟随系统） + 强调色 | 低 |

---

## v2 · 长尾 / 探索

- iOS 客户端（NetworkExtension PacketTunnelProvider，需把内核换成 sing-box / 自己 cgo mihomo）
- 远程控制：把自己暴露成可被外部 yacd/metacubexd 接入的 External Controller 代理层
- 配置生成器（GUI 拼装代理 / 规则）
- 节点测速排行榜、自动选择策略可视化
- 内置规则集市场（订阅社区维护的 ruleset）

---

## 显式不做

- 不做"机场分销"或集成商业订阅
- 不做内置广告 / 数据上报
- 不做 Linux/Windows port（精力聚焦）
- 不为旧 macOS（< 14）适配（反正 SwiftUI 新 API 都用不了）

---

## 优先级判断准则

遇到取舍时按这个序列权衡：

1. **稳定**（不崩 / 不漏代理 / 退出干净）> 一切
2. **核心循环可用**（启动 → 选节点 → 上网）> 锦上添花
3. **可观测**（看得到流量、连接、日志）> 设置项数量
4. **原生体验**（系统集成、键盘可达、辅助功能）> 视觉花哨
