import Foundation

final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    let fileURL: URL
    private let queue = DispatchQueue(label: "dev.rhythmicc.Riff.diagnostics")
    private let timestampFormatter = ISO8601DateFormatter()

    private init() {
        let logsDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Logs/Riff", isDirectory: true)
        fileURL = logsDirectory.appendingPathComponent("debug.log")

#if DEBUG
        prepareLogFile()
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 2_000_000 {
            try? FileManager.default.removeItem(at: fileURL)
            prepareLogFile()
        }
#endif
    }

    func startSession() {
#if DEBUG
        let timestamp = timestampFormatter.string(from: Date())
        append(
            "\(timestamp) [session] ---------------- new debug session pid=\(ProcessInfo.processInfo.processIdentifier) ----------------\n"
        )
#endif
    }

    func log(_ category: String, _ message: @autoclosure @escaping () -> String) {
#if DEBUG
        let timestamp = timestampFormatter.string(from: Date())
        let resolved = message()
        queue.async { [self] in
            let line = "\(timestamp) [\(category)] \(resolved)\n"
            append(line)
        }
#endif
    }

#if DEBUG
    private func prepareLogFile() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
        } catch {
            fputs("Riff diagnostics: unable to create log file: \(error)\n", stderr)
        }
    }

    private func append(_ line: String) {
        prepareLogFile()
        guard let data = line.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            fputs("Riff diagnostics: unable to append log: \(error)\n", stderr)
        }
    }
#endif

    func recentSummary(maxLines: Int = 240) -> String {
#if DEBUG
        return queue.sync {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return "Riff debug log is empty."
            }
            return content.split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(maxLines)
                .joined(separator: "\n")
        }
#else
        return "Detailed diagnostics are disabled in this build."
#endif
    }
}
