import AppKit
import XCTest
@testable import Riff

final class AppearanceSettingsTests: XCTestCase {
    @MainActor
    func testNativeGlassBackdropKeepsItsMaterialWhileItsShapeChanges() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Native Liquid Glass requires macOS 26 or newer.")
        }

        let backdrop = RiffGlassBackdropView()
        backdrop.update(
            cornerRadius: 31,
            opacity: 0.62,
            interactive: true,
            animated: false
        )

        XCTAssertEqual(backdrop.style, .regular)
        XCTAssertEqual(backdrop.cornerRadius, 31, accuracy: 0.001)
        XCTAssertEqual(backdrop.alphaValue, 0.62, accuracy: 0.001)
        if #available(macOS 27.0, *) {
            XCTAssertTrue(backdrop.effectIsInteractive)
        }

        backdrop.update(
            cornerRadius: 18,
            opacity: 0.62,
            interactive: true,
            animated: false
        )

        XCTAssertEqual(backdrop.style, .regular)
        XCTAssertEqual(backdrop.cornerRadius, 18, accuracy: 0.001)
    }

    @MainActor
    func testGlassOpacityPersistsAndRestores() {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.glassOpacity, AppearancePreferences.defaultGlassOpacity)

        settings.glassOpacity = 0.43
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.glassOpacity, 0.43, accuracy: 0.001)
    }

    @MainActor
    func testGlassOpacityIsClampedToReadableRange() {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)

        settings.glassOpacity = -1
        XCTAssertEqual(settings.glassOpacity, AppearancePreferences.glassOpacityRange.lowerBound)

        settings.glassOpacity = 2
        XCTAssertEqual(settings.glassOpacity, AppearancePreferences.glassOpacityRange.upperBound)
    }
}
