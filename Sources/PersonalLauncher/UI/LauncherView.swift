import AppKit
import SwiftUI

struct LauncherView: View {
    static let designSize = CGSize(width: 980, height: 650)
    static let scale: CGFloat = 0.84
    static let windowSize = CGSize(
        width: designSize.width * scale,
        height: designSize.height * scale
    )

    @ObservedObject var model: AppModel
    let close: () -> Void
    let showNote: () -> Void
    let showSettings: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().overlay(LauncherTheme.hairline)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(LauncherTheme.hairline)
            footer
        }
        .frame(width: Self.designSize.width, height: Self.designSize.height)
        .background(
            LinearGradient(colors: [LauncherTheme.panelTop, LauncherTheme.panelBottom], startPoint: .top, endPoint: .bottom)
        )
        .scaleEffect(Self.scale)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .environment(\.colorScheme, .dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { searchFocused = true }
        }
        .onChange(of: model.query) { _ in model.refreshQuery() }
    }

    private var searchHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: contextualSymbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LauncherTheme.secondary)

            TextField(prompt, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 27, weight: .regular, design: .rounded))
                .foregroundStyle(LauncherTheme.primary)
                .focused($searchFocused)

            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LauncherTheme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var content: some View {
        if model.hasInferredContent {
            inferredResults
        } else {
            switch model.mode {
            case .apps: appResults
            case .clipboard: clipboardResults
            }
        }
    }

    private var appResults: some View {
        Group {
            if model.isIndexing {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在建立应用索引…").foregroundStyle(LauncherTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        if model.showsNoteAction {
                            Button {
                                model.selectedIndex = 0
                                model.activateSelection()
                                close()
                            } label: {
                                NoteActionRow(selected: model.selectedIndex == 0)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(model.filteredApplications.indices, id: \.self) { index in
                            let selectionIndex = index + (model.showsNoteAction ? 1 : 0)
                            let application = model.filteredApplications[index]
                            Button {
                                model.selectedIndex = selectionIndex
                                model.activateSelection()
                                close()
                            } label: {
                                AppRow(
                                    application: application,
                                    selected: model.selectedIndex == selectionIndex
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var clipboardResults: some View {
        HStack(spacing: 0) {
            resultList(model.filteredClipboard) { index, item in
                Button {
                    model.selectedIndex = index
                } label: {
                    ClipboardRow(item: item, selected: model.selectedIndex == index)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 565)

            Rectangle().fill(LauncherTheme.hairline).frame(width: 1)
            ClipboardPreview(item: model.selectedClipboardItem())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inferredResults: some View {
        Group {
            if let expression = model.graphExpression {
                FunctionGraphCard(expression: expression)
            } else if let graphError = model.graphError {
                graphErrorCard(graphError)
            } else if let result = model.currencyResult {
                calculationCard(result, detail: "ECB 每个工作日更新的欧元参考汇率")
            } else if model.isConvertingCurrency {
                calculationCard("正在获取参考汇率…", detail: "例如 100 USD to CNY")
            } else if let result = model.calculation {
                calculationCard(result)
            } else { EmptyView() }
        }
    }

    private func calculationCard(_ result: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("结果")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LauncherTheme.secondary)
            HStack {
                Text(result)
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(LauncherTheme.primary)
                Spacer()
                Label("回车复制", systemImage: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(LauncherTheme.secondary)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(LauncherTheme.secondary)
            }
        }
        .padding(26)
        .background(LauncherTheme.selection, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(28)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func graphErrorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28, weight: .light))
            Text(message)
                .font(.system(size: 14))
        }
        .foregroundStyle(LauncherTheme.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultList<C: RandomAccessCollection, Row: View>(
        _ items: C,
        @ViewBuilder row: @escaping (Int, C.Element) -> Row
    ) -> some View where C.Index == Int {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(items.indices, id: \.self) { index in row(index, items[index]) }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: showNote) {
                Label("便笺", systemImage: "note.text")
            }
            Button(action: showSettings) {
                Label("设置", systemImage: "gearshape")
            }
            Spacer()
            if model.isGraphQuery {
                Label("实时函数图", systemImage: "chart.xyaxis.line")
                    .foregroundStyle(LauncherTheme.secondary)
            } else {
                KeyCap(text: "↑↓")
                Text("选择").foregroundStyle(LauncherTheme.secondary)
                KeyCap(text: "↩")
                Text(model.mode == .clipboard || model.hasInferredContent ? "复制" : "打开")
                    .foregroundStyle(LauncherTheme.secondary)
            }
            KeyCap(text: "esc")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(LauncherTheme.secondary)
        .padding(.horizontal, 24)
        .frame(height: 54)
    }

    private var prompt: String {
        switch model.mode {
        case .apps: return "搜索应用，输入算式或 y=sinx…"
        case .clipboard: return "筛选剪贴板历史…"
        }
    }

    private var contextualSymbol: String {
        if model.showsNoteAction { return "note.text" }
        if model.isGraphQuery { return "chart.xyaxis.line" }
        if model.currencyResult != nil || model.isConvertingCurrency { return "arrow.left.arrow.right" }
        if model.calculation != nil { return "function" }
        return model.mode.symbol
    }
}

private struct NoteActionRow: View {
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(LauncherTheme.secondary)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("打开笔记")
                    .font(.system(size: 17, weight: .medium))
                Text("管理和编辑 Markdown 笔记")
                    .font(.system(size: 11.5))
                    .foregroundStyle(LauncherTheme.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondary)
            }
        }
        .foregroundStyle(LauncherTheme.primary)
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(
            selected ? LauncherTheme.selection : .clear,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}

private struct AppRow: View {
    let application: ApplicationRecord
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(application.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LauncherTheme.primary)
                if let bundleIdentifier = application.bundleIdentifier {
                    Text(bundleIdentifier)
                        .font(.system(size: 11.5))
                        .foregroundStyle(LauncherTheme.secondary)
                }
            }
            Spacer()
            Text(application.url.deletingLastPathComponent().lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(LauncherTheme.secondary)
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(selected ? LauncherTheme.selection : .clear,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            if let url = item.imagePreviewURL,
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.7)
                    }
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LauncherTheme.secondary)
                    .frame(width: 42)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.summary.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(LauncherTheme.primary)
                    .lineLimit(2)
                Text(item.createdAt, style: .relative)
                    .font(.system(size: 11.5))
                    .foregroundStyle(LauncherTheme.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 67)
        .background(selected ? LauncherTheme.selection : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct ClipboardPreview: View {
    let item: ClipboardItem?

    var body: some View {
        Group {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(item.previewTitle, systemImage: item.imagePreviewURL == nil ? item.kind.symbol : "photo")
                        Spacer()
                        Text(item.createdAt, style: .time)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LauncherTheme.secondary)
                    if let url = item.imagePreviewURL,
                       NSImage(contentsOf: url) != nil {
                        AnimatedClipboardImageView(url: url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white.opacity(0.025))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.7)
                            }
                    } else {
                        RichSelectableTextView(
                            source: item.text,
                            syntax: .plain,
                            fontSize: 15,
                            textColor: NSColor.white.withAlphaComponent(0.91)
                        )
                    }
                }
                .padding(24)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .light))
                    Text("复制一些内容后会出现在这里")
                }
                .foregroundStyle(LauncherTheme.secondary)
            }
        }
    }
}

private struct AnimatedClipboardImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> ClipboardNSImageView {
        let imageView = ClipboardNSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        imageView.animates = true
        update(imageView)
        return imageView
    }

    func updateNSView(_ imageView: ClipboardNSImageView, context: Context) {
        update(imageView)
    }

    private func update(_ imageView: ClipboardNSImageView) {
        guard imageView.representedURL != url else { return }
        imageView.representedURL = url
        imageView.image = NSImage(contentsOf: url)
        imageView.animates = true
    }
}

private final class ClipboardNSImageView: NSImageView {
    var representedURL: URL?
}
