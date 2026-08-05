import XCTest
@testable import Riff

final class SearchCandidateBuilderTests: XCTestCase {
    func testSplitsWordsCamelCaseAndDigits() {
        XCTAssertEqual(
            SearchCandidateBuilder.splitComponents("CleanShot X"),
            ["clean", "shot", "x"]
        )
        XCTAssertEqual(
            SearchCandidateBuilder.splitComponents("Visual Studio Code"),
            ["visual", "studio", "code"]
        )
        XCTAssertEqual(
            SearchCandidateBuilder.splitComponents("OmniGraffle"),
            ["omni", "graffle"]
        )
        XCTAssertEqual(
            SearchCandidateBuilder.splitComponents("A12B"),
            ["a", "12", "b"]
        )
    }

    func testInitialsFromComponents() {
        XCTAssertEqual(
            SearchCandidateBuilder.initials(
                of: SearchCandidateBuilder.splitComponents("CleanShot X")
            ),
            "csx"
        )
        XCTAssertEqual(
            SearchCandidateBuilder.initials(
                of: SearchCandidateBuilder.splitComponents("Visual Studio Code")
            ),
            "vsc"
        )
    }

    func testPinyinVariantsForChineseNames() {
        XCTAssertEqual(
            SearchCandidateBuilder.pinyinVariants(for: "微信"),
            ["wei xin", "weixin", "wx"]
        )
        XCTAssertTrue(
            SearchCandidateBuilder.pinyinVariants(for: "哔哩哔哩")
                .contains("bilibili")
        )
        XCTAssertTrue(
            SearchCandidateBuilder.pinyinVariants(for: "哔哩哔哩")
                .contains("blbl")
        )
    }

    func testEnglishNamesOnlyProduceInitials() {
        XCTAssertEqual(
            SearchCandidateBuilder.pinyinVariants(for: "Visual Studio Code"),
            ["vsc"]
        )
    }

    func testLocalizedNamesAreEmptyForFakeBundles() {
        XCTAssertTrue(
            SearchCandidateBuilder.localizedNames(
                for: URL(fileURLWithPath: "/Applications/Does Not Exist.app")
            ).isEmpty
        )
    }
}
