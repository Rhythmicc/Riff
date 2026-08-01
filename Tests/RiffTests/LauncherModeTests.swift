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

    func testCommandNumberNavigationKeyCodes() {
        XCTAssertEqual(LauncherMode.navigationMode(for: 18), .apps)
        XCTAssertEqual(LauncherMode.navigationMode(for: 19), .clipboard)
        XCTAssertNil(LauncherMode.navigationMode(for: 20))
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
}
