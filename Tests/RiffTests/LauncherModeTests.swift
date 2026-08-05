import XCTest
@testable import Riff

final class LauncherModeTests: XCTestCase {
    @MainActor
    func testDefaultLauncherStaysCollapsedUntilTheUserTypes() {
        let model = AppModel(clipboard: ClipboardStore())
        XCTAssertFalse(model.shouldShowResults)

        model.query = "safari"
        XCTAssertTrue(model.shouldShowResults)

        model.query = "   "
        XCTAssertFalse(model.shouldShowResults)

        model.switchMode(.clipboard)
        XCTAssertTrue(model.shouldShowResults)
    }

    func testLauncherHeightTracksVisibleResultRows() {
        let twoRows = LauncherView.resultDesignHeight(rowCount: 2)
        let sixRows = LauncherView.resultDesignHeight(rowCount: 6)
        let manyRows = LauncherView.resultDesignHeight(rowCount: 20)

        XCTAssertLessThan(twoRows, sixRows)
        XCTAssertLessThan(sixRows, LauncherView.designSize.height)
        XCTAssertEqual(manyRows, LauncherView.designSize.height)
    }

    func testCollapsedLauncherUsesCompactSpotlightProportions() {
        let size = LauncherView.windowSize(designHeight: LauncherView.collapsedDesignHeight)

        XCTAssertLessThanOrEqual(size.width, 710)
        XCTAssertLessThanOrEqual(size.height, 63)
        XCTAssertGreaterThan(
            LauncherView.answerFontSize / LauncherView.searchFontSize,
            0.70
        )
    }

    func testLauncherMotionDurationsStayBriefAndDeliberate() {
        XCTAssertLessThan(LauncherMotion.presentationFadeDuration, LauncherMotion.presentationDuration)
        XCTAssertLessThanOrEqual(LauncherMotion.presentationFadeDuration, LauncherMotion.resizeDuration)
        XCTAssertLessThanOrEqual(LauncherMotion.resizeDuration, LauncherMotion.dismissalDuration)
        XCTAssertLessThan(LauncherMotion.dismissalDuration, LauncherMotion.presentationDuration)
        XCTAssertLessThanOrEqual(LauncherMotion.presentationDuration, 0.40)
        XCTAssertGreaterThanOrEqual(LauncherMotion.resizeCoalescingDelay, 0.20)
    }

