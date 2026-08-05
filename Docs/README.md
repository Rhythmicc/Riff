# Riff 架构设计文档

本目录记录 Riff 下一阶段的三项架构设计。当前均为设计稿，尚未开始实现。

| 文档 | 内容 | 状态 |
| --- | --- | --- |
| [ComponentSystem.md](ComponentSystem.md) | 组件管理系统：内置组件注册表、第三方组件规范、安装与安全模型 | 已实现（含第三方脚本组件安装/卸载与启动器结果） |
| [AIServiceUnification.md](AIServiceUnification.md) | AI 服务层重构：合并 provider 分支、统一流式与工具调用 | 已实现 |
| [ChatSQLite.md](ChatSQLite.md) | AI 对话持久化迁移：从 `chat.json` 迁移到 SQLite | 已实现，本地数据已一次性迁移 |
| [SearchMatchingRedesign.md](SearchMatchingRedesign.md) | 搜索匹配重设计：统一候选生成、特征打分、跨类别结果池与个性化 | Phase A/B 已实现（候选生成 + 特征打分 + 跨类别候选池 + frecency）；Phase C 待实施 |

## 建议实施顺序

1. **ChatSQLite**：改动面最小、独立性强，先落地并沉淀 SQLite 封装范式（复用 `ClipboardDatabase` 的经验）。
2. **AIServiceUnification**：纯内部重构，不改变任何对外行为，测试可以完整守住。
3. **ComponentSystem 第一阶段**：先定义协议和内置组件注册表，把现有 mode/quick action 迁入，再开放第三方组件。

每项设计都包含测试计划和迁移策略。对话迁移按约定只在本机执行一次，应用内不携带正式迁移代码。
