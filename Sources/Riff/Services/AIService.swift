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
        }
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
        return try await sendStreaming(request, provider: .openAI, onDelta: onDelta)
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
        return try await sendStreaming(request, provider: .openRouter, onDelta: onDelta)
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
        return try await sendStreaming(request, provider: .gemini, onDelta: onDelta)
    }

    private func sendStreaming(
        _ request: URLRequest,
        provider: AIProvider,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
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
        }
        guard !output.isEmpty else { throw AIServiceError.invalidResponse }
        return output
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
