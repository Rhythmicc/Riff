import Foundation

/// Discovers components: the built-in catalog plus installed third-party
/// script components. The installed store is reloaded by `ComponentManager`,
/// so keystroke-path matching never scans the disk.
final class ComponentRegistry {
    private let builtIn: [any RiffComponent]
    let installedStore: InstalledComponentStore

    init(
        builtIn: [any RiffComponent] = BuiltinComponentCatalog.all,
        installedStore: InstalledComponentStore = InstalledComponentStore()
    ) {
        self.builtIn = builtIn
        self.installedStore = installedStore
    }

    func builtInComponents() -> [any RiffComponent] {
        builtIn
    }

    func installedComponents() -> [ScriptComponentAdapter] {
        installedStore.loadInstalled().map(ScriptComponentAdapter.init)
    }

    func matching(
        _ query: String,
        mode: LauncherMode,
        enabledIDs: Set<String>,
        installed: [ScriptComponentAdapter] = []
    ) -> [ComponentMatch] {
        let components = builtIn + installed
        return components.compactMap { component in
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