    func testVisibilityTransformsPreserveFrameAndUseTheGeometricCenter() {
        let layer = CALayer()
        layer.frame = CGRect(x: 17, y: 23, width: 240, height: 72)
        let originalFrame = layer.frame

        LauncherMotion.centerTransformAnchor(of: layer)

        XCTAssertEqual(layer.anchorPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(layer.frame, originalFrame)
    }

    func testLauncherOnlyCoalescesResizesWhileItIsAlreadyExpanded() {
        let collapsed: CGFloat = 62

        XCTAssertEqual(
            LauncherMotion.resizeDelay(
                currentHeight: collapsed,
                targetHeight: 420,
                collapsedHeight: collapsed
            ),
            0
        )
        XCTAssertEqual(
            LauncherMotion.resizeDelay(
                currentHeight: 420,
                targetHeight: collapsed,
                collapsedHeight: collapsed
            ),
            0
        )
        XCTAssertEqual(
            LauncherMotion.resizeDelay(
                currentHeight: 420,
                targetHeight: 250,
                collapsedHeight: collapsed
            ),
            LauncherMotion.resizeCoalescingDelay
        )
    }

    func testApplicationUpdatesKeepTheSamePresentationKind() {
        let searching = LauncherContent.applications(
            actions: [],
            items: [],
            hasMore: false,
            isSearching: true
        )
        let loaded = LauncherContent.applications(
            actions: [],
            items: [],
            hasMore: false,
            isSearching: false
        )

        XCTAssertEqual(searching.presentationKind, .applications)
        XCTAssertEqual(loaded.presentationKind, .applications)
    }

    func testUnicodeGridHeightTracksGridRowsInsteadOfIndividualSymbols() {
        let oneRow = LauncherView.unicodeGridDesignHeight(itemCount: 8)
        let twoRows = LauncherView.unicodeGridDesignHeight(itemCount: 16)
        let manyRows = LauncherView.unicodeGridDesignHeight(itemCount: 64)

        XCTAssertEqual(LauncherView.unicodeGridDesignHeight(itemCount: 1), oneRow)
        XCTAssertLessThan(oneRow, twoRows)
        XCTAssertEqual(manyRows, LauncherView.designSize.height)
    }

    func testCommandNumberNavigationKeyCodes() {
        XCTAssertEqual(LauncherMode.navigationMode(for: 18), .apps)
        XCTAssertEqual(LauncherMode.navigationMode(for: 19), .clipboard)
        XCTAssertEqual(LauncherMode.navigationMode(for: 20), .password)
        XCTAssertNil(LauncherMode.navigationMode(for: 21))
    }

    func testNoteQueriesAreRecognized() {
        XCTAssertTrue(AppModel.isNoteQuery("笔记"))
        XCTAssertTrue(AppModel.isNoteQuery("便笺"))
        XCTAssertTrue(AppModel.isNoteQuery("note"))
        XCTAssertTrue(AppModel.isNoteQuery("notes"))
        XCTAssertTrue(AppModel.isNoteQuery("markdown"))
        XCTAssertFalse(AppModel.isNoteQuery("Safari"))
        XCTAssertFalse(AppModel.isNoteQuery(""))
    }

    func testClipboardQueriesOfferClipboardNavigation() {
        XCTAssertEqual(LauncherQuickAction.matching("剪贴板"), [.clipboard])
        XCTAssertEqual(LauncherQuickAction.matching("粘贴板历史"), [.clipboard])
        XCTAssertEqual(LauncherQuickAction.matching("clipboard"), [.clipboard])
    }

    func testTranslationQueriesOfferTranslationNavigation() {
        XCTAssertEqual(LauncherQuickAction.matching("翻译"), [.translation])
        XCTAssertEqual(LauncherQuickAction.matching("translate"), [.translation])
        XCTAssertEqual(LauncherQuickAction.matching("translator"), [.translation])
    }

    func testPasswordQueriesOfferPasswordGeneration() {
        XCTAssertEqual(LauncherQuickAction.matching("密码"), [.password])
        XCTAssertEqual(LauncherQuickAction.matching("口令"), [.password])
        XCTAssertEqual(LauncherQuickAction.matching("password"), [.password])
    }

    func testChatQueriesOfferChatNavigation() {
        XCTAssertEqual(LauncherQuickAction.matching("对话"), [.chat])
        XCTAssertEqual(LauncherQuickAction.matching("chat"), [.chat])
        XCTAssertEqual(LauncherQuickAction.matching("ai"), [.chat])
    }

    @MainActor
    func testAIAnswerCommitRequiresCompletedAnswer() {
        let model = AppModel(clipboard: ClipboardStore())
        var committed = false
        model.onCommitAIAnswerToChat = { _, _ in committed = true }

        XCTAssertFalse(model.commitAIAnswerToChat())
        XCTAssertFalse(committed)
        XCTAssertFalse(model.canOpenChatAfterCommittedAIAnswer)
    }

    @MainActor
    func testPasswordCommandEntersComponent() {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "随机密码"

        XCTAssertEqual(model.mode, .password)
        XCTAssertTrue(model.isPasswordQuery)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.passwordRequest?.length, 16)
        XCTAssertTrue(model.shouldShowResults)
    }

    @MainActor
    func testPasswordCommandCarriesParametersIntoComponent() {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "随机密码 24 无符号"

        XCTAssertEqual(model.mode, .password)
        XCTAssertEqual(model.query, "24 无符号")
        XCTAssertEqual(model.passwordRequest?.length, 24)
        XCTAssertEqual(model.passwordRequest?.includeSymbols, false)
        XCTAssertEqual(model.generatedPassword?.length, 24)
    }

