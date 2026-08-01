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
        XCTAssertNil(AppModel.applicationScore(query: "note", application: unrelated))
    }

    func testBundleIdentifierSupportsContiguousQueries() {
        let code = ApplicationRecord(
            url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
            name: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode"
        )
        XCTAssertNotNil(AppModel.applicationScore(query: "vscode", application: code))
    }
}
