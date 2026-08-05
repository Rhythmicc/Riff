import Foundation

/// OpenAI-compatible `/chat/completions` streaming client shared by
/// OpenRouter and DeepSeek.
struct OpenAICompatibleTransport: AITransport {
    let provider: AIProvider
    let format: AIConversationFormat = .chatCompletions
    let baseURL: URL
    let apiKey: String
    let headers: [String: String]

    func stream(
        _ request: AIRequest,
        onEvent: @escaping (AIStreamEvent) async -> Void
    ) async throws -> AIStreamResult {
        var httpRequest = URLRequest(url: baseURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            httpRequest.setValue(value, forHTTPHeaderField: key)
        }
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
        var payload: [String: Any] = [
            "model": request.model,
            "messages": format.serializedMessages(request.messages),
            "temperature": request.temperature,
            "stream": true
        ]
        if let maxOutputTokens = request.maxOutputTokens {
            payload["max_tokens"] = maxOutputTokens
        }
        if let schemas = format.toolSchemas(request.tools) {
            payload["tools"] = schemas
        }
        if provider == .openRouter {
            // Translation and completion do not benefit from hidden
            // chain-of-thought; some OpenRouter models enable it by default.
            payload["reasoning"] = ["enabled": false, "exclude": true]
        }
        return payload
    }

    static func delta(from json: [String: Any]) throws -> String? {
        if let error = json["error"] as? [String: Any] {
            throw AIHTTPError.server(
                json["error"] as? Int ?? 0,
                error["message"] as? String ?? "流式请求失败"
            )
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }
        return delta["content"] as? String
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
}
