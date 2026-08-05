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

    func testMatchingRespectsEnablement() {
        let defaults = makeDefaults()
        let manager = ComponentManager(defaults: defaults)

        XCTAssertEqual(
            manager.matching("密码", mode: .apps).map(\.componentID),
            [ComponentID.password]
        )

        manager.setEnabled(ComponentID.password, false)
        XCTAssertTrue(manager.matching("密码", mode: .apps).isEmpty)
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

        if case .systemOperations = model.state.content {
            XCTFail("system operations should be disabled")
        }
    }

    func testQuickActionComponentIDMapping() {
        XCTAssertEqual(AppModel.componentID(for: .note), ComponentID.note)
        XCTAssertEqual(AppModel.componentID(for: .clipboard), ComponentID.clipboard)
        XCTAssertEqual(AppModel.componentID(for: .translation), ComponentID.translation)
        XCTAssertEqual(AppModel.componentID(for: .password), ComponentID.password)
        XCTAssertEqual(AppModel.componentID(for: .chat), ComponentID.chat)
    }
}
