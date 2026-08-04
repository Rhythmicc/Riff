import AppKit
import XCTest
@testable import Riff

final class MaterialPanelTests: XCTestCase {
    @MainActor
    func testTransparentMaterialPanelDoesNotAddSystemShadow() {
        let controller = MaterialPanelController(size: NSSize(width: 320, height: 80))

        XCTAssertFalse(controller.panel.isOpaque)
        XCTAssertEqual(controller.panel.backgroundColor, .clear)
        XCTAssertFalse(controller.panel.hasShadow)
        XCTAssertFalse(controller.panel.styleMask.contains(.nonactivatingPanel))
    }
}
