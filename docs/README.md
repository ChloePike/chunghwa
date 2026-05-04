# ChungHwa 设计文档

ChungHwa 是一款基于 [mihomo](https://github.com/MetaCubeX/mihomo) 内核的 macOS 桌面 Clash 面板。
本目录收录项目的设计与规划文档，按主题分册维护。

## 文档索引

| 编号 | 文件 | 内容 |
| --- | --- | --- |
| 00 | [overview.md](./00-overview.md) | 项目概览、目标、非目标、参考产品 |
| 01 | [architecture.md](./01-architecture.md) | 整体架构、进程模型、技术选型 |
| 02 | [mihomo-integration.md](./02-mihomo-integration.md) | mihomo 内核集成方案（子进程 / cgo / TUN / 提权） |
| 03 | [features.md](./03-features.md) | 功能清单、MVP 范围、优先级 |
| 04 | [modules.md](./04-modules.md) | 代码模块划分与目录结构 |
| 05 | [roadmap.md](./05-roadmap.md) | 里程碑与迭代计划 |
| 06 | [open-questions.md](./06-open-questions.md) | 待决策问题与风险 |

## 阅读顺序

1. 先读 `00-overview.md` 对齐目标
2. 读 `01-architecture.md` 与 `02-mihomo-integration.md` 理解技术骨架
3. 再读 `03-features.md` 与 `05-roadmap.md` 决定先做什么
4. `04-modules.md` 在动手写代码前再看

## 文档维护原则

- 每篇短小聚焦，单一主题
- 决策写明 **为什么**，不只是 **是什么**
- 重大决策变更要在原文档处更新而非另起一篇
- 未决问题统一收敛到 `06-open-questions.md`
