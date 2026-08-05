import AppKit
import SwiftUI

struct ChatView: View {
    static let windowSize = NSSize(width: 840, height: 600)

    @ObservedObject var model: ChatModel
    let close: () -> Void

    @State private var draft = ""
    @State private var modelText = ""
    @State private var renameTitle = ""
    @State private var confirmsDeletion = false
    @State private var showsRename = false
    @FocusState private var inputFocused: Bool
    @AppStorage("chat.sidebarCollapsed") private var sidebarCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LauncherTheme.hairline)
            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    sidebar
                        .frame(width: 232)
                    Rectangle().fill(LauncherTheme.hairline).frame(width: 1)
                }
                workspace
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .riffPanelSurface(cornerRadius: 20, style: .content)
        .foregroundStyle(LauncherTheme.primary)
        .onAppear {
            modelText = model.selectedModel
            inputFocused = true
        }
        .onChange(of: model.selectedConversationID) { _, _ in
            modelText = model.selectedModel
        }
        .alert("删除这段对话？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { model.deleteSelectedConversation() }
        } message: {
            Text("对话记录将从本机移除，无法撤销。")
        }
        .alert("重命名对话", isPresented: $showsRename) {
            TextField("对话名", text: $renameTitle)
            Button("取消", role: .cancel) {}
            Button("确定") { model.renameSelected(renameTitle) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(LauncherTheme.secondary)
            Text("AI 对话")
                .font(.system(size: 14, weight: .semibold))
            Text("多轮对话 · 模型可编辑")
                .font(.system(size: 11.5))
                .foregroundStyle(LauncherTheme.secondary)
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    sidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left")
            }
            .riffGlassButton()
            .controlSize(.small)
            .help(sidebarCollapsed ? "展开侧边栏" : "收起侧边栏")

            Text(model.providerTitle)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(LauncherTheme.primary.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(LauncherTheme.secondary.opacity(0.14))
                )
                .help("当前 Provider（设置中可更换）")

            TextField("模型", text: $modelText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .font(.system(size: 12))
                .onSubmit { model.updateSelectedModel(modelText) }
                .help("当前对话使用的模型，回车保存")

            Button(action: model.createConversation) {
                Label("新建", systemImage: "plus")
            }
            .riffGlassButton()
            .controlSize(.small)

            Button {
                renameTitle = model.selectedConversation?.title ?? ""
                showsRename = true
            } label: {
                Image(systemName: "pencil")
            }
            .riffGlassButton()
            .controlSize(.small)
            .help("重命名当前对话")
            .disabled(model.selectedConversation == nil)

            PanelCloseButton(title: "关闭 AI 对话", action: close)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(LauncherTheme.secondary)
                TextField(
                    "搜索对话",
                    text: Binding(
                        get: { model.searchQuery },
                        set: { model.updateSearch($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                if !model.searchQuery.isEmpty {
                    Button {
                        model.updateSearch("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LauncherTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)

            HStack {
                Text("对话")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondary)
                Spacer()
                Text(
                    model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "\(model.conversations.count)"
                        : "\(model.filteredConversations.count)/\(model.conversations.count)"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(LauncherTheme.secondary.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            List(selection: conversationSelection) {
                ForEach(model.filteredConversations) { conversation in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversation.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        Text("\(conversation.messages.count) 条消息 · \(conversation.model)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(LauncherTheme.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .tag(conversation.id)
                    .contextMenu {
                        Button("重命名…") {
                            model.select(conversation)
                            renameTitle = conversation.title
                            showsRename = true
                        }
                        Divider()
                        Button("删除对话", role: .destructive) {
                            model.select(conversation)
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(LauncherTheme.contentSurface)
    }

    private var conversationSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedConversationID },
            set: { id in
                guard let id,
                      let conversation = model.conversations.first(where: { $0.id == id }) else {
                    return
                }
                model.select(conversation)
            }
        )
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            messages
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = model.streamError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider().overlay(LauncherTheme.hairline)
            inputBar
        }
        .background(LauncherTheme.contentSurface)
    }

    private var messages: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if let conversation = model.selectedConversation,
                           conversation.messages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(LauncherTheme.secondary.opacity(0.7))
                                Text("输入消息，开始一段新对话")
                                    .font(.system(size: 13))
                                    .foregroundStyle(LauncherTheme.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                        } else {
                            ForEach(model.selectedConversation?.messages ?? []) { message in
                                messageBubble(
                                    message,
                                    contentWidth: bubbleContentWidth(
                                        in: geometry.size.width
                                    )
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(18)
                }
                .onChange(of: model.selectedConversation?.messages) { _, _ in
                    if let last = model.selectedConversation?.messages.last {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func bubbleContentWidth(in availableWidth: CGFloat) -> CGFloat {
        min(Self.bubbleContentWidth, max(240, availableWidth - 36))
    }

    private func messageBubble(
        _ message: ChatMessage,
        contentWidth: CGFloat
    ) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            if message.role == .user {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LauncherTheme.selection)
                    }
            } else {
                MarkdownBubbleText(
                    source: message.content,
                    fontSize: 13,
                    textColor: .labelColor
                )
                .frame(
                    width: contentWidth,
                    height: markdownBubbleHeight(
                        message.content,
                        width: contentWidth
                    )
                )
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.75))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
                            }
                }
            }
            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private static let bubbleContentWidth: CGFloat = 540

    private func markdownBubbleHeight(_ source: String, width: CGFloat) -> CGFloat {
        guard !source.isEmpty else { return 18 }
        let attributed = RichTextRenderer.render(
            source,
            syntax: .markdownAndMath,
            fontSize: 13,
            textColor: .labelColor
        )
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(bounds.height) + 1
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("输入消息…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { send() }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
                        }
                }

            if model.isStreaming {
                Button {
                    model.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help("停止生成")
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LauncherTheme.selection)
                .help("发送（回车）")
            }
        }
        .padding(12)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isStreaming else { return }
        draft = ""
        model.send(text)
    }
}

/// Renders one assistant message with the shared Markdown renderer (headings,
/// lists, code, inline styles, math, and tables) in a selectable text view.
private struct MarkdownBubbleText: NSViewRepresentable {
    let source: String
    let fontSize: CGFloat
    let textColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        textView.textStorage?.setAttributedString(
            RichTextRenderer.render(
                source,
                syntax: .markdownAndMath,
                fontSize: fontSize,
                textColor: textColor
            )
        )
    }
}
