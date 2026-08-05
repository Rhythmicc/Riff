import Foundation

/// Discovers components. This phase only knows the built-in catalog; the
/// installed-component store for third-party components plugs in here later.
final class ComponentRegistry: Sendable {
    private let builtIn: [any RiffComponent]

    init(builtIn: [any RiffComponent] = BuiltinComponentCatalog.all) {
        self.builtIn = builtIn
    }

    func builtInComponents() -> [any RiffComponent] {
        builtIn
    }

    func component(id: String) -> (any RiffComponent)? {
        builtIn.first { $0.id == id }
    }

    func matching(
        _ query: String,
        mode: LauncherMode,
        enabledIDs: Set<String>
    ) -> [ComponentMatch] {
        builtIn.compactMap { component in
            guard enabledIDs.contains(component.id),
                  let priority = component.matchPriority(for: query, mode: mode)
            else { return nil }
            return ComponentMatch(componentID: component.id, priority: priority)
        }
        .sorted { $0.priority > $1.priority }
    }
}

enum BuiltinComponentCatalog {
    static let all: [any RiffComponent] = [
        AppsComponent(),
        ClipboardComponent(),
        PasswordComponent(),
        NoteComponent(),
        TranslationComponent(),
        ChatComponent(),
        SystemOperationsComponent()
    ]
}
