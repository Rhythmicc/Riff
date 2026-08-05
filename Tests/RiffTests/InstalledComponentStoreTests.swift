import XCTest
@testable import Riff

final class InstalledComponentStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-installed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeComponentDirectory(
        id: String = "dev.example.weather",
        script: String = "print '{\"results\":[]}'"
    ) throws -> URL {
        let directory = root.appendingPathComponent("source-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manifest = ComponentManifest(
            schemaVersion: 1,
            id: id,
            name: "天气",
            version: "1.0.0",
            author: "Example",
            icon: nil,
            keywords: ["天气"],
            executable: "bin/run",
            permissions: [],
            timeoutMs: 2_000,
            surfaces: [.launcher]
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
        let scriptURL = directory.appendingPathComponent("bin/run")
        try """
        #!/bin/zsh
        read -r line
        \(script)
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return directory
    }

    private func makeStore() throws -> InstalledComponentStore {
        let storeRoot = root.appendingPathComponent("components", isDirectory: true)
        return InstalledComponentStore(rootDirectory: storeRoot)
    }

    func testInstallFromDirectoryAndReload() throws {
        let store = try makeStore()
        let source = try makeComponentDirectory()

        let installed = try store.install(from: source)

        XCTAssertEqual(installed.id, "dev.example.weather")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installed.executableURL.path))
        XCTAssertEqual(store.loadInstalled().map(\.id), ["dev.example.weather"])
    }

    func testInstallFromZipArchive() throws {
        let store = try makeStore()
        let source = try makeComponentDirectory(id: "dev.example.zipcomponent")
        let zipURL = root.appendingPathComponent("component.riffcomponent")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", source.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let installed = try store.install(from: zipURL)

        XCTAssertEqual(installed.id, "dev.example.zipcomponent")
        XCTAssertEqual(store.loadInstalled().count, 1)
    }

    func testUpdateBacksUpPreviousVersion() throws {
        let store = try makeStore()
        let first = try makeComponentDirectory(id: "dev.example.updatable")
        _ = try store.install(from: first)
        let second = try makeComponentDirectory(id: "dev.example.updatable")
        _ = try store.install(from: second)

        XCTAssertEqual(store.loadInstalled().count, 1)
        let trash = store.rootDirectory.appendingPathComponent(".trash", isDirectory: true)
        let backups = (try? FileManager.default.contentsOfDirectory(
            at: trash,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].lastPathComponent.hasPrefix("dev.example.updatable-"))
    }

    func testUninstallMovesComponentToTrash() throws {
        let store = try makeStore()
        _ = try store.install(from: try makeComponentDirectory())

        try store.uninstall(id: "dev.example.weather")

        XCTAssertTrue(store.loadInstalled().isEmpty)
        let trash = store.rootDirectory.appendingPathComponent(".trash", isDirectory: true)
        let backups = (try? FileManager.default.contentsOfDirectory(
            at: trash,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].lastPathComponent.hasPrefix("dev.example.weather-"))
    }

    func testDirectoryWithoutExecutableIsIgnored() throws {
        let store = try makeStore()
        let source = try makeComponentDirectory()
        let destination = store.rootDirectory
            .appendingPathComponent("dev.example.weather", isDirectory: true)
        try FileManager.default.createDirectory(
            at: store.rootDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: destination.appendingPathComponent("bin/run").path
        )

        XCTAssertTrue(store.loadInstalled().isEmpty)
    }
}
