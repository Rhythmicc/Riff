import Foundation

enum AppearancePreferences {
    static let glassOpacityKey = "appearance.glassOpacity"
    static let defaultGlassOpacity = 0.78
    static let glassOpacityRange = 0.20...1.0

    static func normalizedGlassOpacity(_ value: Double) -> Double {
        min(max(value, glassOpacityRange.lowerBound), glassOpacityRange.upperBound)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var provider: AIProvider {
        didSet { defaults.set(provider.rawValue, forKey: "ai.provider") }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: "ai.model") }
    }
    @Published var noteCompletionEnabled: Bool {
        didSet { defaults.set(noteCompletionEnabled, forKey: "note.completion.enabled") }
    }
    @Published var noteCompletionBackend: NoteCompletionBackend {
        didSet { defaults.set(noteCompletionBackend.rawValue, forKey: "note.completion.backend") }
    }
    @Published var noteCompletionModel: String {
        didSet {
            defaults.set(noteCompletionModel, forKey: "note.completion.model")
            defaults.set(noteCompletionModel, forKey: "note.completion.model.\(provider.rawValue)")
        }
    }
    @Published var noteCompletionLocalEndpoint: String {
        didSet { defaults.set(noteCompletionLocalEndpoint, forKey: "note.completion.localEndpoint") }
    }
    @Published var noteCompletionLocalModel: NoteCompletionLocalModel {
        didSet { defaults.set(noteCompletionLocalModel.rawValue, forKey: "note.completion.localModel") }
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
    @Published var glassOpacity: Double {
        didSet {
            let normalized = AppearancePreferences.normalizedGlassOpacity(glassOpacity)
            if normalized != glassOpacity {
                glassOpacity = normalized
            } else {
                defaults.set(normalized, forKey: AppearancePreferences.glassOpacityKey)
            }
        }
    }
    @Published var apiKey: String {
        didSet {
            guard !isApplyingKeychainValue else { return }
            loadedKeyProvider = provider
            KeychainStore.set(apiKey, account: provider.rawValue)
        }
    }

    private let defaults: UserDefaults
    private var loadedKeyProvider: AIProvider?
    private var isApplyingKeychainValue = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedProvider = defaults.string(forKey: "ai.provider")
            .flatMap(AIProvider.init(rawValue:)) ?? .openAI
        let savedModel = defaults.string(forKey: "ai.model") ?? savedProvider.defaultModel
        provider = savedProvider
        model = savedModel
        noteCompletionEnabled = defaults.object(forKey: "note.completion.enabled") as? Bool ?? false
        noteCompletionBackend = defaults.string(forKey: "note.completion.backend")
            .flatMap(NoteCompletionBackend.init(rawValue:)) ?? .cloud
        noteCompletionModel = defaults.string(forKey: "note.completion.model.\(savedProvider.rawValue)")
            ?? defaults.string(forKey: "note.completion.model")
            ?? savedModel
        let savedLocalEndpoint = defaults.string(forKey: "note.completion.localEndpoint")
        noteCompletionLocalEndpoint = savedLocalEndpoint == nil
            || savedLocalEndpoint == "http://127.0.0.1:11435/completion"
            ? "http://127.0.0.1:11435/v1/chat/completions"
            : savedLocalEndpoint!
        noteCompletionLocalModel = defaults.string(forKey: "note.completion.localModel")
            .flatMap(NoteCompletionLocalModel.init(rawValue:)) ?? .balanced
        let legacyLanguage = defaults.string(forKey: "ai.targetLanguage")
        let savedNative = defaults.string(forKey: "translation.nativeLanguage")
        let resolvedNative = TranslationLanguage.fromStoredValue(savedNative)
            ?? TranslationLanguage.fromStoredValue(legacyLanguage)
            ?? .simplifiedChinese
        nativeLanguage = resolvedNative
        let savedPriority = TranslationLanguage.fromStoredValue(
            defaults.string(forKey: "translation.priorityLanguage")
        )
        priorityLanguage = savedPriority == resolvedNative || savedPriority == nil
            ? TranslationLanguage.defaultPriority(for: resolvedNative)
            : savedPriority!
        glassOpacity = AppearancePreferences.normalizedGlassOpacity(
            defaults.object(forKey: AppearancePreferences.glassOpacityKey) as? Double
                ?? AppearancePreferences.defaultGlassOpacity
        )
        apiKey = ""
    }

    func selectProvider(_ newProvider: AIProvider) {
        provider = newProvider
        model = defaults.string(forKey: "ai.model.\(newProvider.rawValue)") ?? newProvider.defaultModel
        noteCompletionModel = defaults.string(forKey: "note.completion.model.\(newProvider.rawValue)")
            ?? model
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

    func saveNoteCompletionModel() {
        defaults.set(noteCompletionModel, forKey: "note.completion.model.\(provider.rawValue)")
    }

    func resetGlassOpacity() {
        glassOpacity = AppearancePreferences.defaultGlassOpacity
    }
}
