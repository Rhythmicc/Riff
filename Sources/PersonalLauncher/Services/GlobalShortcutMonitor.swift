import ApplicationServices
import Carbon
import Foundation

final class GlobalShortcutMonitor {
    struct Registration {
        let action: ShortcutAction
        let binding: ShortcutBinding
    }

    private(set) var isActive = false

    private let registrations: [Registration]
    private let onAction: (ShortcutAction) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(registrations: [Registration], onAction: @escaping (ShortcutAction) -> Void) {
        self.registrations = registrations
        self.onAction = onAction

        let trusted = AXIsProcessTrusted()
        DiagnosticLogger.shared.log("event-tap", "initialize trusted=\(trusted) registrations=\(registrations.count)")
        guard trusted, !registrations.isEmpty else {
            DiagnosticLogger.shared.log("event-tap", "not created: missing trust or registrations")
            return
        }

        let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalShortcutMonitor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DiagnosticLogger.shared.log("event-tap", "disabled type=\(type.rawValue); re-enabling")
                    if let eventTap = monitor.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown, monitor.handle(event) else {
                    return Unmanaged.passUnretained(event)
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DiagnosticLogger.shared.log("event-tap", "CGEvent.tapCreate returned nil")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isActive = true
        DiagnosticLogger.shared.log("event-tap", "created and enabled")
    }

    deinit {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    private func handle(_ event: CGEvent) -> Bool {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Self.carbonModifiers(from: event.flags)
        if keyCode == 17 || (modifiers & UInt32(cmdKey | shiftKey)) == UInt32(cmdKey | shiftKey) {
            DiagnosticLogger.shared.log(
                "event-tap",
                "candidate keyCode=\(keyCode) modifiers=\(modifiers) flagsRaw=\(event.flags.rawValue)"
            )
        }
        guard let registration = registrations.first(where: {
            $0.binding.keyCode == keyCode && $0.binding.modifiers == modifiers
        }) else {
            if keyCode == 17 {
                DiagnosticLogger.shared.log("event-tap", "keyCode 17 did not match")
            }
            return false
        }

        DiagnosticLogger.shared.log("event-tap", "matched action=\(registration.action.rawValue); consuming")
        DispatchQueue.main.async { [onAction] in
            DiagnosticLogger.shared.log("event-tap", "dispatch action=\(registration.action.rawValue) on main")
            onAction(registration.action)
        }
        return true
    }

    static func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
        if flags.contains(.maskControl) { result |= UInt32(controlKey) }
        if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
        return result
    }
}
