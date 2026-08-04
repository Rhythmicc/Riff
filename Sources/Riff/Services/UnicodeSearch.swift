import Foundation

struct UnicodeSearchQuery: Equatable, Hashable, Sendable {
    enum Scope: Equatable, Hashable, Sendable {
        case unicode
        case emoji
    }

    let scope: Scope
    let term: String

    static func parse(_ input: String) -> UnicodeSearchQuery? {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = source.lowercased()
        guard !lowered.isEmpty else { return nil }

        if lowered.hasPrefix("u+") {
            return UnicodeSearchQuery(scope: .unicode, term: source)
        }

        let prefixes: [(String, Scope)] = [
            ("unicode", .unicode),
            ("字符", .unicode),
            ("符号", .unicode),
            ("字元", .unicode),
            ("記号", .unicode),
            ("文字", .unicode),
            ("문자", .unicode),
            ("기호", .unicode),
            ("caractere", .unicode),
            ("caractère", .unicode),
            ("symbole", .unicode),
            ("zeichen", .unicode),
            ("symbol", .unicode),
            ("caracter", .unicode),
            ("carácter", .unicode),
            ("simbolo", .unicode),
            ("símbolo", .unicode),
            ("carattere", .unicode),
            ("символ", .unicode),
            ("رمز", .unicode),
            ("emoji", .emoji),
            ("表情符号", .emoji),
            ("表情符號", .emoji),
            ("表情", .emoji),
            ("絵文字", .emoji),
            ("이모지", .emoji),
            ("эмодзи", .emoji),
            ("رموز تعبيرية", .emoji)
        ]

        for (prefix, scope) in prefixes {
            if lowered == prefix {
                return UnicodeSearchQuery(scope: scope, term: "")
            }
            guard lowered.hasPrefix(prefix) else { continue }
            let boundary = lowered.index(lowered.startIndex, offsetBy: prefix.count)
            guard boundary < lowered.endIndex,
                  lowered[boundary].isWhitespace || lowered[boundary] == ":" || lowered[boundary] == "：" else {
                continue
            }
            let term = source[boundary...]
                .drop { $0.isWhitespace || $0 == ":" || $0 == "：" }
            return UnicodeSearchQuery(scope: scope, term: String(term))
        }
        return nil
    }
}

struct UnicodeSymbol: Identifiable, Hashable, Sendable {
    let symbol: String
    let displayGlyph: String
    let name: String
    let codePointLabel: String
    let isEmoji: Bool

    var id: String { codePointLabel }
}

