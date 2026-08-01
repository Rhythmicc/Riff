import XCTest
@testable import PersonalLauncher

final class AIServiceStreamingTests: XCTestCase {
    func testTranslationPromptRequiresExactLineBreakPreservation() {
        let source = "First paragraph.\n\nSecond paragraph."
        let prompt = AIService.translationPrompt(text: source, targetLanguage: "Simplified Chinese")

        XCTAssertTrue(prompt.contains("Preserve every paragraph break and line break exactly"))
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
