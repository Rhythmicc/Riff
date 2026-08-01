import XCTest
@testable import Riff

final class ClipboardItemTests: XCTestCase {
    @MainActor
    func testClipboardImagePreviewCannotExpandTheSplitLayout() {
        let view = ClipboardNSImageView()
        view.image = NSImage(size: NSSize(width: 2_000, height: 1_200))

        XCTAssertEqual(view.intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertEqual(view.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }

    func testImageFileURLsReceiveImagePreviewsWithoutChangingKind() {
        for path in ["/tmp/screenshot.png", "/tmp/animation.GIF", "/tmp/photo.heic", "/tmp/image.webp"] {
            let item = ClipboardItem(kind: .file, text: path)

            XCTAssertEqual(item.kind, .file)
            XCTAssertEqual(item.imagePreviewURL?.path, path)
            XCTAssertEqual(item.previewTitle, "图片文件")
        }
    }

    func testOrdinaryFilesDoNotReceiveImagePreviews() {
        for path in ["/tmp/document.pdf", "/tmp/archive.zip", "/tmp/source.swift"] {
            let item = ClipboardItem(kind: .file, text: path)

            XCTAssertNil(item.imagePreviewURL)
            XCTAssertEqual(item.previewTitle, "文件")
        }
    }

    func testPersistedPasteboardImagesRemainPreviewable() {
        let item = ClipboardItem(kind: .image, text: "/tmp/captured-image")

        XCTAssertEqual(item.imagePreviewURL?.path, "/tmp/captured-image")
        XCTAssertEqual(item.previewTitle, "图片")
    }
}
