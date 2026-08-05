import XCTest
@testable import Riff

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    func testClipboardModeLoadsEntireHistoryNotJustTheFirstSeven() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-clipboard-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try ClipboardDatabase(
            url: directory.appendingPathComponent("clipboard.sqlite3")
        )
        for index in 0..<71 {
            try database.upsert(ClipboardItem(
                kind: .text,
                text: "历史条目 \(index)",
                createdAt: Date().addingTimeInterval(-Double(index) * 60)
            ))
        }

        let store = ClipboardStore(
            pasteboard: NSPasteboard(name: NSPasteboard.Name("history-\(UUID().uuidString)")),
            applicationSupportDirectory: directory,
            startsMonitoring: false
        )
        let model = AppModel(clipboard: store)

        model.switchMode(.clipboard)

        XCTAssertEqual(model.filteredClipboard.count, 71)
        XCTAssertEqual(model.clipboardSections.reduce(0) { $0 + $1.items.count }, 71)
    }
}
