import AppKit
import SwiftUI

struct NoteView: View {
    static let windowSize = NSSize(width: 960, height: 640)

    @ObservedObject var model: NoteModel
    @ObservedObject var completion: NoteCompletionModel
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
        .riffPanelSurface(cornerRadius: 20, style: .content)
        .foregroundStyle(LauncherTheme.primary)
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
            Text("Markdown · 原地编辑")
                .font(.system(size: 11.5))
                .foregroundStyle(LauncherTheme.secondary)
            if completion.isEnabled {
                completionStatus
            }
            Spacer()
            Button(action: model.createNote) {
                Label("新建", systemImage: "square.and.pencil")
            }
            .riffGlassButton()
            .controlSize(.small)
            Button {
                confirmsDeletion = true
            } label: {
                Image(systemName: "trash")
            }
            .riffGlassButton()
            .controlSize(.small)
            .help("删除当前笔记")
            PanelCloseButton(title: "关闭笔记", action: close)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }

    @ViewBuilder
    private var completionStatus: some View {
        if completion.isLoading {
            ProgressView()
                .controlSize(.mini)
                .help("正在生成补全建议")
        } else if let error = completion.errorMessage {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .help(error)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 10.5))
                .foregroundStyle(LauncherTheme.secondary)
                .help("智能补全已启用")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(LauncherTheme.secondary)
                TextField("搜索笔记", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LauncherTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            Divider().overlay(LauncherTheme.hairline)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(model.filteredNotes) { note in
                        Button { model.select(note) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    if note.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(LauncherTheme.accent)
                                    }
                                    Text(note.title.isEmpty ? "未命名笔记" : note.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .lineLimit(1)
                                }
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
                            .riffSelectedSurface(note.id == model.selectedNoteID, cornerRadius: 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(note.isPinned ? "取消固定" : "固定") {
                                model.togglePin(id: note.id)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .background(LauncherTheme.sidebarSurface)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            TextField("笔记标题", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .padding(.horizontal, 20)
                .frame(height: 56)

            Divider().overlay(LauncherTheme.hairline)
            ZStack(alignment: .bottomTrailing) {
                InlineMarkdownEditor(
                    text: textBinding,
                    documentID: model.selectedNoteID
                )
                .id(model.selectedNoteID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !completion.suggestion.isEmpty {
                    completionHint
                        .padding(18)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .background(LauncherTheme.contentSurface)
        .onChange(of: model.selectedNoteID) { _, _ in completion.cancel() }
        .onDisappear { completion.cancel() }
    }

    private var completionHint: some View {
        Button { completion.requestAcceptance() } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LauncherTheme.accent)
                Text(completion.suggestion)
                    .font(.system(size: 13.5))
                    .foregroundStyle(LauncherTheme.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                KeyCap(text: "Tab")
                Text("接受")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(LauncherTheme.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("按 Tab 接受补全")
        .animation(.easeOut(duration: 0.12), value: completion.suggestion)
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