actor UnicodeSearchIndex {
    static let shared = UnicodeSearchIndex()

    private struct Entry: Sendable {
        let result: UnicodeSymbol
        let searchText: String
        let primaryValue: UInt32
        let popularity: Int
    }

    private var cachedEntries: [Entry]?
    private var cachedSearches: [SearchCacheKey: [UnicodeSymbol]] = [:]

    private struct SearchCacheKey: Hashable {
        let scope: UnicodeSearchQuery.Scope
        let term: String
        let nativeLanguage: TranslationLanguage
        let limit: Int
    }

    private struct RankedEntry {
        let entry: Entry
        let score: Int
    }

    func search(
        _ query: UnicodeSearchQuery,
        nativeLanguage: TranslationLanguage = .simplifiedChinese,
        limit: Int = 8
    ) -> [UnicodeSymbol] {
        let normalizedTerm = Self.normalizedSearchTerm(
            query.term,
            nativeLanguage: nativeLanguage
        )
        let cacheKey = SearchCacheKey(
            scope: query.scope,
            term: normalizedTerm,
            nativeLanguage: nativeLanguage,
            limit: limit
        )
        if let cached = cachedSearches[cacheKey] { return cached }
        if let direct = Self.directCodePointResult(query.term) {
            let result = query.scope == .emoji && !direct.isEmoji ? [] : [direct]
            cachedSearches[cacheKey] = result
            return result
        }

        let entries = loadEntries()
        if normalizedTerm.isEmpty {
            let defaults: [UInt32] = query.scope == .emoji
                ? [0x1F600, 0x1F602, 0x1F979, 0x1F60D, 0x1F914, 0x1F44D, 0x1F389, 0x2764]
                : [0x2192, 0x2190, 0x2191, 0x2193, 0x2713, 0x2715, 0x2022, 0x2026]
            let results = defaults.compactMap { value in
                entries.first { $0.primaryValue == value }?.result
            }
            cachedSearches[cacheKey] = results
            return results
        }

        let tokens = normalizedTerm.split(whereSeparator: \.isWhitespace).map(String.init)
        var matches: [RankedEntry] = []
        matches.reserveCapacity(limit)

        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return [] }
            if query.scope == .emoji && !entry.result.isEmoji { continue }
            guard let score = Self.score(
                term: normalizedTerm,
                tokens: tokens,
                candidate: entry.searchText
            ) else { continue }
            let candidate = RankedEntry(entry: entry, score: score + entry.popularity)
            if matches.count < limit {
                matches.append(candidate)
            } else if let worstIndex = Self.worstMatchIndex(in: matches),
                      Self.isBetter(candidate, than: matches[worstIndex]) {
                matches[worstIndex] = candidate
            }
        }

        matches.sort { Self.isBetter($0, than: $1) }
        let results = matches.prefix(limit).map(\.entry.result)
        if cachedSearches.count >= 64 {
            cachedSearches.removeAll(keepingCapacity: true)
        }
        cachedSearches[cacheKey] = results
        return results
    }

    private static func isBetter(_ lhs: RankedEntry, than rhs: RankedEntry) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.entry.result.name != rhs.entry.result.name {
            return lhs.entry.result.name < rhs.entry.result.name
        }
        return lhs.entry.primaryValue < rhs.entry.primaryValue
    }

    private static func worstMatchIndex(in matches: [RankedEntry]) -> Int? {
        guard !matches.isEmpty else { return nil }
        var worst = 0
        for index in matches.indices.dropFirst() where isBetter(matches[worst], than: matches[index]) {
            worst = index
        }
        return worst
    }

    private func loadEntries() -> [Entry] {
        if let cachedEntries { return cachedEntries }

        let popularValues: [UInt32] = [
            0x2192, 0x2190, 0x2191, 0x2193, 0x2194,
            0x2713, 0x2714, 0x2715, 0x2716, 0x2022, 0x2026,
            0x1F600, 0x1F602, 0x1F979, 0x1F60D, 0x1F914,
            0x1F44D, 0x1F389, 0x2764, 0x26A0
        ]
        let popularity = Dictionary(
            uniqueKeysWithValues: popularValues.enumerated().map { index, value in
                (value, 2_000 - index * 10)
            }
        )

        var generated: [Entry] = []
        generated.reserveCapacity(150_000)
        for value in UInt32(0)...UInt32(0x10FFFF) {
            guard let scalar = Unicode.Scalar(value),
                  let symbol = Self.symbol(for: scalar) else { continue }
            generated.append(Entry(
                result: symbol,
                searchText: symbol.name.lowercased(),
                primaryValue: value,
                popularity: popularity[value, default: 0]
            ))
        }
        generated.append(contentsOf: Self.flagEntries())
        cachedEntries = generated
        return generated
    }

    private static func symbol(for scalar: Unicode.Scalar) -> UnicodeSymbol? {
        guard let name = scalar.properties.name else { return nil }
        switch scalar.properties.generalCategory {
        case .control, .format, .privateUse, .surrogate, .unassigned,
             .lineSeparator, .paragraphSeparator, .spaceSeparator:
            return nil
        default:
            break
        }

        let isEmoji = scalar.properties.isEmojiPresentation
            || (scalar.properties.isEmoji && scalar.value >= 0xA9)
        var text = String(scalar)
        if isEmoji && !scalar.properties.isEmojiPresentation {
            text.append("\u{FE0F}")
        }
        let isCombiningMark: Bool
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            isCombiningMark = true
        default:
            isCombiningMark = false
        }
        return UnicodeSymbol(
            symbol: text,
            displayGlyph: isCombiningMark ? "◌\(text)" : text,
            name: name,
            codePointLabel: codePointLabel(for: text),
            isEmoji: isEmoji
        )
    }

    private static func directCodePointResult(_ term: String) -> UnicodeSymbol? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let rawTokens = trimmed.split { $0.isWhitespace || $0 == "," }
        guard !rawTokens.isEmpty else { return nil }

        var scalars: [Unicode.Scalar] = []
        for rawToken in rawTokens {
            var token = rawToken.uppercased()
            if token.hasPrefix("U+") {
                token.removeFirst(2)
            } else if token.hasPrefix("0X") {
                token.removeFirst(2)
            } else {
                guard (4...6).contains(token.count),
                      token.contains(where: \.isNumber) else { return nil }
            }
            guard !token.isEmpty,
                  token.allSatisfy(\.isHexDigit),
                  let value = UInt32(token, radix: 16),
                  let scalar = Unicode.Scalar(value) else { return nil }
            scalars.append(scalar)
        }

        guard !scalars.isEmpty else { return nil }
        let text = String(String.UnicodeScalarView(scalars))
        let names = scalars.compactMap { $0.properties.name }
        guard names.count == scalars.count else { return nil }
        let isEmoji = scalars.contains { $0.properties.isEmoji || $0.properties.isEmojiPresentation }
        return UnicodeSymbol(
            symbol: text,
            displayGlyph: text,
            name: names.joined(separator: " + "),
            codePointLabel: codePointLabel(for: text),
            isEmoji: isEmoji
        )
    }

    private static func flagEntries() -> [Entry] {
        let english = Locale(identifier: "en_US")
        let localizedLocales = TranslationLanguage.allCases.map { Locale(identifier: $0.rawValue) }
        return Locale.Region.isoRegions.compactMap { region in
            let uppercased = region.identifier.uppercased()
            guard uppercased.count == 2,
                  let first = uppercased.unicodeScalars.first,
                  let last = uppercased.unicodeScalars.last,
                  let firstRegional = Unicode.Scalar(0x1F1E6 + first.value - 65),
                  let lastRegional = Unicode.Scalar(0x1F1E6 + last.value - 65) else {
                return nil
            }
            let text = String(firstRegional) + String(lastRegional)
            let englishName = english.localizedString(forRegionCode: uppercased) ?? uppercased
            let localizedNames = localizedLocales.compactMap {
                $0.localizedString(forRegionCode: uppercased)?.lowercased()
            }
            let result = UnicodeSymbol(
                symbol: text,
                displayGlyph: text,
                name: "FLAG: \(englishName.uppercased())",
                codePointLabel: codePointLabel(for: text),
                isEmoji: true
            )
            return Entry(
                result: result,
                searchText: (["flag", englishName.lowercased()] + localizedNames)
                    .joined(separator: " "),
                primaryValue: firstRegional.value,
                popularity: 0
            )
        }
    }

    private static func normalizedSearchTerm(
        _ term: String,
        nativeLanguage: TranslationLanguage
    ) -> String {
        let normalized = term
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return localizedAliases[nativeLanguage]?[normalized]
            ?? sharedAliases[normalized]
            ?? normalized
    }

    private static let sharedAliases: [String: String] = [
        "smile": "smiling face", "smiley": "smiling face", "happy": "smiling face",
        "grin": "grinning face", "laugh": "face tears joy", "lol": "face tears joy",
        "cry": "crying face", "sad": "sad face", "angry": "angry face",
        "love": "heart", "tick": "check mark", "x mark": "cross mark",
        "celebrate": "party popper", "present": "wrapped gift"
    ]

    /// Unicode only exposes English character names. These compact, offline
    /// aliases cover the concepts people most often look up and are selected
    /// using the native language already configured for translation.
    private static let localizedAliases: [TranslationLanguage: [String: String]] = [
        .simplifiedChinese: [
            "箭头": "arrow", "右箭头": "right arrow", "左箭头": "left arrow",
            "上箭头": "up arrow", "下箭头": "down arrow", "双向箭头": "left right arrow",
            "微笑": "smiling face", "笑脸": "smiling face", "大笑": "grinning face",
            "哭": "crying face", "哭脸": "crying face", "难过": "sad face", "生气": "angry face",
            "爱心": "heart", "红心": "red heart", "心": "heart", "星星": "star", "星": "star",
            "火": "fire", "对勾": "check mark", "勾": "check mark", "叉": "cross mark",
            "警告": "warning", "版权": "copyright", "货币": "currency", "数学": "mathematical",
            "庆祝": "party popper", "礼物": "wrapped gift", "国旗": "flag", "中国国旗": "flag china",
            "猫": "cat face", "狗": "dog face", "咖啡": "hot beverage", "太阳": "sun", "月亮": "moon",
            "点赞": "thumbs up", "鼓掌": "clapping hands", "举手": "raising hand", "举手的人": "person raising hand",
            "招手": "waving hand", "手": "hand", "汽车": "automobile", "飞机": "airplane",
            "音乐": "musical note", "花": "flower", "树": "tree", "雨": "rain", "雪": "snowflake"
        ],
        .traditionalChinese: [
            "箭頭": "arrow", "右箭頭": "right arrow", "左箭頭": "left arrow",
            "上箭頭": "up arrow", "下箭頭": "down arrow", "雙向箭頭": "left right arrow",
            "微笑": "smiling face", "笑臉": "smiling face", "大笑": "grinning face",
            "哭": "crying face", "哭臉": "crying face", "難過": "sad face", "生氣": "angry face",
            "愛心": "heart", "紅心": "red heart", "心": "heart", "星星": "star", "火": "fire",
            "勾": "check mark", "叉": "cross mark", "警告": "warning", "版權": "copyright",
            "貨幣": "currency", "數學": "mathematical", "慶祝": "party popper", "禮物": "wrapped gift",
            "國旗": "flag", "中國國旗": "flag china", "貓": "cat face", "狗": "dog face",
            "咖啡": "hot beverage", "太陽": "sun", "月亮": "moon", "點讚": "thumbs up",
            "鼓掌": "clapping hands", "汽車": "automobile", "飛機": "airplane", "音樂": "musical note"
        ],
        .japanese: [
            "矢印": "arrow", "右矢印": "right arrow", "左矢印": "left arrow",
            "上矢印": "up arrow", "下矢印": "down arrow", "笑顔": "smiling face",
            "大笑い": "grinning face", "泣き顔": "crying face", "悲しい": "sad face", "怒り": "angry face",
            "ハート": "heart", "星": "star", "火": "fire", "チェック": "check mark", "警告": "warning",
            "著作権": "copyright", "通貨": "currency", "数学": "mathematical", "お祝い": "party popper",
            "プレゼント": "wrapped gift", "旗": "flag", "中国": "china", "猫": "cat face", "犬": "dog face",
            "コーヒー": "hot beverage", "太陽": "sun", "月": "moon", "拍手": "clapping hands",
            "車": "automobile", "飛行機": "airplane", "音楽": "musical note", "花": "flower", "雪": "snowflake"
        ],
        .korean: [
            "화살표": "arrow", "오른쪽 화살표": "right arrow", "왼쪽 화살표": "left arrow",
            "위쪽 화살표": "up arrow", "아래쪽 화살표": "down arrow", "웃는 얼굴": "smiling face",
            "웃음": "grinning face", "우는 얼굴": "crying face", "슬픔": "sad face", "화난 얼굴": "angry face",
            "하트": "heart", "별": "star", "불": "fire", "체크": "check mark", "경고": "warning",
            "저작권": "copyright", "통화": "currency", "수학": "mathematical", "축하": "party popper",
            "선물": "wrapped gift", "국기": "flag", "중국": "china", "고양이": "cat face", "개": "dog face",
            "커피": "hot beverage", "태양": "sun", "달": "moon", "박수": "clapping hands",
            "자동차": "automobile", "비행기": "airplane", "음악": "musical note", "눈": "snowflake"
        ],
        .french: [
            "fleche": "arrow", "fleche droite": "right arrow", "fleche gauche": "left arrow",
            "fleche haut": "up arrow", "fleche bas": "down arrow", "sourire": "smiling face",
            "rire": "grinning face", "pleurer": "crying face", "triste": "sad face", "colere": "angry face",
            "coeur": "heart", "etoile": "star", "feu": "fire", "coche": "check mark", "avertissement": "warning",
            "droit d'auteur": "copyright", "monnaie": "currency", "mathematiques": "mathematical",
            "fete": "party popper", "cadeau": "wrapped gift", "drapeau": "flag", "chine": "china",
            "chat": "cat face", "chien": "dog face", "cafe": "hot beverage", "soleil": "sun", "lune": "moon",
            "applaudissements": "clapping hands", "voiture": "automobile", "avion": "airplane", "musique": "musical note"
        ],
        .german: [
            "pfeil": "arrow", "pfeil rechts": "right arrow", "pfeil links": "left arrow",
            "pfeil oben": "up arrow", "pfeil unten": "down arrow", "lacheln": "smiling face",
            "lachen": "grinning face", "weinen": "crying face", "traurig": "sad face", "wutend": "angry face",
            "herz": "heart", "stern": "star", "feuer": "fire", "hakchen": "check mark", "warnung": "warning",
            "urheberrecht": "copyright", "wahrung": "currency", "mathematik": "mathematical", "feier": "party popper",
            "geschenk": "wrapped gift", "flagge": "flag", "china": "china", "katze": "cat face", "hund": "dog face",
            "kaffee": "hot beverage", "sonne": "sun", "mond": "moon", "applaus": "clapping hands",
            "auto": "automobile", "flugzeug": "airplane", "musik": "musical note"
        ],
        .spanish: [
            "flecha": "arrow", "flecha derecha": "right arrow", "flecha izquierda": "left arrow",
            "flecha arriba": "up arrow", "flecha abajo": "down arrow", "sonrisa": "smiling face",
            "reir": "grinning face", "llorar": "crying face", "triste": "sad face", "enojado": "angry face",
            "corazon": "heart", "estrella": "star", "fuego": "fire", "marca": "check mark", "advertencia": "warning",
            "derechos de autor": "copyright", "moneda": "currency", "matematicas": "mathematical", "fiesta": "party popper",
            "regalo": "wrapped gift", "bandera": "flag", "china": "china", "gato": "cat face", "perro": "dog face",
            "cafe": "hot beverage", "sol": "sun", "luna": "moon", "aplausos": "clapping hands",
            "coche": "automobile", "avion": "airplane", "musica": "musical note"
        ],
        .portuguese: [
            "seta": "arrow", "seta direita": "right arrow", "seta esquerda": "left arrow",
            "seta cima": "up arrow", "seta baixo": "down arrow", "sorriso": "smiling face",
            "rir": "grinning face", "chorar": "crying face", "triste": "sad face", "bravo": "angry face",
            "coracao": "heart", "estrela": "star", "fogo": "fire", "marca": "check mark", "aviso": "warning",
            "direitos autorais": "copyright", "moeda": "currency", "matematica": "mathematical", "festa": "party popper",
            "presente": "wrapped gift", "bandeira": "flag", "china": "china", "gato": "cat face", "cachorro": "dog face",
            "cafe": "hot beverage", "sol": "sun", "lua": "moon", "aplausos": "clapping hands",
            "carro": "automobile", "aviao": "airplane", "musica": "musical note"
        ],
        .italian: [
            "freccia": "arrow", "freccia destra": "right arrow", "freccia sinistra": "left arrow",
            "freccia su": "up arrow", "freccia giu": "down arrow", "sorriso": "smiling face",
            "ridere": "grinning face", "piangere": "crying face", "triste": "sad face", "arrabbiato": "angry face",
            "cuore": "heart", "stella": "star", "fuoco": "fire", "spunta": "check mark", "avviso": "warning",
            "copyright": "copyright", "valuta": "currency", "matematica": "mathematical", "festa": "party popper",
            "regalo": "wrapped gift", "bandiera": "flag", "cina": "china", "gatto": "cat face", "cane": "dog face",
            "caffe": "hot beverage", "sole": "sun", "luna": "moon", "applauso": "clapping hands",
            "auto": "automobile", "aereo": "airplane", "musica": "musical note"
        ],
        .russian: [
            "стрелка": "arrow", "стрелка вправо": "right arrow", "стрелка влево": "left arrow",
            "стрелка вверх": "up arrow", "стрелка вниз": "down arrow", "улыбка": "smiling face",
            "смех": "grinning face", "плач": "crying face", "грусть": "sad face", "злость": "angry face",
            "сердце": "heart", "звезда": "star", "огонь": "fire", "галочка": "check mark", "предупреждение": "warning",
            "авторское право": "copyright", "валюта": "currency", "математика": "mathematical", "праздник": "party popper",
            "подарок": "wrapped gift", "флаг": "flag", "китай": "china", "кошка": "cat face", "собака": "dog face",
            "кофе": "hot beverage", "солнце": "sun", "луна": "moon", "аплодисменты": "clapping hands",
            "машина": "automobile", "самолет": "airplane", "музыка": "musical note"
        ],
        .arabic: [
            "سهم": "arrow", "سهم يمين": "right arrow", "سهم يسار": "left arrow",
            "سهم أعلى": "up arrow", "سهم أسفل": "down arrow", "ابتسامة": "smiling face",
            "ضحك": "grinning face", "بكاء": "crying face", "حزين": "sad face", "غاضب": "angry face",
            "قلب": "heart", "نجمة": "star", "نار": "fire", "علامة صح": "check mark", "تحذير": "warning",
            "حقوق النشر": "copyright", "عملة": "currency", "رياضيات": "mathematical", "احتفال": "party popper",
            "هدية": "wrapped gift", "علم": "flag", "الصين": "china", "قطة": "cat face", "كلب": "dog face",
            "قهوة": "hot beverage", "شمس": "sun", "قمر": "moon", "تصفيق": "clapping hands",
            "سيارة": "automobile", "طائرة": "airplane", "موسيقى": "musical note"
        ],
        .english: [:]
    ]

    private static func score(term: String, tokens: [String], candidate: String) -> Int? {
        if candidate == term { return 10_000 }
        if candidate.hasPrefix(term) { return 9_000 - candidate.count }
        if let range = candidate.range(of: term) {
            let startsAtWordBoundary = range.lowerBound == candidate.startIndex
                || candidate[candidate.index(before: range.lowerBound)].isWhitespace
            let endsAtWordBoundary = range.upperBound == candidate.endIndex
                || candidate[range.upperBound].isWhitespace
            if startsAtWordBoundary && endsAtWordBoundary {
                return 8_500 - candidate.count
            }
            return 7_000 - candidate.distance(from: candidate.startIndex, to: range.lowerBound)
        }
        guard !tokens.isEmpty, tokens.allSatisfy({ candidate.contains($0) }) else { return nil }
        return 5_000 - candidate.count
    }

    private static func codePointLabel(for text: String) -> String {
        text.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
    }
}
