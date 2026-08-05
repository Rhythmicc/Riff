import Foundation

enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct ChatConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var model: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        model: String = ChatModel.defaultModel,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Owns AI conversations: list, selection, auto-generated titles, per-chat
/// model choice, persistence, and streaming multi-turn requests.
@MainActor
final class ChatModel: ObservableObject {
    /// Fallback used only when a provider default cannot be resolved.
    static let defaultModel = "deepseek-v4-flash"

    private struct Archive: Codable {
        var conversations: [ChatConversation]
        var selectedConversationID: UUID
    }

    @Published private(set) var conversations: [ChatConversation]
    @Published private(set) var selectedConversationID: UUID
    @Published private(set) var isStreaming = false
    @Published private(set) var streamError: String?

    private let settings: SettingsStore
    private let noteModel: NoteModel?
    private let archiveURL: URL
    private var saveTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?

    init(settings: SettingsStore, noteModel: NoteModel? = nil, directory: URL? = nil) {
        self.settings = settings
        self.noteModel = noteModel
        let resolvedDirectory = directory ?? RiffPaths.applicationSupportDirectory
        try? FileManager.default.createDirectory(
            at: resolvedDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        archiveURL = resolvedDirectory.appendingPathComponent("chat.json")

        if let data = try? Data(contentsOf: archiveURL),
           let archive = try? JSONDecoder().decode(Archive.self, from: data),
           !archive.conversations.isEmpty {
            conversations = archive.conversations
            selectedConversationID = archive.conversations.contains(where: {
                $0.id == archive.selectedConversationID
            }) ? archive.selectedConversationID : archive.conversations[0].id
        } else {
            let initial = ChatConversation()
            conversations = [initial]
            selectedConversationID = initial.id
            saveImmediately()
        }
    }

    var selectedConversation: ChatConversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    var selectedModel: String {
        selectedConversation?.model ?? settings.provider.defaultModel
    }

    var providerTitle: String {
        settings.provider.title
    }

    var providerDefaultModel: String {
        settings.provider.defaultModel
    }

    func select(_ conversation: ChatConversation) {
        selectedConversationID = conversation.id
        scheduleSave()
    }

    func createConversation() {
        let conversation = ChatConversation(model: settings.provider.defaultModel)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        scheduleSave()
    }

    func deleteSelectedConversation() {
        conversations.removeAll { $0.id == selectedConversationID }
        if conversations.isEmpty {
            conversations = [ChatConversation()]
        }
        selectedConversationID = conversations[0].id
        scheduleSave()
    }

    func renameSelected(_ title: String) {
        guard let index = selectedIndex else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].title = trimmed.isEmpty ? "新对话" : trimmed
        conversations[index].updatedAt = Date()
        scheduleSave()
    }

