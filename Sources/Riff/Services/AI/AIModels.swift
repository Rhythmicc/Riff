import Foundation

/// Accumulated streaming tool-call fragment.
struct PendingToolCall: Equatable, Sendable {
    var id: String
    var name: String
    var arguments: String
}

struct AIStreamResult: Sendable {
    var text: String
    var toolCalls: [PendingToolCall]
}

/// Provider-agnostic conversation message. `assistantToolCalls` and
/// `toolResult` are produced by the tool loop; each transport serializes them
/// into its own wire format.
enum ConversationMessage: Sendable {
    case chat(ChatMessage)
    case assistantToolCalls([PendingToolCall])
    case toolResult(callID: String, output: String)
}

struct AIRequest: Sendable {
    var model: String
    var messages: [ConversationMessage]
    var tools: [RiffTool]
    var temperature: Double
    var maxOutputTokens: Int?

    init(
        model: String,
        messages: [ConversationMessage],
        tools: [RiffTool] = [],
        temperature: Double = 0.2,
        maxOutputTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
    }
}

/// How a provider represents multi-turn conversation and tool round-trips.
enum AIConversationFormat: Sendable {
    case chatCompletions
    case responses
    case gemini

    /// Serializes a message list into the provider's `input`/`messages`/`contents`
    /// array. A single logical message may expand to multiple items (Responses
    /// function calls, Gemini function responses).
    func serializedMessages(_ messages: [ConversationMessage]) -> [Any] {
        var serialized: [Any] = []
        for message in messages {
            switch (self, message) {
            case (.chatCompletions, .chat(let chatMessage)):
                serialized.append([
                    "role": chatMessage.role == .assistant ? "assistant" : "user",
                    "content": chatMessage.content
                ])
            case (.chatCompletions, .assistantToolCalls(let calls)):
                serialized.append([
                    "role": "assistant",
                    "content": "",
                    "tool_calls": calls.map { call in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.name,
                                "arguments": call.arguments
                            ]
                        ]
                    }
                ])
            case (.chatCompletions, .toolResult(let callID, let output)):
                serialized.append([
                    "role": "tool",
                    "tool_call_id": callID,
                    "content": output
                ])
            case (.responses, .chat(let chatMessage)):
                serialized.append([
                    "role": chatMessage.role == .assistant ? "assistant" : "user",
                    "content": chatMessage.content
                ])
            case (.responses, .assistantToolCalls(let calls)):
                serialized.append(contentsOf: calls.map { call -> [String: Any] in
                    [
                        "type": "function_call",
                        "call_id": call.id,
                        "name": call.name,
                        "arguments": call.arguments
                    ] as [String: Any]
                })
            case (.responses, .toolResult(let callID, let output)):
                serialized.append([
                    "type": "function_call_output",
                    "call_id": callID,
                    "output": output
                ])
            case (.gemini, .chat(let chatMessage)):
                serialized.append([
                    "role": chatMessage.role == .assistant ? "model" : "user",
                    "parts": [["text": chatMessage.content]]
                ])
            case (.gemini, .assistantToolCalls(let calls)):
                serialized.append(contentsOf: calls.map { call -> [String: Any] in
                    [
                        "role": "model",
                        "parts": [[
                            "functionCall": [
                                "name": call.name,
                                "args": (try? JSONSerialization.jsonObject(
                                    with: Data(call.arguments.utf8)
                                )) as? [String: Any] ?? [:]
                            ]
                        ]]
                    ] as [String: Any]
                })
            case (.gemini, .toolResult(let callID, let output)):
                serialized.append([
                    "role": "user",
                    "parts": [[
                        "functionResponse": [
                            "name": callID,
                            "response": ["output": output]
                        ]
                    ]]
                ])
            }
        }
        return serialized
    }

    /// Appends the assistant tool-call message and one result message per call.
    func appendingToolRound(
        to messages: [ConversationMessage],
        calls: [PendingToolCall],
        outputs: [String]
    ) -> [ConversationMessage] {
        precondition(calls.count == outputs.count)
        var result = messages
        result.append(.assistantToolCalls(calls))
        for (call, output) in zip(calls, outputs) {
            result.append(.toolResult(callID: call.id, output: output))
        }
        return result
    }

    /// OpenAI-compatible tool schema. Responses API flattens `function` into
    /// top-level fields; Gemini wraps declarations in `functionDeclarations`.
    func toolSchemas(_ tools: [RiffTool]) -> [Any]? {
        guard !tools.isEmpty else { return nil }
        switch self {
        case .chatCompletions:
            return tools.map(\.openAISchema)
        case .responses:
            return tools.map { tool in
                let function = tool.openAISchema["function"] as? [String: Any] ?? [:]
                var schema: [String: Any] = ["type": "function"]
                if let name = function["name"] { schema["name"] = name }
                if let description = function["description"] { schema["description"] = description }
                if let parameters = function["parameters"] { schema["parameters"] = parameters }
                return schema
            }
        case .gemini:
            return [[
                "functionDeclarations": tools.map { tool in
                    let function = tool.openAISchema["function"] as? [String: Any] ?? [:]
                    var declaration: [String: Any] = [:]
                    if let name = function["name"] { declaration["name"] = name }
                    if let description = function["description"] { declaration["description"] = description }
                    if let parameters = function["parameters"] { declaration["parameters"] = parameters }
                    return declaration
                }
            ]]
        }
    }
}
