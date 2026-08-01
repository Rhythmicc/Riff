import XCTest
@testable import PersonalLauncher

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
}
