import Foundation
import XCTest
@testable import Riff

final class TranslationCacheTests: XCTestCase {
    func testCachePersistsAcrossInstances() async {
        let fileURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let key = TranslationCache.key(
            source: "Hello",
            targetLanguage: .simplifiedChinese,
            provider: .openRouter,
            model: "test-model"
        )
        let firstCache = TranslationCache(fileURL: fileURL)
        await firstCache.insert("你好", forKey: key)

        let restoredCache = TranslationCache(fileURL: fileURL)
        let restoredValue = await restoredCache.value(forKey: key)
        XCTAssertEqual(restoredValue, "你好")
    }

    func testKeySeparatesProviderModelTargetAndSource() {
        let baseline = TranslationCache.key(
            source: "Hello",
            targetLanguage: .simplifiedChinese,
            provider: .openRouter,
            model: "model-a"
        )

        XCTAssertNotEqual(
            baseline,
            TranslationCache.key(
                source: "Hello",
                targetLanguage: .english,
                provider: .openRouter,
                model: "model-a"
            )
        )
        XCTAssertNotEqual(
            baseline,
            TranslationCache.key(
                source: "Hello",
                targetLanguage: .simplifiedChinese,
                provider: .openAI,
                model: "model-a"
            )
        )
        XCTAssertNotEqual(
            baseline,
            TranslationCache.key(
                source: "Hello",
                targetLanguage: .simplifiedChinese,
                provider: .openRouter,
                model: "model-b"
            )
        )
        XCTAssertNotEqual(
            baseline,
            TranslationCache.key(
                source: "Hello!",
                targetLanguage: .simplifiedChinese,
                provider: .openRouter,
                model: "model-a"
            )
        )
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("translation-cache.json")
    }
}
