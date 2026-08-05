import XCTest
@testable import Riff

final class FuzzyMatcherTests: XCTestCase {
    func testPrefixRanksAboveSubsequence() {
        let prefix = FuzzyMatcher.score(query: "saf", candidate: "Safari")!
        let subsequence = FuzzyMatcher.score(query: "saf", candidate: "Super App Finder")!
        XCTAssertGreaterThan(prefix, subsequence)
    }

    func testMissingSequenceDoesNotMatch() {
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", candidate: "Safari"))
    }

    func testCaseAndWidthAreIgnored() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "ＮＯＴＥ", candidate: "Notes"))
    }

    func testRejectsAWidelyScatteredSubsequence() {
        XCTAssertNil(FuzzyMatcher.score(query: "note", candidate: "NVIDIA Nsight Compute"))
    }

    func testWordInitialAcronymsRemainUseful() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "saf", candidate: "Super App Finder"))
    }

    func testApplicationNameAndBundleIdentifierCannotFormOneMatch() {
        let unrelated = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/AM_Master.app"),
            name: "AM_Master",
            bundleIdentifier: "com.angrymiao.master"
        )
        XCTAssertNil(SearchScorer.score(
            query: "note",
            candidate: SearchCandidateBuilder.build(for: unrelated)
        ))
    }

    func testBundleIdentifierSupportsContiguousQueries() {
        let code = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            name: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode"
        )
        XCTAssertNotNil(SearchScorer.score(
            query: "vscode",
            candidate: SearchCandidateBuilder.build(for: code)
        ))
    }

    func testApplicationNameScoreOutranksAnExactBundleIdentifierScore() throws {
        let nameMatch = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Cool Draft Xylophone.app"),
            name: "Cool Draft Xylophone",
            bundleIdentifier: "dev.example.editor"
        )
        let bundleOnlyMatch = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Utility.app"),
            name: "Utility",
            bundleIdentifier: "cdx"
        )

        let nameScore = try XCTUnwrap(SearchScorer.score(
            query: "cdx",
            candidate: SearchCandidateBuilder.build(for: nameMatch)
        ))
        let bundleScore = try XCTUnwrap(SearchScorer.score(
            query: "cdx",
            candidate: SearchCandidateBuilder.build(for: bundleOnlyMatch)
        ))

        XCTAssertGreaterThan(nameScore, bundleScore)
    }

    func testShortQueriesRequireComponentBoundary() {
        XCTAssertNil(FuzzyMatcher.score(
            query: "we",
            candidate: "Microsoft PowerPoint",
            requireBoundaryForShortQueries: true
        ))
        XCTAssertNil(FuzzyMatcher.score(
            query: "we",
            candidate: "Dowine 4",
            requireBoundaryForShortQueries: true
        ))
        XCTAssertNotNil(FuzzyMatcher.score(
            query: "we",
            candidate: "Welly",
            requireBoundaryForShortQueries: true
        ))
        XCTAssertNil(FuzzyMatcher.contiguousScore(
            query: "we",
            candidate: "pl.maketheweb.cleanshotx",
            requireBoundaryForShortQueries: true
        ))
        XCTAssertNotNil(FuzzyMatcher.contiguousScore(
            query: "we",
            candidate: "com.tencent.xinWeChat",
            requireBoundaryForShortQueries: true
        ))
    }

    func testInteriorMatchesStillWorkForLongerQueries() {
        XCTAssertNotNil(FuzzyMatcher.score(
            query: "ower",
            candidate: "Microsoft PowerPoint",
            requireBoundaryForShortQueries: true
        ))
    }

    func testWechatAliasCatalog() {
        XCTAssertEqual(
            AppAliasCatalog.aliases(for: "com.tencent.xinWeChat"),
            ["wechat", "weixin"]
        )
        XCTAssertTrue(AppAliasCatalog.aliases(for: "com.unknown.example").isEmpty)
    }
}
