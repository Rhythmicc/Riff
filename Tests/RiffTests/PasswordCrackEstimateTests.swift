import XCTest
@testable import Riff

final class PasswordCrackEstimateTests: XCTestCase {
    func testEntropyMatchesRequestLengthAndAlphabet() {
        let full = PasswordRequest(length: 16)
        let noSymbols = PasswordRequest(length: 16, includeSymbols: false)
        let fullAlphabet = Double(PasswordGenerator.alphabetSize(includeSymbols: true))
        let reducedAlphabet = Double(PasswordGenerator.alphabetSize(includeSymbols: false))

        XCTAssertEqual(
            PasswordCrackEstimate.entropyBits(for: full),
            16 * log2(fullAlphabet),
            accuracy: 0.001
        )
        XCTAssertEqual(
            PasswordCrackEstimate.entropyBits(for: noSymbols),
            16 * log2(reducedAlphabet),
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            PasswordCrackEstimate.entropyBits(for: full),
            PasswordCrackEstimate.entropyBits(for: noSymbols)
        )
    }

    func testLongerPasswordsTakeExponentiallyLonger() {
        let short = PasswordCrackEstimate.averageSeconds(
            toCrack: PasswordRequest(length: 8)
        )
        let long = PasswordCrackEstimate.averageSeconds(
            toCrack: PasswordRequest(length: 16)
        )

        XCTAssertGreaterThan(long / short, 100_000_000)
    }

    func testDefaultPasswordSummaryExceedsUniverseAge() {
        let summary = PasswordCrackEstimate.localizedSummary(for: PasswordRequest())

        XCTAssertTrue(summary.contains("位熵"))
        XCTAssertTrue(summary.contains("宇宙年龄"))
        XCTAssertTrue(summary.contains("每秒 100 亿次"))
    }

    func testShortPasswordIsMeasuredInHours() {
        let duration = PasswordCrackEstimate.localizedDuration(
            PasswordCrackEstimate.averageSeconds(toCrack: PasswordRequest(length: 8))
        )

        XCTAssertTrue(duration.contains("小时"))
    }

    func testDurationFormattingUsesAppropriateUnits() {
        XCTAssertTrue(PasswordCrackEstimate.localizedDuration(0.5).contains("秒"))
        XCTAssertTrue(PasswordCrackEstimate.localizedDuration(90).contains("分钟"))
        XCTAssertTrue(PasswordCrackEstimate.localizedDuration(7_200).contains("小时"))
        XCTAssertTrue(PasswordCrackEstimate.localizedDuration(2 * 86_400).contains("天"))
        XCTAssertTrue(
            PasswordCrackEstimate.localizedDuration(2 * PasswordCrackEstimate.secondsPerYear)
                .contains("年")
        )
    }

    func testNoSymbolRuleReducesTheEstimate() {
        let withSymbols = PasswordCrackEstimate.averageSeconds(
            toCrack: PasswordRequest(length: 16)
        )
        let withoutSymbols = PasswordCrackEstimate.averageSeconds(
            toCrack: PasswordRequest(length: 16, includeSymbols: false)
        )

        XCTAssertGreaterThan(withSymbols, withoutSymbols)
    }
}
