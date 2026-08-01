import AppKit
import Foundation
import NaturalLanguage

@MainActor
final class TranslationModel: ObservableObject {
    @Published var source = ""
    @Published var result = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var targetLanguage: TranslationLanguage
    @Published private(set) var detectedLanguage: NLLanguage?
    @Published private(set) var firstTokenLatency: TimeInterval?
    @Published private(set) var streamUpdateCount = 0

    private let settings: SettingsStore
    private let service = AIService()
    private let cache: TranslationCache
    private var translationTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var streamBuffer = ""
    private var lastStreamPublish = Date.distantPast
    private var requestStartedAt: Date?

    init(settings: SettingsStore, cache: TranslationCache = .shared) {
        self.settings = settings
        self.cache = cache
        targetLanguage = settings.nativeLanguage
    }

    func begin(with text: String) {
        DiagnosticLogger.shared.log("translation", "model.begin sourceLength=\(text.count)")
        if text == source, isLoading {
            DiagnosticLogger.shared.log("translation", "model.begin reused in-flight request")
            return
        }
        source = text
        result = ""
        errorMessage = nil
        translate()
    }

    var hasSession: Bool {
        !source.isEmpty || isLoading || !result.isEmpty
    }

    func translate(forceRefresh: Bool = false) {
        guard !source.isEmpty else {
            DiagnosticLogger.shared.log("translation", "model.translate aborted: empty source")
            errorMessage = "没有读到选中的文字；请先选中文字，再按 ⌘ ⇧ T"
            return
        }
        isLoading = true
        errorMessage = nil
        let source = source
        let provider = settings.provider
        let model = settings.model
        let direction = TranslationDirectionResolver.resolve(
            text: source,
            nativeLanguage: settings.nativeLanguage,
            priorityLanguage: settings.priorityLanguage
        )
        targetLanguage = direction.targetLanguage
        detectedLanguage = direction.detectedLanguage
        DiagnosticLogger.shared.log(
            "translation",
            "direction detected=\(direction.detectedLanguage?.rawValue ?? "nil") sourceIsNative=\(direction.sourceIsNative) target=\(direction.targetLanguage.rawValue)"
        )
        let language = direction.targetLanguage
        let cacheKey = TranslationCache.key(
            source: source,
            targetLanguage: language,
            provider: provider,
            model: model
        )
        translationTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID
        streamBuffer = ""
        lastStreamPublish = .distantPast
        firstTokenLatency = nil
        streamUpdateCount = 0
        requestStartedAt = Date()
        translationTask = Task { [weak self] in
            guard let self else { return }
            if !forceRefresh, let cached = await cache.value(forKey: cacheKey) {
                guard !Task.isCancelled, activeRequestID == requestID else { return }
                result = cached
                isLoading = false
                requestStartedAt = nil
                DiagnosticLogger.shared.log("translation-cache", "hit resultLength=\(cached.count)")
                return
            }
            DiagnosticLogger.shared.log(
                "translation-cache",
                forceRefresh ? "bypass for retry" : "miss"
            )
            let key = settings.apiKeyForCurrentProvider()
            do {
                let translated = try await service.translate(
                    text: source,
                    targetLanguage: language.promptName,
                    provider: provider,
                    model: model,
                    apiKey: key,
                    onDelta: { [weak self] delta in
                        self?.receiveStreamDelta(delta, requestID: requestID)
                    }
                )
                guard !Task.isCancelled, activeRequestID == requestID else { return }
                result = translated
                await cache.insert(translated, forKey: cacheKey)
                DiagnosticLogger.shared.log("translation", "request succeeded resultLength=\(translated.count)")
            } catch is CancellationError {
                DiagnosticLogger.shared.log("translation", "request cancelled")
            } catch {
                guard activeRequestID == requestID else { return }
                DiagnosticLogger.shared.log("translation", "request failed type=\(String(describing: type(of: error)))")
                errorMessage = error.localizedDescription
            }
            if activeRequestID == requestID { isLoading = false }
            if activeRequestID == requestID { requestStartedAt = nil }
        }
    }

    private func receiveStreamDelta(_ delta: String, requestID: UUID) {
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        let isFirstChunk = streamBuffer.isEmpty
        streamBuffer.append(delta)
        let now = Date()
        if isFirstChunk || delta.contains("\n") || now.timeIntervalSince(lastStreamPublish) >= 0.035 {
            result = streamBuffer
            lastStreamPublish = now
            streamUpdateCount += 1
            if isFirstChunk {
                let latency = requestStartedAt.map { now.timeIntervalSince($0) }
                firstTokenLatency = latency
                let latencyDescription = latency.map { String(format: "%.3f", $0) } ?? "unknown"
                DiagnosticLogger.shared.log(
                    "translation",
                    "stream first delta received latencySeconds=\(latencyDescription)"
                )
            }
        }
    }

    func retry() {
        translate(forceRefresh: true)
    }

    @discardableResult
    func copyResult() -> Bool {
        guard !result.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        return true
    }

    /// Supplies deterministic content for SwiftUI previews and visual regression tests.
    /// The values remain the unmodified source strings; presentation formatting belongs
    /// exclusively to `RichSelectableTextView`.
    func preparePreview(
        source: String,
        result: String,
        targetLanguage: TranslationLanguage,
        detectedLanguage: NLLanguage? = nil
    ) {
        translationTask?.cancel()
        activeRequestID = nil
        self.source = source
        self.result = result
        self.targetLanguage = targetLanguage
        self.detectedLanguage = detectedLanguage
        isLoading = false
        errorMessage = nil
        firstTokenLatency = nil
        streamUpdateCount = 0
        requestStartedAt = nil
    }
}
