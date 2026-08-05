import XCTest
@testable import Riff

final class AIServiceStreamingTests: XCTestCase {
    func testGeneralAnswerPromptKeepsTheUserRequestAndLanguageInstruction() {
        let prompt = AIService.answerPrompt(query: "解释稀疏矩阵")

        XCTAssertTrue(prompt.contains("same language as the request"))
        XCTAssertTrue(prompt.contains("<request>\n解释稀疏矩阵\n</request>"))
    }

    func testTranslationPromptUsesMarkdownParagraphSemantics() {
        let source = "First paragraph.\n\nSecond paragraph."
        let prompt = AIService.translationPrompt(text: source, targetLanguage: "Simplified Chinese")

        XCTAssertTrue(prompt.contains("preserve blank-line paragraph breaks"))
        XCTAssertTrue(prompt.contains("do not introduce hard line breaks inside ordinary prose paragraphs"))
        XCTAssertTrue(prompt.contains("<source>\n\(source)\n</source>"))
    }

    func testExtractsOpenAIResponsesDelta() throws {
        let delta = try AIService.streamDelta(from: [
            "type": "response.output_text.delta",
            "delta": "你好"
        ], provider: .openAI)

        XCTAssertEqual(delta, "你好")
    }

    func testExtractsOpenRouterChatCompletionDelta() throws {
        let delta = try AIService.streamDelta(from: [
            "choices": [["delta": ["content": "世界"]]]
        ], provider: .openRouter)

        XCTAssertEqual(delta, "世界")
    }

    func testOpenRouterTranslationDisablesDefaultReasoningAndStreams() throws {
        let payload = AIService.openRouterPayload(prompt: "Translate me", model: "example/model")
        let reasoning = try XCTUnwrap(payload["reasoning"] as? [String: Bool])

        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertEqual(reasoning["enabled"], false)
        XCTAssertEqual(reasoning["exclude"], true)
    }

    func testOpenRouterCompletionUsesLowLatencyBoundedGeneration() {
        let payload = AIService.openRouterPayload(
            prompt: "Continue",
            model: "small-model",
            maxOutputTokens: 96,
            temperature: 0.1
        )

        XCTAssertEqual(payload["max_tokens"] as? Int, 96)
        XCTAssertEqual(payload["temperature"] as? Double, 0.1)
        XCTAssertEqual(payload["stream"] as? Bool, true)
    }

    func testDeepSeekPayloadUsesOpenAICompatibleChatCompletions() {
        let payload = AIService.deepSeekPayload(
            prompt: "Translate me",
            model: "deepseek-chat",
            maxOutputTokens: 96,
            temperature: 0.1
        )

        XCTAssertEqual(payload["model"] as? String, "deepseek-chat")
        XCTAssertEqual(payload["max_tokens"] as? Int, 96)
        XCTAssertEqual(payload["temperature"] as? Double, 0.1)
        XCTAssertEqual(payload["stream"] as? Bool, true)
        let messages = try? XCTUnwrap(payload["messages"] as? [[String: String]])
        XCTAssertEqual(messages?.first?["content"], "Translate me")
    }

    func testExtractsDeepSeekDeltaAndIgnoresReasoningOnlyChunks() throws {
        let delta = try AIService.streamDelta(from: [
            "choices": [["delta": ["content": "你好"]]]
        ], provider: .deepSeek)
        XCTAssertEqual(delta, "你好")

        let reasoningOnly = try AIService.streamDelta(from: [
            "choices": [["delta": ["reasoning_content": "思考中…"]]]
        ], provider: .deepSeek)
        XCTAssertNil(reasoningOnly)
    }

    func testOpenAICompatibleChatPayloadPreservesRoles() {
        let messages = [
            ChatMessage(role: .user, content: "第一问"),
            ChatMessage(role: .assistant, content: "第一答"),
            ChatMessage(role: .user, content: "追问")
        ]
        let payload = AIService.openAICompatibleChatPayload(
            messages: messages,
            model: "deepseek-v4-flash-0731",
            temperature: 0.2
        )

        XCTAssertEqual(payload["model"] as? String, "deepseek-v4-flash-0731")
        XCTAssertEqual(payload["max_tokens"] as? Int, 1024)
        XCTAssertEqual(payload["stream"] as? Bool, true)
        let serialized = payload["messages"] as? [[String: String]]
        XCTAssertEqual(serialized?.map { $0["role"] }, ["user", "assistant", "user"])
        XCTAssertEqual(serialized?.map { $0["content"] }, ["第一问", "第一答", "追问"])
    }

    func testOpenAICompatibleChatPayloadIncludesTools() {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "北京天气怎么样？"]
        ]
        let tools = RiffToolRegistry.tools(provider: .deepSeek, model: "m", apiKey: "k")
        let payload = AIService.openAICompatibleChatPayload(
            messages: messages,
            model: "deepseek-v4-flash-0731",
            temperature: 0.2,
            tools: tools
        )

        let toolSchemas = payload["tools"] as? [[String: Any]]
        XCTAssertEqual(toolSchemas?.count, tools.count)
        XCTAssertEqual(
            (toolSchemas?.first?["function"] as? [String: Any])?["name"] as? String,
            "weather_forecast"
        )
    }

    func testCollectToolCallDeltasAccumulatesFragments() {
        var accumulator: [Int: PendingToolCall] = [:]

        AIService.collectToolCallDeltas(
            from: [
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": "call_1",
                            "function": ["name": "weather_forecast", "arguments": #"{"city": "北"#]
                        ]]
                    ]
                ]]
            ],
            into: &accumulator
        )
        AIService.collectToolCallDeltas(
            from: [
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "function": ["arguments": #"京"}"#]
                        ]]
                    ]
                ]]
            ],
            into: &accumulator
        )

        XCTAssertEqual(accumulator.count, 1)
        XCTAssertEqual(accumulator[0]?.id, "call_1")
        XCTAssertEqual(accumulator[0]?.name, "weather_forecast")
        XCTAssertEqual(accumulator[0]?.arguments, #"{"city": "北京"}"#)
    }

    func testExtractsGeminiDeltaAndIgnoresThoughtParts() throws {
        let delta = try AIService.streamDelta(from: [
            "candidates": [[
                "content": ["parts": [
                    ["text": "internal", "thought": true],
                    ["text": "译文"]
                ]]
            ]]
        ], provider: .gemini)

        XCTAssertEqual(delta, "译文")
    }

    func testStreamingErrorsAreSurfaced() {
        XCTAssertThrowsError(try AIService.streamDelta(from: [
            "error": ["message": "provider unavailable"]
        ], provider: .openRouter))
    }
}
