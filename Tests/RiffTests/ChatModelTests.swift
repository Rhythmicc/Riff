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

    func testContextWindowKeepsShortConversationUntouched() {
        let messages = (0..<10).map { index in
            ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, content: "消息 \(index)")
        }

        XCTAssertEqual(ChatModel.contextWindow(for: messages), messages)
    }

    func testContextWindowTrimsToMessageLimitAndKeepsFirstUserAnchor() {
        let messages = (0..<50).map { index in
            ChatMessage(
                role: index == 0 ? .user : .assistant,
                content: "第 \(index) 条消息"
            )
        }

        let window = ChatModel.contextWindow(for: messages)

        XCTAssertEqual(window.count, ChatModel.maximumContextMessages + 1)
        XCTAssertEqual(window.first?.content, "第 0 条消息")
        XCTAssertEqual(window.last?.content, "第 49 条消息")
    }

    func testContextWindowTrimsByCharacterBudget() {
        let messages = (0..<40).map { index in
            ChatMessage(role: .user, content: String(repeating: "字", count: 1_000))
        }

        let window = ChatModel.contextWindow(for: messages)

        XCTAssertLessThan(window.count, messages.count)
        XCTAssertEqual(window.first?.content, messages[0].content)
        XCTAssertEqual(window.last?.content, messages[39].content)
    }

    func testMessagesLoadLazilyAndMetadataOnlySaveKeepsThem() throws {
        let fixture = try makeFixture()
        let settings = SettingsStore(defaults: fixture.defaults)
        let model = ChatModel(settings: settings, directory: fixture.directory)
        model.renameSelected("第一段")
        _ = model.importInquiry(question: "问题A", answer: "回答A")
        model.createConversation()
        model.flush()

        let reopened = ChatModel(settings: settings, directory: fixture.directory)
        XCTAssertEqual(reopened.conversations.count, 3)
        XCTAssertTrue(reopened.conversations[0].messages.isEmpty)
        XCTAssertTrue(reopened.conversations[1].messages.isEmpty)

        // Saving only the selected conversation's metadata must not wipe the
        // unloaded conversation's messages.
        reopened.flush()
        let reopenedAgain = ChatModel(settings: settings, directory: fixture.directory)
        let importedIndex = try XCTUnwrap(
            reopenedAgain.conversations.firstIndex { $0.title == "问题A" }
        )
        XCTAssertTrue(reopenedAgain.conversations[importedIndex].messages.isEmpty)
        reopenedAgain.select(reopenedAgain.conversations[importedIndex])
        XCTAssertEqual(
            reopenedAgain.conversations[importedIndex].messages.map(\.content),
            ["问题A", "回答A"]
        )
    }

    func testUpdateSearchFiltersConversationsByTitleAndContent() throws {
        let fixture = try makeFixture()
        let model = ChatModel(
            settings: SettingsStore(defaults: fixture.defaults),
            directory: fixture.directory
        )
        model.renameSelected("北京天气")
        _ = model.importInquiry(question: "帮我看看这段 Swift", answer: "好的")
        model.flush()

        model.updateSearch("天气")
        XCTAssertEqual(model.filteredConversations.map(\.title), ["北京天气"])

        model.updateSearch("Swift")
        XCTAssertEqual(model.filteredConversations.map(\.title), ["帮我看看这段 Swift"])

        model.updateSearch("不存在的内容")
        XCTAssertTrue(model.filteredConversations.isEmpty)

        model.updateSearch("")
        XCTAssertEqual(model.filteredConversations.count, 2)
    }
}
