import NaturalLanguage
import XCTest
@testable import Riff

final class TranslationLanguageTests: XCTestCase {
    func testMigratesLegacyLanguageNames() {
        XCTAssertEqual(TranslationLanguage.fromStoredValue("简体中文"), .simplifiedChinese)
        XCTAssertEqual(TranslationLanguage.fromStoredValue("English"), .english)
        XCTAssertEqual(TranslationLanguage.fromStoredValue("ja"), .japanese)
    }

    func testNonNativeTextTargetsNativeLanguage() {
        let direction = TranslationDirectionResolver.resolve(
            text: "This is a sentence written in English.",
            nativeLanguage: .simplifiedChinese,
            priorityLanguage: .english
        )
        XCTAssertFalse(direction.sourceIsNative)
        XCTAssertEqual(direction.targetLanguage, .simplifiedChinese)
    }

    func testNativeTextTargetsPriorityLanguage() {
        let direction = TranslationDirectionResolver.resolve(
            text: "这是一段需要翻译的中文。",
            nativeLanguage: .simplifiedChinese,
            priorityLanguage: .english
        )
        XCTAssertTrue(direction.sourceIsNative)
        XCTAssertEqual(direction.targetLanguage, .english)
    }

    func testChineseVariantsAreTreatedAsSameNativeLanguage() {
        XCTAssertTrue(TranslationLanguage.simplifiedChinese.matches(.traditionalChinese))
    }

    func testDefaultPriorityDoesNotEqualNativeLanguage() {
        XCTAssertEqual(TranslationLanguage.defaultPriority(for: .english), .simplifiedChinese)
        XCTAssertEqual(TranslationLanguage.defaultPriority(for: .japanese), .english)
    }
}
