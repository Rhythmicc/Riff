import AppKit
import XCTest
@testable import Riff

final class ClipboardDatabaseTests: XCTestCase {
    func testDatabaseKeepsAnUnboundedNumberOfTextRecords() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try ClipboardDatabase(url: directory.appendingPathComponent("clipboard.sqlite3"))

        for index in 0..<175 {
            try database.upsert(ClipboardItem(
                kind: .text,
                text: "permanent text \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }

        let loaded = try database.loadAll()
        XCTAssertEqual(loaded.count, 175)
        XCTAssertEqual(loaded.first?.text, "permanent text 174")
        XCTAssertEqual(loaded.last?.text, "permanent text 0")
    }

    func testRecopyingContentMovesOneExistingRecordToTheTop() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try ClipboardDatabase(url: directory.appendingPathComponent("clipboard.sqlite3"))
        let original = ClipboardItem(
            kind: .text,
            text: "same text",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ClipboardItem(
            kind: .text,
            text: "same text",
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try database.upsert(original)
        try database.upsert(newer)

        let loaded = try database.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, newer.id)
        XCTAssertEqual(loaded.first?.createdAt, newer.createdAt)
    }

    @MainActor
    func testTextHistorySurvivesStoreRecreationAndCanBeManaged() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(name: .init("RiffTests.Clipboard.\(UUID().uuidString)"))
        pasteboard.clearContents()

        var store: ClipboardStore? = ClipboardStore(
            pasteboard: pasteboard,
            applicationSupportDirectory: directory,
            startsMonitoring: false
        )
        pasteboard.clearContents()
        pasteboard.setString("first permanent text", forType: .string)
        store?.captureIfNeeded()
        pasteboard.clearContents()
        pasteboard.setString("second permanent text", forType: .string)
        store?.captureIfNeeded()
        XCTAssertEqual(store?.items.count, 2)
        store = nil

        let reopened = ClipboardStore(
            pasteboard: pasteboard,
            applicationSupportDirectory: directory,
            startsMonitoring: false
        )
        XCTAssertEqual(reopened.items.map(\.text), [
            "second permanent text",
            "first permanent text"
        ])

        reopened.remove(reopened.items[0])
        let afterRemoval = ClipboardStore(
            pasteboard: pasteboard,
            applicationSupportDirectory: directory,
            startsMonitoring: false
        )
        XCTAssertEqual(afterRemoval.items.map(\.text), ["first permanent text"])

        afterRemoval.clear()
        let afterClear = ClipboardStore(
            pasteboard: pasteboard,
            applicationSupportDirectory: directory,
            startsMonitoring: false
        )
        XCTAssertTrue(afterClear.items.isEmpty)
    }

    @MainActor
    func testLegacyJSONIsNotImportedIntoTheNewDatabase() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = [ClipboardItem(kind: .text, text: "legacy text")]
        try JSONEncoder().encode(legacy).write(
            to: directory.appendingPathComponent("clipboard.json")
        )
        let pasteboard = NSPasteboard(name: .init("RiffTests.Clipboard.\(UUID().uuidString)"))

        let store = ClipboardStore(
            pasteboard: pasteboard,
            applicationSupportDirectory: directory,
            startsMonitoring: false
        )

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("clipboard.sqlite3").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("clipboard.json").path
        ))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-clipboard-\(UUID().uuidString)", isDirectory: true)
    }
}
