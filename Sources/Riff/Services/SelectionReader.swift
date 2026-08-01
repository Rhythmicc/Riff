import AppKit
import ApplicationServices
import Foundation

enum SelectionReader {
    private static let launchPromptKey = "accessibility.didPromptAutomatically"

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        guard !isAccessibilityTrusted else { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestAccessibilityPermissionOnLaunch() -> Bool {
        guard !isAccessibilityTrusted else { return true }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: launchPromptKey) == nil,
           defaults.bool(forKey: "hasCompletedFirstLaunch") {
            // Existing installations already went through the old startup prompt flow.
            defaults.set(true, forKey: launchPromptKey)
            return false
        }
        guard !defaults.bool(forKey: launchPromptKey) else { return false }
        defaults.set(true, forKey: launchPromptKey)
        return requestAccessibilityPermission()
    }

    static func selectedText(promptForPermission: Bool = false) -> String? {
        let trusted = isAccessibilityTrusted
        let sourceApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        DiagnosticLogger.shared.log("selection", "begin trusted=\(trusted) prompt=\(promptForPermission)")
        if !trusted {
            guard promptForPermission, requestAccessibilityPermission() else {
                DiagnosticLogger.shared.log("selection", "aborted: accessibility is not trusted")
                return nil
            }
        }

        waitForShortcutModifiersToClear()

        // Native Copy is the highest-fidelity representation of a selection.
        // Browsers frequently flatten DOM paragraphs in AXSelectedText, while
        // their plain-text pasteboard representation preserves block breaks.
        if let sourceApplicationPID,
           let copied = selectedTextByCopying(applicationPID: sourceApplicationPID) {
            DiagnosticLogger.shared.log(
                "selection",
                "success strategy=copy length=\(copied.count) lines=\(copied.components(separatedBy: .newlines).count)"
            )
            return copied
        }

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusedStatus == .success, let focused else {
            DiagnosticLogger.shared.log("selection", "focused element failed status=\(focusedStatus.rawValue)")
            return nil
        }

        var element = unsafeBitCast(focused, to: AXUIElement.self)
        for level in 0..<8 {
            logRole(of: element, level: level)
            if let text = selectedText(from: element, level: level) {
                DiagnosticLogger.shared.log("selection", "success level=\(level) length=\(text.count)")
                return text
            }

            var parent: CFTypeRef?
            let parentStatus = AXUIElementCopyAttributeValue(
                element,
                kAXParentAttribute as CFString,
                &parent
            )
            guard parentStatus == .success, let parent else {
                DiagnosticLogger.shared.log("selection", "parent traversal stopped level=\(level) status=\(parentStatus.rawValue)")
                break
            }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        DiagnosticLogger.shared.log("selection", "no selected text found")
        return nil
    }

    private static func selectedText(from element: AXUIElement, level: Int) -> String? {
        var selected: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selected
        )
        if selectedStatus == .success,
           let text = selected as? String,
           let normalized = normalizedSelection(text) {
            return normalized
        }

        var selectedRange: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )
        guard rangeStatus == .success, let selectedRange else {
            DiagnosticLogger.shared.log(
                "selection",
                "level=\(level) selectedStatus=\(selectedStatus.rawValue) rangeStatus=\(rangeStatus.rawValue)"
            )
            return nil
        }