    func updateSelectedModel(_ model: String) {
        guard let index = selectedIndex else { return }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].model = trimmed.isEmpty ? settings.provider.defaultModel : trimmed
        conversations[index].updatedAt = Date()
        scheduleSave()
    }

    /// Adds a completed launcher AI inquiry as the first exchange of a new
    /// conversation and selects it, so ⌘J can continue the discussion there.
    @discardableResult
    func importInquiry(question: String, answer: String) -> UUID {
        let conversation = ChatConversation(
            title: Self.inferredTitle(from: question) ?? "新对话",
            model: settings.model,
            messages: [
                ChatMessage(role: .user, content: question),
                ChatMessage(role: .assistant, content: answer)
            ]
        )
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        scheduleSave()
        scheduleAITitleIfNeeded(conversationID: conversation.id, overwriteFallback: true)
        return conversation.id
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming, let index = selectedIndex else { return }
        streamError = nil

        if conversations[index].title == "新对话" {
            conversations[index].title = Self.inferredTitle(from: trimmed) ?? "新对话"
        }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        let assistantPlaceholder = ChatMessage(role: .assistant, content: "")
        conversations[index].messages.append(userMessage)
        conversations[index].messages.append(assistantPlaceholder)
        conversations[index].updatedAt = Date()

        let conversationID = conversations[index].id
        let model = conversations[index].model
        let history = conversations[index].messages
        let provider = settings.provider
        let apiKey = settings.apiKeyForCurrentProvider()
        let tavilyKey = settings.tavilyAPIKey()
        isStreaming = true

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await AIService().chatWithTools(
                    messages: history,
                    tools: RiffToolRegistry.tools(
                        provider: provider,
                        model: model,
                        apiKey: apiKey,
                        tavilyAPIKey: tavilyKey,
                        noteModel: noteModel
                    ),
                    provider: self.settings.provider,
                    model: model,
                    apiKey: apiKey,
                    onDelta: { [weak self] delta in
                        await self?.appendStreamingDelta(delta, conversationID: conversationID)
                    }
                )
                try Task.checkCancellation()
                self.finishStreaming(
                    conversationID: conversationID,
                    finalText: result,
                    error: nil
                )
            } catch is CancellationError {
                self.finishStreaming(conversationID: conversationID, finalText: nil, error: nil)
            } catch {
                self.finishStreaming(
                    conversationID: conversationID,
                    finalText: nil,
                    error: error.localizedDescription
                )
            }
        }
    }

    func stop() {
        streamingTask?.cancel()
    }

    func flush() {
        saveTask?.cancel()
        saveImmediately()
    }

    private var selectedIndex: Int? {
        conversations.firstIndex { $0.id == selectedConversationID }
    }

    private func appendStreamingDelta(_ delta: String, conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              conversations[index].messages.last?.role == .assistant else { return }
        conversations[index].messages[conversations[index].messages.count - 1].content += delta
    }

    private func finishStreaming(
        conversationID: UUID,
        finalText: String?,
        error: String?
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        isStreaming = false
        streamingTask = nil

        if let error {
            if conversations[index].messages.last?.role == .assistant,
               conversations[index].messages.last?.content.isEmpty == true {
                conversations[index].messages.removeLast()
            }
            streamError = error
        } else {
            streamError = nil
        }

        if let finalText {
            if conversations[index].messages.last?.role == .assistant {
                conversations[index].messages[conversations[index].messages.count - 1].content = finalText
            } else {
                conversations[index].messages.append(ChatMessage(role: .assistant, content: finalText))
            }
        }
        conversations[index].updatedAt = Date()
        scheduleSave()
        if finalText != nil, conversations[index].messages.contains(where: { $0.role == .user }) {
            scheduleAITitleIfNeeded(conversationID: conversationID, overwriteFallback: false)
        }
    }

    // MARK: - AI-generated conversation titles

    /// Asks the model for a short conversation title once, after the first
    /// exchange completes. Failures keep the truncated fallback title.
    private func scheduleAITitleIfNeeded(
        conversationID: UUID,
        overwriteFallback: Bool
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              let firstUserMessage = conversations[index].messages.first(where: {
                  $0.role == .user
              }) else { return }
        let shouldRename = overwriteFallback || conversations[index].title == "新对话"
        guard shouldRename else { return }

        let model = conversations[index].model
        let provider = settings.provider
        let apiKey = KeychainStore.get(account: provider.rawValue)
        let prompt = Self.titlePrompt(message: firstUserMessage.content)

        Task { [weak self] in
            guard let self else { return }
            do {
                let title = try await AIService().chat(
                    messages: [ChatMessage(role: .user, content: prompt)],
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    onDelta: { _ in }
                )
                let cleaned = Self.cleanedTitle(title)
                guard !cleaned.isEmpty else { return }
                await self.applyGeneratedTitle(cleaned, conversationID: conversationID)
            } catch {
                // Keep the existing fallback title.
            }
        }
    }

    private func applyGeneratedTitle(_ title: String, conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].title = title
        conversations[index].updatedAt = Date()
        scheduleSave()
    }

    static func titlePrompt(message: String) -> String {
        """
        根据这条用户消息，为这段对话生成一个简洁的中文标题。
        要求：不超过 12 个汉字；不使用引号、标点、Markdown 或任何解释；只返回标题本身。

        <message>
        \(message)
        </message>
        """
    }

    static func cleanedTitle(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(
                of: #"^["'「」『』“”‘’\s*#\-`]+|["'「」『』“”‘’\s*#\-`]+$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(20))
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
        let archive = Archive(
            conversations: conversations,
            selectedConversationID: selectedConversationID
        )
        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? data.write(to: archiveURL, options: .atomic)
    }

    static func inferredTitle(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(24))
    }
}
