import AppKit
import SwiftUI

struct NoteView: View {
    static let windowSize = NSSize(width: 960, height: 640)

    @ObservedObject var model: NoteModel
    let close: () -> Void
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LauncherTheme.hairline)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 224)
                Rectangle().fill(LauncherTheme.hairline).frame(width: 1)
                workspace
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(
            LinearGradient(
                colors: [LauncherTheme.panelTop, LauncherTheme.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(LauncherTheme.primary)
        .environment(\.colorScheme, .dark)
        .alert("删除这篇笔记？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { model.deleteSelectedNote() }
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .foregroundStyle(LauncherTheme.secondary)
            Text("笔记")
                .font(.system(size: 14, weight: .semibold))
            Text("Markdown · 即时预览")
                .font(.system(size: 11.5))
                .foregroundStyle(LauncherTheme.secondary)
            Spacer()
            Button(action: model.createNote) {
                Label("新建", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            Button {
                confirmsDeletion = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除当前笔记")
            PanelCloseButton(title: "关闭笔记", action: close)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(model.notes) { note in
                    Button { model.select(note) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.title.isEmpty ? "未命名笔记" : note.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .lineLimit(1)
                            Text(note.summary)
                                .font(.system(size: 11.5))
                                .foregroundStyle(LauncherTheme.secondary)
                                .lineLimit(2)
                            Text(note.updatedAt, style: .relative)
                                .font(.system(size: 10.5))
                                .foregroundStyle(LauncherTheme.secondary.opacity(0.78))
                        }
                        .foregroundStyle(LauncherTheme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            note.id == model.selectedNoteID ? LauncherTheme.selection : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.opacity(0.08))
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            TextField("笔记标题", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .padding(.horizontal, 20)
                .frame(height: 56)

            Divider().overlay(LauncherTheme.hairline)

            HStack(spacing: 0) {
                paneHeader("MARKDOWN", symbol: "chevron.left.forwardslash.chevron.right") {
                    TextEditor(text: textBinding)
                        .font(.system(size: 14.5, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                }
                Rectangle().fill(LauncherTheme.hairline).frame(width: 1)
                paneHeader("预览", symbol: "doc.richtext") {
                    RichSelectableTextView(
                        source: model.selectedText,
                        syntax: .markdownAndMath,
                        fontSize: 15.5,
                        textColor: NSColor.white.withAlphaComponent(0.91),
                        contentInset: NSSize(width: 18, height: 18)
                    )
                }
            }
        }
    }

    private func paneHeader<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                Spacer()
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(LauncherTheme.secondary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            Divider().overlay(LauncherTheme.hairline)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { model.selectedTitle },
            set: { model.updateSelectedTitle($0) }
        )
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { model.selectedText },
            set: { model.updateSelectedText($0) }
        )
    }

}
