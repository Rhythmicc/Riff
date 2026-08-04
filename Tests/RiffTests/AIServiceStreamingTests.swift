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
