import XCTest
@testable import Riff

final class SearchGoldenTests: XCTestCase {
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

    private func makeSearch(
        _ applications: [ApplicationRecord]
    ) async -> ApplicationSearch {
        let search = ApplicationSearch()
        _ = await search.replaceApplications(applications, runningBundleIdentifiers: [])
        return search
    }

    func testWeSurfacesWeChatViaPinyinAlone() async throws {
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
            // No curated aliases: pinyin must do the work.
            makeApplication(
                path: "/Applications/WeChat.app",
                name: "微信",
                bundleIdentifier: "com.tencent.xinWeChat"
            )
        ]
        let search = await makeSearch(applications)

        let results = await search.search("we")

        XCTAssertEqual(results.first?.name, "微信")
        XCTAssertFalse(results.contains { $0.name == "CleanShot X" })
        XCTAssertFalse(results.contains { $0.name == "Dowine 4" })
        XCTAssertFalse(results.contains { $0.name == "Microsoft PowerPoint" })
    }

    func testMaAndMaiSurfaceMail() async throws {
        let applications = [
            makeApplication(
                path: "/Applications/Mail.app",
                name: "Mail",
                bundleIdentifier: "com.apple.mail",
                aliases: ["邮箱"]
            ),
            makeApplication(
                path: "/Applications/Mactracker.app",
                name: "Mactracker",
                bundleIdentifier: "com.example.mactracker"
            )
        ]
        let search = await makeSearch(applications)

        let maResults = await search.search("ma")
        XCTAssertEqual(maResults.first?.name, "Mail")
        let maiResults = await search.search("mai")
        XCTAssertEqual(maiResults.first?.name, "Mail")
        let aliasResults = await search.search("邮箱")
        XCTAssertEqual(aliasResults.first?.name, "Mail")
    }

    func testInitialsMatchCleanShotAndVisualStudioCode() async throws {
        let applications = [
            makeApplication(
                path: "/Applications/CleanShot X.app",
                name: "CleanShot X",
                bundleIdentifier: "pl.maketheweb.cleanshotx"
            ),
            makeApplication(
                path: "/Applications/Visual Studio Code.app",
                name: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode"
            )
        ]
        let search = await makeSearch(applications)

        let csxResults = await search.search("csx")
        XCTAssertEqual(csxResults.first?.name, "CleanShot X")
        let vscResults = await search.search("vsc")
        XCTAssertEqual(vscResults.first?.name, "Visual Studio Code")
    }

    func testPinyinForUnfamiliarChineseApps() async throws {
        let applications = [
            makeApplication(
                path: "/Applications/Bilibili.app",
                name: "哔哩哔哩",
                bundleIdentifier: "tv.danmaku.bili"
            ),
            makeApplication(
                path: "/Applications/NetEase Music.app",
                name: "网易云音乐",
                bundleIdentifier: "com.netease.cloudmusic"
            )
        ]
        let search = await makeSearch(applications)

        let bilibiliResults = await search.search("bilibili")
        XCTAssertEqual(bilibiliResults.first?.name, "哔哩哔哩")
        let blblResults = await search.search("blbl")
        XCTAssertEqual(blblResults.first?.name, "哔哩哔哩")
        let wyyResults = await search.search("wyy")
        XCTAssertEqual(wyyResults.first?.name, "网易云音乐")
    }

    func testAcronymSubsequenceStillMatchesViaInitials() async throws {
        let applications = [
            makeApplication(
                path: "/Applications/Super App Finder.app",
                name: "Super App Finder",
                bundleIdentifier: "com.example.saf"
            )
        ]
        let search = await makeSearch(applications)

        let safResults = await search.search("saf")
        XCTAssertEqual(safResults.first?.name, "Super App Finder")
    }
}
