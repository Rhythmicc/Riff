import SwiftUI

struct TranslationView: View {
    @ObservedObject var model: TranslationModel
    @ObservedObject var settings: SettingsStore
    let openSettings: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("翻译", systemImage: "character.book.closed")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(settings.provider.title) · \(settings.model)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(LauncherTheme.secondary)
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .help("打开设置")
                PanelCloseButton(title: "关闭翻译", action: close)
            }
            .padding(.horizontal, 20)
            .frame(height: 50)

            Divider().overlay(LauncherTheme.hairline)

            HStack(spacing: 0) {
                translationPane(title: "原文", text: model.source, placeholder: "没有读到选中的文字")
                Rectangle().fill(LauncherTheme.hairline).frame(width: 1)
                translationPane(title: model.targetLanguage.title, text: model.result, placeholder: loadingText)
            }

            Divider().overlay(LauncherTheme.hairline)

            HStack {
                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color(red: 0.82, green: 0.58, blue: 0.54))
                        .lineLimit(1)
                } else {
                    Text(directionSummary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(LauncherTheme.secondary)
                }
                Spacer()
                Button("重试") { model.retry() }
                    .disabled(model.isLoading)
                    .keyboardShortcut("r", modifiers: .command)
                Button(action: copyAndClose) {
                    HStack(spacing: 7) {
                        Text("复制译文")
                        KeyCap(text: "⌘↩")
                    }
                }
                    .disabled(model.result.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 20)
            .frame(height: 52)
        }
        .frame(width: 840, height: 470)
        .background(LinearGradient(colors: [LauncherTheme.panelTop, LauncherTheme.panelBottom], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(LauncherTheme.primary)
        .environment(\.colorScheme, .dark)
    }

    private func translationPane(title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(LauncherTheme.secondary)
            RichSelectableTextView(
                source: text.isEmpty ? placeholder : text,
                syntax: .markdownAndMath,
                fontSize: 17,
                textColor: text.isEmpty
                    ? NSColor.white.withAlphaComponent(0.48)
                    : NSColor.white.withAlphaComponent(0.91)
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var loadingText: String {
        model.isLoading ? "正在翻译…" : "翻译结果会显示在这里"
    }

    private func copyAndClose() {
        if model.copyResult() { close() }
    }

    private var directionSummary: String {
        let source = model.detectedLanguage.flatMap { detected in
            TranslationLanguage.allCases.first(where: { $0.matches(detected) })?.title
        } ?? "自动识别"
        return "\(source) → \(model.targetLanguage.title)"
    }
}
