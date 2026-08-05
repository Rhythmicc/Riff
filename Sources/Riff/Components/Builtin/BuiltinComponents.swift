import Foundation

/// The application launcher itself. Essential; it is the default surface when
/// no other component matches.
struct AppsComponent: RiffComponent {
    let id = ComponentID.apps

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: "应用启动",
            version: "1.0.0",
            author: "Riff",
            keywords: [],
            surfaces: [.launcher],
            permissions: [],
            icon: ComponentIcon(systemName: "square.grid.2x2"),
            isSystemEssential: true
        )
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? { nil }
    func results(for query: String) async throws -> ComponentResults { .empty }
    func perform(_ action: ComponentAction) async throws {}
}

struct ClipboardComponent: RiffComponent {
    let id = ComponentID.clipboard

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: "剪贴板历史",
            version: "1.0.0",
            author: "Riff",
            keywords: ["剪贴板", "粘贴板", "剪贴板历史", "粘贴板历史", "clipboard", "pasteboard", "history"],
            surfaces: [.launcher, .panel],
            permissions: [.pasteboard, .files],
            icon: ComponentIcon(systemName: "doc.on.clipboard"),
            isSystemEssential: false
        )
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? {
        LauncherQuickAction.matching(query).contains(.clipboard) ? 20 : nil
    }

    func results(for query: String) async throws -> ComponentResults { .empty }
    func perform(_ action: ComponentAction) async throws {}
}

struct PasswordComponent: RiffComponent {
    let id = ComponentID.password

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: "随机密码",
            version: "1.0.0",
            author: "Riff",
            keywords: ["密码", "口令", "password", "passwd", "随机密码", "生成密码", "pwgen"],
            surfaces: [.launcher],
            permissions: [.pasteboard],
            icon: ComponentIcon(systemName: "key.horizontal"),
            isSystemEssential: false
        )
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? {
        LauncherQuickAction.matching(query).contains(.password) ? 20 : nil
    }

    func results(for query: String) async throws -> ComponentResults { .empty }
    func perform(_ action: ComponentAction) async throws {}
}

struct NoteComponent: RiffComponent {
    let id = ComponentID.note

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: "便笺",
            version: "1.0.0",
            author: "Riff",
            keywords: ["笔记", "便笺", "记事", "note", "notes", "markdown", "md"],
            surfaces: [.launcher, .panel],
            permissions: [.files],
            icon: ComponentIcon(systemName: "note.text"),
            isSystemEssential: false
        )
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? {
        LauncherQuickAction.matching(query).contains(.note) ? 20 : nil
    }

    func results(for query: String) async throws -> ComponentResults { .empty }
    func perform(_ action: ComponentAction) async throws {}
}

struct TranslationComponent: RiffComponent {
    let id = ComponentID.translation

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: "翻译",
            version: "1.0.0",
            author: "Riff",
            keywords: ["翻译", "译文", "translate", "translation", "translator"],
            surfaces: [.launcher, .panel],
            permissions: [.network],
            icon: ComponentIcon(systemName: "character.book.closed"),
            isSystemEssential: false
        )
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? {
        LauncherQuickAction.matching(query).contains(.translation) ? 20 : nil
    }

    func results(for query: String) async throws -> ComponentResults { .empty }
    func perform(_ action: ComponentAction) async throws {}
}

struct ChatComponent: RiffComponent {
    let id = ComponentID.chat

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: "AI 对话",
            version: "1.0.0",
            author: "Riff",
            keywords: ["对话", "聊天", "chat", "ai"],
            surfaces: [.launcher, .panel],
            permissions: [.network, .pasteboard],
            icon: ComponentIcon(systemName: "bubble.left.and.bubble.right"),
            isSystemEssential: false
        )
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? {
        LauncherQuickAction.matching(query).contains(.chat) ? 20 : nil
    }

    func results(for query: String) async throws -> ComponentResults { .empty }
    func perform(_ action: ComponentAction) async throws {}
}

struct SystemOperationsComponent: RiffComponent {
    let id = ComponentID.systemOperations

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: "系统操作",
            version: "1.0.0",
            author: "Riff",
            keywords: ["睡眠", "锁屏", "关闭显示器", "屏保", "sleep", "lock screen"],
            surfaces: [.launcher],
            permissions: [],
            icon: ComponentIcon(systemName: "power"),
            isSystemEssential: false
        )
    }

    func matchPriority(for query: String, mode: LauncherMode) -> Int? { nil }
    func results(for query: String) async throws -> ComponentResults { .empty }
    func perform(_ action: ComponentAction) async throws {}
}
