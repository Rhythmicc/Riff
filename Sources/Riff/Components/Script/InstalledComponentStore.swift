import Foundation

struct InstalledComponent: Identifiable, Equatable, Sendable {
    var id: String { manifest.id }
    var manifest: ComponentManifest
    var directoryURL: URL
    var executableURL: URL
}

enum InstalledComponentStoreError: LocalizedError {
    case manifestMissing
    case invalidManifest(String)
    case notFound(String)
    case unzipFailed
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "组件包中缺少 manifest.json"
        case .invalidManifest(let detail):
            return "组件清单无效：\(detail)"
        case .notFound(let id):
            return "未找到组件：\(id)"
        case .unzipFailed:
            return "无法解压组件包"
        case .copyFailed(let detail):
            return "无法安装组件：\(detail)"
        }
    }
}

/// Manages third-party component directories under
/// `~/Library/Application Support/Riff/Components/`.
final class InstalledComponentStore {
    let rootDirectory: URL

    init(
        rootDirectory: URL = RiffPaths.applicationSupportDirectory.appendingPathComponent(
            "Components",
            isDirectory: true
        )
    ) {
        self.rootDirectory = rootDirectory
    }

    private var trashDirectory: URL {
        rootDirectory.appendingPathComponent(".trash", isDirectory: true)
    }

    func loadInstalled() -> [InstalledComponent] {
        try? FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.compactMap { directory in
            guard directory.hasDirectoryPath else { return nil }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(ComponentManifest.self, from: data),
                  let executableURL = try? manifest.resolvedExecutableURL(in: directory),
                  FileManager.default.isExecutableFile(atPath: executableURL.path)
            else { return nil }
            return InstalledComponent(
                manifest: manifest,
                directoryURL: directory,
                executableURL: executableURL
            )
        }
    }

    /// Installs a component directory or a `.riffcomponent`/`.zip` archive.
    /// Replaces an existing component with the same id after backing it up.
    func install(from sourceURL: URL) throws -> InstalledComponent {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let workingDirectory: URL
        let isTemporary: Bool
        if sourceURL.pathExtension.lowercased() == "zip"
            || sourceURL.pathExtension.lowercased() == "riffcomponent" {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("riff-component-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            try Self.unzip(sourceURL, to: temporary)
            workingDirectory = temporary
            isTemporary = true
        } else {
            workingDirectory = sourceURL
            isTemporary = false
        }
        defer {
            if isTemporary {
                try? FileManager.default.removeItem(at: workingDirectory)
            }
        }

        let manifest = try Self.readManifest(in: workingDirectory)
        try ComponentManifest.validate(manifest)

        let destination = rootDirectory.appendingPathComponent(manifest.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try backup(id: manifest.id)
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: workingDirectory, to: destination)
        } catch {
            throw InstalledComponentStoreError.copyFailed(
                error.localizedDescription
            )
        }

        let executableURL = try manifest.resolvedExecutableURL(in: destination)
        if !FileManager.default.isExecutableFile(atPath: executableURL.path) {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path
            )
        }
        return InstalledComponent(
            manifest: manifest,
            directoryURL: destination,
            executableURL: executableURL
        )
    }

    func uninstall(id: String) throws {
        let destination = rootDirectory.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw InstalledComponentStoreError.notFound(id)
        }
        try backup(id: id)
    }

    private func backup(id: String) throws {
        let destination = rootDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(
            at: trashDirectory,
            withIntermediateDirectories: true
        )
        let timestamp = Int(Date().timeIntervalSince1970)
        let target = trashDirectory.appendingPathComponent("\(id)-\(timestamp)", isDirectory: true)
        try FileManager.default.moveItem(at: destination, to: target)
    }

    private static func readManifest(in directory: URL) throws -> ComponentManifest {
        let direct = directory.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: direct),
           let manifest = try? JSONDecoder().decode(ComponentManifest.self, from: data) {
            return manifest
        }
        // Accept archives whose root contains a single component directory.
        let subdirectories = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.hasDirectoryPath } ?? []
        for subdirectory in subdirectories {
            if let data = try? Data(contentsOf: subdirectory.appendingPathComponent("manifest.json")),
               let manifest = try? JSONDecoder().decode(ComponentManifest.self, from: data) {
                return manifest
            }
        }
        throw InstalledComponentStoreError.manifestMissing
    }

    private static func unzip(_ archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destination.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw InstalledComponentStoreError.unzipFailed
        }
        guard process.terminationStatus == 0 else {
            throw InstalledComponentStoreError.unzipFailed
        }
    }
}
