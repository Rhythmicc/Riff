import Foundation

struct NoteDocument: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var isPinned: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "未命名笔记",
        text: String = "# 新笔记\n\n",
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, text, isPinned, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        text = try container.decode(String.self, forKey: .text)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var summary: String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { String($0.prefix(70)) } ?? "空白笔记"
    }
}

@MainActor
final class NoteModel: ObservableObject {
    private struct Archive: Codable {
        var notes: [NoteDocument]
        var selectedNoteID: UUID
    }

    @Published private(set) var notes: [NoteDocument]
    @Published private(set) var selectedNoteID: UUID
    @Published var searchQuery = ""

    private let archiveURL: URL
    private let legacyURL: URL
    private var saveTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        let resolvedDirectory = directory
            ?? RiffPaths.applicationSupportDirectory
        try? FileManager.default.createDirectory(
            at: resolvedDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        archiveURL = resolvedDirectory.appendingPathComponent("notes.json")
        legacyURL = resolvedDirectory.appendingPathComponent("note.md")

        if let data = try? Data(contentsOf: archiveURL),
           let archive = try? JSONDecoder().decode(Archive.self, from: data),
           !archive.notes.isEmpty {
            notes = archive.notes
            selectedNoteID = archive.notes.contains(where: { $0.id == archive.selectedNoteID })
                ? archive.selectedNoteID
                : archive.notes[0].id
        } else {
            let legacyText = try? String(contentsOf: legacyURL, encoding: .utf8)
            let initial = NoteDocument(
                title: Self.inferredTitle(from: legacyText ?? "") ?? "随手记",
                text: legacyText ?? "# 随手记\n\n"
            )
            notes = [initial]
            selectedNoteID = initial.id
            saveImmediately()
        }
    }

    var selectedNote: NoteDocument? {
        notes.first { $0.id == selectedNoteID }
    }

    var selectedTitle: String { selectedNote?.title ?? "" }

    var filteredNotes: [NoteDocument] {
        let filtered: [NoteDocument]
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = notes
        } else {
            filtered = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(query)
                    || note.text.localizedCaseInsensitiveContains(query)
            }
        }
        return filtered.enumerated().sorted { lhs, rhs in
            if lhs.element.isPinned != rhs.element.isPinned {
                return lhs.element.isPinned
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func togglePin(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        scheduleSave()
    }
    var selectedText: String { selectedNote?.text ?? "" }

    func select(_ note: NoteDocument) {
        selectedNoteID = note.id
        scheduleSave()
    }

    func createNote() {
        let note = NoteDocument()
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        scheduleSave()
    }

    func deleteSelectedNote() {
        notes.removeAll { $0.id == selectedNoteID }
        if notes.isEmpty { notes = [NoteDocument()] }
        selectedNoteID = notes[0].id
        scheduleSave()
    }

    func updateSelectedTitle(_ title: String) {
        guard let index = selectedIndex else { return }
        notes[index].title = title
        notes[index].updatedAt = Date()
        scheduleSave()
    }

    func updateSelectedText(_ text: String) {
        guard let index = selectedIndex else { return }
        let shouldInferTitle = notes[index].title == "未命名笔记"
            || notes[index].title == "新笔记"
        notes[index].text = text
        if shouldInferTitle, let inferred = Self.inferredTitle(from: text) {
            notes[index].title = inferred
        }
        notes[index].updatedAt = Date()
        scheduleSave()
    }

    func flush() {
        saveTask?.cancel()
        saveImmediately()
    }

    private var selectedIndex: Int? {
        notes.firstIndex { $0.id == selectedNoteID }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func saveImmediately() {
        let archive = Archive(notes: notes, selectedNoteID: selectedNoteID)
        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? data.write(to: archiveURL, options: .atomic)
    }

    private static func inferredTitle(from text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let cleaned = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            if !cleaned.isEmpty { return String(cleaned.prefix(48)) }
        }
        return nil
    }
}
