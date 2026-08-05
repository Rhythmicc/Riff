import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum ChatDatabaseError: LocalizedError {
    case open(String)
    case statement(String)
    case execution(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): return "无法打开对话数据库：\(message)"
        case .statement(let message): return "无法准备对话数据库操作：\(message)"
        case .execution(let message): return "对话数据库操作失败：\(message)"
        }
    }
}

/// Durable chat store. Conversations and messages live in one WAL-mode SQLite
/// database; the schema mirrors `ChatConversation` / `ChatMessage` so the UI
/// model can keep its in-memory array as the single presentation source.
final class ChatDatabase {
    let url: URL
    private var connection: OpaquePointer?

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw ChatDatabaseError.open(message)
        }

        sqlite3_busy_timeout(connection, 2_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                model TEXT NOT NULL,
                provider TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY NOT NULL,
                conversation_id TEXT NOT NULL
                    REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
                content TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_messages_conversation
            ON messages(conversation_id, created_at)
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS chat_state (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                selected_conversation_id TEXT NOT NULL
            )
            """)
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    /// Loads every conversation with its messages, newest conversation first
    /// so reopening reproduces the in-memory ordering used by `ChatModel`.
    func loadAll() throws -> [ChatConversation] {
        var conversations = try loadConversationSummaries()
        for index in conversations.indices {
            conversations[index].messages = try loadMessages(
                conversationID: conversations[index].id
            )
        }
        return conversations
    }

    /// Loads conversation metadata only, without messages. `ChatModel` uses
    /// this at startup and loads messages lazily for the selected conversation.
    func loadConversationSummaries() throws -> [ChatConversation] {
        let conversationStatement = try prepare("""
            SELECT id, title, model, provider, created_at, updated_at
            FROM conversations
            ORDER BY created_at DESC, rowid DESC
            """)
        defer { sqlite3_finalize(conversationStatement) }

        var conversations: [ChatConversation] = []
        while sqlite3_step(conversationStatement) == SQLITE_ROW {
            guard let idString = text(conversationStatement, column: 0),
                  let id = UUID(uuidString: idString),
                  let title = text(conversationStatement, column: 1),
                  let model = text(conversationStatement, column: 2),
                  let provider = text(conversationStatement, column: 3) else { continue }
            conversations.append(ChatConversation(
                id: id,
                title: title,
                model: model,
                provider: provider,
                messages: [],
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(conversationStatement, 4)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(conversationStatement, 5))
            ))
        }
        try checkCompletion(of: conversationStatement)
        return conversations
    }

    func loadMessages(conversationID: UUID) throws -> [ChatMessage] {
        let statement = try prepare("""
            SELECT id, role, content, created_at
            FROM messages
            WHERE conversation_id = ?
            ORDER BY created_at ASC, rowid ASC
            """)
        defer { sqlite3_finalize(statement) }
        try bind(conversationID.uuidString, to: statement, index: 1)

        var messages: [ChatMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idString = text(statement, column: 0),
                  let id = UUID(uuidString: idString),
                  let roleValue = text(statement, column: 1),
                  let role = ChatRole(rawValue: roleValue),
                  let content = text(statement, column: 2) else { continue }
            messages.append(ChatMessage(
                id: id,
                role: role,
                content: content,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        try checkCompletion(of: statement)
        return messages
    }

    /// Replaces one conversation and all of its messages atomically.
    func upsertConversation(_ conversation: ChatConversation) throws {
        try upsertConversation(conversation, includeMessages: true)
    }

    func upsertConversation(
        _ conversation: ChatConversation,
        includeMessages: Bool
    ) throws {
        try transaction {
            let conversationStatement = try prepare("""
                INSERT INTO conversations
                    (id, title, model, provider, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    model = excluded.model,
                    provider = excluded.provider,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at
                """)
            defer { sqlite3_finalize(conversationStatement) }
            try bind(conversation.id.uuidString, to: conversationStatement, index: 1)
            try bind(conversation.title, to: conversationStatement, index: 2)
            try bind(conversation.model, to: conversationStatement, index: 3)
            try bind(conversation.provider, to: conversationStatement, index: 4)
            try bind(conversation.createdAt.timeIntervalSince1970, to: conversationStatement, index: 5)
            try bind(conversation.updatedAt.timeIntervalSince1970, to: conversationStatement, index: 6)
            try step(conversationStatement)

            guard includeMessages else { return }

            let deleteStatement = try prepare(
                "DELETE FROM messages WHERE conversation_id = ?"
            )
            defer { sqlite3_finalize(deleteStatement) }
            try bind(conversation.id.uuidString, to: deleteStatement, index: 1)
            try step(deleteStatement)

            for message in conversation.messages {
                let messageStatement = try prepare("""
                    INSERT INTO messages (id, conversation_id, role, content, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """)
                defer { sqlite3_finalize(messageStatement) }
                try bind(message.id.uuidString, to: messageStatement, index: 1)
                try bind(conversation.id.uuidString, to: messageStatement, index: 2)
                try bind(message.role.rawValue, to: messageStatement, index: 3)
                try bind(message.content, to: messageStatement, index: 4)
                try bind(message.createdAt.timeIntervalSince1970, to: messageStatement, index: 5)
                try step(messageStatement)
            }
        }
    }

    func deleteConversation(id: UUID) throws {
        let statement = try prepare("DELETE FROM conversations WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, to: statement, index: 1)
        try step(statement)
    }

    func setSelectedConversation(id: UUID) throws {
        let statement = try prepare("""
            INSERT OR REPLACE INTO chat_state (id, selected_conversation_id)
            VALUES (1, ?)
            """)
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, to: statement, index: 1)
        try step(statement)
    }

    func selectedConversationID() throws -> UUID? {
        let statement = try prepare(
            "SELECT selected_conversation_id FROM chat_state WHERE id = 1"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = text(statement, column: 0) else {
            try checkCompletion(of: statement)
            return nil
        }
        return UUID(uuidString: value)
    }

    /// Conversation ids whose title or any message content contains the query.
    func searchConversationIDs(matching query: String) throws -> Set<UUID> {
        let pattern = Self.likePattern(from: query)
        let statement = try prepare("""
            SELECT DISTINCT conversation_id FROM messages
            WHERE content LIKE '%' || ? || '%' ESCAPE '\\'
            UNION
            SELECT id FROM conversations
            WHERE title LIKE '%' || ? || '%' ESCAPE '\\'
            """)
        defer { sqlite3_finalize(statement) }
        try bind(pattern, to: statement, index: 1)
        try bind(pattern, to: statement, index: 2)

        var ids = Set<UUID>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = text(statement, column: 0),
               let id = UUID(uuidString: value) {
                ids.insert(id)
            }
        }
        try checkCompletion(of: statement)
        return ids
    }

    func checkpoint() {
        try? execute("PRAGMA wal_checkpoint(PASSIVE)")
    }

    private static func likePattern(from query: String) -> String {
        query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ChatDatabaseError.statement(errorMessage)
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32) throws {
        let result = value.withCString { pointer in
            sqlite3_bind_text(
                statement,
                index,
                pointer,
                Int32(value.lengthOfBytes(using: .utf8)),
                sqliteTransient
            )
        }
        guard result == SQLITE_OK else { throw currentError() }
    }

    private func bind(_ value: Double, to statement: OpaquePointer, index: Int32) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw currentError()
        }
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private func checkCompletion(of statement: OpaquePointer) throws {
        let status = sqlite3_errcode(connection)
        guard status == SQLITE_OK || status == SQLITE_DONE else { throw currentError() }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }

    private var errorMessage: String {
        connection.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable"
    }

    private func currentError() -> ChatDatabaseError {
        .execution(errorMessage)
    }
}
