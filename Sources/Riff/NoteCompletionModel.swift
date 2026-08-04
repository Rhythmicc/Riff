import Combine
import Foundation

enum NoteCompletionBackend: String, CaseIterable, Identifiable, Sendable {
    case local
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "本地"
        case .cloud: return "云端"
        }
    }
}

enum NoteCompletionLocalModel: String, CaseIterable, Identifiable, Sendable {
    case balanced = "riff-4b"
    case quality = "riff-9b"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "平衡 · 4B"
        case .quality: return "高质量 · 9B"
        }
    }

    var detail: String {
        switch self {
        case .balanced: return "响应更快，适合日常中英文补全"
        case .quality: return "语义理解更强，耗电和首次加载时间更高"
        }
    }
}

enum NoteCompletionServiceConfiguration: Sendable {
    case local(endpoint: URL, model: String)
    case cloud(provider: AIProvider, model: String, apiKey: String)

    var cacheIdentity: String {
        switch self {
        case .local(let endpoint, let model):
            return "local:\(endpoint.absoluteString):\(model)"
        case .cloud(let provider, let model, _):
            return "cloud:\(provider.rawValue):\(model)"
        }
    }
}

protocol NoteCompletionServing {
    func completeNote(
        context: NoteCompletionContext,
        configuration: NoteCompletionServiceConfiguration,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String
}

extension AIService: NoteCompletionServing {}

struct NoteCompletionContext: Equatable, Sendable {
    static let maximumBeforeCharacters = 2_400
    static let maximumAfterCharacters = 480

    let documentID: UUID
    let textSnapshot: String
    let caretUTF16Location: Int
    let before: String
    let after: String

    static func make(
        text: String,
        selectedRange: NSRange,
        documentID: UUID
    ) -> NoteCompletionContext? {
        let nsText = text as NSString
        guard selectedRange.length == 0,
              selectedRange.location != NSNotFound,
              selectedRange.location <= nsText.length else { return nil }

        let fullBefore = nsText.substring(to: selectedRange.location)
        let fullAfter = nsText.substring(from: selectedRange.location)
        let before = String(fullBefore.suffix(maximumBeforeCharacters))
        let after = String(fullAfter.prefix(maximumAfterCharacters))

        // A couple of meaningful characters are enough for CJK text, while
        // still preventing an API request for a blank document or lone marker.
        let meaningful = before.filter { !$0.isWhitespace }
        guard meaningful.count >= 2 else { return nil }

        return NoteCompletionContext(
            documentID: documentID,
            textSnapshot: text,
            caretUTF16Location: selectedRange.location,
            before: before,
            after: after
        )
    }

    func matches(text: String, selectedRange: NSRange, documentID: UUID) -> Bool {
        self.documentID == documentID
            && textSnapshot == text
            && selectedRange.length == 0
            && selectedRange.location == caretUTF16Location
    }
}

enum NoteCompletionSanitizer {
    static let maximumCharacters = 160

    static func sanitize(_ rawValue: String, for context: NoteCompletionContext) -> String {
        var value = rawValue.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if value.hasPrefix("```") {
            if let firstNewline = value.firstIndex(of: "\n") {
                value = String(value[value.index(after: firstNewline)...])
            }
            if let closingFence = value.range(of: "```", options: .backwards) {
                value = String(value[..<closingFence.lowerBound])
            }
        }

        for prefix in ["<completion>", "Completion:", "补全：", "续写："] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if let closingTag = value.range(of: "</completion>") {
            value = String(value[..<closingTag.lowerBound])
        }
        if let specialToken = value.range(of: "<|") {
            value = String(value[..<specialToken.lowerBound])
        }

        let repeatedTail = String(context.before.suffix(80))
        if repeatedTail.count >= 12, value.hasPrefix(repeatedTail) {
            value.removeFirst(repeatedTail.count)
        }

        if context.before.last?.isWhitespace == true,
           value.first?.isWhitespace == true,
           !value.hasPrefix("\n\n") {
            value.removeFirst()
        }

        value = String(value.prefix(maximumCharacters))
        while value.last?.isWhitespace == true { value.removeLast() }
        return value.trimmingCharacters(in: .newlines)
    }
}

@MainActor
final class NoteCompletionModel: ObservableObject {
    @Published private(set) var suggestion = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isEnabled: Bool

    var onAcceptRequested: (() -> Void)?

    private let settings: SettingsStore
    private let service: any NoteCompletionServing
    private let debounceDuration: Duration
    private let apiKeyProvider: () -> String
    private var requestTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private(set) var activeContext: NoteCompletionContext?
    private var streamBuffer = ""
    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []
    private var settingsCancellable: AnyCancellable?

    init(
        settings: SettingsStore,
        service: any NoteCompletionServing = AIService(),
        debounceDuration: Duration = .milliseconds(480),
        apiKeyProvider: (() -> String)? = nil
    ) {
        self.settings = settings
        self.service = service
        self.debounceDuration = debounceDuration
        isEnabled = settings.noteCompletionEnabled
        self.apiKeyProvider = apiKeyProvider ?? { [weak settings] in
            settings?.apiKeyForCurrentProvider() ?? ""
        }
        settingsCancellable = settings.$noteCompletionEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.isEnabled = enabled
                if !enabled { self?.cancel() }
            }
    }

