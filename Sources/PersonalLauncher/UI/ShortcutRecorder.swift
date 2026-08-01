import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let binding: ShortcutBinding
    let onRecord: (ShortcutBinding) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.binding = binding
        button.onRecord = onRecord
        button.refreshTitle()
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.binding = binding
        button.onRecord = onRecord
        if !button.isRecording { button.refreshTitle() }
    }
}

final class ShortcutRecorderButton: NSButton {
    var binding = ShortcutBinding.doubleShift
    var onRecord: ((ShortcutBinding) -> Void)?
    private(set) var isRecording = false

    private var doubleShiftDetector = DoubleTapDetector()
    private var pressedShiftKeys = Set<UInt16>()

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecording)
        bezelStyle = .rounded
        controlSize = .regular
        focusRingType = .exterior
        font = .systemFont(ofSize: 12, weight: .medium)
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func beginRecording() {
        isRecording = true
        doubleShiftDetector.reset()
        pressedShiftKeys.removeAll()
        title = "请按快捷键…"
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = Self.carbonModifiers(from: flags)
        guard modifiers != 0 else {
            NSSound.beep()
            title = "请加修饰键"
            return
        }

        let recorded = ShortcutBinding.key(
            UInt32(event.keyCode),
            modifiers: modifiers,
            label: Self.keyLabel(for: event)
        )
        finish(with: recorded)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShiftKey = event.keyCode == 56 || event.keyCode == 60
        guard isShiftKey else {
            doubleShiftDetector.reset()
            return
        }

        if !flags.contains(.shift) {
            pressedShiftKeys.remove(event.keyCode)
            return
        }

        guard flags.subtracting(.shift).isEmpty else {
            doubleShiftDetector.reset()
            return
        }

        guard pressedShiftKeys.insert(event.keyCode).inserted else { return }
        title = "再按一次 Shift"
        if doubleShiftDetector.registerTap(at: event.timestamp) {
            finish(with: .doubleShift)
        }
    }

    func refreshTitle() {
        title = binding.displayName
        toolTip = "点击后按下新的快捷键；连续按两次 Shift 可设为双击 Shift"
    }

    private func finish(with binding: ShortcutBinding) {
        isRecording = false
        self.binding = binding
        onRecord?(binding)
        refreshTitle()
        window?.makeFirstResponder(nil)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36, 76: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let value = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return value.isEmpty ? "Key \(event.keyCode)" : value
        }
    }
}
