import CryptoKit
import XCTest
@testable import Riff

final class AppUpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppUpdater.isNewer("0.4.0", than: "0.3.0"))
        XCTAssertTrue(AppUpdater.isNewer("v0.4.0", than: "0.3.0"))
        XCTAssertTrue(AppUpdater.isNewer("0.3.10", than: "0.3.9"))
        XCTAssertFalse(AppUpdater.isNewer("0.3.0", than: "0.3.0"))
        XCTAssertFalse(AppUpdater.isNewer("0.3.0", than: "0.4.0"))
        XCTAssertFalse(AppUpdater.isNewer("0.2.0", than: "0.3.0"))
        XCTAssertTrue(AppUpdater.isNewer("1.0.0", than: "0.9.9"))
    }

    func testVersionComponentsIgnorePrefixAndTruncate() {
        XCTAssertEqual(AppUpdater.versionComponents("v0.4.0"), [0, 4, 0])
        XCTAssertEqual(AppUpdater.versionComponents("0.3.0-beta.2"), [0, 3, 0])
        XCTAssertEqual(AppUpdater.versionComponents("0.3"), [0, 3])
    }

    func testTagNameExtractionFromLatestRedirect() {
        XCTAssertEqual(
            AppUpdater.tagName(fromLatestRedirectURL: URL(string: "https://github.com/Rhythmicc/Riff/releases/tag/v0.4.0")!),
            "v0.4.0"
        )
        XCTAssertNil(
            AppUpdater.tagName(fromLatestRedirectURL: URL(string: "https://github.com/Rhythmicc/Riff/releases")!)
        )
    }

    func testReleaseURLsUseTheWorkflowAssetNaming() {
        let release = RiffUpdateRelease(tagName: "v0.4.0")

        XCTAssertEqual(
            release.zipURL.absoluteString,
            "https://github.com/Rhythmicc/Riff/releases/download/v0.4.0/Riff-v0.4.0-macOS-universal.zip"
        )
        XCTAssertEqual(
            release.checksumURL.absoluteString,
            "https://github.com/Rhythmicc/Riff/releases/download/v0.4.0/Riff-v0.4.0-macOS-universal.zip.sha256"
        )
    }

    func testSha256HexMatchesCryptoKit() {
        let data = Data("Riff update checksum test".utf8)

        XCTAssertEqual(
            AppUpdater.sha256Hex(of: data),
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}