    func schedule(_ context: NoteCompletionContext?) {
        cancel(clearSuggestion: true)
        guard settings.noteCompletionEnabled else {
            errorMessage = nil
            return
        }
        guard let context else { return }
        errorMessage = nil

        let configuration: NoteCompletionServiceConfiguration
        switch settings.noteCompletionBackend {
        case .local:
            let value = settings.noteCompletionLocalEndpoint
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let endpoint = URL(string: value),
                  let scheme = endpoint.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  endpoint.host != nil else {
                errorMessage = "本地补全地址无效"
                return
            }
            configuration = .local(
                endpoint: endpoint,
                model: settings.noteCompletionLocalModel.rawValue
            )
        case .cloud:
            let model = settings.noteCompletionModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                errorMessage = "请在设置中填写补全模型"
                return
            }
            let apiKey = apiKeyProvider()
            guard !apiKey.isEmpty else {
                errorMessage = "请先在设置中填写 API Key"
                return
            }
            configuration = .cloud(
                provider: settings.provider,
                model: model,
                apiKey: apiKey
            )
        }

        let cacheKey = Self.cacheKey(context: context, configuration: configuration)
        if let cached = cache[cacheKey] {
            activeContext = context
            suggestion = cached
            DiagnosticLogger.shared.log("note-completion", "cache hit")
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        activeContext = context
        isLoading = true
        streamBuffer = ""
        let requestDebounceDuration: Duration
        switch configuration {
        case .local:
            requestDebounceDuration = .milliseconds(220)
        case .cloud:
            requestDebounceDuration = debounceDuration
        }
        requestTask = Task { [weak self] in
            do {
                try await Task.sleep(for: requestDebounceDuration)
                guard let self,
                      !Task.isCancelled,
                      self.activeRequestID == requestID else { return }

                let completed = try await self.service.completeNote(
                    context: context,
                    configuration: configuration,
                    onDelta: { [weak self] delta in
                        self?.receive(delta, requestID: requestID, context: context)
                    }
                )
                guard !Task.isCancelled, self.activeRequestID == requestID else { return }
                let normalized = NoteCompletionSanitizer.sanitize(completed, for: context)
                self.suggestion = normalized
                self.errorMessage = nil
                if !normalized.isEmpty {
                    self.insertCache(normalized, forKey: cacheKey)
                }
            } catch is CancellationError {
                return
            } catch {
                guard self?.activeRequestID == requestID else { return }
                self?.errorMessage = error.localizedDescription
                DiagnosticLogger.shared.log(
                    "note-completion",
                    "request failed type=\(String(describing: type(of: error)))"
                )
            }
            guard let self, self.activeRequestID == requestID else { return }
            self.isLoading = false
        }
    }

    func cancel(clearSuggestion: Bool = true) {
        requestTask?.cancel()
        requestTask = nil
        activeRequestID = nil
        activeContext = nil
        streamBuffer = ""
        isLoading = false
        if clearSuggestion { suggestion = "" }
    }

    func requestAcceptance() {
        guard !suggestion.isEmpty else { return }
        onAcceptRequested?()
    }

    /// Keeps a prediction alive when the user manually types its leading
    /// characters. This makes completion feel continuous and avoids paying for
    /// another request simply because the user accepted part of it by typing.
    func advanceIfMatching(_ newContext: NoteCompletionContext?) -> Bool {
        guard let oldContext = activeContext,
              let newContext,
              oldContext.documentID == newContext.documentID,
              !suggestion.isEmpty else { return false }

        let oldText = oldContext.textSnapshot as NSString
        let newText = newContext.textSnapshot as NSString
        let insertedLength = newText.length - oldText.length
        guard insertedLength > 0,
              newContext.caretUTF16Location == oldContext.caretUTF16Location + insertedLength,
              oldText.substring(to: oldContext.caretUTF16Location)
                == newText.substring(to: oldContext.caretUTF16Location),
              oldText.substring(from: oldContext.caretUTF16Location)
                == newText.substring(from: newContext.caretUTF16Location) else { return false }

        let inserted = newText.substring(with: NSRange(
            location: oldContext.caretUTF16Location,
            length: insertedLength
        ))
        let suggestionText = suggestion as NSString
        guard suggestionText.length >= insertedLength,
              suggestionText.substring(to: insertedLength) == inserted else { return false }

        requestTask?.cancel()
        requestTask = nil
        activeRequestID = nil
        streamBuffer = ""
        isLoading = false
        activeContext = newContext
        suggestion = suggestionText.substring(from: insertedLength)
        return !suggestion.isEmpty
    }

    func suggestion(
        matching text: String,
        selectedRange: NSRange,
        documentID: UUID
    ) -> String? {
        guard !suggestion.isEmpty,
              activeContext?.matches(
                text: text,
                selectedRange: selectedRange,
                documentID: documentID
              ) == true else { return nil }
        return suggestion
    }

    private func receive(
        _ delta: String,
        requestID: UUID,
        context: NoteCompletionContext
    ) {
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        streamBuffer.append(delta)
        suggestion = NoteCompletionSanitizer.sanitize(streamBuffer, for: context)
    }

    private func insertCache(_ value: String, forKey key: String) {
        cache[key] = value
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > 96 {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private static func cacheKey(
        context: NoteCompletionContext,
        configuration: NoteCompletionServiceConfiguration
    ) -> String {
        "\(configuration.cacheIdentity)\u{1F}\(context.before)\u{1E}\(context.after)"
    }
}
