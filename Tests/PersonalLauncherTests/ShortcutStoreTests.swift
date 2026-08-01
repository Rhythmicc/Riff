import Carbon
import XCTest
@testable import PersonalLauncher

@MainActor
final class ShortcutStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ShortcutStoreTests")!
        defaults.removePersistentDomain(forName: "ShortcutStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ShortcutStoreTests")
        defaults = nil
        super.tearDown()
    }

    func testDefaultBindingsMatchProductShortcuts() {
        let store = ShortcutStore(defaults: defaults)
        XCTAssertEqual(store.binding(for: .launcher).displayName, "⇧ ⇧")
        XCTAssertEqual(store.binding(for: .clipboard).displayName, "⌥ V")
        XCTAssertEqual(store.binding(for: .translation).displayName, "⌘ ⇧ T")
        XCTAssertEqual(store.binding(for: .note).displayName, "⌥ N")
    }

    func testUpdatePersistsAcrossStoreInstances() {
        let store = ShortcutStore(defaults: defaults)
        let custom = ShortcutBinding.key(8, modifiers: UInt32(cmdKey | optionKey), label: "C")
        XCTAssertTrue(store.update(custom, for: .clipboard))

        let reloaded = ShortcutStore(defaults: defaults)
        XCTAssertEqual(reloaded.binding(for: .clipboard), custom)
    }

    func testDuplicateShortcutIsRejected() {
        let store = ShortcutStore(defaults: defaults)
        let clipboard = store.binding(for: .clipboard)
        XCTAssertFalse(store.update(clipboard, for: .note))
        XCTAssertEqual(store.binding(for: .note), ShortcutStore.defaultBindings[.note])
        XCTAssertNotNil(store.errorMessage)
    }
}
