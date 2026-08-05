import XCTest
@testable import Riff

final class ComponentManifestTests: XCTestCase {
    private func validManifest() -> ComponentManifest {
        ComponentManifest(
            schemaVersion: 1,
            id: "dev.example.weather",
            name: "天气",
            version: "1.0.0",
            author: "Example",
            icon: nil,
            keywords: ["天气", "weather"],
            executable: "bin/run",
            permissions: [.network],
            timeoutMs: 5_000,
            surfaces: [.launcher]
        )
    }

    func testValidManifestPassesValidation() throws {
        let manifest = validManifest()
        XCTAssertNoThrow(try ComponentManifest.validate(manifest))
    }

    func testRejectsUnsupportedSchema() {
        var manifest = validManifest()
        manifest.schemaVersion = 2
        XCTAssertThrowsError(try ComponentManifest.validate(manifest)) { error in
            guard case ComponentManifestError.unsupportedSchema(2) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsInvalidIDs() {
        for id in ["weather", "dev..example", "dev.example.", "dev example", "dev.example.1bad"] {
            var manifest = validManifest()
            manifest.id = id
            XCTAssertThrowsError(try ComponentManifest.validate(manifest), "id: \(id)")
        }
    }

    func testRejectsInvalidVersion() {
        for version in ["1.0", "v1.0.0", "1.0.0-beta", "1.0.0.0"] {
            var manifest = validManifest()
            manifest.version = version
            XCTAssertThrowsError(try ComponentManifest.validate(manifest), "version: \(version)")
        }
    }

    func testRejectsUnsafeExecutables() {
        for executable in ["/bin/sh", "../bin/run", "~/bin/run", "bin/../../run", ""] {
            var manifest = validManifest()
            manifest.executable = executable
            XCTAssertThrowsError(
                try ComponentManifest.validate(manifest),
                "executable: \(executable)"
            )
        }
    }

    func testRejectsEmptyKeywordsAndBadTimeout() {
        var manifest = validManifest()
        manifest.keywords = []
        XCTAssertThrowsError(try ComponentManifest.validate(manifest))

        manifest = validManifest()
        manifest.timeoutMs = 10
        XCTAssertThrowsError(try ComponentManifest.validate(manifest))

        manifest = validManifest()
        manifest.timeoutMs = 90_000
        XCTAssertThrowsError(try ComponentManifest.validate(manifest))
    }

    func testResolvedExecutableStaysInsideDirectory() throws {
        let manifest = validManifest()
        let directory = URL(fileURLWithPath: "/tmp/riff-components/weather")
        let resolved = try manifest.resolvedExecutableURL(in: directory)

        XCTAssertEqual(resolved.path, "/tmp/riff-components/weather/bin/run")
    }
}
