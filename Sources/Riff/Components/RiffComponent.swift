import Foundation

struct ComponentResults: Sendable {
    var items: [ComponentResultItem]
    var isComplete: Bool

    static let empty = ComponentResults(items: [], isComplete: true)
}

struct ComponentResultItem: Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var icon: ComponentIcon?
    var actions: [ComponentAction]
}

enum ComponentAction: Sendable {
    case copy(String)
    case openURL(URL)
    case callback(id: String, payload: [String: String])
    case openPanel(panelID: String)
}

struct ComponentMatch: Sendable, Equatable {
    var componentID: String
    var priority: Int
}

/// A user-facing Riff capability. Built-in components implement this directly;
/// third-party components will be adapted through a script host in a later
/// phase while presenting the same surface to the launcher and settings.
protocol RiffComponent: Identifiable, Sendable {
    var id: String { get }
    var descriptor: ComponentDescriptor { get }

    /// Returns a positive priority when the component wants to answer the
    /// current launcher query. Higher priority wins when multiple components
    /// match; `nil` means the component is not interested.
    func matchPriority(for query: String, mode: LauncherMode) -> Int?

    func results(for query: String) async throws -> ComponentResults

    func perform(_ action: ComponentAction) async throws
}
