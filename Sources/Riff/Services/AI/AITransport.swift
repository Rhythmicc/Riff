import Foundation

/// A provider-specific streaming client. Transports translate `AIRequest`
/// into HTTP payloads and normalize responses into `AIStreamResult`.
protocol AITransport: Sendable {
    var provider: AIProvider { get }
    var format: AIConversationFormat { get }

    func stream(
        _ request: AIRequest,
        onEvent: @escaping (AIStreamEvent) async -> Void
    ) async throws -> AIStreamResult
}

enum AIStreamEvent: Sendable {
    case text(String)
    case toolCallDelta(PendingToolCall)
}

enum AITransportFactory {
    static func transport(for provider: AIProvider, apiKey: String) -> any AITransport {
        switch provider {
        case .openAI:
            return OpenAIResponsesTransport(apiKey: apiKey)
        case .openRouter:
            return OpenAICompatibleTransport(
                provider: .openRouter,
                baseURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                apiKey: apiKey,
                headers: ["X-OpenRouter-Title": "Riff"]
            )
        case .deepSeek:
            return OpenAICompatibleTransport(
                provider: .deepSeek,
                baseURL: URL(string: "https://api.deepseek.com/chat/completions")!,
                apiKey: apiKey,
                headers: [:]
            )
        case .gemini:
            return GeminiTransport(apiKey: apiKey)
        }
    }
}

enum AIHTTPError: LocalizedError {
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务返回了无法识别的内容"
        case .server(let status, let message):
            return message.isEmpty ? "请求失败（HTTP \(status)）" : message
        }
    }
}

enum AIErrorParser {
    /// Reads up to 1 MB of an error body and extracts a server-provided message.
    static func serverError(
        from bytes: URLSession.AsyncBytes,
        statusCode: Int
    ) async throws -> Error {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= 1_048_576 { break }
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let message = error?["message"] as? String
            ?? json?["error"] as? String
            ?? ""
        return AIHTTPError.server(statusCode, message)
    }
}
