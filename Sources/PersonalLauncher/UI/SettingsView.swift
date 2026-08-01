import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var shortcuts: ShortcutStore
    let close: () -> Void
    @State private var accessibilityGranted = SelectionReader.isAccessibilityTrusted

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
                Section("翻译服务") {
                    Picker("Provider", selection: Binding(
                        get: { settings.provider },
                        set: { settings.selectProvider($0) }
                    )) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField("模型", text: $settings.model)
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

                Section {
                    Text("API Key 只保存在 macOS Keychain。翻译窗口不会因选中文本自动出现。")
                        .font(.system(size: 12))
                        .foregroundStyle(LauncherTheme.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 560, height: 540)
        .background(LinearGradient(colors: [LauncherTheme.panelTop, LauncherTheme.panelBottom], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
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

    private func pasteAPIKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        settings.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshAccessibilityStatus() {
        accessibilityGranted = SelectionReader.isAccessibilityTrusted
    }
}
