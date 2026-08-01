import XCTest
@testable import Riff

@MainActor
final class TranslationModelSessionTests: XCTestCase {
    func testCompletedTranslationRemainsAReopenableSession() {
        let model = TranslationModel(settings: SettingsStore())
        model.preparePreview(
            source: "Hello",
            result: "你好",
            targetLanguage: .simplifiedChinese
        )

        XCTAssertTrue(model.hasSession)
        XCTAssertEqual(model.source, "Hello")
        XCTAssertEqual(model.result, "你好")
    }

    func testFreshModelDoesNotClaimToHaveSession() {
        let model = TranslationModel(settings: SettingsStore())

        XCTAssertFalse(model.hasSession)
    }
}
