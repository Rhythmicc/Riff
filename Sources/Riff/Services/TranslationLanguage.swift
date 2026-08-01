import Foundation
import NaturalLanguage

enum TranslationLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt"
    case italian = "it"
    case russian = "ru"
    case arabic = "ar"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        case .german: "德语"
        case .spanish: "西班牙语"
        case .portuguese: "葡萄牙语"
        case .italian: "意大利语"
        case .russian: "俄语"
        case .arabic: "阿拉伯语"
        }
    }

    var promptName: String {
        "\(title) (\(rawValue))"
    }

    func matches(_ language: NLLanguage) -> Bool {
        let detected = language.rawValue.lowercased()
        let configured = rawValue.lowercased()
        if configured.hasPrefix("zh"), detected.hasPrefix("zh") { return true }
        return detected == configured || detected.split(separator: "-").first == configured.split(separator: "-").first
    }

    static func fromStoredValue(_ value: String?) -> TranslationLanguage? {
        guard let value else { return nil }
        if let direct = TranslationLanguage(rawValue: value) { return direct }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { language in
            language.title.lowercased() == normalized || language.legacyNames.contains(normalized)
        }
    }

    static func defaultPriority(for nativeLanguage: TranslationLanguage) -> TranslationLanguage {
        nativeLanguage == .english ? .simplifiedChinese : .english
    }

    private var legacyNames: Set<String> {
        switch self {
        case .simplifiedChinese: ["中文", "简体中文", "simplified chinese", "chinese"]
        case .traditionalChinese: ["繁体中文", "繁體中文", "traditional chinese"]
        case .english: ["英文", "英语", "英語", "english"]
        case .japanese: ["日文", "日语", "日語", "japanese"]
        case .korean: ["韩文", "韩语", "韓語", "korean"]
        case .french: ["法语", "法語", "french"]
        case .german: ["德语", "德語", "german"]
        case .spanish: ["西班牙语", "西班牙語", "spanish"]
        case .portuguese: ["葡萄牙语", "葡萄牙語", "portuguese"]
        case .italian: ["意大利语", "意大利語", "italian"]
        case .russian: ["俄语", "俄語", "russian"]
        case .arabic: ["阿拉伯语", "阿拉伯語", "arabic"]
        }
    }
}

struct TranslationDirection: Equatable {
    let detectedLanguage: NLLanguage?
    let sourceIsNative: Bool
    let targetLanguage: TranslationLanguage
}

enum TranslationDirectionResolver {
    static func resolve(
        text: String,
        nativeLanguage: TranslationLanguage,
        priorityLanguage: TranslationLanguage
    ) -> TranslationDirection {
        let detected = detectLanguage(in: text)
        let sourceIsNative = detected.map(nativeLanguage.matches) ?? false
        return TranslationDirection(
            detectedLanguage: detected,
            sourceIsNative: sourceIsNative,
            targetLanguage: sourceIsNative ? priorityLanguage : nativeLanguage
        )
    }

    static func detectLanguage(in text: String) -> NLLanguage? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        if source.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return .japanese
        }
        if source.unicodeScalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) {
            return .korean
        }
        if source.unicodeScalars.contains(where: {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }) {
            return .simplifiedChinese
        }

        return NLLanguageRecognizer.dominantLanguage(for: source)
    }
}
