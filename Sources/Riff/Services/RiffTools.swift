import Foundation

enum RiffToolError: LocalizedError {
    case invalidArguments(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let detail):
            return "工具参数无效：\(detail)"
        case .unavailable(let detail):
            return detail
        }
    }
}

/// A local Riff capability exposed to the AI as an OpenAI-compatible function
/// tool. Tools are executed on this Mac and their result is fed back to the
/// model, so queries like “北京天气” or “100 美元是多少人民币” are answered
/// with real local data instead of model guesses.
struct RiffTool: Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]
    let execute: @Sendable ([String: Any]) async throws -> String

    var openAISchema: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }

    private static func objectSchema(
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required
        ]
    }

    static var weather: RiffTool {
        RiffTool(
            name: "weather_forecast",
            description: "查询指定城市当前的天气和未来三天的最高/最低温与降水概率。参数 city 为城市名称，例如“北京”“上海”“巴黎”。",
            parameters: objectSchema(
                properties: ["city": ["type": "string", "description": "城市名称"]],
                required: ["city"]
            ),
            execute: { arguments in
                guard let city = arguments["city"] as? String,
                      !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RiffToolError.invalidArguments("缺少 city 参数")
                }
                return try await WeatherService.currentAndForecast(city: city)
            }
        )
    }

    static var currency: RiffTool {
        RiffTool(
            name: "currency_convert",
            description: "使用欧洲央行（ECB）参考汇率换算货币。参数 amount 为金额，from 为源货币三字母代码，to 为目标货币三字母代码，例如 100、USD、CNY。",
            parameters: objectSchema(
                properties: [
                    "amount": ["type": "number", "description": "金额"],
                    "from": ["type": "string", "description": "源货币代码，如 USD"],
                    "to": ["type": "string", "description": "目标货币代码，如 CNY"]
                ],
                required: ["amount", "from", "to"]
            ),
            execute: { arguments in
                let amount = arguments["amount"] as? Double
                    ?? (arguments["amount"] as? NSNumber)?.doubleValue
                    ?? Double(arguments["amount"] as? String ?? "")
                guard let amount,
                      let from = arguments["from"] as? String,
                      let to = arguments["to"] as? String else {
                    throw RiffToolError.invalidArguments("需要 amount、from、to 参数")
                }
                let converter = CurrencyConverter()
                return try await converter.convert(
                    CurrencyQuery(
                        amount: amount,
                        source: from.uppercased(),
                        target: to.uppercased()
                    )
                )
            }
        )
    }

    static var calculator: RiffTool {
        RiffTool(
            name: "calculate",
            description: "计算数学表达式，支持 + - * / ^ 和括号，例如 12 * (8 + 2) 或 2^10。",
            parameters: objectSchema(
                properties: ["expression": ["type": "string", "description": "数学表达式"]],
                required: ["expression"]
            ),
            execute: { arguments in
                guard let expression = arguments["expression"] as? String else {
                    throw RiffToolError.invalidArguments("缺少 expression 参数")
                }
                let value = try Calculator.evaluate(expression)
                return Calculator.formatted(value)
            }
        )
    }

    static var password: RiffTool {
        RiffTool(
            name: "generate_password",
            description: "生成安全随机密码。参数 length 为长度（8–128，默认 16），include_symbols 表示是否包含特殊符号（默认 true）。",
            parameters: objectSchema(
                properties: [
                    "length": ["type": "integer", "description": "密码长度"],
                    "include_symbols": ["type": "boolean", "description": "是否包含特殊符号"]
                ],
                required: []
            ),
            execute: { arguments in
                let length = arguments["length"] as? Int
                    ?? (arguments["length"] as? NSNumber)?.intValue
                    ?? PasswordRequest.defaultLength
                let includeSymbols = (arguments["include_symbols"] as? Bool) ?? true
                let request = PasswordRequest(length: length, includeSymbols: includeSymbols)
                let generated = try PasswordGenerator.generate(request)
                let bits = PasswordCrackEstimate.entropyBits(for: request)
                return "密码：\(generated.value)（\(generated.length) 位，约 \(Int(bits.rounded())) 位熵）"
            }
        )
    }

    static var unicode: RiffTool {
        RiffTool(
            name: "unicode_search",
            description: "搜索 Unicode 或 Emoji 字符。参数 term 为关键词（如 arrow、heart、箭头、笑脸），emoji 为 true 时只搜索 Emoji。",
            parameters: objectSchema(
                properties: [
                    "term": ["type": "string", "description": "搜索关键词"],
                    "emoji": ["type": "boolean", "description": "是否只搜索 Emoji"]
                ],
                required: ["term"]
            ),
            execute: { arguments in
                guard let term = arguments["term"] as? String, !term.isEmpty else {
                    throw RiffToolError.invalidArguments("缺少 term 参数")
                }
                let emoji = (arguments["emoji"] as? Bool) ?? false
                let query = UnicodeSearchQuery(
                    scope: emoji ? .emoji : .unicode,
                    term: term
                )
                let results = await UnicodeSearchIndex.shared.search(query, limit: 8)
                guard !results.isEmpty else { return "没有找到匹配的字符" }
                return results.map { "\($0.symbol) \($0.name)（\($0.codePointLabel)）" }
                    .joined(separator: "；")
            }
        )
    }

    static var currentTime: RiffTool {
        RiffTool(
            name: "current_time",
            description: "获取当前日期时间。参数 timezone 可选，为 IANA 时区名（如 Asia/Shanghai、Europe/Madrid），不填返回本机时区时间。",
            parameters: objectSchema(
                properties: ["timezone": ["type": "string", "description": "IANA 时区名"]],
                required: []
            ),
            execute: { arguments in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                if let id = arguments["timezone"] as? String,
                   !id.isEmpty,
                   let timezone = TimeZone(identifier: id) {
                    formatter.timeZone = timezone
                    return "\(id) 当前时间：\(formatter.string(from: Date()))"
                }
                formatter.timeZone = .current
                return "当前时间：\(formatter.string(from: Date()))（\(TimeZone.current.identifier)）"
            }
        )
    }

    static var timezoneConvert: RiffTool {
        RiffTool(
            name: "timezone_convert",
            description: "把某个时间换算到另一个时区。参数 time 格式为 yyyy-MM-dd HH:mm（24 小时制），from_timezone 和 to_timezone 为 IANA 时区名。",
            parameters: objectSchema(
                properties: [
                    "time": ["type": "string", "description": "时间，格式 yyyy-MM-dd HH:mm"],
                    "from_timezone": ["type": "string", "description": "来源 IANA 时区名"],
                    "to_timezone": ["type": "string", "description": "目标 IANA 时区名"]
                ],
                required: ["time", "from_timezone", "to_timezone"]
            ),
            execute: { arguments in
                guard let time = arguments["time"] as? String,
                      let from = arguments["from_timezone"] as? String,
                      let to = arguments["to_timezone"] as? String,
                      let fromTimezone = TimeZone(identifier: from),
                      let toTimezone = TimeZone(identifier: to) else {
                    throw RiffToolError.invalidArguments("需要 time、from_timezone、to_timezone 参数")
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = fromTimezone
                guard let date = formatter.date(from: time) else {
                    throw RiffToolError.invalidArguments("时间格式应为 yyyy-MM-dd HH:mm")
                }
                formatter.timeZone = toTimezone
                return "\(time)（\(from)）→ \(to)：\(formatter.string(from: date))"
            }
        )
    }

    static var fetchURL: RiffTool {
        RiffTool(
            name: "fetch_url",
            description: "抓取网页正文并返回可读文本（去除 HTML 标签，最长约 12000 字），适合让 AI 总结链接内容。参数 url 为完整网址（http/https）。",
            parameters: objectSchema(
                properties: ["url": ["type": "string", "description": "完整网址"]],
                required: ["url"]
            ),
            execute: { arguments in
                guard let urlString = arguments["url"] as? String,
                      let url = URL(string: urlString),
                      url.scheme == "http" || url.scheme == "https" else {
                    throw RiffToolError.invalidArguments("url 必须是完整的 http/https 网址")
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw RiffToolError.unavailable("无法访问该网页（HTTP \(status)）")
                }
                let html = String(decoding: data, as: UTF8.self)
                let cleaned = plainText(fromHTML: html)
                guard !cleaned.isEmpty else {
                    throw RiffToolError.unavailable("网页没有可读文本")
                }
                if cleaned.count <= 12_000 { return cleaned }
                return String(cleaned.prefix(12_000)) + "\n…（内容过长，已截断）"
            }
        )
    }

    static func webSearch(apiKey: String) -> RiffTool {
        RiffTool(
            name: "web_search",
            description: "用 Tavily 搜索互联网，返回适合 AI 阅读的摘要和带标题、链接的结果列表。参数 query 为搜索词，max_results 可选（1–10，默认 5），topic 可选（general/news），time_range 可选（day/week/month/year），include_answer 表示是否附带 AI 摘要（默认 true）。",
            parameters: objectSchema(
                properties: [
                    "query": ["type": "string", "description": "搜索词"],
                    "max_results": ["type": "integer", "description": "返回结果数，1–10"],
                    "topic": ["type": "string", "description": "general 或 news"],
                    "time_range": ["type": "string", "description": "day/week/month/year"],
                    "include_answer": ["type": "boolean", "description": "是否附带 AI 摘要"]
                ],
                required: ["query"]
            ),
            execute: { arguments in
                guard let query = arguments["query"] as? String,
                      !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RiffToolError.invalidArguments("缺少 query 参数")
                }
                let maxResults = min(
                    max((arguments["max_results"] as? Int)
                        ?? (arguments["max_results"] as? NSNumber)?.intValue
                        ?? 5, 1),
                    10
                )
                let topic = arguments["topic"] as? String ?? "general"
                let timeRange = arguments["time_range"] as? String
                let includeAnswer = (arguments["include_answer"] as? Bool) ?? true
                let request = TavilySearch.makeRequest(
                    query: query,
                    maxResults: maxResults,
                    topic: topic,
                    timeRange: timeRange,
                    includeAnswer: includeAnswer,
                    apiKey: apiKey
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw RiffToolError.unavailable("Tavily 返回了无效响应")
                }
                guard (200..<300).contains(http.statusCode) else {
                    let detail = TavilySearch.errorDetail(from: data)
                    throw RiffToolError.unavailable(detail ?? "Tavily 搜索失败（HTTP \(http.statusCode)）")
                }
                return try TavilySearch.formatResponse(data: data)
            }
        )
    }

    static var selectedText: RiffTool {
        RiffTool(
            name: "selected_text",
            description: "读取当前前台应用中用户选中的文本，适合让 AI 总结、翻译或解释选中内容。无需参数；需要辅助功能权限。",
            parameters: objectSchema(properties: [:], required: []),
            execute: { _ in
                let text = await MainActor.run { SelectionReader.selectedText() }
                guard let text, !text.isEmpty else {
                    throw RiffToolError.unavailable("没有读取到选中的文本（需要辅助功能权限）")
                }
                return String(text.prefix(20_000))
            }
        )
    }

    static func noteRead(noteModel: NoteModel) -> RiffTool {
        RiffTool(
            name: "note_read",
            description: "读取 Riff 便笺。参数 note_title 可选：给定时返回该标题便笺的内容，否则返回便笺列表（标题和摘要）。",
            parameters: objectSchema(
                properties: ["note_title": ["type": "string", "description": "便笺标题"]],
                required: []
            ),
            execute: { arguments in
                try await MainActor.run {
                    if let title = arguments["note_title"] as? String, !title.isEmpty {
                        guard let note = noteModel.notes.first(where: { $0.title == title }) else {
                            throw RiffToolError.unavailable("没有找到标题为“\(title)”的便笺")
                        }
                        return String(note.text.prefix(20_000))
                    }
                    let list = noteModel.notes
                        .map { "\($0.title)：\($0.summary)" }
                        .joined(separator: "\n")
                    return list.isEmpty ? "还没有便笺" : list
                }
            }
        )
    }

    static func noteAppend(noteModel: NoteModel) -> RiffTool {
        RiffTool(
            name: "note_append",
            description: "把内容追加到指定标题的便笺末尾；便笺不存在则新建。参数 note_title 为便笺标题，content 为要追加的内容。",
            parameters: objectSchema(
                properties: [
                    "note_title": ["type": "string", "description": "便笺标题"],
                    "content": ["type": "string", "description": "要追加的内容"]
                ],
                required: ["note_title", "content"]
            ),
            execute: { arguments in
                try await MainActor.run {
                    guard let title = (arguments["note_title"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        !title.isEmpty,
                        let content = arguments["content"] as? String,
                        !content.isEmpty else {
                        throw RiffToolError.invalidArguments("需要 note_title 和 content 参数")
                    }
                    if let note = noteModel.notes.first(where: { $0.title == title }) {
                        noteModel.select(note)
                        let current = noteModel.selectedText
                        noteModel.updateSelectedText(current + "\n\n" + content)
                    } else {
                        noteModel.createNote()
                        noteModel.updateSelectedTitle(title)
                        noteModel.updateSelectedText(content)
                    }
                    return "已追加到便笺“\(title)”"
                }
            }
        )
    }

    static func translate(provider: AIProvider, model: String, apiKey: String) -> RiffTool {
        RiffTool(
            name: "translate_text",
            description: "把文本翻译成指定语言。参数 text 为原文，target_language 为目标语言名称（例如“简体中文”“English”）。",
            parameters: objectSchema(
                properties: [
                    "text": ["type": "string", "description": "待翻译文本"],
                    "target_language": ["type": "string", "description": "目标语言名称"]
                ],
                required: ["text", "target_language"]
            ),
            execute: { arguments in
                guard let text = arguments["text"] as? String,
                      let target = arguments["target_language"] as? String else {
                    throw RiffToolError.invalidArguments("需要 text 和 target_language 参数")
                }
                return try await AIService().translate(
                    text: text,
                    targetLanguage: target,
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    onDelta: { _ in }
                )
            }
        )
    }
}

/// Thin client for Tavily's /search endpoint. Uses the caller's API key when
/// available and falls back to the free keyless mode otherwise.
enum TavilySearch {
    static let endpoint = URL(string: "https://api.tavily.com/search")!

    struct Result: Decodable {
        let title: String
        let url: String
        let content: String?
    }

    private struct Response: Decodable {
        let answer: String?
        let results: [Result]?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let error: String?
        }
        let detail: Detail?
    }

    static func makeRequest(
        query: String,
        maxResults: Int,
        topic: String,
        timeRange: String?,
        includeAnswer: Bool,
        apiKey: String
    ) -> URLRequest {
        var body: [String: Any] = [
            "query": query,
            "max_results": maxResults,
            "search_depth": "basic",
            "topic": topic,
            "include_answer": includeAnswer
        ]
        if let timeRange {
            body["time_range"] = timeRange
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            request.setValue("keyless", forHTTPHeaderField: "X-Tavily-Access-Mode")
        } else {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func formatResponse(data: Data) throws -> String {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw RiffToolError.unavailable("Tavily 响应无法解析")
        }
        let results = response.results ?? []
        guard !results.isEmpty else {
            return "没有找到相关结果"
        }

        var lines: [String] = []
        if let answer = response.answer, !answer.isEmpty {
            lines.append("AI 摘要：\(answer)")
            lines.append("")
        }
        for (index, result) in results.prefix(10).enumerated() {
            let content = (result.content ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(index + 1). \(result.title)")
            lines.append(result.url)
            if !content.isEmpty {
                lines.append(String(content.prefix(600)))
            }
            lines.append("")
        }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        if joined.count <= 12_000 { return joined }
        return String(joined.prefix(12_000)) + "\n…（结果过长，已截断）"
    }

    static func errorDetail(from data: Data) -> String? {
        guard let detail = try? JSONDecoder().decode(ErrorResponse.self, from: data),
              let message = detail.detail?.error,
              !message.isEmpty else { return nil }
        return message
    }
}

enum RiffToolRegistry {
    static func tools(
        provider: AIProvider,
        model: String,
        apiKey: String,
        tavilyAPIKey: String = "",
        noteModel: NoteModel? = nil
    ) -> [RiffTool] {
        var tools: [RiffTool] = [
            .weather,
            .currency,
            .calculator,
            .password,
            .unicode,
            .translate(provider: provider, model: model, apiKey: apiKey),
            .currentTime,
            .timezoneConvert,
            .fetchURL,
            .webSearch(apiKey: tavilyAPIKey),
            .selectedText
        ]
        if let noteModel {
            tools.append(.noteRead(noteModel: noteModel))
            tools.append(.noteAppend(noteModel: noteModel))
        }
        return tools
    }

    static func tool(named name: String) -> RiffTool? {
        tools(provider: .deepSeek, model: "", apiKey: "").first { $0.name == name }
    }
}

extension RiffTool {
    /// Strips scripts, styles, tags, and common entities from an HTML page.
    static func plainText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: #"(?s)<(script|style)[^>]*>.*?</\1>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Weather lookup through Open-Meteo (no API key required).
enum WeatherService {
    struct Location: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    static func currentAndForecast(city: String) async throws -> String {
        let location = try await geocode(city)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
            ),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]
        guard let url = components.url else {
            throw RiffToolError.unavailable("天气服务地址无效")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RiffToolError.unavailable("暂时无法获取天气数据")
        }

        let current = json["current"] as? [String: Any] ?? [:]
        let daily = json["daily"] as? [String: Any] ?? [:]
        let currentTemperature = current["temperature_2m"] as? Double ?? 0
        let humidity = current["relative_humidity_2m"] as? Double ?? 0
        let wind = current["wind_speed_10m"] as? Double ?? 0
        let code = current["weather_code"] as? Int ?? 0

        var lines = [
            "\(location.name)当前天气：\(Int(currentTemperature.rounded()))°C，"
                + "\(describeWeatherCode(code))，湿度 \(Int(humidity.rounded()))%，"
                + "风速 \(Int(wind.rounded())) km/h"
        ]
        let days = daily["time"] as? [String] ?? []
        let maxTemps = daily["temperature_2m_max"] as? [Double] ?? []
        let minTemps = daily["temperature_2m_min"] as? [Double] ?? []
        let codes = daily["weather_code"] as? [Int] ?? []
        let precipitation = daily["precipitation_probability_max"] as? [Double] ?? []

        if !days.isEmpty {
            lines.append("未来三天：")
        }
        for index in days.indices {
            let date = days[index]
            let dayDescription = describeWeatherCode(index < codes.count ? codes[index] : 0)
            let maxText = index < maxTemps.count ? "\(Int(maxTemps[index].rounded()))" : "?"
            let minText = index < minTemps.count ? "\(Int(minTemps[index].rounded()))" : "?"
            let rainText = index < precipitation.count
                ? "降水概率 \(Int(precipitation[index].rounded()))%"
                : "降水概率未知"
            lines.append("\(date)：\(dayDescription)，\(minText)~\(maxText)°C，\(rainText)")
        }
        return lines.joined(separator: "\n")
    }

    private static func geocode(_ city: String) async throws -> Location {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else {
            throw RiffToolError.unavailable("天气服务地址无效")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let latitude = first["latitude"] as? Double,
              let longitude = first["longitude"] as? Double else {
            throw RiffToolError.unavailable("找不到城市“\(city)”")
        }
        return Location(
            name: first["name"] as? String ?? city,
            latitude: latitude,
            longitude: longitude
        )
    }

    static func describeWeatherCode(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1: return "基本晴朗"
        case 2: return "局部多云"
        case 3: return "阴"
        case 45, 48: return "有雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57, 66, 67: return "冻雨"
        case 61, 63, 65: return "有雨"
        case 71, 73, 75: return "有雪"
        case 77: return "霰"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return "天气未知"
        }
    }
}
