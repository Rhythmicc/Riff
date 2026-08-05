# Changelog

## 0.6.0

- AI 对话持久化迁移到 SQLite：对话与消息存入 `chat.sqlite3`（WAL），不再整文件重写 `chat.json`；本机旧数据已一次性迁移，`chat.json` 保留为 `chat.json.migrated`。
- AI 服务层重构：新增统一传输层（OpenAI Responses / OpenAI 兼容 / Gemini），工具调用循环与 provider 无关，OpenAI 与 Gemini 现在同样支持本地工具；本地 llama.cpp 补全拆分为独立客户端。
- 新增组件系统第一阶段：`ComponentRegistry` + `ComponentManager` 统一管理组件，设置页新增“组件”分区，可启停内置组件（应用启动为系统内置，不可禁用）。
- 新增 `Docs/` 架构设计文档：组件系统、AI 服务统一、对话 SQLite 迁移。

## 0.5.0

- 新增 DeepSeek Provider，翻译、启动器 AI 回答和笔记补全均可使用。
- 新增 AI 对话组件：默认从主窗口索引（`对话`/`chat`/`ai`）进入；在主窗口完成 AI 询问后按 `⌘ J` 自动把问答加入对话库并打开窗口继续追问（也可先按 Tab 提交）。按首条消息自动生成对话名，支持对话新建/重命名/删除与本地持久化，每段对话可独立选择模型（默认 `deepseek-v4-flash-0731`）。
- 新增本地工具调用：AI 回答与 AI 对话可调用天气（Open-Meteo，无需 API Key）、汇率（ECB）、计算器、随机密码、Unicode 搜索和翻译工具，工具结果会回传给模型继续回答。
- 新增第一批 AI 工具：当前时间与时区换算（`current_time`/`timezone_convert`）、抓取网页正文（`fetch_url`）、读取前台应用选中文本（`selected_text`，需辅助功能权限）、读取与追加便笺（`note_read`/`note_append`）。
- 新增 Tavily 联网搜索（`web_search`）：AI 可实时搜索互联网并返回带来源的结果；设置中可填写 Tavily API Key（存入钥匙串），未配置时自动使用 Tavily keyless 免费模式。
- 修复 Markdown 表格渲染：AI 对话与 AI 回答中的表格按列对齐、表头加粗、长单元格自动换行，不再显示原始 `|` 语法。
- AI 对话窗口顶部显示当前 Provider，避免同名模型混淆；DeepSeek 默认模型改为 `deepseek-v4-flash`，OpenRouter 默认模型改为 `deepseek-v4-flash-0731`，新对话按当前 Provider 使用对应默认模型。
- AI 对话：对话名改为由 AI 在首轮回答后自动生成（最多 12 个汉字，失败时保留截断标题）；侧栏支持右键重命名/删除对话，移除窗口右上角删除按钮。
- AI 对话：窗口改为可缩放（记忆上次尺寸）并支持收起/展开侧边栏；布局改为随窗口自适应，回复气泡宽度跟随内容区，避免内容被侧边栏遮挡；表格换行优先按词断行。

## 0.4.0

- 新增随机密码组件：输入 `随机密码`、`生成密码`、`pwgen` 等关键词，或选择 `密码` 快捷操作后进入；组件输入框可直接输入长度（8–128 位）和「无符号」实时调整，Tab 或 `⌘R` 重新生成，回车复制；卡片显示熵值与暴力破解耗时估算（按每秒 100 亿次离线猜测）。
- 新增软件更新：设置中可检查 GitHub Releases 新版本，下载后校验 SHA-256 与签名，替换当前 App 并自动重新启动；启动时每天静默检查一次。

## 0.1.0

Riff 的首个公开版本：

- 原生 macOS 应用启动器，连续按两次 Shift 打开或关闭。
- 支持文本、链接、文件和图片预览的剪贴板历史。
- 支持 OpenAI、OpenRouter 和 Gemini 的选中文本翻译、流式输出及本地缓存。
- 支持 Markdown 多便笺、即时预览和置顶窗口。
- 支持算式、汇率换算和函数图绘制。
- 主窗口使用纯文本剪贴板语义，粘贴和复制不会携带富文本样式。
- 修复自定义 field editor 与新版 macOS 系统文本框不兼容导致的启动崩溃。
- 剪贴板历史和便笺不再默认占用全局快捷键。
