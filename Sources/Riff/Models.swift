import AppKit
import Foundation
import UniformTypeIdentifiers

enum LauncherMode: String, CaseIterable, Identifiable {
    case apps
    case clipboard
    case password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "应用"
        case .clipboard: return "剪贴板"
        case .password: return "随机密码"
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .password: return "key.horizontal"
        }
    }

    static func navigationMode(for keyCode: UInt16) -> LauncherMode? {
        switch keyCode {
        case 18: return .apps
        case 19: return .clipboard
        case 20: return .password
        default: return nil
        }
    }
}

enum LauncherQuickAction: String, CaseIterable, Identifiable {
    case note
    case clipboard
    case translation
    case password
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: return "打开笔记"
        case .clipboard: return "打开剪贴板历史"
        case .translation: return "打开翻译"
        case .password: return "生成随机密码"
        case .chat: return "打开 AI 对话"
        }
    }

    var detail: String {
        switch self {
        case .note: return "管理和编辑 Markdown 笔记"
        case .clipboard: return "搜索、预览并复制历史内容"
        case .translation: return "返回当前翻译，或翻译选中的文本"
        case .password: return "生成一个 16 位安全随机密码"
        case .chat: return "多轮对话、对话管理，可自选模型"
        }
    }

    var symbol: String {
        switch self {
        case .note: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .translation: return "character.book.closed"
        case .password: return "key.horizontal"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }

    var keywords: [String] {
        switch self {
        case .note:
            return ["笔记", "便笺", "记事", "note", "notes", "markdown", "md"]
        case .clipboard:
            return ["剪贴板", "粘贴板", "剪贴板历史", "粘贴板历史", "clipboard", "pasteboard", "history"]
        case .translation:
            return ["翻译", "译文", "translate", "translation", "translator"]
        case .password:
            return ["密码", "口令", "password", "passwd", "随机密码", "生成密码"]
        case .chat:
            return ["对话", "聊天", "chat", "ai"]
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

enum SystemOperation: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case lockScreen
    case displaySleep
    case screenSaver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return "睡眠"
        case .lockScreen: return "锁定屏幕"
        case .displaySleep: return "关闭显示器"
        case .screenSaver: return "启动屏幕保护程序"
        }
    }

    var detail: String {
        switch self {
        case .sleep: return "让这台 Mac 立即进入睡眠"
        case .lockScreen: return "立即锁定 Mac 并返回登录界面"
        case .displaySleep: return "立即关闭显示器，Mac 继续运行"
        case .screenSaver: return "立即启动系统屏幕保护程序"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: return "moon.zzz"
        case .lockScreen: return "lock.fill"
        case .displaySleep: return "display"
        case .screenSaver: return "sparkles.rectangle.stack"
        }
    }

    var keywords: [String] {
        switch self {
        case .sleep:
            return ["睡眠", "休眠", "电脑睡眠", "系统睡眠", "mac 睡眠", "sleep", "sleep mac"]
        case .lockScreen:
            return ["锁屏", "锁定", "锁定屏幕", "锁定 mac", "lock", "lock screen", "lock mac"]
        case .displaySleep:
            return ["关闭显示器", "显示器睡眠", "熄屏", "关屏", "display sleep", "sleep display"]
        case .screenSaver:
            return ["屏幕保护", "屏幕保护程序", "屏保", "screensaver", "screen saver"]
        }
    }

    nonisolated static func matching(_ query: String) -> [SystemOperation] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return [] }

        // Short pure-ASCII prefixes are too ambiguous: `ma` must not hijack
        // the launcher by prefixing the compound keyword "mac 睡眠". CJK
        // prefixes stay loose (睡 → 睡眠), and three or more ASCII characters
        // still allow keyword prefix matching (mac → mac 睡眠).
        let canUsePrefix = normalized.unicodeScalars.contains { $0.properties.isIdeographic }
            || normalized.count >= 3
        return allCases.filter { operation in
            operation.keywords.contains { keyword in
                normalized == keyword
                    || (canUsePrefix && keyword.hasPrefix(normalized))
                    || normalized.hasPrefix(keyword + " ")
                    || normalized.hasSuffix(" " + keyword)
            }
        }
    }
}

enum LauncherFallbackAction: String, CaseIterable, Identifiable, Sendable {
    case googleSearch
    case askAI

    var id: String { rawValue }

    func title(for query: String) -> String {
        switch self {
        case .googleSearch: return "使用 Google 搜索"
        case .askAI: return "询问 AI"
        }
    }

    func detail(for query: String, provider: AIProvider, model: String) -> String {
        switch self {
        case .googleSearch:
            return "在默认浏览器中搜索“\(query)”"
        case .askAI:
            return "使用 \(provider.title) · \(model) 回答“\(query)”"
        }
    }

    var symbol: String {
        switch self {
        case .googleSearch: return "magnifyingglass"
        case .askAI: return "sparkles"
        }
    }

    func destinationURL(for query: String) -> URL? {
        guard self == .googleSearch else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

struct ApplicationRecord: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleIdentifier: String?
    var aliases: [String] = []

    var id: String { url.path }
}

enum ClipboardKind: String, Codable, Sendable {
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

struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
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

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case openRouter
    case gemini
    case deepSeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .gemini: return "Gemini"
        case .deepSeek: return "DeepSeek"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-5.6-luna"
        case .openRouter: return "deepseek-v4-flash-0731"
        case .gemini: return "gemini-3.5-flash"
        case .deepSeek: return "deepseek-v4-flash"
        }
    }
}
