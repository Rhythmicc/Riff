import AppKit
import SwiftUI

struct LauncherView: View {
    static let designSize = CGSize(width: 840, height: 650)
    static let collapsedDesignHeight: CGFloat = 74
    static let scale: CGFloat = 0.84
    static let unicodeGridColumnCount = 8
    static let candidateRowDesignHeight: CGFloat = 56
    static let searchFontSize: CGFloat = 24
    static let answerFontSize: CGFloat = 17

    static func windowSize(designHeight: CGFloat) -> CGSize {
        CGSize(
            width: designSize.width * scale,
            height: designHeight * scale
        )
    }

    static func resultDesignHeight(rowCount: Int) -> CGFloat {
        let rows = max(0, rowCount)
        let rowHeight = CGFloat(rows) * candidateRowDesignHeight
        let spacing = CGFloat(max(0, rows - 1)) * 5
        let contentPadding: CGFloat = 28
        let dividersAndFooter: CGFloat = 56
        return min(
            designSize.height,
            collapsedDesignHeight + rowHeight + spacing + contentPadding + dividersAndFooter
        )
    }

    static func unicodeGridDesignHeight(itemCount: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(itemCount) / Double(unicodeGridColumnCount))))
        let tileHeight = CGFloat(rows) * 96
        let spacing = CGFloat(max(0, rows - 1)) * 8
        let contentPadding: CGFloat = 36
        let dividersAndFooter: CGFloat = 56
        return min(
            designSize.height,
            collapsedDesignHeight + tileHeight + spacing + contentPadding + dividersAndFooter
        )
    }

    @ObservedObject var model: AppModel
    let close: () -> Void
    let showNote: () -> Void
    let showSettings: () -> Void
    let setDesignHeight: (CGFloat) -> Void
    let focusReady: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var confirmsClipboardClear = false
    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            if model.shouldShowResults {
                VStack(spacing: 0) {
                    Divider().overlay(LauncherTheme.hairline)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().overlay(LauncherTheme.hairline)
                    footer
                }
            }
        }
        .frame(
            width: Self.designSize.width,
            height: desiredDesignHeight,
            alignment: .top
        )
        .riffPanelSurface(
            cornerRadius: model.shouldShowResults ? 26 : Self.collapsedDesignHeight / 2,
            // Keep the same surface identity on both sides of the first
            // keystroke. The NSPanel reveals the results by resizing; the
            // background should never transition to another material.
            style: .spotlight
        )
        // The launcher grows downward from the search bar. Scaling around the
        // default center point would move the header every time the window
        // height changes, even though the NSPanel's top edge stays fixed.
        .scaleEffect(Self.scale, anchor: .topLeading)
        .frame(
            width: Self.windowSize(designHeight: desiredDesignHeight).width,
            height: Self.windowSize(designHeight: desiredDesignHeight).height,
            alignment: .topLeading
        )
        .onAppear {
            setDesignHeight(desiredDesignHeight)
        }
        .onChange(of: desiredDesignHeight) { _, height in setDesignHeight(height) }
        .onReceive(NotificationCenter.default.publisher(for: .riffFocusLauncherSearch)) { _ in
            // The hosting view exists while its panel is hidden, so onAppear is
            // too early to establish an AppKit field editor. Toggle the focus
            // binding after every explicit show request instead.
            searchFocused = false
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { focusReady() }
        }
        .confirmationDialog(
            "清空剪贴板历史？",
            isPresented: $confirmsClipboardClear,
            titleVisibility: .visible
        ) {
            Button("清空全部记录", role: .destructive) {
                model.clearClipboardHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除 Riff 在此 Mac 上保存的全部剪贴板记录和托管图片，无法撤销。")
        }
    }

    private var desiredDesignHeight: CGFloat {
        guard model.shouldShowResults else { return Self.collapsedDesignHeight }
        if model.isComponentQuery {
            return Self.resultDesignHeight(rowCount: model.resultCount)
        }
        if model.mode == .clipboard || model.isGraphQuery {
            return Self.designSize.height
        }
        if model.isUnicodeQuery {
            return Self.unicodeGridDesignHeight(itemCount: model.resultCount)
        }
        if model.isFallbackQuery {
            return Self.resultDesignHeight(rowCount: model.resultCount)
        }
        if model.isAIAnswer {
            return 520
        }
        if model.hasInferredContent {
            return 310
        }
        return Self.resultDesignHeight(rowCount: model.resultCount)
    }

    private var searchHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: contextualSymbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(LauncherTheme.primary.opacity(0.78))

            TextField(
                "",
                text: Binding(
                    get: { model.query },
                    set: { model.query = $0 }
                ),
                prompt: Text(prompt)
                    .foregroundStyle(LauncherTheme.primary.opacity(0.72))
            )
                .textFieldStyle(.plain)
                .font(.system(size: Self.searchFontSize, weight: .regular))
                .foregroundStyle(LauncherTheme.primary)
                .focused($searchFocused)
                .accessibilityLabel(prompt)

            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LauncherTheme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: Self.collapsedDesignHeight)
    }

    @ViewBuilder
    private var content: some View {
        if model.isComponentQuery {
            componentResults
        } else if model.isFallbackQuery {
            fallbackResults
        } else if model.hasInferredContent {
            inferredResults
        } else {
            switch model.mode {
            case .apps: searchResults
            case .clipboard: clipboardResults
            case .password: passwordCard
            }
        }
    }

    private var fallbackResults: some View {
        resultList(model.fallbackActions) { index, action in
            Button {
                model.selectedIndex = index
                if model.activateSelection() { close() }
            } label: {
                LauncherCommandRow(
                    title: model.fallbackTitle(for: action),
                    symbol: action.symbol,
                    selected: model.selectedIndex == index
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var componentResults: some View {
        Group {
            if model.componentIsLoading {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在查询组件…").foregroundStyle(LauncherTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultList(model.componentItems) { index, item in
                    Button {
                        model.selectedIndex = index
                        if model.activateSelection() { close() }
                    } label: {
                        ComponentResultRow(item: item, selected: model.selectedIndex == index)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchResults: some View {
        Group {
            if model.searchIsLoading, model.searchItems.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.isIndexing ? "正在建立应用索引…" : "正在搜索…")
                        .foregroundStyle(LauncherTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultList(model.searchItems) { index, item in
                    Button {
                        model.selectedIndex = index
                        if model.activateSelection() { close() }
                    } label: {
                        LauncherSearchRow(
                            item: item,
                            selected: model.selectedIndex == index
                        )
                    }
                    .buttonStyle(.plain)
                }
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
                .contextMenu {
                    Button("删除这条记录", role: .destructive) {
                        model.removeClipboardItem(item)
                    }
                }
            }
            .frame(width: 480)

            Rectangle().fill(LauncherTheme.hairline).frame(width: 1)
            ClipboardPreview(item: model.selectedClipboardItem())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inferredResults: some View {
        Group {
            if model.isAIAnswer {
                aiAnswerCard
            } else if model.isUnicodeQuery {
                unicodeResults
            } else if model.isPasswordQuery {
                passwordCard
            } else if let expression = model.graphExpression,
                      let plot = model.graphPlot {
                FunctionGraphCard(expression: expression, plot: plot)
            } else if model.isPlottingGraph {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在绘制函数图…")
                }
                .foregroundStyle(LauncherTheme.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var aiAnswerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("AI 回答", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let summary = model.aiAnswerProviderSummary {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(LauncherTheme.secondary)
                }
                if model.isLoadingAIAnswer {
                    ProgressView().controlSize(.small)
                }
            }

            if let error = model.aiAnswerError, model.aiAnswerResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .foregroundStyle(Color(nsColor: .systemRed))
                    Text("可以在设置中检查 Provider、模型和 API Key。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(LauncherTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if model.isLoadingAIAnswer {
                StreamingSelectableTextView(
                    source: model.aiAnswerResult,
                    placeholder: "等待 Provider 首包…",
                    fontSize: Self.answerFontSize
                )
            } else {
                RichSelectableTextView(
                    source: model.aiAnswerResult,
                    syntax: .markdownAndMath,
                    fontSize: Self.answerFontSize,
                    textColor: .labelColor
                )
            }

            if !model.isLoadingAIAnswer,
               model.aiAnswerError == nil,
               !model.aiAnswerResult.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text(model.aiAnswerCommittedToChat
                        ? "已加入 AI 对话 · 按 ⌘J 继续追问"
                        : "回答完成 · 按 ⌘J 加入对话并继续追问（也可先按 Tab 提交）")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(LauncherTheme.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unicodeResults: some View {
        Group {
            if model.isSearchingUnicode && model.unicodeResults.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在建立 Unicode 索引…")
                }
                .foregroundStyle(LauncherTheme.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.unicodeResults.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "textformat")
                        .font(.system(size: 25, weight: .light))
                    Text("没有找到匹配的字符")
                    Text("试试 unicode arrow、emoji grin 或 U+2192")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(LauncherTheme.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topTrailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), spacing: 8),
                                    count: Self.unicodeGridColumnCount
                                ),
                                spacing: 8
                            ) {
                                ForEach(model.unicodeResults.indices, id: \.self) { index in
                                    let item = model.unicodeResults[index]
                                    Button {
                                        model.selectedIndex = index
                                        if model.activateSelection() { close() }
                                    } label: {
                                        UnicodeSymbolTile(
                                            item: item,
                                            selected: model.selectedIndex == index
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(item.name.capitalized)\n\(item.codePointLabel)")
                                    .id(index)
                                }
                            }
                            .padding(18)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: model.selectedIndex) { _, selectedIndex in
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(selectedIndex, anchor: .center)
                            }
                        }
                    }

                    if model.isSearchingUnicode {
                        ProgressView()
                            .controlSize(.small)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(12)
                    }
                }
            }
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
        }
        .padding(28)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("安全随机密码", systemImage: "key.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondary)
                Spacer()
                Button {
                    model.regeneratePassword()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
                .riffGlassButton()
                .controlSize(.small)
            }

            if let generated = model.generatedPassword {
                Text(generated.value)
                    .font(.system(size: 29, weight: .medium, design: .monospaced))
                    .foregroundStyle(LauncherTheme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .textSelection(.enabled)

                HStack {
                    Text(passwordSummaryText)
                    Spacer()
                    Label("回车复制", systemImage: "doc.on.doc")
                    Text("Tab / ⌘R 重新生成")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(LauncherTheme.secondary)

                if let estimate = model.passwordCrackEstimateText {
                    Text(estimate)
                        .font(.system(size: 12))
                        .foregroundStyle(LauncherTheme.secondary.opacity(0.75))
                }

                if model.passwordRequest?.includeSymbols != false {
                    Text("输入「无符号」可排除特殊符号")
                        .font(.system(size: 12))
                        .foregroundStyle(LauncherTheme.secondary.opacity(0.75))
                }
            } else {
                Text(model.passwordGenerationError ?? "无法生成密码")
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
        }
        .padding(26)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
        }
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
            if model.mode == .clipboard {
                Button {
                    model.removeSelectedClipboardItem()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .riffGlassButton()
                .controlSize(.small)
                .disabled(model.selectedClipboardItem() == nil)

                Button {
                    confirmsClipboardClear = true
                } label: {
                    Label("清空", systemImage: "trash.slash")
                }
                .riffGlassButton()
                .controlSize(.small)
                .disabled(model.clipboardHistoryCount == 0)

                Button {
                    model.revealClipboardStorage()
                } label: {
                    Label("本机存储", systemImage: "internaldrive")
                }
                .riffGlassButton()
                .controlSize(.small)

                if model.clipboardStorageError != nil {
                    Label("保存异常", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(model.clipboardStorageError ?? "")
                } else {
                    Text("\(model.clipboardHistoryCount) 条 · 仅存此 Mac")
                        .foregroundStyle(LauncherTheme.secondary)
                }
            } else {
                Button(action: showNote) {
                    Label("便笺", systemImage: "note.text")
                }
                .riffGlassButton()
                .controlSize(.small)
                Button(action: showSettings) {
                    Label("设置", systemImage: "gearshape")
                }
                .riffGlassButton()
                .controlSize(.small)
            }
            Spacer()
            if model.isLoadingAIAnswer {
                Label("AI 正在流式回答", systemImage: "sparkles")
                    .foregroundStyle(LauncherTheme.secondary)
            } else if model.isGraphQuery {
                Label("实时函数图", systemImage: "chart.xyaxis.line")
                    .foregroundStyle(LauncherTheme.secondary)
            } else {
                KeyCap(text: model.isUnicodeQuery ? "←↑↓→" : "↑↓")
                Text("选择").foregroundStyle(LauncherTheme.secondary)
                KeyCap(text: "↩")
                Text(footerActionTitle)
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
        case .apps: return "搜索…"
        case .clipboard: return "筛选剪贴板历史…"
        case .password: return "长度 8–128，可加「无符号」…"
        }
    }

    private var passwordSummaryText: String {
        guard let request = model.passwordRequest else { return "" }
        let charset = request.includeSymbols
            ? "大小写字母、数字和符号"
            : "大小写字母和数字（无符号）"
        return "\(request.length) 位 · \(charset)"
    }

    private var contextualSymbol: String {
        if model.mode == .apps, model.query.isEmpty { return "magnifyingglass" }
        if let operation = model.systemOperations.first { return operation.symbol }
        if let fallback = model.selectedFallbackAction ?? model.fallbackActions.first {
            return fallback.symbol
        }
        if model.isAIAnswer { return "sparkles" }
        if let action = model.quickActions.first { return action.symbol }
        if model.isGraphQuery { return "chart.xyaxis.line" }
        if model.isUnicodeQuery {
            return model.unicodeQuery?.scope == .emoji ? "face.smiling" : "textformat"
        }
        if model.isPasswordQuery { return "key.horizontal" }
        if model.currencyResult != nil || model.isConvertingCurrency { return "arrow.left.arrow.right" }
        if model.calculation != nil { return "function" }
        return model.mode.symbol
    }

    private var footerActionTitle: String {
        if model.isSystemOperationQuery { return "执行" }
        if let fallback = model.selectedFallbackAction {
            return fallback == .googleSearch ? "搜索" : "询问"
        }
        if model.mode == .clipboard || model.hasInferredContent { return "复制" }
        return "打开"
    }
}
