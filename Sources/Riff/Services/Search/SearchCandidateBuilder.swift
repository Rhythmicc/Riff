import Foundation

enum SearchCandidateBuilder {
    static func build(for application: ApplicationRecord) -> SearchCandidate {
        let components = splitComponents(application.name)
        return SearchCandidate(
            application: application,
            components: components,
            initials: initials(of: components),
            localizedNames: localizedNames(for: application.url),
            pinyinVariants: pinyinVariants(for: application.name),
            aliases: application.bundleIdentifier.flatMap(AppAliasCatalog.aliases(for:)) ?? []
        )
    }

    /// Splits a display name on separators, camelCase transitions, and
    /// digit/letter boundaries: `CleanShot X` → `[cleanshot, x]`,
    /// `OmniGraffle` → `[omni, graffle]`, `A12B` → `[a, 12, b]`.
    static func splitComponents(_ name: String) -> [String] {
        var components: [String] = []
        var current = ""
        var previous: Character?
        for character in name {
            if character.isLetter || character.isNumber {
                if let previous, shouldBreak(between: previous, and: character),
                   !current.isEmpty {
                    components.append(current)
                    current = ""
                }
                current.append(character)
            } else {
                if !current.isEmpty {
                    components.append(current)
                    current = ""
                }
            }
            previous = character
        }
        if !current.isEmpty { components.append(current) }
        return components.map { $0.lowercased() }
    }

    static func initials(of components: [String]) -> String {
        components.compactMap(\.first).map(String.init).joined().lowercased()
    }

    /// Reads `CFBundleDisplayName`/`CFBundleName` from the app's own
    /// localized InfoPlist.strings files, so Chinese apps surface their
    /// English name and vice versa without a curated list.
    static func localizedNames(for url: URL) -> [String] {
        guard let bundle = Bundle(url: url),
              let resourceURL = bundle.resourceURL else { return [] }
        var names: [String] = []
        for language in ["zh-Hans", "zh_CN", "en"] {
            let stringsURL = resourceURL
                .appendingPathComponent("\(language).lproj")
                .appendingPathComponent("InfoPlist.strings")
            guard let dictionary = NSDictionary(contentsOf: stringsURL) else { continue }
            if let display = dictionary["CFBundleDisplayName"] as? String,
               !display.isEmpty {
                names.append(display)
            }
            if let name = dictionary["CFBundleName"] as? String,
               !name.isEmpty {
                names.append(name)
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// Mandarin pinyin via CFStringTransform: `微信` → `wei xin` / `weixin` / `wx`.
    /// English names produce no extra variants because the transform echoes
    /// the normalized name.
    static func pinyinVariants(for name: String) -> [String] {
        let mutable = NSMutableString(string: name)
        guard CFStringTransform(mutable, nil, kCFStringTransformToLatin, false),
              CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        else { return [] }
        let latin = (mutable as String).lowercased()
        let syllables = latin.split { !$0.isLetter }.map(String.init)
        guard !syllables.isEmpty else { return [] }

        var variants: [String] = []
        let isTransformed = latin != FuzzyMatcher.normalized(name)
        if isTransformed {
            variants.append(latin)
        }
        if isTransformed {
            let joined = syllables.joined()
            variants.append(joined)
        }
        let initials = syllables.compactMap(\.first).map(String.init).joined()
        if !initials.isEmpty {
            variants.append(initials)
        }
        return variants
    }

    private static func shouldBreak(between previous: Character, and current: Character) -> Bool {
        if previous.isLowercase, current.isUppercase { return true }
        if previous.isNumber, current.isLetter { return true }
        if previous.isLetter, current.isNumber { return true }
        return false
    }
}
