import AppKit

@main
enum RiffMain {
    static func main() {
        DiagnosticLogger.shared.startSession()
        DiagnosticLogger.shared.log(
            "app",
            "main entered debug=\(_isDebugAssertConfiguration()) executable=\(Bundle.main.executablePath ?? "unknown")"
        )
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
