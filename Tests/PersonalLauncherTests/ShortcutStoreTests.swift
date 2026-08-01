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
        XCTAssertEqual(store.binding(for: .clipboard), .disabled)
        XCTAssertEqual(store.binding(for: .translation).displayName, "⌘ ⇧ T")
        XCTAssertEqual(store.binding(for: .note), .disabled)
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
        let clipboard = ShortcutBinding.key(8, modifiers: UInt32(cmdKey | optionKey), label: "C")
        XCTAssertTrue(store.update(clipboard, for: .clipboard))
        XCTAssertFalse(store.update(clipboard, for: .note))
        XCTAssertEqual(store.binding(for: .note), ShortcutStore.defaultBindings[.note])
        XCTAssertNotNil(store.errorMessage)
    }

    func testDisabledShortcutCanBeUsedByMultipleActions() {
        let store = ShortcutStore(defaults: defaults)
        XCTAssertTrue(store.update(.disabled, for: .clipboard))
        XCTAssertTrue(store.update(.disabled, for: .note))
        XCTAssertNil(store.errorMessage)
    }

    func testMigratesLegacyClipboardAndNoteDefaultsToDisabled() throws {
        let legacy: [String: ShortcutBinding] = [
            ShortcutAction.launcher.rawValue: .doubleShift,
            ShortcutAction.clipboard.rawValue: .key(9, modifiers: UInt32(optionKey), label: "V"),
            ShortcutAction.translation.rawValue: .key(17, modifiers: UInt32(cmdKey | shiftKey), label: "T"),
            ShortcutAction.note.rawValue: .key(45, modifiers: UInt32(optionKey), label: "N")
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "shortcuts.v1")

        let store = ShortcutStore(defaults: defaults)

        XCTAssertEqual(store.binding(for: .clipboard), .disabled)
        XCTAssertEqual(store.binding(for: .note), .disabled)
    }
}
