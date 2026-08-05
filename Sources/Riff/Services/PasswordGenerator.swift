import Foundation
import Security

struct PasswordRequest: Equatable, Sendable {
    static let defaultLength = 16
    static let allowedLengths = 8...128
    fileprivate static let commands = [
        "随机密码", "生成密码", "密码生成器", "生成随机密码",
        "random password", "generate password", "password generator", "pwgen",
    ]
    fileprivate static let noSymbolKeywords = [
        "无符号", "不含符号", "不带符号", "字母数字",
        "nosymbols", "no symbols", "nosymbol", "alphanumeric", "alnum",
    ]

    let length: Int
    let includeSymbols: Bool

    init(length: Int = defaultLength, includeSymbols: Bool = true) {
        self.length = min(max(length, Self.allowedLengths.lowerBound), Self.allowedLengths.upperBound)
        self.includeSymbols = includeSymbols
    }

    static func parse(_ query: String) -> PasswordRequest? {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        guard commands.contains(where: { command in
            normalized == command
                || normalized.hasPrefix(command + " ")
                || (normalized.hasPrefix(command)
                    && normalized.dropFirst(command.count).contains(where: \.isNumber))
        }) else { return nil }

        let requestedLength = normalized
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .first
        return PasswordRequest(
            length: requestedLength ?? defaultLength,
            includeSymbols: !containsNoSymbolRule(normalized)
        )
    }

    /// Extracts the length and character rules from arbitrary launcher text,
    /// used when the user activates the password quick action without typing
    /// a full command.
    static func parseOptions(from query: String) -> PasswordRequest {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let requestedLength = normalized
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .first
        return PasswordRequest(
            length: requestedLength ?? defaultLength,
            includeSymbols: !containsNoSymbolRule(normalized)
        )
    }

    private static func containsNoSymbolRule(_ normalized: String) -> Bool {
        noSymbolKeywords.contains { normalized.contains($0) }
    }

    /// The part of a launcher query that is meaningful inside the password
    /// component, for example "32 无符号" from "随机密码 32 无符号" or "24"
    /// from "密码 24". Partial keyword matches like "pas" yield an empty
    /// parameter text.
    static func parameterText(from query: String) -> String {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        for command in commands where normalized.hasPrefix(command) {
            let suffix = normalized
                .dropFirst(command.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix
        }

        let tokens = normalized.split(whereSeparator: { $0.isWhitespace })
        let kept = tokens.filter { token in
            token.contains(where: \.isNumber)
                || noSymbolKeywords.contains { token.contains($0) }
        }
        return kept.joined(separator: " ")
    }

    /// Whether text typed inside the password component should be treated as
    /// parameters (a length, a rule keyword, or both) instead of a new search.
    static func isParameterText(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.contains(where: \.isNumber) { return true }
        return noSymbolKeywords.contains { normalized.contains($0) }
    }
}

struct GeneratedPassword: Equatable, Sendable {
    let value: String
    let length: Int
}

enum PasswordGeneratorError: LocalizedError {
    case secureRandomUnavailable

    var errorDescription: String? {
        "系统安全随机数生成器暂时不可用"
    }
}

enum PasswordGenerator {
    private static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    private static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    private static let digits = Array("23456789")
    private static let symbols = Array("!@#$%^&*()-_=+[]{};:,.?")
    static let allowedCharacters = Set(lowercase + uppercase + digits + symbols)

    static func alphabetSize(includeSymbols: Bool) -> Int {
        let base = lowercase.count + uppercase.count + digits.count
        return includeSymbols ? base + symbols.count : base
    }

    static func generate(_ request: PasswordRequest) throws -> GeneratedPassword {
        var groups = [lowercase, uppercase, digits]
        if request.includeSymbols {
            groups.append(symbols)
        }
        var characters = try groups.map { group in
            group[try secureRandomIndex(upperBound: group.count)]
        }
        let combined = groups.flatMap { $0 }

        while characters.count < request.length {
            characters.append(combined[try secureRandomIndex(upperBound: combined.count)])
        }
        try secureShuffle(&characters)
        return GeneratedPassword(value: String(characters), length: request.length)
    }

    private static func secureShuffle(_ values: inout [Character]) throws {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let replacement = try secureRandomIndex(upperBound: index + 1)
            values.swapAt(index, replacement)
        }
    }

    /// Rejection sampling avoids the modulo bias introduced by `byte % count`.
    private static func secureRandomIndex(upperBound: Int) throws -> Int {
        precondition(upperBound > 0 && upperBound <= 256)
        let acceptanceLimit = 256 - (256 % upperBound)
        while true {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(
                kSecRandomDefault,
                MemoryLayout<UInt8>.size,
                &byte
            ) == errSecSuccess else {
                throw PasswordGeneratorError.secureRandomUnavailable
            }
            if Int(byte) < acceptanceLimit { return Int(byte) % upperBound }
        }
    }
}
