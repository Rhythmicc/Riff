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
        Preserve every paragraph break and line break exactly: never merge separate lines or paragraphs. For every newline in the source, emit a newline at the corresponding boundary in the translation.
        Return only the translated text, without the <source> tags or commentary.

        <source>
        \(text)
        </source>
        """
    }

    private func openAI(
        prompt: String,
        model: String,
        key: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": prompt,
            "reasoning": ["effort": "none"],
            "text": ["verbosity": "low"],
            "stream": true
        ])
        return try await sendStreaming(request, provider: .openAI, onDelta: onDelta)
    }

    private func openRouter(
        prompt: String,
        model: String,
        key: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Riff", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.2,
            "stream": true
        ])
        return try await sendStreaming(request, provider: .openRouter, onDelta: onDelta)
    }

    private func gemini(
        prompt: String,
        model: String,
        key: String,
        onDelta: @escaping (String) async -> Void
    ) async throws -> String {
        let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):streamGenerateContent?alt=sse")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2]
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
