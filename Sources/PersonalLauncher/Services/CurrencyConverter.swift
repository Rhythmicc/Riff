import Foundation

struct CurrencyQuery: Equatable {
    let amount: Double
    let source: String
    let target: String

    static func parse(_ input: String) -> CurrencyQuery? {
        let pattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]{3})\s+(?:(?:to|in|into|=|->|换成|兑换)\s*)?([A-Za-z]{3})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range), match.numberOfRanges == 4,
              let amountRange = Range(match.range(at: 1), in: input),
              let sourceRange = Range(match.range(at: 2), in: input),
              let targetRange = Range(match.range(at: 3), in: input),
              let amount = Double(input[amountRange]) else { return nil }
        return CurrencyQuery(
            amount: amount,
            source: input[sourceRange].uppercased(),
            target: input[targetRange].uppercased()
        )
    }
}

enum CurrencyError: LocalizedError {
    case unavailable
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "暂时无法获取 ECB 参考汇率"
        case .unsupported(let code): return "ECB 暂不提供 \(code) 的参考汇率"
        }
    }
}

actor CurrencyConverter {
    private var cachedRates: [String: Double] = [:]
    private var cacheDate: Date?
    private let feedURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!

    func convert(_ query: CurrencyQuery) async throws -> String {
        let rates = try await rates()
        guard let sourceRate = rates[query.source] else { throw CurrencyError.unsupported(query.source) }
        guard let targetRate = rates[query.target] else { throw CurrencyError.unsupported(query.target) }
        let value = query.amount / sourceRate * targetRate
        return "\(Calculator.formatted(value)) \(query.target)"
    }

    private func rates() async throws -> [String: Double] {
        if let cacheDate, Date().timeIntervalSince(cacheDate) < 21_600, !cachedRates.isEmpty {
            return cachedRates
        }

        let (data, response) = try await URLSession.shared.data(from: feedURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8) else { throw CurrencyError.unavailable }

        let pattern = #"currency=['\"]([A-Z]{3})['\"]\s+rate=['\"]([0-9.]+)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { throw CurrencyError.unavailable }
        let sourceRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var parsed: [String: Double] = ["EUR": 1]
        for match in regex.matches(in: xml, range: sourceRange) {
            guard let codeRange = Range(match.range(at: 1), in: xml),
                  let valueRange = Range(match.range(at: 2), in: xml),
                  let value = Double(xml[valueRange]) else { continue }
            parsed[String(xml[codeRange])] = value
        }
        guard parsed.count > 1 else { throw CurrencyError.unavailable }
        cachedRates = parsed
        cacheDate = Date()
        return parsed
    }
}
