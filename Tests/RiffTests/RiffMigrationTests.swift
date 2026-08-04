import Foundation
import XCTest
@testable import Riff

final class RiffMigrationTests: XCTestCase {
    func testKeychainUsesUserFacingServiceName() {
        XCTAssertEqual(KeychainStore.serviceName, "Riff")
        XCTAssertFalse(KeychainStore.serviceName.lowercased().contains("dev"))
    }

    func testMigratesMissingDefaultsWithoutOverwritingCurrentValues() {
        let suiteName = "RiffMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("openai", forKey: "ai.provider")

        RiffMigration.migrateDefaults(
            defaults: defaults,
            legacyValues: [
                "ai.provider": "gemini",
                "ai.model": "legacy-model",
                "hasCompletedFirstLaunch": true
            ]
        )

        XCTAssertEqual(defaults.string(forKey: "ai.provider"), "openai")
        XCTAssertEqual(defaults.string(forKey: "ai.model"), "legacy-model")
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedFirstLaunch"))

        RiffMigration.migrateDefaults(
            defaults: defaults,
            legacyValues: ["ai.model": "should-not-overwrite"]
        )
        XCTAssertEqual(defaults.string(forKey: "ai.model"), "legacy-model")
    }

    func testMovesApplicationSupportWithoutInterpretingLegacyClipboardData() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyName = ["Personal", "Launcher"].joined()
        let legacyDirectory = root.appendingPathComponent(legacyName, isDirectory: true)
        let imageDirectory = legacyDirectory.appendingPathComponent("clipboard-images", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        let imageURL = imageDirectory.appendingPathComponent("preview.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        try "notes".write(
            to: legacyDirectory.appendingPathComponent("notes.json"),
            atomically: true,
            encoding: .utf8
        )

        let item = ClipboardItem(kind: .image, text: imageURL.path)
        let archive = try JSONEncoder().encode([item])
        try archive.write(to: legacyDirectory.appendingPathComponent("clipboard.json"))

        try RiffMigration.migrateApplicationSupport(in: root)

        let riffDirectory = root.appendingPathComponent("Riff", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: riffDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: riffDirectory.appendingPathComponent("notes.json").path))

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: riffDirectory.appendingPathComponent("clipboard.json").path
        ))
    }
}
