import XCTest
@testable import Riff

@MainActor
final class ChatModelTests: XCTestCase {
    private func makeFixture() throws -> (
        defaults: UserDefaults,
        directory: URL
    ) {
        let suiteName = "ChatModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-chat-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        return (defaults, directory)
    }

    func testStartsWithOneConversationAndDefaultModel() throws {
        let fixture = try makeFixture()
        let settings = SettingsStore(defaults: fixture.defaults)
        settings.provider = .deepSeek
        let model = ChatModel(
            settings: settings,
            directory: fixture.directory
        )

        XCTAssertEqual(model.conversations.count, 1)
        XCTAssertEqual(model.selectedModel, "deepseek-v4-flash")
        XCTAssertEqual(model.selectedConversation?.title, "新对话")
    }

    func testNewConversationUsesCurrentProviderDefaultModel() throws {
        let fixture = try makeFixture()
        let settings = SettingsStore(defaults: fixture.defaults)
        settings.provider = .openRouter
        let model = ChatModel(settings: settings, directory: fixture.directory)

        model.createConversation()

        XCTAssertEqual(model.conversations[0].model, "deepseek-v4-flash-0731")
        XCTAssertEqual(model.providerTitle, "OpenRouter")
    }

    func testProviderDefaultModels() {
        XCTAssertEqual(AIProvider.deepSeek.defaultModel, "deepseek-v4-flash")
        XCTAssertEqual(AIProvider.openRouter.defaultModel, "deepseek-v4-flash-0731")
        XCTAssertEqual(AIProvider.openAI.defaultModel, "gpt-5.6-luna")
    }

    func testAITitlePromptAndCleaning() {
        let prompt = ChatModel.titlePrompt(message: "帮我写周报")
        XCTAssertTrue(prompt.contains("帮我写周报"))
        XCTAssertTrue(prompt.contains("12 个汉字"))

        XCTAssertEqual(ChatModel.cleanedTitle("「帮我写周报」"), "帮我写周报")
        XCTAssertEqual(ChatModel.cleanedTitle("**周报生成器**"), "周报生成器")
        XCTAssertEqual(ChatModel.cleanedTitle("  周报生成器  "), "周报生成器")
        XCTAssertEqual(ChatModel.cleanedTitle(String(repeating: "长", count: 40)).count, 20)
        XCTAssertEqual(ChatModel.cleanedTitle(""), "")
    }

    func testTitleInferenceCollapsesWhitespaceAndTruncates() {
        XCTAssertEqual(ChatModel.inferredTitle(from: "  帮我写一段\n  Swift 代码  "), "帮我写一段 Swift 代码")
        XCTAssertEqual(ChatModel.inferredTitle(from: "   \n  "), nil)
        XCTAssertEqual(
            ChatModel.inferredTitle(from: String(repeating: "长", count: 40))?.count,
            24
        )
    }

    func testConversationManagementPersistsAcrossReopen() throws {
        let fixture = try makeFixture()
        let settings = SettingsStore(defaults: fixture.defaults)
        let model = ChatModel(settings: settings, directory: fixture.directory)

        model.renameSelected("论文修改讨论")
        model.updateSelectedModel("deepseek-chat")
        model.createConversation()
        model.createConversation()
        XCTAssertEqual(model.conversations.count, 3)
        model.select(model.conversations[2])
        model.renameSelected("第二段对话")
        model.flush()

        let reopened = ChatModel(settings: settings, directory: fixture.directory)
        XCTAssertEqual(reopened.conversations.count, 3)
        XCTAssertEqual(reopened.conversations[2].title, "第二段对话")
        XCTAssertEqual(reopened.conversations[2].model, "deepseek-chat")
        XCTAssertEqual(reopened.selectedConversationID, reopened.conversations[2].id)
    }

    func testDeletingLastConversationCreatesFreshOne() throws {
        let fixture = try makeFixture()
        let model = ChatModel(
            settings: SettingsStore(defaults: fixture.defaults),
            directory: fixture.directory
        )

        model.deleteSelectedConversation()

        XCTAssertEqual(model.conversations.count, 1)
        XCTAssertEqual(model.selectedConversation?.title, "新对话")
    }

    func testImportInquiryCreatesTitledConversation() throws {
        let fixture = try makeFixture()
        let model = ChatModel(
            settings: SettingsStore(defaults: fixture.defaults),
            directory: fixture.directory
        )

        let id = model.importInquiry(question: "帮我解释稀疏矩阵", answer: "稀疏矩阵是大多数元素为零的矩阵。")

        XCTAssertEqual(model.conversations.count, 2)
        XCTAssertEqual(model.conversations[0].id, id)
        XCTAssertEqual(model.conversations[0].title, "帮我解释稀疏矩阵")
        XCTAssertEqual(model.conversations[0].messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(
            model.conversations[0].messages.map(\.content),
            ["帮我解释稀疏矩阵", "稀疏矩阵是大多数元素为零的矩阵。"]
        )
        XCTAssertEqual(model.selectedConversationID, id)
    }
}
