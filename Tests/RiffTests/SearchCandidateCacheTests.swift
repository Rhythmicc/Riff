import XCTest
@testable import Riff

final class SearchCandidateCacheTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-cache-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeApplication() -> ApplicationRecord {
        ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            name: "Test",
            bundleIdentifier: "com.example.test"
        )
    }

    func testReturnsCachedFieldsWithoutRebuilding() {
        let cache = SearchCandidateCache(url: url)
        let application = makeApplication()
        var builds = 0
        let fields = CachedSearchCandidateFields(
            bundleModificationDate: 100,
            localizedNames: ["本地名"],
            pinyinVariants: ["ceshi"]
        )

        _ = cache.fields(for: application, bundleModificationDate: 100) {
            builds += 1
            return fields
        }
        _ = cache.fields(for: application, bundleModificationDate: 100) {
            builds += 1
            return fields
        }

        XCTAssertEqual(builds, 1)
    }

    func testInvalidatesWhenBundleChanges() {
        let cache = SearchCandidateCache(url: url)
        let application = makeApplication()
        var builds = 0

        _ = cache.fields(for: application, bundleModificationDate: 100) {
            builds += 1
            return CachedSearchCandidateFields(
                bundleModificationDate: 100,
                localizedNames: [],
                pinyinVariants: []
            )
        }
        _ = cache.fields(for: application, bundleModificationDate: 200) {
            builds += 1
            return CachedSearchCandidateFields(
                bundleModificationDate: 200,
                localizedNames: ["新版名"],
                pinyinVariants: []
            )
        }

        XCTAssertEqual(builds, 2)
    }

    func testPersistsAcrossInstances() {
        let application = makeApplication()
        let first = SearchCandidateCache(url: url)
        _ = first.fields(for: application, bundleModificationDate: 100) {
            CachedSearchCandidateFields(
                bundleModificationDate: 100,
                localizedNames: ["Localized"],
                pinyinVariants: ["weixin"]
            )
        }
        first.persistIfNeeded()

        let second = SearchCandidateCache(url: url)
        var builds = 0
        let fields = second.fields(for: application, bundleModificationDate: 100) {
            builds += 1
            return CachedSearchCandidateFields(
                bundleModificationDate: 100,
                localizedNames: [],
                pinyinVariants: []
            )
        }

        XCTAssertEqual(builds, 0)
        XCTAssertEqual(fields.localizedNames, ["Localized"])
        XCTAssertEqual(fields.pinyinVariants, ["weixin"])
    }
}
