import AppKit
import Foundation
import UniformTypeIdentifiers

enum LauncherMode: String, CaseIterable, Identifiable {
    case apps
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "应用"
        case .clipboard: return "剪贴板"
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        }
    }

    static func navigationMode(for keyCode: UInt16) -> LauncherMode? {
        switch keyCode {
        case 18: return .apps
        case 19: return .clipboard
        default: return nil
        }
    }
}

enum LauncherQuickAction: String, CaseIterable, Identifiable {
    case note
    case clipboard
    case translation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: return "打开笔记"
        case .clipboard: return "打开剪贴板历史"
        case .translation: return "打开翻译"
        }
    }

    var detail: String {
        switch self {
        case .note: return "管理和编辑 Markdown 笔记"
        case .clipboard: return "搜索、预览并复制历史内容"
        case .translation: return "返回当前翻译，或翻译选中的文本"
        }
    }

    var symbol: String {
        switch self {
        case .note: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .translation: return "character.book.closed"
        }
    }

    fileprivate var keywords: [String] {
        switch self {
        case .note:
            return ["笔记", "便笺", "记事", "note", "notes", "markdown", "md"]
        case .clipboard:
            return ["剪贴板", "粘贴板", "剪贴板历史", "粘贴板历史", "clipboard", "pasteboard", "history"]
        case .translation:
            return ["翻译", "译文", "translate", "translation", "translator"]
        }
    }

    nonisolated static func matching(_ query: String) -> [LauncherQuickAction] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        return allCases.filter { action in
            action.keywords.contains { keyword in
                keyword.hasPrefix(normalized) || normalized.hasPrefix(keyword)
            }
        }
    }
}

struct ApplicationRecord: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleIdentifier: String?

    var id: String { url.path }
}

enum ClipboardKind: String, Codable {
    case text
    case link
    case file
    case image

    var title: String {
        switch self {
        case .text: return "文本"
        case .link: return "链接"
        case .file: return "文件"
        case .image: return "图片"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .file: return "doc"
        case .image: return "photo"
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: ClipboardKind
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), kind: ClipboardKind, text: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
    }

    var summary: String {
        switch kind {
        case .image: return "图片"
        case .file: return URL(fileURLWithPath: text).lastPathComponent
        default: return text
        }
    }

    /// Image data captured directly from the pasteboard is persisted by Riff as
    /// `.image`. Screenshot tools commonly copy a file URL instead, so image files
    /// deliberately keep their `.file` identity while still receiving a preview.
    var imagePreviewURL: URL? {
        switch kind {
        case .image:
            return URL(fileURLWithPath: text)
        case .file:
            let url = URL(fileURLWithPath: text)
            guard let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image) else { return nil }
            return url
        default:
            return nil
        }
    }

    var previewTitle: String {
        kind == .file && imagePreviewURL != nil ? "图片文件" : kind.title
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI
    case openRouter
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .gemini: return "Gemini"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-5.6-luna"
        case .openRouter: return "~openai/gpt-latest"
        case .gemini: return "gemini-3.5-flash"
        }
    }
}
