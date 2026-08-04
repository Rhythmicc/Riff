# Riff

See [ARCHITECTURE.md](ARCHITECTURE.md) for the launcher state and performance boundaries.

一个为个人工作流定制的原生 macOS 快捷入口。

## 已实现

- 连续按两次 `Shift`：应用启动器
- 剪贴板历史：文本、链接、文件和图片的即时预览；记录永久保存在本机 SQLite 数据库中，可逐条删除或全部清空；默认不占用全局快捷键，可在设置中配置
- `⌘ ⇧ T`：读取当前选中文本，再显示翻译窗口；按 Markdown 段落语义合并软换行，仅空行产生普通段落换行
- 便笺：始终置顶的原地渲染 Markdown 笔记；支持标题、列表、表格、代码块和水平分隔线；可用云端模型或本地 llama.cpp 小模型进行多语言自动补全，出现建议时按 `Tab` 接受；默认不占用全局快捷键，可从主窗口打开或在设置中配置
- 搜索框中输入算式，例如 `12 * (8 + 2)`
- 输入 `y=sinx`、`y=2x^2-3x` 等函数表达式，实时绘制自适应坐标图
- 函数等式支持 `f(x)=2x+1`、`z=x+1` 和 `6x^2+x=y` 等写法
- 输入 `unicode arrow`、`emoji grin`、`符号 箭头` 或 `U+2192`，搜索并复制 Unicode/Emoji 字符；关键词支持设置中选择的母语
- 输入 `睡眠`、`锁屏`、`关闭显示器` 或 `屏保`，直接执行对应的 macOS 系统操作；也支持 `sleep`、`lock screen` 等英文关键词
- 输入 `100 USD to CNY`，使用 ECB 每个工作日发布的参考汇率换算
- 没有匹配候选项时，可用默认浏览器执行 Google 搜索，或直接使用设置中的 AI Provider 流式回答；已打开的候选项会按最近使用顺序优先展示
- OpenAI、OpenRouter、Gemini 三种翻译 Provider
- API Key 保存在 macOS Keychain 的 `Riff` 服务项，不使用开发环境命名
- 设置中提供仅保存在本机的体验指标：启动器会话、成功/放弃、焦点与查询耗时 P95；只保存限长数值，不记录任何查询或用户内容

## 构建

```zsh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Riff.app"
```

首次启动时，macOS 会请求辅助功能权限，用于监听双击 `Shift` 和读取选中文本。应用以菜单栏程序运行。

Riff 需要 macOS 14 或更高版本。笔记编辑器使用固定版本的原生 TextKit 2 MarkdownEngine，第三方许可信息随应用一同打包。

搜索框支持 macOS 标准的撤销、重做、剪切、复制、粘贴和全选快捷键。
主窗口的输入框始终以纯文本读写剪贴板，不会把网页或文档中的 RTF/HTML 样式带到目标应用。

### 本地剪贴板历史

剪贴板记录保存在 `~/Library/Application Support/Riff/clipboard.sqlite3`，Riff 捕获的图片保存在同目录的 `clipboard-images` 中。记录没有自动过期时间和条数上限，重启或更新应用不会清除数据库；用户可在剪贴板窗口逐条删除、清空全部记录，或通过“本机存储”在 Finder 中查看数据位置。

这些内容不会上传或同步到云端。当前数据库是新的唯一存储格式，Riff 不导入旧版 `clipboard.json`，也不为上一版数据自动建立备份；成功打开新数据库后会直接丢弃旧文件及未被新数据库引用的旧托管图片。

### 本地笔记补全

Riff 可以连接 llama.cpp 的 OpenAI 兼容聊天接口。设置中将“笔记智能补全”的运行位置切换为“本地”，再选择“平衡 · 4B”或“高质量 · 9B”；默认地址为 `http://127.0.0.1:11435/v1/chat/completions`。本机示例服务使用 Qwen3.5-4B/9B 的 `Q4_K_M` 量化，并通过 llama.cpp 路由器保证同一时间最多加载一个模型。Riff 不会在本地服务失败时自动回退到付费云端。

本地模式关闭模型的思考过程，只发送有限的光标上下文，并要求模型仅返回可直接插入的短续文。模型文件和 llama.cpp 服务不随 Riff 应用分发，需要用户自行安装和启动。

## 默认快捷键

| 功能 | 默认快捷键 |
| --- | --- |
| 打开或关闭主窗口 | 连续按两次 `Shift` |
| 翻译选中文本 | `⌘ ⇧ T` |
| 复制译文并关闭翻译窗口 | `⌘ Enter` |
| 剪贴板历史 | 未设置，可从主窗口进入 |
| 置顶便笺 | 未设置，可从主窗口进入 |
| 任意 Riff 窗口中打开设置 | `⌘ ,` |

快捷键可以在设置中重新录制。录制状态下按 Delete 可清除快捷键；从旧版升级时，原先默认的 `⌥ V` 和 `⌥ N` 会迁移为未设置，不再占用系统组合键。

## 下载

预编译的 Universal 2 应用会发布在 GitHub Releases，同时支持 Apple Silicon 与 Intel Mac。

[前往 Releases 下载 Riff](https://github.com/Rhythmicc/Riff/releases/latest)

1. 下载 `Riff-<版本>-macOS-universal.zip` 并解压。
2. 将 `Riff.app` 移到 `/Applications`。
3. 首次启动时右键点击应用并选择“打开”，然后按提示授予辅助功能权限。

当前公开构建使用稳定本地要求进行 ad-hoc 签名，尚未使用 Apple Developer ID 公证。Release 同时提供 SHA-256 校验文件。

### 自动发布

发布工作流支持两种触发方式：

1. 在 GitHub 的 **Actions → Release → Run workflow** 中直接运行。标签留空时，会读取 `Info.plist` 中的版本并创建对应的 `v<版本>` Release。
2. 在本地推送与 `Info.plist` 版本一致的标签：

```zsh
git tag v0.3.0
git push origin v0.3.0
```

工作流会先运行测试，再构建并验证 Universal 2 应用，随后把 ZIP 和 SHA-256 校验文件同时上传为 Actions Artifact 和 GitHub Release 附件。若 Release 上传阶段失败，仍可从对应的 Actions 运行页面下载构建产物进行排查。

版本号必须使用 `v主版本.次版本.修订号` 格式，并与 `Info.plist` 中的 `CFBundleShortVersionString` 一致。

## 设计

视觉基准在 `Design/muted-launcher-reference.png`。方向是低饱和石墨灰、真实系统材质、克制的钢蓝选中态，不使用高亮霓虹渐变。