        var rangedText: CFTypeRef?
        let rangedStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            selectedRange,
            &rangedText
        )
        if rangedStatus == .success,
           let text = rangedText as? String,
           let normalized = normalizedSelection(text) {
            return normalized
        }

        if let text = selectedTextFromValue(element: element, selectedRange: selectedRange, level: level) {
            return text
        }

        DiagnosticLogger.shared.log(
            "selection",
            "level=\(level) selectedStatus=\(selectedStatus.rawValue) rangedStatus=\(rangedStatus.rawValue) rangedLength=\((rangedText as? String)?.count ?? -1)"
        )
        return nil
    }

    private static func selectedTextFromValue(
        element: AXUIElement,
        selectedRange: CFTypeRef,
        level: Int
    ) -> String? {
        guard CFGetTypeID(selectedRange) == AXValueGetTypeID() else { return nil }
        let rangeValue = unsafeBitCast(selectedRange, to: AXValue.self)
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length > 0 else {
            DiagnosticLogger.shared.log(
                "selection",
                "level=\(level) selected range length=0"
            )
            return nil
        }

        var value: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )
        guard valueStatus == .success, let fullText = value as? String else {
            DiagnosticLogger.shared.log(
                "selection",
                "level=\(level) full value unavailable status=\(valueStatus.rawValue) rangeLength=\(range.length)"
            )
            return nil
        }

        let nsText = fullText as NSString
        guard range.location >= 0,
              range.length > 0,
              range.location + range.length <= nsText.length else {
            DiagnosticLogger.shared.log(
                "selection",
                "level=\(level) invalid range location=\(range.location) length=\(range.length) valueLength=\(nsText.length)"
            )
            return nil
        }
        let normalized = normalizedSelection(
            nsText.substring(with: NSRange(location: range.location, length: range.length))
        )
        if let normalized {
            DiagnosticLogger.shared.log(
                "selection",
                "level=\(level) recovered from value rangeLength=\(range.length) valueLength=\(nsText.length)"
            )
            return normalized
        }
        return nil
    }

    private static func selectedTextByCopying(applicationPID: pid_t?) -> String? {
        guard isAccessibilityTrusted else { return nil }
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                if let data = item.data(forType: type) { values[type] = data }
            }
        } ?? []
        let marker = "riff-selection-\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        let markerChangeCount = pasteboard.changeCount

        if let applicationPID, performCopyMenuAction(applicationPID: applicationPID),
           let copied = waitForCopiedText(
               from: pasteboard,
               marker: marker,
               markerChangeCount: markerChangeCount,
               timeout: 0.32
           ) {
            restorePasteboard(snapshot, to: pasteboard)
            DiagnosticLogger.shared.log("selection", "menu copy fallback success length=\(copied.count)")
            return copied
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let copyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let copyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            restorePasteboard(snapshot, to: pasteboard)
            return nil
        }
        commandDown.flags = .maskCommand
        copyDown.flags = .maskCommand
        copyUp.flags = .maskCommand
        commandUp.flags = []
        commandDown.post(tap: .cghidEventTap)
        copyDown.post(tap: .cghidEventTap)
        copyUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)

        let copied = waitForCopiedText(
            from: pasteboard,
            marker: marker,
            markerChangeCount: markerChangeCount,
            timeout: 0.32
        )
        restorePasteboard(snapshot, to: pasteboard)

        guard let copied else {
            DiagnosticLogger.shared.log("selection", "copy fallback failed")
            return nil
        }
        DiagnosticLogger.shared.log("selection", "copy fallback success length=\(copied.count)")
        return copied
    }

    private static func performCopyMenuAction(applicationPID: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(applicationPID)
        var menuBarValue: CFTypeRef?
        let menuBarStatus = AXUIElementCopyAttributeValue(
            application,
            kAXMenuBarAttribute as CFString,
            &menuBarValue
        )
        guard menuBarStatus == .success, let menuBarValue else {
            DiagnosticLogger.shared.log("selection", "copy menu unavailable status=\(menuBarStatus.rawValue)")
            return false
        }
        let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
        guard let copyItem = findCopyMenuItem(in: menuBar, depth: 0) else {
            DiagnosticLogger.shared.log("selection", "copy menu item not found")
            return false
        }
        let status = AXUIElementPerformAction(copyItem, kAXPressAction as CFString)
        DiagnosticLogger.shared.log("selection", "copy menu press status=\(status.rawValue)")
        return status == .success
    }

    private static func findCopyMenuItem(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 7 else { return nil }
        if attributeString(kAXRoleAttribute, from: element) == (kAXMenuItemRole as String),
           attributeString(kAXMenuItemCmdCharAttribute, from: element)?.lowercased() == "c" {
            let modifiers = attributeNumber(kAXMenuItemCmdModifiersAttribute, from: element)?.uint32Value ?? 0
            let enabled = attributeNumber(kAXEnabledAttribute, from: element)?.boolValue ?? true
            // A value of zero means Command with no additional modifiers.
            if modifiers == 0, enabled { return element }
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        for child in children {
            if let match = findCopyMenuItem(in: child, depth: depth + 1) { return match }
        }
        return nil
    }

    private static func attributeString(_ name: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func attributeNumber(_ name: String, from element: AXUIElement) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? NSNumber
    }

    private static func waitForCopiedText(
        from pasteboard: NSPasteboard,
        marker: String,
        markerChangeCount: Int,
        timeout: TimeInterval
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while pasteboard.changeCount == markerChangeCount, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard pasteboard.changeCount != markerChangeCount else { return nil }
        guard let copied = pasteboard.string(forType: .string),
              copied != marker else { return nil }
        return normalizedSelection(copied)
    }

    static func normalizedSelection(_ text: String) -> String? {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalizedNewlines.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func waitForShortcutModifiersToClear() {
        let deadline = Date().addingTimeInterval(0.35)
        let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        var waited = false
        while !CGEventSource.flagsState(.combinedSessionState)
            .intersection(relevantFlags)
            .isEmpty,
              Date() < deadline {
            waited = true
            Thread.sleep(forTimeInterval: 0.01)
        }
        if waited {
            let remaining = CGEventSource.flagsState(.combinedSessionState).intersection(relevantFlags)
            DiagnosticLogger.shared.log("selection", "waited for modifiers remainingFlags=\(remaining.rawValue)")
        }
    }

    private static func restorePasteboard(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        let items = snapshot.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private static func logRole(of element: AXUIElement, level: Int) {
        var role: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        DiagnosticLogger.shared.log(
            "selection",
            "level=\(level) role=\((role as? String) ?? "unknown") roleStatus=\(status.rawValue)"
        )
    }
}
