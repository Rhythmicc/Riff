import XCTest
@testable import Riff

final class ScriptComponentHostTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riff-host-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeScript(_ body: String) throws -> URL {
        let url = root.appendingPathComponent("run-\(UUID().uuidString)")
        try "#!/bin/zsh\n\(body)".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    func testQueryDecodesResults() async throws {
        let script = try makeScript("""
        read -r line
        print '{"results":[{"id":"1","title":"北京 25°C","subtitle":"晴","icon":"sun.max","copy":"25°C","actions":[{"id":"copy","title":"复制","kind":"copy"},{"id":"visit","title":"查看","kind":"open","url":"https://example.com"}]}],"isComplete":true}'
        """)
        let host = ScriptComponentHost(executableURL: script, timeout: 2)

        let results = try await host.query("北京 天气")

        XCTAssertTrue(results.isComplete)
        XCTAssertEqual(results.items.count, 1)
        XCTAssertEqual(results.items[0].title, "北京 25°C")
        XCTAssertEqual(results.items[0].subtitle, "晴")
        guard case .copy(let text) = results.items[0].actions[0] else {
            return XCTFail("expected copy action")
        }
        XCTAssertEqual(text, "25°C")
        guard case .openURL(let url) = results.items[0].actions[1] else {
            return XCTFail("expected open action")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }

    func testActionReturnsPayload() async throws {
        let script = try makeScript("""
        read -r line
        print '{"result":"ok","payload":"已复制"}'
        """)
        let host = ScriptComponentHost(executableURL: script, timeout: 2)

        let payload = try await host.perform(actionID: "copy", itemID: "1")

        XCTAssertEqual(payload, "已复制")
    }

    func testTimeoutTerminatesSlowComponent() async throws {
        let script = try makeScript("""
        sleep 5
        print '{"results":[]}'
        """)
        let host = ScriptComponentHost(executableURL: script, timeout: 0.3)

        do {
            _ = try await host.query("天气")
            XCTFail("expected timeout")
        } catch {
            guard case ScriptComponentHostError.timeout = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testInvalidResponseThrows() async throws {
        let script = try makeScript("print 'this is not json'")
        let host = ScriptComponentHost(executableURL: script, timeout: 2)

        do {
            _ = try await host.query("天气")
            XCTFail("expected invalid response")
        } catch {
            guard case ScriptComponentHostError.invalidResponse = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
