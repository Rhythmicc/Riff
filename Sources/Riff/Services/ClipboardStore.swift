import AppKit
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum ClipboardDatabaseError: LocalizedError {
    case open(String)
    case statement(String)
    case execution(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): return "无法打开本地剪贴板数据库：\(message)"
        case .statement(let message): return "无法准备本地数据库操作：\(message)"
        case .execution(let message): return "本地数据库操作失败：\(message)"
        }
    }
}

/// A deliberately small SQLite boundary. Clipboard contents never leave this
/// database or the managed image directory beside it.
final class ClipboardDatabase {
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
            throw ClipboardDatabaseError.open(message)
        }

        sqlite3_busy_timeout(connection, 2_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("""
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at REAL NOT NULL,
                UNIQUE(kind, content)
            )
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS clipboard_items_created_at
            ON clipboard_items(created_at DESC)
            """)
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    func loadAll() throws -> [ClipboardItem] {
        let statement = try prepare("""
            SELECT id, kind, content, created_at
            FROM clipboard_items
            ORDER BY created_at DESC, rowid DESC
            """)
        defer { sqlite3_finalize(statement) }

        var result: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                  let kindValue = text(statement, column: 1),
                  let kind = ClipboardKind(rawValue: kindValue),
                  let content = text(statement, column: 2) else { continue }
            result.append(ClipboardItem(
                id: id,
                kind: kind,
                text: content,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        try checkCompletion(of: statement)
        return result
    }

    func upsert(_ item: ClipboardItem) throws {
        try transaction {
            let delete = try prepare("DELETE FROM clipboard_items WHERE kind = ? AND content = ?")
            defer { sqlite3_finalize(delete) }
            try bind(item.kind.rawValue, to: delete, index: 1)
            try bind(item.text, to: delete, index: 2)
            try step(delete)

            let insert = try prepare("""
                INSERT INTO clipboard_items (id, kind, content, created_at)
                VALUES (?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(insert) }
            try bind(item.id.uuidString, to: insert, index: 1)
            try bind(item.kind.rawValue, to: insert, index: 2)
            try bind(item.text, to: insert, index: 3)
            guard sqlite3_bind_double(insert, 4, item.createdAt.timeIntervalSince1970) == SQLITE_OK else {
                throw currentError()
            }
            try step(insert)
        }
    }

    func remove(id: UUID) throws {
        let statement = try prepare("DELETE FROM clipboard_items WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, to: statement, index: 1)
        try step(statement)
    }

    func removeAll() throws {
        try execute("DELETE FROM clipboard_items")
    }

    func checkpoint() {
        try? execute("PRAGMA wal_checkpoint(PASSIVE)")
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
            throw ClipboardDatabaseError.statement(errorMessage)
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

    private func currentError() -> ClipboardDatabaseError {
        .execution(errorMessage)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var storageError: String?

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let database: ClipboardDatabase?
    private let databaseURL: URL
    private let imageDirectory: URL

    var storageDirectory: URL { databaseURL.deletingLastPathComponent() }

    init(
        pasteboard: NSPasteboard = .general,
        applicationSupportDirectory: URL = RiffPaths.applicationSupportDirectory,
        startsMonitoring: Bool = true
    ) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
        databaseURL = applicationSupportDirectory.appendingPathComponent("clipboard.sqlite3")
        imageDirectory = applicationSupportDirectory.appendingPathComponent(
            "clipboard-images",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: imageDirectory,
            withIntermediateDirectories: true
        )

        let openedDatabase: ClipboardDatabase?
        let restoredItems: [ClipboardItem]
        let initialStorageError: String?
        do {
            let candidate = try ClipboardDatabase(url: databaseURL)
            restoredItems = try candidate.loadAll()
            openedDatabase = candidate
            initialStorageError = nil
        } catch {
            openedDatabase = nil
            restoredItems = []
            initialStorageError = error.localizedDescription
        }
        database = openedDatabase
        items = restoredItems
        storageError = initialStorageError

        if openedDatabase != nil {
            discardLegacyStore(
                in: applicationSupportDirectory,
                preserving: restoredItems
            )
        }

        if startsMonitoring {
            timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.captureIfNeeded() }
            }
        }
    }

    deinit { timer?.invalidate() }

    func filtered(by query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.compactMap { item in
            FuzzyMatcher.score(query: query, candidate: item.summary).map { (item, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    func copy(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .file:
            pasteboard.writeObjects([URL(fileURLWithPath: item.text) as NSURL])
        case .image:
            if let image = NSImage(contentsOfFile: item.text) { pasteboard.writeObjects([image]) }
        default:
            pasteboard.setString(item.text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func remove(_ item: ClipboardItem) {
        do {
            try requireDatabase().remove(id: item.id)
            items.removeAll { $0.id == item.id }
            removeManagedImage(for: item)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    func clear() {
        do {
            try requireDatabase().removeAll()
            let removedItems = items
            items.removeAll()
            for item in removedItems { removeManagedImage(for: item) }
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    func revealStorage() {
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }

    func flush() {
        database?.checkpoint()
    }

    func ignoreCurrentPasteboardChange() {
        lastChangeCount = pasteboard.changeCount
    }

    func captureIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        var newlyCreatedImageURL: URL?
        let captured: ClipboardItem?
        if let fileURL = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           fileURL.isFileURL {
            captured = ClipboardItem(kind: .file, text: fileURL.path)
        } else if let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) {
            if let existing = items.first(where: {
                $0.kind == .image && (try? Data(contentsOf: URL(fileURLWithPath: $0.text))) == png
            }) {
                captured = ClipboardItem(kind: .image, text: existing.text)
            } else {
                let id = UUID()
                let file = imageDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("png")
                do {
                    try png.write(to: file, options: .atomic)
                    newlyCreatedImageURL = file
                    captured = ClipboardItem(id: id, kind: .image, text: file.path)
                } catch {
                    storageError = error.localizedDescription
                    captured = nil
                }
            }
        } else if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty {
            let kind: ClipboardKind = URL(string: text)?.scheme != nil ? .link : .text
            captured = ClipboardItem(kind: kind, text: text)
        } else {
            captured = nil
        }

        guard let captured else { return }
        do {
            try requireDatabase().upsert(captured)
            items.removeAll { $0.kind == captured.kind && $0.text == captured.text }
            items.insert(captured, at: 0)
            storageError = nil
        } catch {
            if let newlyCreatedImageURL {
                try? FileManager.default.removeItem(at: newlyCreatedImageURL)
            }
            storageError = error.localizedDescription
        }
    }

    private func removeManagedImage(for item: ClipboardItem) {
        guard item.kind == .image else { return }
        let imageURL = URL(fileURLWithPath: item.text).standardizedFileURL
        let managedDirectory = imageDirectory.standardizedFileURL.path + "/"
        guard imageURL.path.hasPrefix(managedDirectory) else { return }
        try? FileManager.default.removeItem(at: imageURL)
    }

    private func requireDatabase() throws -> ClipboardDatabase {
        guard let database else {
            throw ClipboardDatabaseError.open("database unavailable")
        }
        return database
    }

    private func discardLegacyStore(
        in applicationSupportDirectory: URL,
        preserving restoredItems: [ClipboardItem]
    ) {
        let legacyURL = applicationSupportDirectory.appendingPathComponent("clipboard.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: legacyURL)
            let preservedImagePaths = Set(restoredItems.lazy
                .filter { $0.kind == .image }
                .map { URL(fileURLWithPath: $0.text).standardizedFileURL.path })
            let oldImages = try FileManager.default.contentsOfDirectory(
                at: imageDirectory,
                includingPropertiesForKeys: nil
            )
            for imageURL in oldImages
                where !preservedImagePaths.contains(imageURL.standardizedFileURL.path) {
                try FileManager.default.removeItem(at: imageURL)
            }
        } catch {
            storageError = error.localizedDescription
        }
    }
}
