import Carbon
import Foundation

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case launcher
    case clipboard
    case translation
    case note
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launcher: "应用启动器"
        case .clipboard: "剪贴板历史"
        case .translation: "翻译选中文本"
        case .note: "置顶便笺"
        case .chat: "AI 对话"
        }
    }

    var hotKeyIdentifier: UInt32 {
        switch self {
        case .launcher: 1
        case .clipboard: 2
        case .translation: 3
        case .note: 4
        case .chat: 5
        }
    }
}

enum ShortcutKind: String, Codable {
    case disabled
    case keyCombination
    case doubleShift
}

struct ShortcutBinding: Codable, Equatable {
    let kind: ShortcutKind
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let disabled = ShortcutBinding(
        kind: .disabled,
        keyCode: 0,
        modifiers: 0,
        keyLabel: ""
    )

    static let doubleShift = ShortcutBinding(
        kind: .doubleShift,
        keyCode: 0,
        modifiers: 0,
        keyLabel: "Shift"
    )

    static func key(_ keyCode: UInt32, modifiers: UInt32, label: String) -> ShortcutBinding {
        ShortcutBinding(
            kind: .keyCombination,
            keyCode: keyCode,
            modifiers: modifiers,
            keyLabel: label.uppercased()
        )
    }

    var displayName: String {
        switch kind {
        case .disabled: return "未设置"
        case .doubleShift: return "⇧ ⇧"
        case .keyCombination: break
        }
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        parts.append(keyLabel)
        return parts.joined(separator: " ")
    }
}

@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var bindings: [ShortcutAction: ShortcutBinding]
    @Published var errorMessage: String?

    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private let defaultsKey = "shortcuts.v1"
    private let defaultsMigrationKey = "shortcuts.emptyClipboardAndNoteDefaults.v2"

    static let defaultBindings: [ShortcutAction: ShortcutBinding] = [
        .launcher: .doubleShift,
        .clipboard: .disabled,
        .translation: .key(17, modifiers: UInt32(cmdKey | shiftKey), label: "T"),
        .note: .disabled,
        .chat: .disabled
    ]

    private static let legacyDefaultBindings: [ShortcutAction: ShortcutBinding] = [
        .clipboard: .key(9, modifiers: UInt32(optionKey), label: "V"),
        .note: .key(45, modifiers: UInt32(optionKey), label: "N")
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var resolved = Self.defaultBindings
        if let data = defaults.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            for action in ShortcutAction.allCases {
                if let binding = stored[action.rawValue] {
                    resolved[action] = binding
                }
            }
        }

        if !defaults.bool(forKey: defaultsMigrationKey) {
            for action in [ShortcutAction.clipboard, .note]
            where resolved[action] == Self.legacyDefaultBindings[action] {
                resolved[action] = .disabled
            }
            defaults.set(true, forKey: defaultsMigrationKey)
            let stored = Dictionary(uniqueKeysWithValues: resolved.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(stored) {
                defaults.set(data, forKey: defaultsKey)
            }
        }

        bindings = resolved
    }

    func binding(for action: ShortcutAction) -> ShortcutBinding {
        bindings[action] ?? Self.defaultBindings[action]!
    }

    @discardableResult
    func update(_ binding: ShortcutBinding, for action: ShortcutAction) -> Bool {
        if binding.kind != .disabled,
           let conflict = bindings.first(where: { otherAction, otherBinding in
            otherAction != action && otherBinding == binding
        })?.key {
            errorMessage = "这个快捷键已用于“\(conflict.title)”。"
            return false
        }

        var next = bindings
        next[action] = binding
        bindings = next
        errorMessage = nil
        persist()
        onChange?()
        return true
    }

    func resetDefaults() {
        bindings = Self.defaultBindings
        errorMessage = nil
        persist()
        onChange?()
    }

    func clearRegistrationError() {
        errorMessage = nil
    }

    func reportRegistrationFailure(for action: ShortcutAction) {
        errorMessage = "“\(action.title)”的快捷键已被其他应用占用，请换一个组合。"
    }

    private func persist() {
        let stored = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
