# AI 对话 SQLite 迁移设计

## 1. 现状问题

`ChatModel` 把全部对话保存在一个 `chat.json`（`Archive { conversations, selectedConversationID }`）里，任何改动都整文件序列化 + 原子写入：

- 对话越多文件越大，每次流式结束都重写整个历史。
- 无法做增量加载、搜索、分页。
- 与剪贴板历史（已经是 SQLite）的存储策略不一致。

## 2. 目标

- `ChatDatabase` 成为对话数据的唯一持久化层，WAL 模式，接口风格对齐 `ClipboardDatabase`。
- `ChatModel` 保持内存数组作为 UI 唯一数据源，只把写路径换成数据库。
- 首次启动自动从 `chat.json` 迁移，成功后旧文件改名保留（`chat.json.migrated`）而不是直接删除。

## 3. Schema

```sql
CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    model TEXT NOT NULL,
    provider TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY NOT NULL,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation
    ON messages(conversation_id, created_at);

CREATE TABLE IF NOT EXISTS chat_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    selected_conversation_id TEXT NOT NULL
);
```

`conversations` 保留 `provider` 字段，因为 v0.5.0 之后每段对话独立选择模型，后续可能也要记录 provider 来源。

## 4. ChatDatabase API

```swift
final class ChatDatabase {
    init(url: URL) throws          // 打开 WAL，建表，busy_timeout=2000

    func loadConversationSummaries() throws -> [ChatConversationSummary]
    func loadMessages(conversationID: UUID) throws -> [ChatMessage]
    func upsertConversation(_ conversation: ChatConversation) throws
    func insertMessage(_ message: ChatMessage, conversationID: UUID) throws
    func updateMessageContent(id: UUID, content: String) throws
    func deleteConversation(id: UUID) throws          // 级联删除消息
    func setSelectedConversation(id: UUID) throws
    func selectedConversationID() throws -> UUID?
}
```

写入全部走显式事务；`ChatModel` 的 300ms 防抖 `scheduleSave()` 保留，但每次保存只 upsert 变更的 conversation 和新增/变更的 message。

## 5. ChatModel 改造

```swift
@MainActor
final class ChatModel: ObservableObject {
    private let database: ChatDatabase

    init(settings: SettingsStore, noteModel: NoteModel? = nil, database: ChatDatabase? = nil) {
        // database 参数用于测试注入；生产路径默认打开
        // ~/Library/Application Support/Riff/chat.sqlite3
    }
}
```

关键变化：

- `init`：打开数据库 → 执行 `ChatMigration.migrateIfNeeded(database:legacyURL:)` → 加载对话摘要和选中 id → 按需 `loadMessages`。
- `send`：追加 user 消息后立即 `insertMessage`；流式结束后用最终文本 `updateMessageContent`（或补插 assistant 消息）。
- `deleteSelectedConversation` / `renameSelected` / `updateSelectedModel` / `importInquiry`：对应 `ChatDatabase` 写接口。
- `flush()`：`saveTask?.cancel()` 后同步 `saveImmediately()`，退出时由 `AppDelegate.applicationWillTerminate` 调用。
- 流式中途崩溃最多丢一条未完成的 assistant 消息（与当前 JSON 方案行为一致，但不再丢整个文件）。

## 6. 迁移策略

```swift
enum ChatMigration {
    static func migrateIfNeeded(
        database: ChatDatabase,
        legacyURL: URL
    ) throws
}
```

1. 若 `conversations` 表非空：跳过（可能是重复启动或用户已清空对话，尊重现状）。
2. 若 `chat.json` 存在：解码 `Archive`，逐对话/逐消息 upsert，最后写 `chat_state`。
3. 成功后将 `chat.json` 重命名为 `chat.json.migrated`；失败则保持原文件不动并记录 `DiagnosticLogger`。
4. 迁移幂等：失败重试不会产生重复行（主键约束）。

## 7. 文件布局

```text
Sources/Riff/Services/ChatDatabase.swift
Sources/Riff/Services/ChatMigration.swift
```

## 8. 测试计划

- `ChatDatabaseTests`：建库、upsert/load/update/delete、级联删除、WAL 打开、并发写（FULLMUTEX）。
- `ChatMigrationTests`：空库 + 无文件、空库 + 旧文件、非空库 + 旧文件（跳过）、迁移后旧文件改名、失败回滚。
- `ChatModelTests`：适配注入的 `ChatDatabase`，验证发送/流式结束/删除/导入后数据库与内存一致。
