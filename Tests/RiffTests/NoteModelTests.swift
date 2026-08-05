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

    func testSearchFiltersByTitleAndText() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = NoteModel(directory: directory)
        model.updateSelectedTitle("会议记录")
        model.createNote()
        model.updateSelectedTitle("购物清单")
        model.updateSelectedText("# 购物清单\n\n牛奶、鸡蛋")

        model.searchQuery = "牛奶"
        XCTAssertEqual(model.filteredNotes.map(\.title), ["购物清单"])

        model.searchQuery = "会议"
        XCTAssertEqual(model.filteredNotes.map(\.title), ["会议记录"])

        model.searchQuery = ""
        XCTAssertEqual(model.filteredNotes.count, 2)
    }

    func testPinMovesNoteToFrontAndPersists() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = NoteModel(directory: directory)
        model.updateSelectedTitle("第一段")
        model.createNote()
        model.updateSelectedTitle("第二段")
        let second = model.selectedNote!
        model.togglePin(id: second.id)
        XCTAssertEqual(model.filteredNotes.map(\.title), ["第二段", "第一段"])
        model.flush()

        let restored = NoteModel(directory: directory)
        XCTAssertTrue(restored.notes.first { $0.title == "第二段" }?.isPinned == true)
    }

    func testDecodesLegacyArchiveWithoutPinField() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let json = """
        {
          "selectedNoteID": "\(id)",
          "notes": [
            {
              "id": "\(id)",
              "title": "旧笔记",
              "text": "# 旧笔记\\n\\n内容",
              "createdAt": 1000,
              "updatedAt": 2000
            }
          ]
        }
        """
        try json.write(
            to: directory.appendingPathComponent("notes.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = NoteModel(directory: directory)

        XCTAssertEqual(model.notes.count, 1)
        XCTAssertEqual(model.notes[0].title, "旧笔记")
        XCTAssertFalse(model.notes[0].isPinned)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
