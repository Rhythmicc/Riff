import XCTest
@testable import Riff

@MainActor
final class AppSearchRankingTests: XCTestCase {
    private func makeApplication(
        path: String,
        name: String,
        bundleIdentifier: String,
        aliases: [String] = []
    ) -> ApplicationRecord {
        ApplicationRecord(
            url: URL(fileURLWithPath: path),
            name: name,
            bundleIdentifier: bundleIdentifier,
            aliases: aliases
        )
    }

    func testShortQueryWechatSurfacesAloneFromInteriorMatches() async throws {
        let applications = [
            makeApplication(
                path: "/Applications/Microsoft PowerPoint.app",
                name: "Microsoft PowerPoint",
                bundleIdentifier: "com.microsoft.Powerpoint"
            ),
            makeApplication(
                path: "/Applications/Dowine 4.app",
                name: "Dowine 4",
                bundleIdentifier: "com.example.dowine4"
            ),
            makeApplication(
                path: "/Applications/CleanShot X.app",
                name: "CleanShot X",
                bundleIdentifier: "pl.maketheweb.cleanshotx"
            ),
            makeApplication(
                path: "/Applications/WeChat.app",
                name: "微信",
                bundleIdentifier: "com.tencent.xinWeChat",
                aliases: ["wechat", "weixin"]
            )
        ]
        let search = ApplicationSearch()
        _ = await search.replaceApplications(applications, runningBundleIdentifiers: [])

        let results = await search.search("we")

        XCTAssertEqual(results.map(\.name), ["微信"])
    }

    func testWechatAliasMatchesAtNameLevelForRanking() async throws {
        let wechat = makeApplication(
            path: "/Applications/WeChat.app",
            name: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            aliases: ["wechat", "weixin"]
        )
        let suiteName = "AppSearchRankingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let usage = LauncherUsageStore(defaults: defaults, key: "ranking.test")

        let merged = LauncherSearchPool.merge(
            LauncherSearchPool.appItems(query: "we", applications: [wechat]),
            queryLength: 2,
            usageStore: usage
        )

        XCTAssertEqual(merged.count, 1)
        guard case .application(let first) = merged[0].payload else {
            return XCTFail("expected an application item")
        }
        XCTAssertEqual(first.name, "微信")
    }

    func testApplicationScoreUsesAliasBeforeBundle() {
        let wechat = makeApplication(
            path: "/Applications/WeChat.app",
            name: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            aliases: ["wechat", "weixin"]
        )

        let score = SearchScorer.score(
            query: "we",
            candidate: SearchCandidateBuilder.build(for: wechat)
        )

        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score ?? 0, 0)
    }

    func testShortQueryMaSurfacesAppleMailInsteadOfSystemOperations() async throws {
        let applications = [
            makeApplication(
                path: "/System/Applications/Mail.app",
                name: "Mail",
                bundleIdentifier: "com.apple.mail",
                aliases: ["mail", "邮箱"]
            )
        ]
        let search = ApplicationSearch()
        _ = await search.replaceApplications(applications, runningBundleIdentifiers: [])

        XCTAssertTrue(SystemOperation.matching("ma").isEmpty)
        let maResults = await search.search("ma")
        XCTAssertEqual(maResults.map(\.name), ["Mail"])
        let aliasResults = await search.search("邮箱")
        XCTAssertEqual(aliasResults.map(\.name), ["Mail"])
    }
}
