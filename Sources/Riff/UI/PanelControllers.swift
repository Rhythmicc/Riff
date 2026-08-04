import AppKit
import MarkdownEngine
import QuartzCore
import SwiftUI

final class KeyablePanel: NSPanel {
    var usesPlainTextFieldEditor = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: object)
        if usesPlainTextFieldEditor,
           object is NSTextField,
           let textView = editor as? NSTextView {
            PlainTextFieldEditing.configure(textView)
        }
        return editor
    }
}

enum LauncherKeyRouting {
    static func shouldDeferToInputMethod(firstResponder: NSResponder?) -> Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    static func isSettingsShortcut(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        keyCode == 43 && modifiers == .command
    }
}

enum LauncherMotion {
    static let presentationDuration: TimeInterval = 0.34
    static let presentationFadeDuration: TimeInterval = 0.20
    static let dismissalDuration: TimeInterval = 0.24
    static let resizeDuration: TimeInterval = 0.22
    /// Result counts can change once for every keystroke and once again when an
    /// asynchronous search completes. Hold expanded-to-expanded resizes until
    /// typing settles so the window is a stable surface rather than a live
    /// visualization of every intermediate count.
    static let resizeCoalescingDelay: TimeInterval = 0.26
    // Spotlight arrives slightly oversized and settles into place. Reversing
    // that motion on dismissal feels more like a material surface receding
    // than a dialog abruptly disappearing.
    static let presentationScale = 1.028
    static let presentationOvershootScale = 0.997
    static let presentationReboundScale = 1.0015
    static let dismissalScale = 0.986

    static func resizeDelay(
        currentHeight: CGFloat,
        targetHeight: CGFloat,
        collapsedHeight: CGFloat
    ) -> TimeInterval {
        let tolerance: CGFloat = 0.5
        let currentIsCollapsed = currentHeight <= collapsedHeight + tolerance
        let targetIsCollapsed = targetHeight <= collapsedHeight + tolerance
        return currentIsCollapsed || targetIsCollapsed ? 0 : resizeCoalescingDelay
    }

    static func centerTransformAnchor(of layer: CALayer) {
        guard layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else { return }
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = frame
    }
}

@MainActor
class MaterialPanelController {
    let panel: KeyablePanel
    private let activatesApplication: Bool

    init(
        size: NSSize,
        level: NSWindow.Level = .floating,
        activatesApplication: Bool = true
    ) {
        self.activatesApplication = activatesApplication
        var styleMask: NSWindow.StyleMask = [.borderless, .fullSizeContentView]
        if !activatesApplication {
            styleMask.insert(.nonactivatingPanel)
        }
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // AppKit composites the standard NSWindow shadow against whatever is
        // behind a transparent borderless panel. Around rounded dark corners it
        // becomes a pale, backdrop-dependent halo. Riff already draws its own
        // hairline border, so keep the exterior genuinely transparent.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.setFrameAutosaveName("")
    }

    func install<Content: View>(
        _ view: Content,
        anchorsContentToTop: Bool = false
    ) {
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = anchorsContentToTop
        container.addSubview(host)
        var constraints = [
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor)
        ]
        if !anchorsContentToTop {
            constraints.append(host.bottomAnchor.constraint(equalTo: container.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        panel.contentView = container
    }

    func showCentered(onPresented: (() -> Void)? = nil) {
        panel.center()
        if activatesApplication {
            // IMEs only attach their marked-text session reliably to a window
            // owned by the active application. Hardware key events may still
            // reach an inactive floating panel, which made Latin input appear
            // to work while Chinese/Japanese composition silently failed.
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.activatesApplication {
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)
            } else {
                self.panel.makeKey()
            }
            onPresented?()
        }
    }
}

extension Notification.Name {
    static let riffFocusLauncherSearch = Notification.Name("dev.rhythmicc.Riff.focusLauncherSearch")
}

@MainActor
final class LauncherPanelController: MaterialPanelController {
    private let model: AppModel
    private let showSettings: () -> Void
    private let experienceMetrics: ExperienceMetricsStore?
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pendingResizeWorkItem: DispatchWorkItem?
    private var visibilityGeneration = 0

