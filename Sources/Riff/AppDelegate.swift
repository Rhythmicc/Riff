import AppKit
import Carbon
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var launcherController: LauncherPanelController!
    private var noteController: NotePanelController!
    private var translationController: TranslationPanelController!
    private var settingsController: SettingsPanelController!
    private var noteModel: NoteModel!
    private var translationModel: TranslationModel!
    private var hotKeys: [GlobalHotKey] = []
    private var doubleShiftHotKey: DoubleShiftHotKey?
    private var shortcutMonitor: GlobalShortcutMonitor?

    private let settings = SettingsStore()
    private let shortcuts = ShortcutStore()
    private let clipboard = ClipboardStore()
    private let systemOperationExecutor = SystemOperationExecutor()
    private let experienceMetrics = ExperienceMetricsStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard claimSingleRunningInstance() else { return }

        DiagnosticLogger.shared.log(
            "app",
            "didFinishLaunching debug=\(_isDebugAssertConfiguration()) axTrusted=\(SelectionReader.isAccessibilityTrusted)"
        )
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()

        let model = AppModel(
            clipboard: clipboard,
            settings: settings,
            experienceMetrics: experienceMetrics
        )
        noteModel = NoteModel()
        translationModel = TranslationModel(settings: settings)

        noteController = NotePanelController(model: noteModel, settings: settings)
        model.onOpenNote = { [weak self] in self?.openNoteFromLauncher() }
        model.onOpenTranslation = { [weak self] in self?.openTranslationFromLauncher() }
        model.onPerformSystemOperation = { [weak self] operation in
            DispatchQueue.main.async {
                self?.systemOperationExecutor.perform(operation)
            }
        }
        settingsController = SettingsPanelController(
            settings: settings,
            shortcuts: shortcuts,
            experienceMetrics: experienceMetrics
        )
        translationController = TranslationPanelController(
            model: translationModel,
            settings: settings,
            openSettings: { [weak self] in self?.settingsController.show() }
        )
        launcherController = LauncherPanelController(
            model: model,
            showNote: { [weak self] in self?.openNoteFromLauncher() },
            showSettings: { [weak self] in self?.settingsController.show() },
            experienceMetrics: experienceMetrics
        )

        configureStatusItem()
        shortcuts.onChange = { [weak self] in self?.configureHotKeys() }
        SelectionReader.requestAccessibilityPermissionOnLaunch()
        configureHotKeys()

        if !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
            launcherController.show(mode: .apps)
        }
    }

    /// Launch Services normally keeps an application single-instance, but a
    /// development build can be started directly while an installed copy is
    /// already running. Both processes would then register the same global
    /// shortcuts and present visually overlapping panels. Yield to the older
    /// instance before installing any monitors or UI.
    private func claimSingleRunningInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID && !$0.isTerminated })
        else {
            return true
        }

        existing.activate(options: [])
        NSApp.terminate(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        noteModel?.flush()
        clipboard.flush()
        experienceMetrics.flush()
    }

    private func configureHotKeys() {
        DiagnosticLogger.shared.log("shortcut", "configure begin axTrusted=\(SelectionReader.isAccessibilityTrusted)")
        shortcutMonitor = nil
        doubleShiftHotKey = nil
        hotKeys.removeAll()
        shortcuts.clearRegistrationError()

        var registrations: [GlobalShortcutMonitor.Registration] = []

        for action in ShortcutAction.allCases {
            let binding = shortcuts.binding(for: action)
            DiagnosticLogger.shared.log(
                "shortcut",
                "binding action=\(action.rawValue) kind=\(binding.kind.rawValue) keyCode=\(binding.keyCode) modifiers=\(binding.modifiers)"
            )
            if binding.kind == .disabled {
                continue
            } else if binding.kind == .doubleShift {
                doubleShiftHotKey = DoubleShiftHotKey { [weak self] in
                    self?.perform(action)
                }
            } else {
                registrations.append(.init(action: action, binding: binding))
            }
        }

        let monitor = GlobalShortcutMonitor(registrations: registrations) { [weak self] action in
            self?.perform(action)
        }
        if monitor.isActive {
            shortcutMonitor = monitor
            DiagnosticLogger.shared.log("shortcut", "using CGEvent tap registrations=\(registrations.count)")
        } else {
            DiagnosticLogger.shared.log("shortcut", "event tap unavailable; using Carbon fallback")
            for registration in registrations {
                let hotKey = GlobalHotKey(
                    keyCode: registration.binding.keyCode,
                    modifiers: registration.binding.modifiers,
                    identifier: registration.action.hotKeyIdentifier
                ) { [weak self] in
                    self?.perform(registration.action)
                }
                hotKeys.append(hotKey)
                if !hotKey.isRegistered {
                    shortcuts.reportRegistrationFailure(for: registration.action)
                }
            }
        }

        rebuildStatusMenu()
        DiagnosticLogger.shared.log("shortcut", "configure end")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Riff")

        statusItem = item
        rebuildStatusMenu()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DiagnosticLogger.shared.log(
            "app",
            "didBecomeActive axTrusted=\(SelectionReader.isAccessibilityTrusted) tapActive=\(self.shortcutMonitor?.isActive == true)"
        )
        if SelectionReader.isAccessibilityTrusted, shortcutMonitor?.isActive != true {
            configureHotKeys()
        }
        if launcherController?.panel.isVisible == true {
            launcherController.restoreSearchFocusAfterActivation()
        }
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(menuItem("应用启动器（\(shortcuts.binding(for: .launcher).displayName)）", action: #selector(openLauncher), shortcut: "", modifiers: []))
        menu.addItem(menuItem("剪贴板历史（\(shortcuts.binding(for: .clipboard).displayName)）", action: #selector(openClipboard), shortcut: "", modifiers: []))
        menu.addItem(menuItem("翻译选中文本（\(shortcuts.binding(for: .translation).displayName)）", action: #selector(openTranslation), shortcut: "", modifiers: []))
        menu.addItem(menuItem("置顶便笺（\(shortcuts.binding(for: .note).displayName)）", action: #selector(toggleNote), shortcut: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(menuItem("设置…", action: #selector(openSettings), shortcut: ",", modifiers: .command))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出", action: #selector(quit), shortcut: "q", modifiers: .command))
#if DEBUG
        menu.addItem(.separator())
        menu.addItem(menuItem("调试：打开日志", action: #selector(openDebugLog), shortcut: "", modifiers: []))
        menu.addItem(menuItem("调试：复制诊断摘要", action: #selector(copyDebugSummary), shortcut: "", modifiers: []))
#endif
        statusItem.menu = menu
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Riff")
        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(editingItem("退出 Riff", action: #selector(NSApplication.terminate(_:)), key: "q"))
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(editingItem("撤销", action: Selector(("undo:")), key: "z"))
        editMenu.addItem(editingItem("重做", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(editingItem("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(editingItem("复制", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(editingItem("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(editingItem("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        let closeWindowItem = NSMenuItem(
            title: "关闭窗口",
            action: #selector(closeCurrentWindow),
            keyEquivalent: "w"
        )
        closeWindowItem.keyEquivalentModifierMask = .command
        closeWindowItem.target = self
        windowMenu.addItem(closeWindowItem)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    private func editingItem(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        shortcut: String,
        modifiers: NSEvent.ModifierFlags = .option
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func showTranslation() {
        DiagnosticLogger.shared.log("translation", "showTranslation begin")
        // The user explicitly invoked translation, so this is the appropriate
        // time to request missing Accessibility access. Startup remains quiet.
        let selected = SelectionReader.selectedText(promptForPermission: true) ?? ""
        clipboard.ignoreCurrentPasteboardChange()
        DiagnosticLogger.shared.log("translation", "selection finished length=\(selected.count)")
        if selected.isEmpty, translationModel.hasSession {
            DiagnosticLogger.shared.log("translation", "empty selection; restoring existing session")
            translationController.showCurrent()
            return
        }
        translationController.show(text: selected)
        DiagnosticLogger.shared.log("translation", "panel show requested")
    }

    private func openTranslationFromLauncher() {
        if translationModel.hasSession {
            translationController.showCurrent()
            return
        }
        // Let the launcher resign key status first so Accessibility reads the
        // previously focused app rather than Riff's own search field.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            self?.showTranslation()
        }
    }

    private func openNoteFromLauncher() {
        // The launcher is intentionally a nonactivating panel. Remove it before
        // presenting the editor so the note window becomes the sole key-window
        // candidate and the system input method can bind to its NSTextView.
        launcherController?.dismiss()
        noteController.show()
    }

    private func perform(_ action: ShortcutAction) {
        let settingsIsKey = settingsController?.panel.isKeyWindow == true
        DiagnosticLogger.shared.log("shortcut", "perform action=\(action.rawValue) settingsIsKey=\(settingsIsKey)")
        guard !settingsIsKey else {
            DiagnosticLogger.shared.log("shortcut", "action blocked while settings is key")
            return
        }
        switch action {
        case .launcher: launcherController.toggle(mode: .apps)
        case .clipboard: launcherController.show(mode: .clipboard)
        case .translation: showTranslation()
        case .note: noteController.toggle()
        }
    }

    @objc private func openLauncher() { launcherController.show(mode: .apps) }
    @objc private func openClipboard() { launcherController.show(mode: .clipboard) }
    @objc private func openTranslation() { showTranslation() }
    @objc private func toggleNote() { noteController.toggle() }
    @objc private func openSettings() { settingsController.show() }
    @objc private func closeCurrentWindow() {
        if NSApp.keyWindow === launcherController?.panel {
            launcherController.dismiss()
        } else {
            NSApp.keyWindow?.orderOut(nil)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

#if DEBUG
    @objc private func openDebugLog() {
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLogger.shared.fileURL])
    }

    @objc private func copyDebugSummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticLogger.shared.recentSummary(), forType: .string)
    }
#endif
}
