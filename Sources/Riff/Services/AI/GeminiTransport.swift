import Foundation

/// Google Gemini streaming client (`:streamGenerateContent?alt=sse`).
struct GeminiTransport: AITransport {
    let provider: AIProvider = .gemini
    let format: AIConversationFormat = .gemini
    let apiKey: String

    func stream(
        _ request: AIRequest,
        onEvent: @escaping (AIStreamEvent) async -> Void
    ) async throws -> AIStreamResult {
        let escaped = request.model.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? request.model
        var httpRequest = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):streamGenerateContent?alt=sse"
            )!
        )
        httpRequest.httpMethod = "POST"
        httpRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try JSONSerialization.data(
            withJSONObject: payload(request: request)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: httpRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIHTTPError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw try await AIErrorParser.serverError(from: bytes, statusCode: http.statusCode)
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
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let delta = try Self.delta(from: json), !delta.isEmpty {
                output.append(delta)
                await onEvent(.text(delta))
            }
            Self.collectToolCallDeltas(from: json, into: &toolCallAccumulator)
        }
        guard !output.isEmpty || !toolCallAccumulator.isEmpty else {
            throw AIHTTPError.invalidResponse
        }
        return AIStreamResult(
            text: output,
            toolCalls: toolCallAccumulator.sorted { $0.key < $1.key }.map(\.value)
        )
    }

    func payload(request: AIRequest) -> [String: Any] {
        var generationConfig: [String: Any] = [
            "temperature": request.temperature
        ]
        if let maxOutputTokens = request.maxOutputTokens {
            generationConfig["maxOutputTokens"] = maxOutputTokens
        }
        var payload: [String: Any] = [
            "contents": format.serializedMessages(request.messages),
            "generationConfig": generationConfig
        ]
        if let schemas = format.toolSchemas(request.tools) {
            payload["tools"] = schemas
        }
        return payload
    }

    static func delta(from json: [String: Any]) throws -> String? {
        if let error = json["error"] as? [String: Any] {
            throw AIHTTPError.server(0, error["message"] as? String ?? "流式请求失败")
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }
        let text = parts.compactMap { part -> String? in
            guard part["thought"] as? Bool != true else { return nil }
            return part["text"] as? String
        }.joined()
        return text.isEmpty ? nil : text
    }

    static func collectToolCallDeltas(
        from json: [String: Any],
        into accumulator: inout [Int: PendingToolCall]
    ) {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return }
        for (index, part) in parts.enumerated() {
            guard let call = part["functionCall"] as? [String: Any],
                  let name = call["name"] as? String else { continue }
            let arguments = call["args"] as? [String: Any] ?? [:]
            let argumentsData = (try? JSONSerialization.data(withJSONObject: arguments))
                .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            accumulator[index] = PendingToolCall(
                id: name,
                name: name,
                arguments: argumentsData
            )
        }
    }
}