    init(
        model: AppModel,
        showNote: @escaping () -> Void,
        showSettings: @escaping () -> Void,
        experienceMetrics: ExperienceMetricsStore? = nil
    ) {
        self.model = model
        self.showSettings = showSettings
        self.experienceMetrics = experienceMetrics
        super.init(
            size: LauncherView.windowSize(designHeight: LauncherView.collapsedDesignHeight),
            level: .popUpMenu,
            activatesApplication: false
        )
        panel.usesPlainTextFieldEditor = true
        install(LauncherView(
            model: model,
            close: { [weak self] in self?.dismiss() },
            showNote: showNote,
            showSettings: { [weak self] in self?.openSettings() },
            setDesignHeight: { [weak self] height in self?.setDesignHeight(height) },
            focusReady: { [weak self] in self?.experienceMetrics?.markLauncherFocusReady() }
        ), anchorsContentToTop: true)
        panel.hasShadow = true
        panel.animationBehavior = .none
        configureVisibleSurface(
            for: LauncherView.windowSize(designHeight: LauncherView.collapsedDesignHeight),
            animated: false
        )

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
            if LauncherKeyRouting.isSettingsShortcut(
                keyCode: event.keyCode,
                modifiers: modifiers
            ) {
                self.openSettings()
                return nil
            }
            switch event.keyCode {
            case 53:
                self.dismiss()
                return nil
            case 13 where modifiers == .command:
                self.dismiss()
                return nil
            case 125:
                if self.model.isUnicodeQuery {
                    self.model.moveUnicodeSelection(
                        rows: 1,
                        columns: LauncherView.unicodeGridColumnCount
                    )
                } else {
                    self.model.moveSelection(by: 1)
                }
                return nil
            case 126:
                if self.model.isUnicodeQuery {
                    self.model.moveUnicodeSelection(
                        rows: -1,
                        columns: LauncherView.unicodeGridColumnCount
                    )
                } else {
                    self.model.moveSelection(by: -1)
                }
                return nil
            case 123 where self.model.isUnicodeQuery:
                self.model.moveSelection(by: -1)
                return nil
            case 124 where self.model.isUnicodeQuery:
                self.model.moveSelection(by: 1)
                return nil
            case 36, 76:
                if self.model.selectionIsActionable {
                    if self.model.activateSelection() {
                        self.dismiss()
                    }
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
            self.dismiss()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            Task { @MainActor in self?.closeIfPointerIsOutside() }
        }
    }

    deinit {
        pendingResizeWorkItem?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    func show(mode: LauncherMode) {
        experienceMetrics?.beginLauncherSession()
        visibilityGeneration += 1
        pendingResizeWorkItem?.cancel()
        panel.contentView?.layer?.removeAnimation(forKey: "riff.launcher.visibility")
        model.reset(for: mode)
        if mode == .apps { model.refreshApplications() }
        setDesignHeight(
            mode == .apps ? LauncherView.collapsedDesignHeight : LauncherView.designSize.height,
            animated: false
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        showCentered { [weak self] in self?.requestSearchFocus() }
        panel.invalidateShadow()

        guard !reduceMotion else { return }
        animatePresentationSpring()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = LauncherMotion.presentationFadeDuration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.18, 0.72, 0.22, 1
            )
            panel.animator().alphaValue = 1
        }
    }

    func toggle(mode: LauncherMode) {
        if panel.isVisible {
            dismiss()
        } else {
            show(mode: mode)
        }
    }

    func dismiss(animated: Bool = true) {
        guard panel.isVisible else { return }
        experienceMetrics?.abandonLauncherSession()
        visibilityGeneration += 1
        let generation = visibilityGeneration
        pendingResizeWorkItem?.cancel()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.contentView?.layer?.removeAnimation(forKey: "riff.launcher.visibility")
            return
        }

        animateContentScale(
            from: 1,
            to: LauncherMotion.dismissalScale,
            duration: LauncherMotion.dismissalDuration,
            timingFunction: CAMediaTimingFunction(name: .easeIn),
            keepsFinalState: true
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = LauncherMotion.dismissalDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.visibilityGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.contentView?.layer?.removeAnimation(forKey: "riff.launcher.visibility")
            }
        }
    }

    private func closeIfPointerIsOutside() {
        guard panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        dismiss()
    }

    private func setDesignHeight(_ designHeight: CGFloat, animated: Bool = true) {
        let targetSize = LauncherView.windowSize(designHeight: designHeight)
        pendingResizeWorkItem?.cancel()
        pendingResizeWorkItem = nil
        guard panel.frame.size != targetSize else { return }

        let shouldAnimate = animated
            && panel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            applySize(targetSize, animated: false)
            return
        }

