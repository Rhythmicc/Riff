import XCTest
@testable import Riff

final class AITransportPayloadTests: XCTestCase {
    private func request(model: String = "test-model") -> AIRequest {
        AIRequest(
            model: model,
            messages: [
                .chat(ChatMessage(role: .user, content: "第一问")),
                .chat(ChatMessage(role: .assistant, content: "第一答"))
            ],
            temperature: 0.1,
            maxOutputTokens: 96
        )
    }

    func testOpenAIResponsesPayloadUsesResponsesShape() throws {
        let payload = OpenAIResponsesTransport(apiKey: "k").payload(request: request())

        XCTAssertEqual(payload["model"] as? String, "test-model")
        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertEqual(payload["max_output_tokens"] as? Int, 96)
        XCTAssertEqual(
            (payload["reasoning"] as? [String: String])?["effort"],
            "none"
        )
        let input = try XCTUnwrap(payload["input"] as? [[String: String]])
        XCTAssertEqual(input.map { $0["role"] }, ["user", "assistant"])
        XCTAssertEqual(input.map { $0["content"] }, ["第一问", "第一答"])
    }

    func testOpenAIResponsesToolsAreFlattened() throws {
        let payload = OpenAIResponsesTransport(apiKey: "k").payload(
            request: AIRequest(
                model: "m",
                messages: [.chat(ChatMessage(role: .user, content: "北京天气"))],
                tools: [.weather]
            )
        )
        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertEqual(tools.first?["name"] as? String, "weather_forecast")
        XCTAssertNil(tools.first?["function"])
    }

    func testGeminiPayloadMapsRolesAndTools() throws {
        let payload = GeminiTransport(apiKey: "k").payload(
            request: AIRequest(
                model: "gemini-test",
                messages: [
                    .chat(ChatMessage(role: .user, content: "hi")),
                    .chat(ChatMessage(role: .assistant, content: "hello"))
                ],
                tools: [.calculator]
            )
        )
        let contents = try XCTUnwrap(payload["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model"])
        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        let declarations = try XCTUnwrap(
            tools.first?["functionDeclarations"] as? [[String: Any]]
        )
        XCTAssertEqual(declarations.first?["name"] as? String, "calculate")
    }

    func testChatCompletionsToolRoundTripSerialization() throws {
        let messages: [ConversationMessage] = [
            .assistantToolCalls([
                PendingToolCall(id: "call_1", name: "weather_forecast", arguments: #"{"city":"北京"}"#)
            ]),
            .toolResult(callID: "call_1", output: "35°C")
        ]
        let serialized = AIConversationFormat.chatCompletions.serializedMessages(messages)
        let first = try XCTUnwrap(serialized[0] as? [String: Any])
        XCTAssertEqual(first["role"] as? String, "assistant")
        let calls = try XCTUnwrap(first["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.first?["id"] as? String, "call_1")
        let second = try XCTUnwrap(serialized[1] as? [String: Any])
        XCTAssertEqual(second["role"] as? String, "tool")
        XCTAssertEqual(second["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(second["content"] as? String, "35°C")
    }

    func testResponsesToolRoundTripSerialization() throws {
        let messages: [ConversationMessage] = [
            .assistantToolCalls([
                PendingToolCall(id: "call_9", name: "calculate", arguments: #"{"expression":"2^10"}"#)
            ]),
            .toolResult(callID: "call_9", output: "1024")
        ]
        let serialized = AIConversationFormat.responses.serializedMessages(messages)
        XCTAssertEqual(serialized.count, 2)
        let call = try XCTUnwrap(serialized[0] as? [String: Any])
        XCTAssertEqual(call["type"] as? String, "function_call")
        XCTAssertEqual(call["call_id"] as? String, "call_9")
        let output = try XCTUnwrap(serialized[1] as? [String: Any])
        XCTAssertEqual(output["type"] as? String, "function_call_output")
        XCTAssertEqual(output["output"] as? String, "1024")
    }

    func testGeminiToolRoundTripSerialization() throws {
        let messages: [ConversationMessage] = [
            .assistantToolCalls([
                PendingToolCall(id: "weather_forecast", name: "weather_forecast", arguments: #"{"city":"北京"}"#)
            ]),
            .toolResult(callID: "weather_forecast", output: "25°C")
        ]
        let serialized = AIConversationFormat.gemini.serializedMessages(messages)
        let model = try XCTUnwrap(serialized[0] as? [String: Any])
        let parts = try XCTUnwrap(model["parts"] as? [[String: Any]])
        let call = try XCTUnwrap(parts.first?["functionCall"] as? [String: Any])
        XCTAssertEqual(call["name"] as? String, "weather_forecast")
        let user = try XCTUnwrap(serialized[1] as? [String: Any])
        let userParts = try XCTUnwrap(user["parts"] as? [[String: Any]])
        let response = try XCTUnwrap(userParts.first?["functionResponse"] as? [String: Any])
        XCTAssertEqual(response["name"] as? String, "weather_forecast")
    }

    func testAppendingToolRoundProducesAssistantAndResultMessages() {
        let format = AIConversationFormat.chatCompletions
        let messages: [ConversationMessage] = [
            .chat(ChatMessage(role: .user, content: "北京天气"))
        ]
        let appended = format.appendingToolRound(
            to: messages,
            calls: [
                PendingToolCall(id: "call_1", name: "weather_forecast", arguments: "{}")
            ],
            outputs: ["35°C"]
        )

        XCTAssertEqual(appended.count, 3)
        guard case .assistantToolCalls(let calls) = appended[1] else {
            return XCTFail("expected assistant tool-call message")
        }
        XCTAssertEqual(calls.first?.id, "call_1")
        guard case .toolResult(let callID, let output) = appended[2] else {
            return XCTFail("expected tool result message")
        }
        XCTAssertEqual(callID, "call_1")
        XCTAssertEqual(output, "35°C")
    }
}
