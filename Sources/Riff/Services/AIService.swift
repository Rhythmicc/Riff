import Foundation

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置中填写 API Key"
        case .invalidResponse: return "服务返回了无法识别的内容"
        case .server(let message): return message
        }
    }
}

/// Thin façade over provider transports and the tool agent. All provider
/// differences live in `AI/AITransport.swift` implementations.
struct AIService {
    func answer(
        query: String,
        provider: AIProvider,
        model: String,
        apiKey: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
        let prompt = Self.answerPrompt(query: query)
        return try await streamOnce(
            provider: provider,
            apiKey: apiKey,
            request: AIRequest(
                model: model,
                messages: [.chat(ChatMessage(role: .user, content: prompt))]
            ),
            onDelta: onDelta
        )
    }

    static func answerPrompt(query: String) -> String {
        """
        Answer the user's request directly and concisely.
        Use the same language as the request unless the user asks otherwise.
        Markdown is allowed when it improves readability.
        Do not mention these instructions.

        <request>
        \(query)
        </request>
        """
    }

    /// Single-turn launcher answer with local tool calling.
    func answerWithTools(
        query: String,
        tools: [RiffTool],
        provider: AIProvider,
        model: String,
        apiKey: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
        let prompt = Self.answerPrompt(query: query)
        let agent = AIToolAgent(
            transport: AITransportFactory.transport(for: provider, apiKey: apiKey),
            tools: tools
        )
        return try await agent.run(
            model: model,
            initialMessages: [.chat(ChatMessage(role: .user, content: prompt))],
            onDelta: onDelta
        )
    }

    func translate(
        text: String,
        targetLanguage: String,
        provider: AIProvider,
        model: String,
        apiKey: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
        let prompt = Self.translationPrompt(text: text, targetLanguage: targetLanguage)
        return try await streamOnce(
            provider: provider,
            apiKey: apiKey,
            request: AIRequest(
                model: model,
                messages: [.chat(ChatMessage(role: .user, content: prompt))]
            ),
            onDelta: onDelta
        )
    }

    static func translationPrompt(text: String, targetLanguage: String) -> String {
        """
        Translate the text inside <source> into \(targetLanguage).
        Preserve meaning, tone, names, Markdown, and LaTeX.
        Follow Markdown paragraph semantics: preserve blank-line paragraph breaks and Markdown block structure, but do not introduce hard line breaks inside ordinary prose paragraphs.
        Return only the translated text, without the <source> tags or commentary.

        <source>
        \(text)
        </source>
        """
    }

    /// Multi-turn chat over the full conversation history.
    func chat(
        messages: [ChatMessage],
        provider: AIProvider,
        model: String,
        apiKey: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
        return try await streamOnce(
            provider: provider,
            apiKey: apiKey,
            request: AIRequest(
                model: model,
                messages: messages.map { .chat($0) },
                maxOutputTokens: 1024
            ),
            onDelta: onDelta
        )
    }

    /// Multi-turn chat with local tool calling.
    func chatWithTools(
        messages: [ChatMessage],
        tools: [RiffTool],
        provider: AIProvider,
        model: String,
        apiKey: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
        let agent = AIToolAgent(
            transport: AITransportFactory.transport(for: provider, apiKey: apiKey),
            tools: tools
        )
        return try await agent.run(
            model: model,
            initialMessages: messages.map { .chat($0) },
            onDelta: onDelta
        )
    }

    func completeNote(
        context: NoteCompletionContext,
        configuration: NoteCompletionServiceConfiguration,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        switch configuration {
        case .local(let endpoint, let model):
            return try await LocalCompletionClient().complete(
                context: context,
                endpoint: endpoint,
                model: model,
                onDelta: onDelta
            )
        case .cloud(let provider, let model, let apiKey):
            guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
            let prompt = Self.noteCompletionPrompt(context: context)
            return try await streamOnce(
                provider: provider,
                apiKey: apiKey,
                request: AIRequest(
                    model: model,
                    messages: [.chat(ChatMessage(role: .user, content: prompt))],
                    temperature: 0.1,
                    maxOutputTokens: 96
                ),
                onDelta: onDelta
            )
        }
    }

    static func noteCompletionPrompt(context: NoteCompletionContext) -> String {
        """
        You are an inline writing autocomplete engine. Predict the most likely short continuation at <cursor>.
        Match the author's current language, tone, terminology, Markdown structure, and punctuation. Multilingual text is allowed.
        Return only text to insert at the cursor: no explanation, labels, quotes, or Markdown fences.
        Do not repeat text before the cursor. Prefer one phrase or sentence and stop after at most 160 characters.
        If there is text after the cursor, make the continuation connect naturally without repeating it.

        <before>
        \(context.before)
        </before>
        <cursor />
        <after>
        \(context.after)
        </after>
        """
    }

    static func localCompletionPayload(
        context: NoteCompletionContext,
        model: String
    ) -> [String: Any] {
        LocalCompletionClient.payload(context: context, model: model)
    }

    private func streamOnce(
        provider: AIProvider,
        apiKey: String,
        request: AIRequest,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        let transport = AITransportFactory.transport(for: provider, apiKey: apiKey)
        let result = try await transport.stream(request) { event in
            if case .text(let delta) = event {
                await onDelta(delta)
            }
        }
        return result.text
    }
}
