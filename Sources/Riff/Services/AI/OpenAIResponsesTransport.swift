import Foundation

/// OpenAI Responses API streaming client.
struct OpenAIResponsesTransport: AITransport {
    let provider: AIProvider = .openAI
    let format: AIConversationFormat = .responses
    let apiKey: String

    func stream(
        _ request: AIRequest,
        onEvent: @escaping (AIStreamEvent) async -> Void
    ) async throws -> AIStreamResult {
        var httpRequest = URLRequest(
            url: URL(string: "https://api.openai.com/v1/responses")!
        )
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        var payload: [String: Any] = [
            "model": request.model,
            "input": format.serializedMessages(request.messages),
            "reasoning": ["effort": "none"],
            "text": ["verbosity": "low"],
            "stream": true
        ]
        if let maxOutputTokens = request.maxOutputTokens {
            payload["max_output_tokens"] = maxOutputTokens
        }
        if let schemas = format.toolSchemas(request.tools) {
            payload["tools"] = schemas
        }
        return payload
    }

    static func delta(from json: [String: Any]) throws -> String? {
        if let error = json["error"] as? [String: Any] {
            throw AIHTTPError.server(0, error["message"] as? String ?? "流式请求失败")
        }
        if json["type"] as? String == "response.failed",
           let response = json["response"] as? [String: Any],
           let error = response["error"] as? [String: Any] {
            throw AIHTTPError.server(0, error["message"] as? String ?? "流式请求失败")
        }
        guard json["type"] as? String == "response.output_text.delta" else {
            return nil
        }
        return json["delta"] as? String
    }

    static func collectToolCallDeltas(
        from json: [String: Any],
        into accumulator: inout [Int: PendingToolCall]
    ) {
        switch json["type"] as? String {
        case "response.output_item.added":
            guard let item = json["item"] as? [String: Any],
                  item["type"] as? String == "function_call",
                  let index = json["output_index"] as? Int else { return }
            accumulator[index] = PendingToolCall(
                id: item["call_id"] as? String ?? "",
                name: item["name"] as? String ?? "",
                arguments: item["arguments"] as? String ?? ""
            )
        case "response.function_call_arguments.delta":
            guard let index = json["output_index"] as? Int,
                  let delta = json["delta"] as? String else { return }
            var pending = accumulator[index] ?? PendingToolCall(id: "", name: "", arguments: "")
            pending.arguments += delta
            accumulator[index] = pending
        case "response.output_item.done":
            guard let item = json["item"] as? [String: Any],
                  item["type"] as? String == "function_call",
                  let index = json["output_index"] as? Int else { return }
            var pending = accumulator[index] ?? PendingToolCall(id: "", name: "", arguments: "")
            if let id = item["call_id"] as? String, !id.isEmpty { pending.id = id }
            if let name = item["name"] as? String, !name.isEmpty { pending.name = name }
            if let arguments = item["arguments"] as? String, !arguments.isEmpty {
                pending.arguments = arguments
            }
            accumulator[index] = pending
        default:
            break
        }
    }
}
