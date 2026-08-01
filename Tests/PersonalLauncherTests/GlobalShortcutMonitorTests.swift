import ApplicationServices
import Carbon
import XCTest
@testable import PersonalLauncher

final class GlobalShortcutMonitorTests: XCTestCase {
    func testConvertsCGEventFlagsToCarbonModifiers() {
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        XCTAssertEqual(
            GlobalShortcutMonitor.carbonModifiers(from: flags),
            UInt32(cmdKey | shiftKey)
        )
    }

    func testIgnoresUnrelatedCGEventFlags() {
        let flags: CGEventFlags = [.maskCommand, .maskNonCoalesced]
        XCTAssertEqual(
            GlobalShortcutMonitor.carbonModifiers(from: flags),
            UInt32(cmdKey)
        )
    }
}
