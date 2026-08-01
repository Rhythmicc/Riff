# Riff

一个为个人工作流定制的原生 macOS 快捷入口。

## 已实现

- 连续按两次 `Shift`：应用启动器
- `⌥ V`：文本、链接、文件和图片的剪贴板历史与即时预览
- `⌘ ⇧ T`：读取当前选中文本，再显示翻译窗口
- `⌥ N`：始终置顶的 Markdown 便笺
- 搜索框中输入算式，例如 `12 * (8 + 2)`
- 输入 `y=sinx`、`y=2x^2-3x` 等函数表达式，实时绘制自适应坐标图
- 输入 `100 USD to CNY`，使用 ECB 每个工作日发布的参考汇率换算
- OpenAI、OpenRouter、Gemini 三种翻译 Provider
- API Key 保存在 macOS Keychain

## 构建

```zsh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Riff.app"
```

首次启动时，macOS 会请求辅助功能权限，用于监听双击 `Shift` 和读取选中文本。应用以菜单栏程序运行。

搜索框支持 macOS 标准的撤销、重做、剪切、复制、粘贴和全选快捷键。
主窗口的输入框始终以纯文本读写剪贴板，不会把网页或文档中的 RTF/HTML 样式带到目标应用。

## 下载

预编译的 Universal 2 应用会发布在 GitHub Releases，同时支持 Apple Silicon 与 Intel Mac。

1. 下载 `Riff-<版本>-macOS-universal.zip` 并解压。
2. 将 `Riff.app` 移到 `/Applications`。
3. 首次启动时右键点击应用并选择“打开”，然后按提示授予辅助功能权限。

当前公开构建使用稳定本地要求进行 ad-hoc 签名，尚未使用 Apple Developer ID 公证。Release 同时提供 SHA-256 校验文件。

维护者创建版本：

```zsh
git tag v0.1.0
git push origin v0.1.0
```

推送 `v*` 标签后，GitHub Actions 会构建 Universal 2 应用并创建 Release；也可以从 Actions 页面手动指定标签运行。

## 设计

视觉基准在 `Design/muted-launcher-reference.png`。方向是低饱和石墨灰、真实系统材质、克制的钢蓝选中态，不使用高亮霓虹渐变。
