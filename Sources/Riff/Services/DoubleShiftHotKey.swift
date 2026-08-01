import AppKit
import Foundation

struct DoubleTapDetector {
    let maximumInterval: TimeInterval
    private(set) var lastTap: TimeInterval?

    init(maximumInterval: TimeInterval = 0.36) {
        self.maximumInterval = maximumInterval
    }

    mutating func registerTap(at timestamp: TimeInterval) -> Bool {
        if let lastTap {
            let interval = timestamp - lastTap
            if interval > 0, interval <= maximumInterval {
                self.lastTap = nil
                return true
            }
        }
        self.lastTap = timestamp
        return false
    }

    mutating func reset() {
        lastTap = nil
    }
}

@MainActor
final class DoubleShiftHotKey {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var detector = DoubleTapDetector()
    private var pressedShiftKeys = Set<UInt16>()
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            detector.reset()
            return
        }

        let isShiftKey = event.keyCode == 56 || event.keyCode == 60
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard isShiftKey else {
            if !flags.isEmpty { detector.reset() }
            return
        }

        let otherFlags = flags.subtracting(.shift)
        guard flags.contains(.shift), otherFlags.isEmpty else {
            if !flags.contains(.shift) { pressedShiftKeys.removeAll() }
            if !otherFlags.isEmpty { detector.reset() }
            return
        }

        guard pressedShiftKeys.insert(event.keyCode).inserted else { return }
        if detector.registerTap(at: event.timestamp) {
            action()
        }
    }
}
