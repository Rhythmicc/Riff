import Foundation

enum ComponentSurface: String, Codable, CaseIterable, Sendable {
    case launcher
    case panel
    case settings
}

enum ComponentPermission: String, Codable, CaseIterable, Sendable {
    case network
    case pasteboard
    case files
    case keychain
}

struct ComponentIcon: Codable, Equatable, Sendable {
    var systemName: String

    init(systemName: String) {
        self.systemName = systemName
    }
}

/// Stable identifiers for built-in components. Third-party components use
/// reverse-DNS ids from their manifest.
enum ComponentID {
    static let apps = "dev.rhythmicc.apps"
    static let clipboard = "dev.rhythmicc.clipboard"
    static let password = "dev.rhythmicc.password"
    static let note = "dev.rhythmicc.note"
    static let translation = "dev.rhythmicc.translation"
    static let chat = "dev.rhythmicc.chat"
    static let systemOperations = "dev.rhythmicc.system-operations"
}

struct ComponentDescriptor: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var version: String
    var author: String
    var keywords: [String]
    var surfaces: Set<ComponentSurface>
    var permissions: Set<ComponentPermission>
    var icon: ComponentIcon

    /// System-essential components (for example the application launcher)
    /// cannot be disabled and cannot be uninstalled.
    var isSystemEssential: Bool
}
