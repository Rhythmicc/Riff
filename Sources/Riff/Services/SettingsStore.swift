import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var provider: AIProvider {
        didSet { defaults.set(provider.rawValue, forKey: "ai.provider") }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: "ai.model") }
    }
    @Published var nativeLanguage: TranslationLanguage {
        didSet {
            defaults.set(nativeLanguage.rawValue, forKey: "translation.nativeLanguage")
            if priorityLanguage == nativeLanguage {
                priorityLanguage = TranslationLanguage.defaultPriority(for: nativeLanguage)
            }
        }
    }
    @Published var priorityLanguage: TranslationLanguage {
        didSet { defaults.set(priorityLanguage.rawValue, forKey: "translation.priorityLanguage") }
    }
    @Published var apiKey: String {
        didSet {
            guard !isApplyingKeychainValue else { return }
            loadedKeyProvider = provider
            KeychainStore.set(apiKey, account: provider.rawValue)
        }
    }

    private let defaults = UserDefaults.standard
    private var loadedKeyProvider: AIProvider?
    private var isApplyingKeychainValue = false

    init() {
        let savedProvider = UserDefaults.standard.string(forKey: "ai.provider")
            .flatMap(AIProvider.init(rawValue:)) ?? .openAI
        provider = savedProvider
        model = UserDefaults.standard.string(forKey: "ai.model") ?? savedProvider.defaultModel
        let legacyLanguage = UserDefaults.standard.string(forKey: "ai.targetLanguage")
        let savedNative = UserDefaults.standard.string(forKey: "translation.nativeLanguage")
        let resolvedNative = TranslationLanguage.fromStoredValue(savedNative)
            ?? TranslationLanguage.fromStoredValue(legacyLanguage)
            ?? .simplifiedChinese
        nativeLanguage = resolvedNative
        let savedPriority = TranslationLanguage.fromStoredValue(
            UserDefaults.standard.string(forKey: "translation.priorityLanguage")
        )
        priorityLanguage = savedPriority == resolvedNative || savedPriority == nil
            ? TranslationLanguage.defaultPriority(for: resolvedNative)
            : savedPriority!
        apiKey = ""
    }

    func selectProvider(_ newProvider: AIProvider) {
        provider = newProvider
        model = defaults.string(forKey: "ai.model.\(newProvider.rawValue)") ?? newProvider.defaultModel
        loadedKeyProvider = nil
        loadAPIKeyIfNeeded()
    }

    func loadAPIKeyIfNeeded() {
        guard loadedKeyProvider != provider else { return }
        let storedValue = KeychainStore.get(account: provider.rawValue)
        isApplyingKeychainValue = true
        apiKey = storedValue
        isApplyingKeychainValue = false
        loadedKeyProvider = provider
    }

    func apiKeyForCurrentProvider() -> String {
        loadAPIKeyIfNeeded()
        return apiKey
    }

    func saveModel() {
        defaults.set(model, forKey: "ai.model.\(provider.rawValue)")
    }
}
