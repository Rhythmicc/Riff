import Foundation

enum RiffPaths {
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Riff", isDirectory: true)
    }
}

enum RiffMigration {
    static let currentBundleIdentifier = "dev.rhythmicc.Riff"
    static let legacyBundleIdentifier = ["dev", "rhythmicc", "Personal", "Launcher"]
        .joined(separator: ".")

    private static let legacySupportDirectoryName = ["Personal", "Launcher"].joined()
    private static let defaultsMigrationKey = "migration.riffBranding.v1"

    static func prepare(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        migrateDefaults(defaults: defaults)
        KeychainStore.migrateLegacyItems(accounts: AIProvider.allCases.map(\.rawValue))

        do {
            let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try migrateApplicationSupport(in: root, fileManager: fileManager)
        } catch {
            DiagnosticLogger.shared.log(
                "migration",
                "application support migration failed type=\(String(describing: type(of: error)))"
            )
        }
    }

    static func migrateDefaults(
        defaults: UserDefaults,
        legacyValues: [String: Any]? = nil
    ) {
        guard !defaults.bool(forKey: defaultsMigrationKey) else { return }
        let values = legacyValues
            ?? UserDefaults.standard.persistentDomain(forName: legacyBundleIdentifier)
            ?? [:]
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: defaultsMigrationKey)
    }

    static func migrateApplicationSupport(
        in root: URL,
        fileManager: FileManager = .default
    ) throws {
        let legacyDirectory = root.appendingPathComponent(legacySupportDirectoryName, isDirectory: true)
        let riffDirectory = root.appendingPathComponent("Riff", isDirectory: true)

        guard fileManager.fileExists(atPath: legacyDirectory.path) else {
            try fileManager.createDirectory(
                at: riffDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return
        }
        guard !fileManager.fileExists(atPath: riffDirectory.path) else { return }

        try fileManager.moveItem(at: legacyDirectory, to: riffDirectory)
    }
}
