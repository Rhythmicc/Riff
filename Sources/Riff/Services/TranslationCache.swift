import CryptoKit
import Foundation

actor TranslationCache {
    static let shared = TranslationCache()

    private struct Entry: Codable {
        let result: String
        var lastAccessedAt: Date
    }

    private let fileURL: URL
    private let maximumEntryCount: Int
    private let lifetime: TimeInterval
    private var entries: [String: Entry]

    init(
        fileURL: URL? = nil,
        maximumEntryCount: Int = 200,
        lifetime: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.rhythmicc.Riff", isDirectory: true)
            .appendingPathComponent("translation-cache.json")
        self.maximumEntryCount = maximumEntryCount
        self.lifetime = lifetime

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    static func key(
        source: String,
        targetLanguage: TranslationLanguage,
        provider: AIProvider,
        model: String
    ) -> String {
        let payload = [
            "translation-prompt-v2-markdown-paragraphs",
            provider.rawValue,
            model,
            targetLanguage.rawValue,
            source
        ].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func value(forKey key: String) -> String? {
        guard var entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.lastAccessedAt) <= lifetime else {
            entries.removeValue(forKey: key)
            persist()
            return nil
        }
        entry.lastAccessedAt = Date()
        entries[key] = entry
        return entry.result
    }

    func insert(_ result: String, forKey key: String) {
        entries[key] = Entry(result: result, lastAccessedAt: Date())
        removeExpiredEntries()
        if entries.count > maximumEntryCount {
            let overflow = entries.count - maximumEntryCount
            let oldestKeys = entries
                .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
                .prefix(overflow)
                .map(\.key)
            for key in oldestKeys { entries.removeValue(forKey: key) }
        }
        persist()
    }

    private func removeExpiredEntries() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        entries = entries.filter { $0.value.lastAccessedAt >= cutoff }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DiagnosticLogger.shared.log(
                "translation-cache",
                "persist failed type=\(String(describing: type(of: error)))"
            )
        }
    }
}
