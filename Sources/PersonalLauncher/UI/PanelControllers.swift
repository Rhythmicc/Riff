import AppKit
import SwiftUI

final class KeyablePanel: NSPanel {
    var usesPlainTextFieldEditor = false
    private lazy var plainTextFieldEditor = PlainTextFieldEditor()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        guard usesPlainTextFieldEditor, object is NSTextField else {
            return super.fieldEditor(createFlag, for: object)
        }
        return plainTextFieldEditor
    }
}

enum LauncherKeyRouting {
    static func shouldDeferToInputMethod(firstResponder: NSResponder?) -> Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() == true
    }
}

@MainActor
class MaterialPanelController {
    let panel: KeyablePanel

    init(size: NSSize, level: NSWindow.Level = .floating) {
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("")
    }

    func install<Content: View>(_ view: Content, cornerRadius: CGFloat = 22) {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.7
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        panel.contentView = effect
    }

    func showCentered() {
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class LauncherPanelController: MaterialPanelController {
    private let model: AppModel
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(model: AppModel, showNote: @escaping () -> Void, showSettings: @escaping () -> Void) {
        self.model = model
        super.init(size: LauncherView.windowSize, level: .popUpMenu)
        panel.usesPlainTextFieldEditor = true
        install(LauncherView(
            model: model,
            close: { [weak panel] in panel?.orderOut(nil) },
            showNote: showNote,
            showSettings: showSettings
        ))

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if LauncherKeyRouting.shouldDeferToInputMethod(firstResponder: self.panel.firstResponder) {
                return event
            }
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
            if modifiers == .command,
               let mode = LauncherMode.navigationMode(for: event.keyCode) {
                self.model.switchMode(mode)
                return nil
            }
            switch event.keyCode {
            case 53:
                self.panel.orderOut(nil)
                return nil
            case 13 where modifiers == .command:
                self.panel.orderOut(nil)
                return nil
            case 125:
                self.model.moveSelection(by: 1)
                return nil
            case 126:
                self.model.moveSelection(by: -1)
                return nil
            case 36, 76:
                if self.model.selectionIsActionable {
                    self.model.activateSelection()
                    self.panel.orderOut(nil)
                }
                return nil
            case 48 where event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty:
                let modes = LauncherMode.allCases
                if let index = modes.firstIndex(of: self.model.mode) {
                    self.model.switchMode(modes[(index + 1) % modes.count])
                }
                return nil
            default:
                return event
            }
        }

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard let self, self.panel.isVisible, event.window !== self.panel else { return event }
            self.panel.orderOut(nil)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor in self?.closeIfPointerIsOutside() }
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    func show(mode: LauncherMode) {
        model.reset(for: mode)
        showCentered()
    }

    func toggle(mode: LauncherMode) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(mode: mode)
        }
    }

    private func closeIfPointerIsOutside() {
        guard panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        panel.orderOut(nil)
    }
}

@MainActor
final class NotePanelController: MaterialPanelController {
    init(model: NoteModel) {
        super.init(size: NoteView.windowSize, level: .floating)
        install(NoteView(
            model: model,
            close: { [weak panel] in panel?.orderOut(nil) }
        ), cornerRadius: 20)
    }

    func show() { showCentered() }

    func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { showCentered() }
    }
}

@MainActor
final class TranslationPanelController: MaterialPanelController {
    let model: TranslationModel
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(model: TranslationModel, settings: SettingsStore, openSettings: @escaping () -> Void) {
        self.model = model
        super.init(size: NSSize(width: 840, height: 470), level: .popUpMenu)
        install(TranslationView(
            model: model,
            settings: settings,
            openSettings: openSettings,
            close: { [weak panel] in panel?.orderOut(nil) }
        ), cornerRadius: 20)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
            if event.keyCode == 53 || (event.keyCode == 13 && modifiers == .command) {
                self.panel.orderOut(nil)
                return nil
            }
            if modifiers == .command, (event.keyCode == 36 || event.keyCode == 76) {
                if self.model.copyResult() { self.panel.orderOut(nil) }
                return nil
            }
            if modifiers == .command, event.keyCode == 15 {
                self.model.retry()
                return nil
            }
            return event
        }

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard let self, self.panel.isVisible, event.window !== self.panel else { return event }
            self.panel.orderOut(nil)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor in self?.closeIfPointerIsOutside() }
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    func show(text: String) {
        DiagnosticLogger.shared.log("translation", "panel.show begin textLength=\(text.count)")
        model.begin(with: text)
        showCentered()
        DiagnosticLogger.shared.log(
            "translation",
            "panel.show end visible=\(self.panel.isVisible) key=\(self.panel.isKeyWindow) frame=\(NSStringFromRect(self.panel.frame))"
        )
    }

    private func closeIfPointerIsOutside() {
        guard panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        panel.orderOut(nil)
    }
}

@MainActor
final class SettingsPanelController: MaterialPanelController {
    private var monitor: Any?

    init(settings: SettingsStore, shortcuts: ShortcutStore) {
        super.init(size: NSSize(width: 560, height: 540), level: .floating)
        install(SettingsView(
            settings: settings,
            shortcuts: shortcuts,
            close: { [weak panel] in panel?.orderOut(nil) }
        ), cornerRadius: 18)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
            guard event.keyCode == 53 || (event.keyCode == 13 && modifiers == .command) else {
                return event
            }
            self.panel.orderOut(nil)
            return nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func show() { showCentered() }
}
