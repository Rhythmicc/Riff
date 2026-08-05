import ApplicationServices
import Carbon
import XCTest
@testable import Riff

final class GlobalShortcutMonitorTests: XCTestCase {
    func testConvertsCGEventFlagsToCarbonModifiersAndIgnoresUnrelatedFlags() {
        XCTAssertEqual(
            GlobalShortcutMonitor.carbonModifiers(from: [.maskCommand, .maskShift]),
            UInt32(cmdKey | shiftKey)
        )
        XCTAssertEqual(
            GlobalShortcutMonitor.carbonModifiers(from: [.maskCommand, .maskNonCoalesced]),
            UInt32(cmdKey)
        )
    }
}
