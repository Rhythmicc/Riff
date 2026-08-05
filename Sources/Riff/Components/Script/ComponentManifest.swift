import Foundation

enum ComponentManifestError: LocalizedError {
    case unsupportedSchema(Int)
    case invalidID(String)
    case invalidVersion(String)
    case invalidExecutable(String)
    case emptyName
    case emptyKeywords
    case invalidTimeout(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "不支持的组件规范版本：\(version)"
        case .invalidID(let id):
            return "组件 id 必须是反向域名格式：\(id)"
        case .invalidVersion(let version):
            return "组件版本必须是 x.y.z 格式：\(version)"
        case .invalidExecutable(let executable):
            return "可执行文件路径无效：\(executable)"
        case .emptyName:
            return "组件缺少名称"
        case .emptyKeywords:
            return "组件至少需要一个启动器关键词"
        case .invalidTimeout(let timeout):
            return "超时时间必须在 100–60000ms：\(timeout)"
        }
    }
}

/// Third-party component manifest. Schema version 1.
struct ComponentManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var name: String
    var version: String
    var author: String
    var icon: String?
    var keywords: [String]
    var executable: String
    var permissions: Set<ComponentPermission>
    var timeoutMs: Int
    var surfaces: Set<ComponentSurface>

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case name
        case version
        case author
        case icon
        case keywords
        case executable
        case permissions
        case timeoutMs = "timeout_ms"
        case surfaces
    }

    var descriptor: ComponentDescriptor {
        ComponentDescriptor(
            id: id,
            name: name,
            version: version,
            author: author,
            keywords: keywords,
            surfaces: surfaces,
            permissions: permissions,
            icon: ComponentIcon(systemName: icon ?? "square.grid.2x2"),
            isSystemEssential: false
        )
    }

    static func validate(_ manifest: ComponentManifest) throws {
        guard manifest.schemaVersion == 1 else {
            throw ComponentManifestError.unsupportedSchema(manifest.schemaVersion)
        }
        let idPattern = #"^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$"#
        guard manifest.id.range(of: idPattern, options: .regularExpression) != nil else {
            throw ComponentManifestError.invalidID(manifest.id)
        }
        let versionPattern = #"^\d+\.\d+\.\d+$"#
        guard manifest.version.range(of: versionPattern, options: .regularExpression) != nil else {
            throw ComponentManifestError.invalidVersion(manifest.version)
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComponentManifestError.emptyName
        }
        guard !manifest.keywords.isEmpty else {
            throw ComponentManifestError.emptyKeywords
        }
        guard (100...60_000).contains(manifest.timeoutMs) else {
            throw ComponentManifestError.invalidTimeout(manifest.timeoutMs)
        }
        let pathComponents = manifest.executable.split(separator: "/").map(String.init)
        guard !manifest.executable.isEmpty,
              !manifest.executable.hasPrefix("/"),
              !pathComponents.contains(".."),
              !pathComponents.contains("~") else {
            throw ComponentManifestError.invalidExecutable(manifest.executable)
        }
    }

    /// Resolves the executable URL inside a component directory and verifies
    /// that it stays within that directory.
    func resolvedExecutableURL(in directory: URL) throws -> URL {
        try Self.validate(self)
        let root = directory.standardizedFileURL
        let candidate = directory
            .appendingPathComponent(executable)
            .standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw ComponentManifestError.invalidExecutable(executable)
        }
        return candidate
    }
}
