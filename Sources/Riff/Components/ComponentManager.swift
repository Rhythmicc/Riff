import Foundation

/// The single entry point for component state: enablement, discovery, and
/// launcher matching. `AppModel` and `SettingsView` depend on this type, not
/// on individual components.
@MainActor
final class ComponentManager: ObservableObject {
    @Published private(set) var enabledIDs: Set<String>

    private let registry: ComponentRegistry
    private let defaults: UserDefaults
    private static let enabledKey = "components.enabled"

    init(
        registry: ComponentRegistry = ComponentRegistry(),
        defaults: UserDefaults = .standard
    ) {
        self.registry = registry
        self.defaults = defaults

        let allIDs = Set(registry.builtInComponents().map(\.id))
        if let stored = defaults.stringArray(forKey: Self.enabledKey), !stored.isEmpty {
            var restored = Set(stored)
            // System-essential components are always re-enabled.
            for component in registry.builtInComponents()
            where component.descriptor.isSystemEssential {
                restored.insert(component.id)
            }
            enabledIDs = restored.intersection(allIDs)
        } else {
            enabledIDs = allIDs
            defaults.set(allIDs.sorted(), forKey: Self.enabledKey)
        }
    }

    var components: [any RiffComponent] {
        registry.builtInComponents()
    }

    func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let component = registry.component(id: id),
              !component.descriptor.isSystemEssential else { return }
        if enabled {
            enabledIDs.insert(id)
        } else {
            enabledIDs.remove(id)
        }
        defaults.set(enabledIDs.sorted(), forKey: Self.enabledKey)
    }

    func matching(_ query: String, mode: LauncherMode) -> [ComponentMatch] {
        registry.matching(query, mode: mode, enabledIDs: enabledIDs)
    }
}
