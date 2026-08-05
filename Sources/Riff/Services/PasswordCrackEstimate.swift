import Foundation

/// Estimates how long a uniformly random Riff password would take to crack
/// with an offline brute-force attack. Riff passwords are drawn uniformly from
/// the configured alphabet, so the estimate depends only on the request
/// (length and character groups), not on the generated value.
enum PasswordCrackEstimate {
    /// A realistic high-end offline brute-force rate (GPU cluster, hashcat).
    static let guessesPerSecond: Double = 10_000_000_000
    static let secondsPerYear: Double = 31_557_600
    static let universeAgeYears: Double = 13_800_000_000

    static func entropyBits(for request: PasswordRequest) -> Double {
        let alphabetSize = Double(
            PasswordGenerator.alphabetSize(includeSymbols: request.includeSymbols)
        )
        return Double(request.length) * log2(alphabetSize)
    }

    /// Average brute-force time: half of the full keyspace at the assumed rate.
    static func averageSeconds(toCrack request: PasswordRequest) -> Double {
        pow(2, entropyBits(for: request)) / 2 / guessesPerSecond
    }

    static func localizedSummary(for request: PasswordRequest) -> String {
        let bits = entropyBits(for: request)
        let seconds = averageSeconds(toCrack: request)
        return "约 \(Int(bits.rounded())) 位熵 · 按每秒 100 亿次离线猜测，暴力破解约需 \(localizedDuration(seconds))"
    }

    static func localizedDuration(_ seconds: Double) -> String {
        if seconds < 1 { return "不到 1 秒" }
        if seconds < 60 { return "约 \(Int(seconds.rounded())) 秒" }
        if seconds < 3_600 { return "约 \(Int((seconds / 60).rounded())) 分钟" }
        if seconds < 86_400 { return "约 \(Int((seconds / 3_600).rounded())) 小时" }
        if seconds < secondsPerYear { return "约 \(Int((seconds / 86_400).rounded())) 天" }

        let years = seconds / secondsPerYear
        if years < 10_000 { return "约 \(Int(years.rounded())) 年" }
        if years < 100_000_000 { return "约 \(trimmed(years / 10_000)) 万年" }
        if years < universeAgeYears { return "约 \(trimmed(years / 100_000_000)) 亿年" }

        let multiplier = years / universeAgeYears
        if multiplier >= 100_000_000 {
            return "约宇宙年龄的 \(trimmed(multiplier / 100_000_000)) 亿倍"
        }
        if multiplier >= 10_000 {
            return "约宇宙年龄的 \(trimmed(multiplier / 10_000)) 万倍"
        }
        return "约宇宙年龄的 \(trimmed(multiplier)) 倍"
    }

    private static func trimmed(_ value: Double) -> String {
        if value >= 100 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}