        let delay = LauncherMotion.resizeDelay(
            currentHeight: panel.frame.height,
            targetHeight: targetSize.height,
            collapsedHeight: LauncherView.windowSize(
                designHeight: LauncherView.collapsedDesignHeight
            ).height
        )
        guard delay > 0 else {
            applySize(targetSize, animated: true)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingResizeWorkItem = nil
            self.applySize(targetSize, animated: true)
        }
        pendingResizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    private func applySize(_ targetSize: CGSize, animated: Bool) {
        guard panel.frame.size != targetSize else { return }

        let searchWasFocused = panel.firstResponder is NSTextView
        configureVisibleSurface(for: targetSize, animated: animated)

        // Keep the search bar fixed while results unfold below it.
        let topEdge = panel.frame.maxY
        var targetFrame = panel.frame
        targetFrame.size = targetSize
        targetFrame.origin.y = topEdge - targetSize.height

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = LauncherMotion.resizeDuration
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.20, 0.80, 0.20, 1
                )
                panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.panel.invalidateShadow()
                    self?.restoreSearchFocusIfNeeded(searchWasFocused)
                }
            }
        } else {
            panel.setFrame(targetFrame, display: true, animate: false)
            panel.invalidateShadow()
            Task { @MainActor [weak self] in
                self?.restoreSearchFocusIfNeeded(searchWasFocused)
            }
        }
    }

    private func configureVisibleSurface(for targetSize: CGSize, animated: Bool) {
        guard let layer = panel.contentView?.layer else { return }
        let collapsedHeight = LauncherView.windowSize(
            designHeight: LauncherView.collapsedDesignHeight
        ).height
        let targetRadius = targetSize.height <= collapsedHeight + 0.5
            ? targetSize.height / 2
            : 26 * LauncherView.scale

        layer.masksToBounds = true
        layer.cornerCurve = .continuous
        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              abs(layer.cornerRadius - targetRadius) > 0.1
        else {
            layer.cornerRadius = targetRadius
            return
        }

        let animation = CABasicAnimation(keyPath: "cornerRadius")
        animation.fromValue = layer.presentation()?.cornerRadius ?? layer.cornerRadius
        animation.toValue = targetRadius
        animation.duration = LauncherMotion.resizeDuration
        animation.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.20, 0.80, 0.20, 1
        )
        layer.cornerRadius = targetRadius
        layer.add(animation, forKey: "riff.launcher.cornerRadius")
    }

    private func restoreSearchFocusIfNeeded(_ searchWasFocused: Bool) {
        guard searchWasFocused, !(panel.firstResponder is NSTextView) else { return }
        requestSearchFocus()
    }

    private func animateContentScale(
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        keepsFinalState: Bool
    ) {
        guard let layer = panel.contentView?.layer else { return }
        // AppKit resets a view-backed layer to a bottom-left anchor during
        // layout. Re-center it immediately before every visibility transform
        // so both window edges move by the same amount.
        LauncherMotion.centerTransformAnchor(of: layer)
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timingFunction
        animation.isRemovedOnCompletion = !keepsFinalState
        if keepsFinalState {
            animation.fillMode = .forwards
        }
        layer.add(animation, forKey: "riff.launcher.visibility")
    }

    private func animatePresentationSpring() {
        guard let layer = panel.contentView?.layer else { return }
        LauncherMotion.centerTransformAnchor(of: layer)
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [
            LauncherMotion.presentationScale,
            LauncherMotion.presentationOvershootScale,
            LauncherMotion.presentationReboundScale,
            1
        ]
        animation.keyTimes = [0, 0.58, 0.82, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(controlPoints: 0.16, 0.82, 0.24, 1),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        animation.duration = LauncherMotion.presentationDuration
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "riff.launcher.visibility")
    }

    private func requestSearchFocus() {
        guard panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .riffFocusLauncherSearch, object: panel)
        DiagnosticLogger.shared.log(
            "launcher",
            "focus requested key=\(self.panel.isKeyWindow) responder=\(String(describing: self.panel.firstResponder.map { type(of: $0) }))"
        )
    }

    func restoreSearchFocusAfterActivation() {
        requestSearchFocus()
    }

    private func openSettings() {
        dismiss()
        showSettings()
    }
}

