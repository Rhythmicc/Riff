import XCTest
@testable import Riff

final class RiffToolTests: XCTestCase {
    func testRegistryExposesCoreToolsWithValidSchemas() {
        let tools = RiffToolRegistry.tools(provider: .deepSeek, model: "m", apiKey: "k")

        let names = Set(tools.map(\.name))
        XCTAssertTrue(
            names.isSuperset(of: [
                "weather_forecast", "currency_convert", "calculate",
                "generate_password", "unicode_search", "translate_text",
                "current_time", "timezone_convert", "fetch_url",
                "web_search", "selected_text"
            ])
        )
        for tool in tools {
            XCTAssertFalse(tool.description.isEmpty)
            XCTAssertTrue(JSONSerialization.isValidJSONObject(tool.parameters))
            XCTAssertTrue(JSONSerialization.isValidJSONObject(tool.openAISchema))
            XCTAssertEqual((tool.openAISchema["function"] as? [String: Any])?["name"] as? String, tool.name)
        }
    }

    func testCalculateToolExecutes() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "calculate"))

        let result = try await tool.execute(["expression": "2 + 3 * 4"])

        XCTAssertEqual(result, "14")
    }

    func testPasswordToolExecutesWithLengthAndRule() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "generate_password"))

        let result = try await tool.execute(["length": 24, "include_symbols": false])
        let value = result.split(separator: "（").first.map { String($0.dropFirst(3)) } ?? ""

        XCTAssertTrue(result.contains("24 位"))
        XCTAssertTrue(result.contains("位熵"))
        XCTAssertEqual(value.count, 24)
        XCTAssertFalse(value.contains(where: { "!@#$%^&*()-_=+[]{};:,.?".contains($0) }))
    }

    func testUnicodeToolSearchesSymbols() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "unicode_search"))

        let result = try await tool.execute(["term": "arrow"])

        XCTAssertTrue(result.contains("→"))
        XCTAssertTrue(result.contains("U+2192"))
    }

    func testCurrentTimeToolHonorsTimezone() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "current_time"))

        let result = try await tool.execute(["timezone": "Asia/Shanghai"])
        let prefix = "Asia/Shanghai 当前时间："

        XCTAssertTrue(result.hasPrefix(prefix))
        let stamp = String(result.dropFirst(prefix.count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertNotNil(formatter.date(from: stamp), "时间格式不正确: \(stamp)")
    }

    func testTimezoneConvertToolIsDeterministic() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "timezone_convert"))

        let result = try await tool.execute([
            "time": "2026-01-15 10:00",
            "from_timezone": "Asia/Shanghai",
            "to_timezone": "UTC"
        ])

        XCTAssertTrue(result.contains("2026-01-15 10:00（Asia/Shanghai）→ UTC：2026-01-15 02:00"))
    }

    func testTimezoneConvertToolRejectsBadInput() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "timezone_convert"))

        do {
            _ = try await tool.execute([
                "time": "not-a-time",
                "from_timezone": "Asia/Shanghai",
                "to_timezone": "UTC"
            ])
            XCTFail("应当拒绝非法时间")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("时间格式"))
        }
    }

    func testFetchURLToolRejectsNonHTTPURLs() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "fetch_url"))

        do {
            _ = try await tool.execute(["url": "file:///etc/passwd"])
            XCTFail("应当拒绝非 http/https 链接")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("http/https"))
        }
    }

    func testWebSearchToolRejectsEmptyQuery() async throws {
        let tool = try XCTUnwrap(RiffToolRegistry.tool(named: "web_search"))

        do {
            _ = try await tool.execute(["query": "   "])
            XCTFail("应当拒绝空搜索词")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("query"))
        }
    }

    func testTavilyRequestFallsBackToKeylessWithoutKey() {
        let request = TavilySearch.makeRequest(
            query: "北京天气",
            maxResults: 5,
            topic: "general",
            timeRange: nil,
            includeAnswer: true,
            apiKey: ""
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Tavily-Access-Mode"),
            "keyless"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotNil(request.httpBody)
    }

    func testTavilyRequestUsesBearerWithKey() {
        let request = TavilySearch.makeRequest(
            query: "latest AI news",
            maxResults: 3,
            topic: "news",
            timeRange: "week",
            includeAnswer: false,
            apiKey: "tvly-test-key"
        )

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer tvly-test-key"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Tavily-Access-Mode"))
        let body = request.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        XCTAssertEqual(body?["query"] as? String, "latest AI news")
        XCTAssertEqual(body?["max_results"] as? Int, 3)
        XCTAssertEqual(body?["topic"] as? String, "news")
        XCTAssertEqual(body?["time_range"] as? String, "week")
        XCTAssertEqual(body?["include_answer"] as? Bool, false)
    }

    func testTavilyFormatsResponse() throws {
        let json = """
        {
          "query": "test",
          "answer": "这是摘要",
          "results": [
            {
              "title": "示例标题",
              "url": "https://example.com/1",
              "content": "第一段内容"
            },
            {
              "title": "第二标题",
              "url": "https://example.com/2",
              "content": null
            }
          ]
        }
        """

        let text = try TavilySearch.formatResponse(data: Data(json.utf8))

        XCTAssertTrue(text.contains("AI 摘要：这是摘要"))
        XCTAssertTrue(text.contains("示例标题"))
        XCTAssertTrue(text.contains("https://example.com/1"))
        XCTAssertTrue(text.contains("第一段内容"))
        XCTAssertTrue(text.contains("第二标题"))
    }

    func testTavilyErrorDetailParsing() {
        let json = #"{"detail": {"error": "Unauthorized: missing or invalid API key."}}"#

        XCTAssertEqual(
            TavilySearch.errorDetail(from: Data(json.utf8)),
            "Unauthorized: missing or invalid API key."
        )
    }

    func testPlainTextStripsHTML() {
        let html = """
        <html><head><style>p { color: red }</style><script>alert('x')</script></head>
        <body><h1>标题</h1><p>第一段 &amp; 第二段</p></body></html>
        """

        let text = RiffTool.plainText(fromHTML: html)

        XCTAssertTrue(text.contains("标题"))
        XCTAssertTrue(text.contains("第一段 & 第二段"))
        XCTAssertFalse(text.contains("<"))
        XCTAssertFalse(text.contains("color: red"))
        XCTAssertFalse(text.contains("alert"))
    }

    @MainActor
    func testNoteToolsAppendAndRead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let noteModel = NoteModel(directory: directory)
        let tools = RiffToolRegistry.tools(
            provider: .deepSeek,
            model: "m",
            apiKey: "k",
            noteModel: noteModel
        )
        let append = try XCTUnwrap(tools.first { $0.name == "note_append" })
        let read = try XCTUnwrap(tools.first { $0.name == "note_read" })

        let appended = try await append.execute([
            "note_title": "测试便笺",
            "content": "第一行内容"
        ])
        XCTAssertTrue(appended.contains("测试便笺"))

        let content = try await read.execute(["note_title": "测试便笺"])
        XCTAssertTrue(content.contains("第一行内容"))

        let listing = try await read.execute([:])
        XCTAssertTrue(listing.contains("测试便笺"))
    }

    func testWeatherCodeDescriptionsCoverCommonCases() {
        XCTAssertEqual(WeatherService.describeWeatherCode(0), "晴")
        XCTAssertEqual(WeatherService.describeWeatherCode(61), "有雨")
        XCTAssertEqual(WeatherService.describeWeatherCode(95), "雷暴")
        XCTAssertEqual(WeatherService.describeWeatherCode(999), "天气未知")
    }
}
