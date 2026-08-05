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

struct PendingToolCall: Equatable, Sendable {
    var id: String
    var name: String
    var arguments: String
}

struct AIStreamResult: Sendable {
    var text: String
    var toolCalls: [PendingToolCall]
}

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

        switch provider {
        case .openAI:
            return try await openAI(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        case .openRouter:
            return try await openRouter(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        case .gemini:
            return try await gemini(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        case .deepSeek:
            return try await deepSeek(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        }
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

    /// Single-turn launcher answer with local tool calling (weather, currency,
    /// calculator, passwords, Unicode, translation).
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
        return try await runToolAgent(
            initialMessages: [["role": "user", "content": prompt]],
            tools: tools,
            provider: provider,
            model: model,
            apiKey: apiKey,
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

        switch provider {
        case .openAI:
            return try await openAI(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        case .openRouter:
            return try await openRouter(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        case .gemini:
            return try await gemini(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        case .deepSeek:
            return try await deepSeek(prompt: prompt, model: model, key: apiKey, onDelta: onDelta)
        }
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

        switch provider {
        case .openAI:
            let input = messages.map { message in
                [
                    "role": message.role == .assistant ? "assistant" : "user",
                    "content": message.content
                ]
            }
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "model": model,
                "input": input,
                "reasoning": ["effort": "none"],
                "text": ["verbosity": "low"],
                "stream": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            return try await sendStreaming(request, provider: .openAI, onDelta: onDelta).text

        case .openRouter:
            return try await chatOpenAICompatible(
                url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                provider: .openRouter,
                model: model,
                key: apiKey,
                messages: messages,
                temperature: 0.2,
                onDelta: onDelta
            )

        case .deepSeek:
            return try await chatOpenAICompatible(
                url: URL(string: "https://api.deepseek.com/chat/completions")!,
                provider: .deepSeek,
                model: model,
                key: apiKey,
                messages: messages,
                temperature: 0.2,
                onDelta: onDelta
            )

        case .gemini:
            let contents = messages.map { message -> [String: Any] in
                [
                    "role": message.role == .assistant ? "model" : "user",
                    "parts": [["text": message.content]]
                ]
            }
            let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            var request = URLRequest(
                url: URL(
                    string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):streamGenerateContent?alt=sse"
                )!
            )
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "contents": contents,
                "generationConfig": ["temperature": 0.2]
            ])
            return try await sendStreaming(request, provider: .gemini, onDelta: onDelta).text
        }
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
        let serialized = messages.map { message -> [String: Any] in
            [
                "role": message.role == .assistant ? "assistant" : "user",
                "content": message.content
            ]
        }
        return try await runToolAgent(
            initialMessages: serialized,
            tools: tools,
            provider: provider,
            model: model,
            apiKey: apiKey,
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

    func completeNote(
        context: NoteCompletionContext,
        configuration: NoteCompletionServiceConfiguration,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        switch configuration {
        case .local(let endpoint, let model):
            return try await localCompletion(
                context: context,
                endpoint: endpoint,
                model: model,
                onDelta: onDelta
            )
        case .cloud(let provider, let model, let apiKey):
            guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey }
            let prompt = Self.noteCompletionPrompt(context: context)
            switch provider {
            case .openAI:
                return try await openAI(
                    prompt: prompt,
                    model: model,
                    key: apiKey,
                    maxOutputTokens: 96,
                    onDelta: onDelta
                )
            case .openRouter:
                return try await openRouter(
                    prompt: prompt,
                    model: model,
                    key: apiKey,
                    maxOutputTokens: 96,
                    temperature: 0.1,
                    onDelta: onDelta
                )
            case .gemini:
                return try await gemini(
                    prompt: prompt,
                    model: model,
                    key: apiKey,
                    maxOutputTokens: 96,
                    temperature: 0.1,
                    onDelta: onDelta
                )
            case .deepSeek:
                return try await deepSeek(
                    prompt: prompt,
                    model: model,
                    key: apiKey,
                    maxOutputTokens: 96,
                    temperature: 0.1,
                    onDelta: onDelta
                )
            }
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
        [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are an inline writing autocomplete engine. Return only the short text to insert at the cursor. Match the author's language, tone, terminology, Markdown, and punctuation. Never explain, label, quote, or repeat the preceding text. Prefer 2–12 words and stop at a natural boundary."
                ],
                [
                    "role": "user",
                    "content": "<before>\n\(context.before)\n</before>\n<cursor />\n<after>\n\(context.after)\n</after>"
                ]
            ],
            "max_tokens": 24,
            "temperature": 0.2,
            "top_p": 0.8,
            "top_k": 20,
            "presence_penalty": 0.2,
            "repeat_penalty": 1.05,
            "chat_template_kwargs": ["enable_thinking": false],
            "stream": true,
            "stop": ["\n", "<|endoftext|>", "<|im_end|>", "</completion>"]
        ]
    }

    private func localCompletion(
        context: NoteCompletionContext,
        endpoint: URL,
        model: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.localCompletionPayload(context: context, model: model)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 262_144 { break }
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = json?["error"] as? [String: Any]
            throw AIServiceError.server(
                message?["message"] as? String
                    ?? json?["error"] as? String
                    ?? "本地补全服务请求失败（HTTP \(http.statusCode)）"
            )
        }

        var output = ""
        for try await rawLine in bytes.lines {
            try Task.checkCancellation()
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let nativeDelta = json["content"] as? String
            let choices = json["choices"] as? [[String: Any]]
            let openAIDelta = (choices?.first?["delta"] as? [String: Any])?["content"] as? String
            if let delta = nativeDelta ?? openAIDelta, !delta.isEmpty {
                output.append(delta)
                await onDelta(delta)
            }
            let finishReason = choices?.first?["finish_reason"] as? String
            if json["stop"] as? Bool == true || finishReason != nil { break }
        }
        guard !output.isEmpty else { throw AIServiceError.invalidResponse }
        return output
    }

    private func openAI(
        prompt: String,
        model: String,
        key: String,
        maxOutputTokens: Int? = nil,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "model": model,
            "input": prompt,
            "reasoning": ["effort": "none"],
            "text": ["verbosity": "low"],
            "stream": true
        ]
        if let maxOutputTokens { payload["max_output_tokens"] = maxOutputTokens }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await sendStreaming(request, provider: .openAI, onDelta: onDelta).text
    }

    private func openRouter(
        prompt: String,
        model: String,
        key: String,
        maxOutputTokens: Int? = nil,
        temperature: Double = 0.2,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Riff", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.openRouterPayload(
            prompt: prompt,
            model: model,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature
        ))
        return try await sendStreaming(request, provider: .openRouter, onDelta: onDelta).text
    }

    static func openRouterPayload(
        prompt: String,
        model: String,
        maxOutputTokens: Int? = nil,
        temperature: Double = 0.2
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": temperature,
            // Translation does not benefit from hidden chain-of-thought. Some
            // OpenRouter models enable high-effort reasoning by default, which
            // delays the first visible content token by several seconds.
            "reasoning": ["enabled": false, "exclude": true],
            "stream": true
        ]
        if let maxOutputTokens { payload["max_tokens"] = maxOutputTokens }
        return payload
    }

    static func deepSeekPayload(
        prompt: String,
        model: String,
        maxOutputTokens: Int? = nil,
        temperature: Double = 0.2
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": temperature,
            "stream": true
        ]
        if let maxOutputTokens { payload["max_tokens"] = maxOutputTokens }
        return payload
    }

    static func openAICompatibleChatPayload(
        messages: [ChatMessage],
        model: String,
        temperature: Double
    ) -> [String: Any] {
        [
            "model": model,
            "messages": messages.map { message in
                [
                    "role": message.role == .assistant ? "assistant" : "user",
                    "content": message.content
                ]
            },
            "temperature": temperature,
            "max_tokens": 1024,
            "stream": true
        ]
    }

    static func openAICompatibleChatPayload(
        messages: [[String: Any]],
        model: String,
        temperature: Double,
        tools: [RiffTool]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": 1024,
            "stream": true
        ]
        if !tools.isEmpty {
            payload["tools"] = tools.map(\.openAISchema)
        }
        return payload
    }

    /// Runs up to four model/tool rounds for OpenAI-compatible providers.
    /// Tool results are fed back as `tool` messages; only the final assistant
    /// text is returned to the caller.
    private func runToolAgent(
        initialMessages: [[String: Any]],
        tools: [RiffTool],
        provider: AIProvider,
        model: String,
        apiKey: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        guard provider == .deepSeek || provider == .openRouter else {
            // OpenAI Responses and Gemini do not share this tool protocol yet;
            // fall back to a plain single-turn answer.
            let prompt = initialMessages
                .compactMap { $0["content"] as? String }
                .joined(separator: "\n")
            switch provider {
            case .openAI:
                return try await openAI(
                    prompt: prompt,
                    model: model,
                    key: apiKey,
                    onDelta: onDelta
                )
            case .gemini:
                return try await gemini(
                    prompt: prompt,
                    model: model,
                    key: apiKey,
                    onDelta: onDelta
                )
            case .deepSeek, .openRouter:
                throw AIServiceError.invalidResponse
            }
        }

        let url = provider == .deepSeek
            ? URL(string: "https://api.deepseek.com/chat/completions")!
            : URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var messages = initialMessages
        var finalText = ""

        for _ in 0..<4 {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: Self.openAICompatibleChatPayload(
                    messages: messages,
                    model: model,
                    temperature: 0.2,
                    tools: tools
                )
            )
            let result = try await sendStreaming(
                request,
                provider: provider,
                onDelta: onDelta
            )
            finalText += result.text
            guard !result.toolCalls.isEmpty else {
                return finalText.isEmpty ? result.text : finalText
            }

            var assistantMessage: [String: Any] = [
                "role": "assistant",
                "content": ""
            ]
            assistantMessage["tool_calls"] = result.toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.arguments
                    ]
                ]
            }
            messages.append(assistantMessage)

            for call in result.toolCalls {
                let output: String
                if let tool = tools.first(where: { $0.name == call.name }) {
                    let arguments = (try? JSONSerialization.jsonObject(
                        with: Data(call.arguments.utf8)
                    )) as? [String: Any] ?? [:]
                    do {
                        output = try await tool.execute(arguments)
                    } catch {
                        output = "工具执行失败：\(error.localizedDescription)"
                    }
                } else {
                    output = "没有名为 \(call.name) 的本地工具"
                }
                messages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": output
                ])
            }
        }
        throw AIServiceError.server("工具调用轮次过多，已停止")
    }

    private func chatOpenAICompatible(
        url: URL,
        provider: AIProvider,
        model: String,
        key: String,
        messages: [ChatMessage],
        temperature: Double,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.openAICompatibleChatPayload(
                messages: messages,
                model: model,
                temperature: temperature
            )
        )
        return try await sendStreaming(request, provider: provider, onDelta: onDelta).text
    }

    private func deepSeek(
        prompt: String,
        model: String,
        key: String,
        maxOutputTokens: Int? = nil,
        temperature: Double = 0.2,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.deepSeekPayload(
            prompt: prompt,
            model: model,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature
        ))
        return try await sendStreaming(request, provider: .deepSeek, onDelta: onDelta).text
    }

    private func gemini(
        prompt: String,
        model: String,
        key: String,
        maxOutputTokens: Int? = nil,
        temperature: Double = 0.2,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):streamGenerateContent?alt=sse")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var generationConfig: [String: Any] = ["temperature": temperature]
        if let maxOutputTokens { generationConfig["maxOutputTokens"] = maxOutputTokens }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": generationConfig
        ])
        return try await sendStreaming(request, provider: .gemini, onDelta: onDelta).text
    }

    private func sendStreaming(
        _ request: URLRequest,
        provider: AIProvider,
        onDelta: @escaping (String) async -> Void
    ) async throws -> AIStreamResult {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 1_048_576 { break }
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            throw AIServiceError.server(error?["message"] as? String ?? "请求失败（HTTP \(http.statusCode)）")
        }

        var output = ""
        var toolCallAccumulator: [Int: PendingToolCall] = [:]
        for try await rawLine in bytes.lines {
            try Task.checkCancellation()
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let delta = try Self.streamDelta(from: json, provider: provider), !delta.isEmpty {
                output.append(delta)
                await onDelta(delta)
            }
            if provider == .deepSeek || provider == .openRouter {
                Self.collectToolCallDeltas(from: json, into: &toolCallAccumulator)
            }
        }
        guard !output.isEmpty || !toolCallAccumulator.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return AIStreamResult(
            text: output,
            toolCalls: toolCallAccumulator.sorted { $0.key < $1.key }.map(\.value)
        )
    }

    static func collectToolCallDeltas(
        from json: [String: Any],
        into accumulator: inout [Int: PendingToolCall]
    ) {
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let calls = delta["tool_calls"] as? [[String: Any]] else { return }
        for call in calls {
            let index = call["index"] as? Int ?? 0
            var pending = accumulator[index] ?? PendingToolCall(id: "", name: "", arguments: "")
            if let id = call["id"] as? String, !id.isEmpty {
                pending.id = id
            }
            if let function = call["function"] as? [String: Any] {
                if let name = function["name"] as? String, !name.isEmpty {
                    pending.name = name
                }
                if let arguments = function["arguments"] as? String {
                    pending.arguments += arguments
                }
            }
            accumulator[index] = pending
        }
    }

    static func streamDelta(from json: [String: Any], provider: AIProvider) throws -> String? {
        if let error = json["error"] as? [String: Any] {
            throw AIServiceError.server(error["message"] as? String ?? "流式请求失败")
        }
        if json["type"] as? String == "response.failed",
           let response = json["response"] as? [String: Any],
           let error = response["error"] as? [String: Any] {
            throw AIServiceError.server(error["message"] as? String ?? "流式请求失败")
        }

        switch provider {
        case .openAI:
            guard json["type"] as? String == "response.output_text.delta" else { return nil }
            return json["delta"] as? String
        case .openRouter:
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { return nil }
            return delta["content"] as? String
        case .deepSeek:
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { return nil }
            return delta["content"] as? String
        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let text = parts.compactMap { part -> String? in
                guard part["thought"] as? Bool != true else { return nil }
                return part["text"] as? String
            }.joined()
            return text.isEmpty ? nil : text
        }
    }
}
