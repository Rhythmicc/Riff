import AppKit
import CoreGraphics
import Foundation

@MainActor
final class SystemOperationExecutor {
    func perform(_ operation: SystemOperation) {
        DiagnosticLogger.shared.log("system-operation", "perform operation=\(operation.rawValue)")

        switch operation {
        case .sleep:
            run("/usr/bin/pmset", arguments: ["sleepnow"])
        case .lockScreen:
            lockScreen()
        case .displaySleep:
            run("/usr/bin/pmset", arguments: ["displaysleepnow"])
        case .screenSaver:
            run(
                "/usr/bin/open",
                arguments: ["/System/Library/CoreServices/ScreenSaverEngine.app"]
            )
        }
    }

    private func lockScreen() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false)
        else {
            DiagnosticLogger.shared.log("system-operation", "lock failed: unable to create key event")
            return
        }

        let modifiers: CGEventFlags = [.maskCommand, .maskControl]
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func run(_ executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            DiagnosticLogger.shared.log(
                "system-operation",
                "command failed executable=\(executable) status=\(process.terminationStatus)"
            )
        }

        do {
            try process.run()
        } catch {
            DiagnosticLogger.shared.log(
                "system-operation",
                "command launch failed executable=\(executable) error=\(error.localizedDescription)"
            )
        }
    }
}
