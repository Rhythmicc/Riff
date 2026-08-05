import XCTest
@testable import Riff

@MainActor
final class ComponentManagerTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ComponentManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testDefaultEnablesEveryBuiltInComponent() {
        let manager = ComponentManager(defaults: makeDefaults())

        XCTAssertEqual(manager.components.count, 7)
        for component in manager.components {
            XCTAssertTrue(manager.isEnabled(component.id))
        }
    }

    func testSystemEssentialComponentCannotBeDisabled() {
        let manager = ComponentManager(defaults: makeDefaults())

        manager.setEnabled(ComponentID.apps, false)

        XCTAssertTrue(manager.isEnabled(ComponentID.apps))
    }

    func testDisablePersistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = ComponentManager(defaults: defaults)
        first.setEnabled(ComponentID.password, false)
        first.setEnabled(ComponentID.chat, false)

        let reopened = ComponentManager(defaults: defaults)

        XCTAssertFalse(reopened.isEnabled(ComponentID.password))
        XCTAssertFalse(reopened.isEnabled(ComponentID.chat))
        XCTAssertTrue(reopened.isEnabled(ComponentID.clipboard))
    }

    func testAppModelFiltersQuickActionsForDisabledComponents() {
        let defaults = makeDefaults()
        let manager = ComponentManager(defaults: defaults)
        manager.setEnabled(ComponentID.password, false)
        let model = AppModel(
            clipboard: ClipboardStore(startsMonitoring: false),
            componentManager: manager
        )

        model.query = "密码"

        XCTAssertFalse(model.quickActions.contains(.password))
        XCTAssertTrue(model.quickActions.isEmpty)
        XCTAssertFalse(model.isPasswordQuery)
    }

    func testAppModelGatesSystemOperationsByComponent() {
        let defaults = makeDefaults()
        let manager = ComponentManager(defaults: defaults)
        manager.setEnabled(ComponentID.systemOperations, false)
        let model = AppModel(
            clipboard: ClipboardStore(startsMonitoring: false),
            componentManager: manager
        )

        model.query = "睡眠"

        if case .search(let items, _, _) = model.state.content {
            XCTAssertFalse(items.contains { $0.category == .systemOperation })
        }
    }

    func testQuickActionComponentIDMapping() {
        XCTAssertEqual(AppModel.componentID(for: .note), ComponentID.note)
        XCTAssertEqual(AppModel.componentID(for: .clipboard), ComponentID.clipboard)
        XCTAssertEqual(AppModel.componentID(for: .translation), ComponentID.translation)
        XCTAssertEqual(AppModel.componentID(for: .password), ComponentID.password)
        XCTAssertEqual(AppModel.componentID(for: .chat), ComponentID.chat)
    }

    func testInstalledComponentMatchingAndAppModelRouting() async throws {
        let suiteName = "ComponentManagerInstalledTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-manager-installed-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manifest = ComponentManifest(
            schemaVersion: 1,
            id: "dev.example.traffic",
            name: "路况",
            version: "1.0.0",
            author: "Example",
            icon: "car.fill",
            keywords: ["路况", "traffic"],
            executable: "bin/run",
            permissions: [.network],
            timeoutMs: 3_000,
            surfaces: [.launcher]
        )
        try JSONEncoder().encode(manifest).write(to: source.appendingPathComponent("manifest.json"))
        let scriptURL = source.appendingPathComponent("bin/run")
        try """
        #!/bin/zsh
        read -r line
        print '{"results":[{"id":"1","title":"长安街 缓行","subtitle":"约 20 分钟","copy":"长安街 缓行"}]}'
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let store = InstalledComponentStore(
            rootDirectory: root.appendingPathComponent("components", isDirectory: true)
        )
        let manager = ComponentManager(
            registry: ComponentRegistry(installedStore: store),
            defaults: defaults
        )
        try manager.install(from: source)

        XCTAssertEqual(manager.installed.map(\.id), ["dev.example.traffic"])
        XCTAssertTrue(manager.isEnabled("dev.example.traffic"))
        XCTAssertNotNil(manager.installedMatch("路况", mode: .apps))

        let adapter = try XCTUnwrap(manager.installedComponents().first)
        let results = try await adapter.results(for: "路况")
        XCTAssertEqual(results.items.first?.title, "长安街 缓行")

        try manager.uninstall(id: "dev.example.traffic")
        XCTAssertTrue(manager.installed.isEmpty)
        XCTAssertNil(manager.installedMatch("路况", mode: .apps))
    }
}
