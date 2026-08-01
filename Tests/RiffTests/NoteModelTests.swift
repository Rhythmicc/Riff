import Foundation
import XCTest
@testable import Riff

@MainActor
final class NoteModelTests: XCTestCase {
    func testMigratesLegacyNoteAndPersistsMultipleNotes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# 旧便笺\n\n迁移内容".write(
            to: directory.appendingPathComponent("note.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = NoteModel(directory: directory)
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertEqual(model.selectedTitle, "旧便笺")
        XCTAssertTrue(model.selectedText.contains("迁移内容"))

        model.createNote()
        model.updateSelectedText("# 项目计划\n\n- 第一项")
        XCTAssertEqual(model.selectedTitle, "项目计划")
        model.flush()

        let restored = NoteModel(directory: directory)
        XCTAssertEqual(restored.notes.count, 2)
        XCTAssertEqual(restored.selectedTitle, "项目计划")
        XCTAssertTrue(restored.selectedText.contains("第一项"))
    }

    func testDeletingLastNoteCreatesFreshNote() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = NoteModel(directory: directory)
        model.deleteSelectedNote()

        XCTAssertEqual(model.notes.count, 1)
        XCTAssertFalse(model.selectedText.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