    @MainActor
    func testPasswordQuickActionEntersComponent() {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "pas"
        guard let passwordIndex = model.quickActions.firstIndex(of: .password) else {
            return XCTFail("Expected a password quick action for pas")
        }
        model.selectedIndex = passwordIndex

        _ = model.activateSelection()

        XCTAssertEqual(model.mode, .password)
        XCTAssertTrue(model.isPasswordQuery)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.passwordRequest?.length, 16)
        XCTAssertTrue(model.shouldShowResults)
    }

    @MainActor
    func testPasswordComponentAcceptsParameterEdits() {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "随机密码"
        XCTAssertEqual(model.query, "")

        model.query = "24 无符号"
        XCTAssertEqual(model.mode, .password)
        XCTAssertEqual(model.passwordRequest?.length, 24)
        XCTAssertEqual(model.passwordRequest?.includeSymbols, false)
        XCTAssertEqual(model.generatedPassword?.length, 24)

        model.query = ""
        XCTAssertEqual(model.mode, .password)
        XCTAssertEqual(model.passwordRequest?.length, 16)
        XCTAssertEqual(model.passwordRequest?.includeSymbols, true)
    }

    @MainActor
    func testPasswordComponentExitsForNonParameterInput() {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "随机密码"
        XCTAssertEqual(model.mode, .password)

        model.query = "safari"

        XCTAssertEqual(model.mode, .apps)
        XCTAssertFalse(model.isPasswordQuery)
        XCTAssertEqual(model.query, "safari")
    }

    @MainActor
    func testTabRegeneratesInsidePasswordComponent() {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "pwgen 32"
        let first = model.generatedPassword?.value

        XCTAssertTrue(model.regeneratePassword())

        XCTAssertNotEqual(model.generatedPassword?.value, first)
        XCTAssertEqual(model.query, "32")
        XCTAssertEqual(model.mode, .password)
    }

    @MainActor
    func testPasswordComponentShowsCrackEstimate() {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "随机密码"

        XCTAssertTrue(model.passwordCrackEstimateText?.contains("位熵") == true)
        XCTAssertTrue(model.passwordCrackEstimateText?.contains("宇宙年龄") == true)
    }

    @MainActor
    func testUnicodeIntentReplacesApplicationResults() async throws {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "U+2192"
        model.refreshQuery()

        for _ in 0..<30 where model.isSearchingUnicode {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(model.isUnicodeQuery)
        XCTAssertTrue(model.hasInferredContent)
        XCTAssertEqual(model.unicodeResults.first?.symbol, "→")
        XCTAssertEqual(model.resultCount, 1)
        XCTAssertTrue(model.selectionIsActionable)
    }

    @MainActor
    func testUnicodeSelectionClampsInsteadOfWrapping() async throws {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "unicode arrow"
        model.refreshQuery()

        for _ in 0..<80 where model.isSearchingUnicode {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertGreaterThan(model.resultCount, LauncherView.unicodeGridColumnCount)
        model.selectedIndex = model.resultCount - 1
        model.moveUnicodeSelection(rows: 1, columns: LauncherView.unicodeGridColumnCount)
        XCTAssertEqual(model.selectedIndex, model.resultCount - 1)

        model.selectedIndex = 3
        model.moveUnicodeSelection(rows: -1, columns: LauncherView.unicodeGridColumnCount)
        XCTAssertEqual(model.selectedIndex, 3)
    }

    @MainActor
    func testUnicodeResultsRemainVisibleWhileTheLatestQueryIsDebounced() async throws {
        let model = AppModel(clipboard: ClipboardStore())
        model.query = "U+2192"
        model.refreshQuery()

        for _ in 0..<80 where model.isSearchingUnicode {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.unicodeResults.first?.symbol, "→")

        model.query = "emoji heart"
        model.refreshQuery()
        XCTAssertTrue(model.isSearchingUnicode)
        XCTAssertEqual(model.unicodeResults.first?.symbol, "→")

        for _ in 0..<80 where model.isSearchingUnicode {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(model.unicodeResults.contains {
            $0.name.localizedCaseInsensitiveContains("heart")
        })
    }
}
