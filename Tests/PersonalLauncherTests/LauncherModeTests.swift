import XCTest
@testable import PersonalLauncher

final class LauncherModeTests: XCTestCase {
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
}
