import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var shortcuts: ShortcutStore
    @ObservedObject var experienceMetrics: ExperienceMetricsStore
    @ObservedObject var updater: AppUpdater
    @ObservedObject var components: ComponentManager
    let close: () -> Void
    @State private var accessibilityGranted = SelectionReader.isAccessibilityTrusted
    @State private var componentError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(LauncherTheme.secondary)
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                PanelCloseButton(title: "关闭设置", action: close)
            }
            .padding(.horizontal, 20)
            .frame(height: 50)

            Divider().overlay(LauncherTheme.hairline)

            Form {
                Section("外观") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("玻璃不透明度")
                            Spacer()
                            Text("\(Int((settings.glassOpacity * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(LauncherTheme.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }

                        Slider(
                            value: $settings.glassOpacity,
                            in: AppearancePreferences.glassOpacityRange
                        ) {
                            Text("玻璃不透明度")
                        } minimumValueLabel: {
                            Image(systemName: "circle.lefthalf.filled")
                                .foregroundStyle(LauncherTheme.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(LauncherTheme.secondary)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15, weight: .medium))
                            Text("搜索…")
                                .font(.system(size: 16))
                            Spacer()
                        }
                        .foregroundStyle(LauncherTheme.primary.opacity(0.82))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .riffPanelSurface(cornerRadius: 22, style: .spotlight)
                        .animation(.easeOut(duration: 0.12), value: settings.glassOpacity)

                        HStack(alignment: .firstTextBaseline) {
                            Text("只调整启动器和翻译等浮动窗口的玻璃背景，文字与内容保持清晰。")
                                .font(.system(size: 11))
                                .foregroundStyle(LauncherTheme.secondary)
                            Spacer()
                            Button("恢复默认") { settings.resetGlassOpacity() }
                                .controlSize(.small)
                        }
                    }
                }

                Section("AI 服务") {
                    Picker("Provider", selection: Binding(
                        get: { settings.provider },
                        set: { settings.selectProvider($0) }
                    )) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField("翻译模型", text: $settings.model)
                        .onSubmit { settings.saveModel() }

                    HStack {
                        SecureField("API Key", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("粘贴") { pasteAPIKey() }
                            .help("从剪贴板粘贴 API Key")
                        if !settings.apiKey.isEmpty {
                            Button {
                                settings.apiKey = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(LauncherTheme.secondary)
                            .help("清除 API Key")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Tavily 搜索 Key（可选）")
                            Spacer()
                            if !settings.tavilyApiKey.isEmpty {
                                Text("已配置")
                                    .font(.system(size: 10))
                                    .foregroundStyle(LauncherTheme.secondary)
                            }
                        }
                        HStack {
                            SecureField("留空则使用 Tavily keyless 免费模式", text: $settings.tavilyApiKey)
                                .textFieldStyle(.roundedBorder)
                            Button("粘贴") { pasteTavilyKey() }
                                .help("从剪贴板粘贴 Tavily API Key")
                            if !settings.tavilyApiKey.isEmpty {
                                Button {
                                    settings.tavilyApiKey = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(LauncherTheme.secondary)
                                .help("清除 Tavily API Key")
                            }
                        }
                    }

                    Picker("母语", selection: $settings.nativeLanguage) {
                        ForEach(TranslationLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }

                    Picker("高优先级语言", selection: $settings.priorityLanguage) {
                        ForEach(TranslationLanguage.allCases.filter { $0 != settings.nativeLanguage }) { language in
                            Text(language.title).tag(language)
                        }
                    }

                    Text("非母语文本 → 母语；母语文本 → 高优先级语言。")
                        .font(.system(size: 11))
                        .foregroundStyle(LauncherTheme.secondary)
                }

                Section("笔记智能补全") {
                    Toggle("启用多语言自动补全", isOn: $settings.noteCompletionEnabled)

                    Picker("运行位置", selection: $settings.noteCompletionBackend) {
                        ForEach(NoteCompletionBackend.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!settings.noteCompletionEnabled)

                    if settings.noteCompletionBackend == .local {
                        TextField("本地 llama.cpp 地址", text: $settings.noteCompletionLocalEndpoint)
                            .disabled(!settings.noteCompletionEnabled)

                        Picker("本地模型", selection: $settings.noteCompletionLocalModel) {
                            ForEach(NoteCompletionLocalModel.allCases) { model in
                                VStack(alignment: .leading) {
                                    Text(model.title)
                                    Text(model.detail)
                                }
                                .tag(model)
                            }
                        }
                        .disabled(!settings.noteCompletionEnabled)

                        Text("通过 llama.cpp 按需加载 Qwen3.5 4B 或 9B；同一时间只保留一个模型。Riff 不使用 API Key，也不会自动回退到付费云端。")
                            .font(.system(size: 11))
                            .foregroundStyle(LauncherTheme.secondary)
                    } else {
                        TextField("低延迟补全模型", text: $settings.noteCompletionModel)
                            .disabled(!settings.noteCompletionEnabled)
                            .onSubmit { settings.saveNoteCompletionModel() }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "sparkles")
                        Text(completionPrivacyDescription)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(LauncherTheme.secondary)
                }

                Section("组件") {
                    ForEach(components.components, id: \.id) { component in
                        HStack(spacing: 10) {
                            Image(systemName: component.descriptor.icon.systemName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(LauncherTheme.primary.opacity(0.8))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.descriptor.name)
                                Text("\(component.descriptor.author) · v\(component.descriptor.version)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(LauncherTheme.secondary)
                            }
                            Spacer()
                            if component.descriptor.isSystemEssential {
                                Text("内置")
                                    .font(.system(size: 10))
                                    .foregroundStyle(LauncherTheme.secondary)
                            } else {
                                Toggle("", isOn: Binding(
                                    get: { components.isEnabled(component.id) },
                                    set: { components.setEnabled(component.id, $0) }
                                ))
                                .labelsHidden()
                            }
                        }
                    }

                    if !components.installed.isEmpty {
                        Divider()
                        ForEach(components.installed, id: \.id) { component in
                            HStack(spacing: 10) {
                                Image(systemName: component.manifest.icon ?? "square.grid.2x2")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(LauncherTheme.primary.opacity(0.8))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.manifest.name)
                                    Text("\(component.manifest.author) · v\(component.manifest.version) · 第三方")
                                        .font(.system(size: 10))
                                        .foregroundStyle(LauncherTheme.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { components.isEnabled(component.id) },
                                    set: { components.setEnabled(component.id, $0) }
                                ))
                                .labelsHidden()
                                Button("卸载") {
                                    do {
                                        try components.uninstall(id: component.id)
                                        componentError = nil
                                    } catch {
                                        componentError = error.localizedDescription
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("安装组件…") { installComponent() }
                        Button("打开组件目录") { components.openComponentsDirectory() }
                    }

                    if let componentError {
                        Text(componentError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }

                    Text("停用后，对应组件的启动器关键词与快捷操作不再出现。第三方组件以子进程运行，按 manifest 声明的权限执行，安装或更新前请确认来源可信。")
                        .font(.system(size: 11))
                        .foregroundStyle(LauncherTheme.secondary)
                }

                Section("快捷键") {
                    ForEach(ShortcutAction.allCases) { action in
                        shortcutRow(action)
                    }

                    if let message = shortcuts.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Text("点击键位后直接按新组合；连续按两次 Shift 可设为双击 Shift；按 Delete 可清除快捷键。")
                            .font(.system(size: 11))
                            .foregroundStyle(LauncherTheme.secondary)
                        Spacer()
                        Button("恢复默认") { shortcuts.resetDefaults() }
                            .controlSize(.small)
                    }
                }

                Section("系统权限") {
                    HStack {
                        Label(
                            accessibilityGranted ? "无障碍访问已授权" : "无障碍访问未授权",
                            systemImage: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(accessibilityGranted ? .green : .orange)

                        Spacer()

                        if accessibilityGranted {
                            Button("重新检查") { refreshAccessibilityStatus() }
                                .controlSize(.small)
                        } else {
                            Button("请求授权") {
                                accessibilityGranted = SelectionReader.requestAccessibilityPermission()
                            }
                            .controlSize(.small)
                        }
                    }

                    Text("Riff 只会在首次需要时自动询问一次。之后可在这里主动请求，不会在每次启动时重复弹窗。")
                        .font(.system(size: 11))
                        .foregroundStyle(LauncherTheme.secondary)
                }

                Section("软件更新") {
                    HStack {
                        Text("当前版本")
                        Spacer()
                        Text("\(updater.currentVersion) (\(updater.currentBuild))")
                            .monospacedDigit()
                            .foregroundStyle(LauncherTheme.secondary)
                    }

                    switch updater.state {
                    case .idle:
                        Button("检查更新") {
                            Task { await updater.checkForUpdates() }
                        }
                    case .checking:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在检查更新…")
                        }
                    case .upToDate:
                        Label("已是最新版本", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("再次检查") {
                            Task { await updater.checkForUpdates() }
                        }
                    case .available(let release):
                        Label("发现新版本 \(release.tagName)", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(LauncherTheme.primary)
                        Button("下载并安装") {
                            Task { await updater.downloadAndInstall(release) }
                        }
                    case .downloading(let release):
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在下载并校验 \(release.tagName)…")
                        }
                    case .installing:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在安装，完成后会自动重启…")
                        }
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Button("重试") {
                            Task { await updater.checkForUpdates() }
                        }
                    }

                    Text("更新来自 GitHub Releases：下载后校验 SHA-256 与签名，替换当前 App 后自动重新启动。")
                        .font(.system(size: 11))
                        .foregroundStyle(LauncherTheme.secondary)
                }

                Section("本机体验指标") {
                    metricRow("启动器会话", value: "\(experienceMetrics.snapshot.launcherSessions)")
                    metricRow(
                        "成功 / 放弃",
                        value: "\(experienceMetrics.snapshot.successfulSessions) / \(experienceMetrics.snapshot.abandonedSessions)"
                    )
                    metricRow(
                        "焦点就绪 P95",
                        value: ExperienceMetricsStore.formatted(experienceMetrics.snapshot.focusReady.p95)
                    )
                    metricRow(
                        "首次输入 P95",
                        value: ExperienceMetricsStore.formatted(experienceMetrics.snapshot.firstInput.p95)
                    )
                    metricRow(
                        "查询响应 P95",
                        value: ExperienceMetricsStore.formatted(experienceMetrics.snapshot.queryResolution.p95)
                    )

                    HStack(alignment: .firstTextBaseline) {
                        Text("只在这台 Mac 上保存限长的耗时和计数，不记录查询、App 名称、剪贴板、笔记或翻译内容。")
                            .font(.system(size: 11))
                            .foregroundStyle(LauncherTheme.secondary)
                        Spacer()
                        Button("复制摘要") { copyExperienceSummary() }
                            .controlSize(.small)
                        Button("重置") { experienceMetrics.reset() }
                            .controlSize(.small)
                    }
                }

                Section {
                    Text("API Key 只保存在 macOS Keychain 的 Riff 条目中。翻译窗口不会因选中文本自动出现。")
                        .font(.system(size: 12))
                        .foregroundStyle(LauncherTheme.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(LauncherTheme.contentSurface)
        }
        .frame(width: 560, height: 620)
        .riffPanelSurface(cornerRadius: 18, style: .content)
        .onAppear {
            settings.loadAPIKeyIfNeeded()
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        HStack {
            Text(action.title)
            Spacer()
            ShortcutRecorder(
                binding: shortcuts.binding(for: action),
                onRecord: { shortcuts.update($0, for: action) }
            )
            .frame(width: 142, height: 28)
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(LauncherTheme.secondary)
        }
    }

    private func copyExperienceSummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            experienceMetrics.diagnosticSummary,
            forType: .string
        )
    }

    private var completionPrivacyDescription: String {
        if settings.noteCompletionBackend == .local {
            return "停止输入片刻后由本机模型预测一小段续文；出现建议时按 Tab 接受。只把光标附近的有限上下文发送到上面的本机地址。"
        }
        return "停止输入片刻后预测一小段续文；出现建议时按 Tab 接受。补全复用上方 Provider 和 API Key，并只发送光标附近的有限上下文。"
    }

    private func pasteAPIKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        settings.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pasteTavilyKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        settings.tavilyApiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshAccessibilityStatus() {
        accessibilityGranted = SelectionReader.isAccessibilityTrusted
    }

    private func installComponent() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        panel.message = "选择 .riffcomponent/.zip 组件包，或包含 manifest.json 的组件目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try components.install(from: url)
            componentError = nil
        } catch {
            componentError = error.localizedDescription
        }
    }
}
