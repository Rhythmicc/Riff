import Carbon
import Foundation

final class GlobalHotKey {
    private(set) var isRegistered = false
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let identifier: UInt32

    init(keyCode: UInt32, modifiers: UInt32, identifier: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.identifier = identifier

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && hotKeyID.id == instance.identifier {
                    DiagnosticLogger.shared.log("carbon-hotkey", "received identifier=\(instance.identifier)")
                    DispatchQueue.main.async { instance.action() }
                    return noErr
                }
                // Several GlobalHotKey instances install handlers on the same
                // application target. A non-matching handler must allow Carbon
                // to continue to the handler that owns this identifier.
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        DiagnosticLogger.shared.log(
            "carbon-hotkey",
            "handler identifier=\(identifier) status=\(installStatus)"
        )

        let signature = OSType(0x504C4155) // PLAU
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        isRegistered = installStatus == noErr && status == noErr
        DiagnosticLogger.shared.log(
            "carbon-hotkey",
            "register identifier=\(identifier) keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)"
        )
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
