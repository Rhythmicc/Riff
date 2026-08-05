import XCTest
@testable import Riff

final class ChatDatabaseTests: XCTestCase {
    private func makeDatabase() throws -> (ChatDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-chat-db-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("chat.sqlite3")
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
            )
        }
        return (try ChatDatabase(url: url), url)
    }

    private func makeConversation(
        title: String,
        model: String,
        messages: [ChatMessage] = []
    ) -> ChatConversation {
        ChatConversation(
            title: title,
            model: model,
            provider: "deepseek",
            messages: messages,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
    }

    func testOpenCreatesSchemaAndRoundTripsConversations() throws {
        let (database, _) = try makeDatabase()
        var conversation = makeConversation(
            title: "北京天气",
            model: "deepseek-v4-flash",
            messages: [
                ChatMessage(role: .user, content: "北京天气"),
                ChatMessage(role: .assistant, content: "35°C 晴朗")
            ]
        )
        try database.upsertConversation(conversation)

        let loaded = try database.loadAll()
        XCTAssertEqual(loaded.count, 1)
        conversation.messages.removeAll()
        XCTAssertEqual(loaded[0].title, "北京天气")
        XCTAssertEqual(loaded[0].model, "deepseek-v4-flash")
        XCTAssertEqual(loaded[0].provider, "deepseek")
        XCTAssertEqual(loaded[0].messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(loaded[0].messages.map(\.content), ["北京天气", "35°C 晴朗"])
    }

    func testUpsertReplacesConversationAndMessages() throws {
        let (database, _) = try makeDatabase()
        var conversation = makeConversation(title: "旧标题", model: "m1", messages: [
            ChatMessage(role: .user, content: "旧内容")
        ])
        try database.upsertConversation(conversation)

        conversation.title = "新标题"
        conversation.model = "m2"
        conversation.messages = [
            ChatMessage(role: .user, content: "新内容"),
            ChatMessage(role: .assistant, content: "回答")
        ]
        try database.upsertConversation(conversation)

        let loaded = try database.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "新标题")
        XCTAssertEqual(loaded[0].model, "m2")
        XCTAssertEqual(loaded[0].messages.map(\.content), ["新内容", "回答"])
    }

    func testDeleteConversationCascadesMessages() throws {
        let (database, _) = try makeDatabase()
        let conversation = makeConversation(title: "待删除", model: "m", messages: [
            ChatMessage(role: .user, content: "内容")
        ])
        try database.upsertConversation(conversation)

        try database.deleteConversation(id: conversation.id)

        XCTAssertTrue(try database.loadAll().isEmpty)
    }

    func testSelectedConversationStatePersists() throws {
        let (database, _) = try makeDatabase()
        let first = makeConversation(title: "第一段", model: "m1")
        let second = makeConversation(title: "第二段", model: "m2")
        try database.upsertConversation(first)
        try database.upsertConversation(second)

        try database.setSelectedConversation(id: second.id)

        XCTAssertEqual(try database.selectedConversationID(), second.id)
    }

    func testLoadsNewestConversationFirst() throws {
        let (database, _) = try makeDatabase()
        let older = ChatConversation(
            title: "旧对话",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let newer = ChatConversation(
            title: "新对话",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        try database.upsertConversation(older)
        try database.upsertConversation(newer)

        XCTAssertEqual(try database.loadAll().map(\.title), ["新对话", "旧对话"])
    }
}
