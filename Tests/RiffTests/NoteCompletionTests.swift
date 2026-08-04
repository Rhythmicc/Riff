import Foundation
import XCTest
@testable import Riff

final class NoteCompletionTests: XCTestCase {
    @MainActor
    func testCompletionSettingsPersist() {
        let suiteName = "NoteCompletionSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.noteCompletionEnabled = true
        settings.noteCompletionBackend = .local
        settings.noteCompletionLocalEndpoint = "http://127.0.0.1:9999/completion"
        settings.noteCompletionLocalModel = .quality
        settings.noteCompletionModel = "fast/model"

        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.noteCompletionEnabled)
        XCTAssertEqual(restored.noteCompletionBackend, .local)
        XCTAssertEqual(restored.noteCompletionLocalEndpoint, "http://127.0.0.1:9999/completion")
        XCTAssertEqual(restored.noteCompletionLocalModel, .quality)
        XCTAssertEqual(restored.noteCompletionModel, "fast/model")
    }

    func testContextUsesUTF16CaretAndLimitsSharedText() throws {
        let text = String(repeating: "前", count: 2_600) + "🙂after"
        let caret = (text as NSString).range(of: "after").location
        let context = try XCTUnwrap(NoteCompletionContext.make(
            text: text,
            selectedRange: NSRange(location: caret, length: 0),
            documentID: UUID()
        ))

        XCTAssertLessThanOrEqual(context.before.count, NoteCompletionContext.maximumBeforeCharacters)
        XCTAssertEqual(context.after, "after")
        XCTAssertTrue(context.before.hasSuffix("🙂"))
    }

    func testContextRejectsSelectionsAndContentWithoutEnoughSignal() {
        XCTAssertNil(NoteCompletionContext.make(
            text: "a",
            selectedRange: NSRange(location: 1, length: 0),
            documentID: UUID()
        ))
        XCTAssertNil(NoteCompletionContext.make(
            text: "enough",
            selectedRange: NSRange(location: 1, length: 2),
            documentID: UUID()
        ))
    }

    func testSanitizerRemovesModelFramingWithoutChangingLanguage() throws {
        let context = try XCTUnwrap(NoteCompletionContext.make(
            text: "今天的天气",
            selectedRange: NSRange(location: 5, length: 0),
            documentID: UUID()
        ))

        XCTAssertEqual(
            NoteCompletionSanitizer.sanitize("```text\n很好，适合出去走走。\n```", for: context),
            "很好，适合出去走走。"
        )
    }

    func testPromptRequestsLanguageAndMarkdownMatching() throws {
        let text = "## 今日计划\n\n- 完成"
        let context = try XCTUnwrap(NoteCompletionContext.make(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            documentID: UUID()
        ))
        let prompt = AIService.noteCompletionPrompt(context: context)

        XCTAssertTrue(prompt.contains("current language"))
        XCTAssertTrue(prompt.contains("Markdown structure"))
        XCTAssertTrue(prompt.contains(context.before))
    }

    func testLocalPayloadUsesSelectedChatModelWithoutThinking() throws {
        let text = "今天我们继续"
        let context = try XCTUnwrap(NoteCompletionContext.make(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            documentID: UUID()
        ))
        let payload = AIService.localCompletionPayload(context: context, model: "riff-4b")

        XCTAssertEqual(payload["model"] as? String, "riff-4b")
        XCTAssertEqual(payload["max_tokens"] as? Int, 24)
        let messages = try XCTUnwrap(payload["messages"] as? [[String: String]])
        XCTAssertTrue(messages.last?["content"]?.contains(text) == true)
        let template = try XCTUnwrap(payload["chat_template_kwargs"] as? [String: Bool])
        XCTAssertEqual(template["enable_thinking"], false)
        XCTAssertEqual(payload["stream"] as? Bool, true)
    }

    func testLiveLocalCompletionServerWhenConfigured() async throws {
        guard let endpointValue = ProcessInfo.processInfo.environment["RIFF_LOCAL_COMPLETION_ENDPOINT"],
              let endpoint = URL(string: endpointValue) else {
            throw XCTSkip("Set RIFF_LOCAL_COMPLETION_ENDPOINT to exercise a running llama.cpp server.")
        }
        let text = "今天天气很好，我们决定"
        let context = try XCTUnwrap(NoteCompletionContext.make(
            text: text,
            selectedRange: NSRange(location: (text as NSString).length, length: 0),
            documentID: UUID()
        ))
        let startedAt = Date()
        let result = try await AIService().completeNote(
            context: context,
            configuration: .local(
                endpoint: endpoint,
                model: ProcessInfo.processInfo.environment["RIFF_LOCAL_COMPLETION_MODEL"] ?? "riff-4b"
            ),
            onDelta: { _ in }
        )
        let latency = Date().timeIntervalSince(startedAt)
        let suggestion = NoteCompletionSanitizer.sanitize(result, for: context)

        XCTAssertFalse(suggestion.isEmpty)
        XCTAssertLessThanOrEqual(suggestion.count, NoteCompletionSanitizer.maximumCharacters)
        // Router mode may need to load the selected model before the first
        // request. Subsequent completions are expected to reuse it.
        XCTAssertLessThan(latency, 15)
    }

    @MainActor
    func testModelStreamsCachesAndValidatesTheCaretSnapshot() async throws {
        let suiteName = "NoteCompletionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.noteCompletionEnabled = true
        settings.noteCompletionModel = "small-model"
        let service = CompletionServiceSpy()
        let model = NoteCompletionModel(
            settings: settings,
            service: service,
            debounceDuration: .milliseconds(1),
            apiKeyProvider: { "test-key" }
        )
        let documentID = UUID()
        let text = "今天我们继续"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let context = try XCTUnwrap(NoteCompletionContext.make(
            text: text,
            selectedRange: range,
            documentID: documentID
        ))

        model.schedule(context)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(model.suggestion, "讨论这个问题。")
        XCTAssertEqual(
            model.suggestion(matching: text, selectedRange: range, documentID: documentID),
            "讨论这个问题。"
        )
        XCTAssertNil(model.suggestion(
            matching: text + "x",
            selectedRange: range,
            documentID: documentID
        ))
        let firstCallCount = await service.numberOfCalls()
        XCTAssertEqual(firstCallCount, 1)

        let advancedText = text + "讨"
        let advancedRange = NSRange(location: (advancedText as NSString).length, length: 0)
        let advancedContext = try XCTUnwrap(NoteCompletionContext.make(
            text: advancedText,
            selectedRange: advancedRange,
            documentID: documentID
        ))
        XCTAssertTrue(model.advanceIfMatching(advancedContext))
        XCTAssertEqual(model.suggestion, "论这个问题。")
        let typeThroughCallCount = await service.numberOfCalls()
        XCTAssertEqual(typeThroughCallCount, 1)

        model.schedule(context)
        XCTAssertEqual(model.suggestion, "讨论这个问题。")
        let cachedCallCount = await service.numberOfCalls()
        XCTAssertEqual(cachedCallCount, 1)
    }
}

private actor CompletionServiceSpy: NoteCompletionServing {
    private(set) var callCount = 0

    func numberOfCalls() -> Int { callCount }

    func completeNote(
        context: NoteCompletionContext,
        configuration: NoteCompletionServiceConfiguration,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        callCount += 1
        await onDelta("讨论")
        await onDelta("这个问题。")
        return "讨论这个问题。"
    }
}