@MainActor
final class NotePanelController: MaterialPanelController {
    private let model: NoteModel
    private let completion: NoteCompletionModel
    private var keyMonitor: Any?
    private var textChangeObserver: NSObjectProtocol?
    private var selectionChangeObserver: NSObjectProtocol?
    private weak var editorTextView: NSTextView?

    init(model: NoteModel, settings: SettingsStore) {
        self.model = model
        completion = NoteCompletionModel(settings: settings)
        super.init(size: NoteView.windowSize, level: .floating)
        install(NoteView(
            model: model,
            completion: completion,
            close: { [weak panel] in panel?.orderOut(nil) }
        ))

        completion.onAcceptRequested = { [weak self] in
            self?.acceptCompletion()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            guard let textView = self.focusedEditorTextView() else {
                self.completion.cancel()
                return event
            }

            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting(.capsLock)
            if event.keyCode == 48, modifiers.isEmpty {
                // Tab belongs to the system input method while it is composing.
                guard !textView.hasMarkedText() else { return event }
                return self.acceptCompletion(in: textView) ? nil : event
            }

            if event.keyCode == 53 { self.completion.cancel() }
            return event
        }

        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let textView = notification.object as? NSTextView else { return }
            Task { @MainActor [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scheduleCompletion(from: textView)
            }
        }

        selectionChangeObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let textView = notification.object as? NSTextView else { return }
            Task { @MainActor [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scheduleCompletion(from: textView)
            }
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let textChangeObserver { NotificationCenter.default.removeObserver(textChangeObserver) }
        if let selectionChangeObserver { NotificationCenter.default.removeObserver(selectionChangeObserver) }
    }

    func show() {
        completion.cancel()
        showCentered()
    }

    func toggle() {
        if panel.isVisible {
            completion.cancel()
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    private func scheduleCompletion(from textView: NSTextView) {
        guard textView.window === panel else { return }
        guard textView.delegate is NativeTextViewCoordinator else {
            completion.cancel()
            return
        }
        editorTextView = textView
        guard panel.isVisible,
              panel.isKeyWindow,
              !textView.hasMarkedText() else {
            completion.cancel()
            return
        }
        let context = NoteCompletionContext.make(
            text: textView.string,
            selectedRange: textView.selectedRange(),
            documentID: model.selectedNoteID
        )
        if completion.advanceIfMatching(context) { return }
        completion.schedule(context)
    }

    private func focusedEditorTextView() -> NSTextView? {
        if let firstResponder = panel.firstResponder as? NSTextView,
           firstResponder.delegate is NativeTextViewCoordinator {
            editorTextView = firstResponder
            return firstResponder
        }
        return nil
    }

    private func acceptCompletion() {
        guard let textView = focusedEditorTextView()
                ?? (editorTextView?.window === panel ? editorTextView : nil) else { return }
        panel.makeFirstResponder(textView)
        _ = acceptCompletion(in: textView)
    }

    @discardableResult
    private func acceptCompletion(in textView: NSTextView) -> Bool {
        guard !textView.hasMarkedText(),
              let suggestion = completion.suggestion(
                matching: textView.string,
                selectedRange: textView.selectedRange(),
                documentID: model.selectedNoteID
              ) else { return false }
        textView.insertText(suggestion, replacementRange: textView.selectedRange())
        completion.cancel()
        return true
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
        ))

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

    func showCurrent() {
        DiagnosticLogger.shared.log(
            "translation",
            "panel.showCurrent loading=\(self.model.isLoading) sourceLength=\(self.model.source.count) resultLength=\(self.model.result.count)"
        )
        showCentered()
    }

    private func closeIfPointerIsOutside() {
        guard panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        panel.orderOut(nil)
    }
}

@MainActor
final class SettingsPanelController: MaterialPanelController {
    private var monitor: Any?

    init(
        settings: SettingsStore,
        shortcuts: ShortcutStore,
        experienceMetrics: ExperienceMetricsStore
    ) {
        super.init(size: NSSize(width: 560, height: 540), level: .floating)
        install(SettingsView(
            settings: settings,
            shortcuts: shortcuts,
            experienceMetrics: experienceMetrics,
            close: { [weak panel] in panel?.orderOut(nil) }
        ))

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
