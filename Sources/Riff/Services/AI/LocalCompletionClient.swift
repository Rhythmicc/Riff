import Foundation

/// llama.cpp OpenAI-compatible client for local note completion.
struct LocalCompletionClient: Sendable {
    static func payload(
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

    func complete(
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
            withJSONObject: Self.payload(context: context, model: model)
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
}
