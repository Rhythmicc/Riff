import AppKit
import Foundation

/// The single entry point for component state: enablement, discovery,
/// installation, and launcher matching. `AppModel` and `SettingsView` depend
/// on this type, not on individual components.
@MainActor
final class ComponentManager: ObservableObject {
    @Published private(set) var enabledIDs: Set<String>
    @Published private(set) var installed: [InstalledComponent]

    private let registry: ComponentRegistry
    private let defaults: UserDefaults
    private static let enabledKey = "components.enabled"

    init(
        registry: ComponentRegistry = ComponentRegistry(),
        defaults: UserDefaults = .standard
    ) {
        self.registry = registry
        self.defaults = defaults
        let loadedInstalled = registry.installedStore.loadInstalled()
        self.installed = loadedInstalled

        let builtInIDs = Set(registry.builtInComponents().map(\.id))
        let allIDs = builtInIDs.union(loadedInstalled.map(\.id))
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

    func installedComponents() -> [ScriptComponentAdapter] {
        installed.map(ScriptComponentAdapter.init)
    }

    func component(id: String) -> (any RiffComponent)? {
        registry.builtInComponents().first { $0.id == id }
            ?? installedComponents().first { $0.id == id }
    }

    func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let component = component(id: id),
              !component.descriptor.isSystemEssential else { return }
        if enabled {
            enabledIDs.insert(id)
        } else {
            enabledIDs.remove(id)
        }
        defaults.set(enabledIDs.sorted(), forKey: Self.enabledKey)
    }

    /// Best matching *installed* component for the launcher, or nil when only
    /// built-in quick actions match (those stay as native quick-action rows).
    func installedMatch(_ query: String, mode: LauncherMode) -> (any RiffComponent)? {
        installedComponents()
            .filter { isEnabled($0.id) }
            .compactMap { component in
                component.matchPriority(for: query, mode: mode).map {
                    (component: component, priority: $0)
                }
            }
            .max { $0.priority < $1.priority }?
            .component
    }

    func install(from url: URL) throws {
        let installedComponent = try registry.installedStore.install(from: url)
        refreshInstalled()
        enabledIDs.insert(installedComponent.id)
        defaults.set(enabledIDs.sorted(), forKey: Self.enabledKey)
    }

    func uninstall(id: String) throws {
        try registry.installedStore.uninstall(id: id)
        refreshInstalled()
        enabledIDs.remove(id)
        defaults.set(enabledIDs.sorted(), forKey: Self.enabledKey)
    }

    func openComponentsDirectory() {
        try? FileManager.default.createDirectory(
            at: registry.installedStore.rootDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(registry.installedStore.rootDirectory)
    }

    private func refreshInstalled() {
        installed = registry.installedStore.loadInstalled()
    }
}
