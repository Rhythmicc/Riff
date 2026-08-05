import AppKit
import Combine
import Foundation

/// Coordinates launcher input and publishes one coherent presentation snapshot
/// per transition. Parsing and search services do not live in the SwiftUI view.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = LauncherState() {
        didSet { recordSettledQueryIfNeeded() }
    }
    @Published private(set) var isIndexing = true

    let clipboard: ClipboardStore
    let componentManager: ComponentManager
    var onOpenNote: (() -> Void)?
    var onOpenTranslation: (() -> Void)?
    var onOpenChat: (() -> Void)?
    var onCommitAIAnswerToChat: ((String, String) -> Void)?
    var onPerformSystemOperation: ((SystemOperation) -> Void)?

    private let applicationIndex: ApplicationIndex
    private let applicationSearch = ApplicationSearch()
    private let currencyConverter = CurrencyConverter()
    private let aiService = AIService()
    private let usageStore: LauncherUsageStore
    private let experienceMetrics: ExperienceMetricsStore?
    private weak var settings: SettingsStore?
    private var noteModel: NoteModel?
    private var applicationRefreshTask: Task<Void, Never>?
    private var applicationSearchTask: Task<Void, Never>?
    private var currencyTask: Task<Void, Never>?
    private var graphTask: Task<Void, Never>?
    private var unicodeSearchTask: Task<Void, Never>?
    private var aiAnswerTask: Task<Void, Never>?
    private var componentTask: Task<Void, Never>?
    private var clipboardCancellable: AnyCancellable?
    private var indexedApplications: [ApplicationRecord] = []
    private var indexedRunningBundleIdentifiers = Set<String>()
    private var rankedApplications: [ApplicationRecord] = []
    private var applicationResultLimit = 8
    private var aiStreamBuffer = ""
    private var lastAIStreamPublish = Date.distantPast
    private var metricsQueryToken: UInt64?
    private var metricsQueryText = ""

    init(
        clipboard: ClipboardStore,
        settings: SettingsStore? = nil,
        noteModel: NoteModel? = nil,
        usageStore: LauncherUsageStore? = nil,
        experienceMetrics: ExperienceMetricsStore? = nil,
        applicationIndex: ApplicationIndex = ApplicationIndex(),
        componentManager: ComponentManager? = nil
    ) {
        self.clipboard = clipboard
        self.componentManager = componentManager ?? ComponentManager()
        self.settings = settings
        self.noteModel = noteModel
        self.usageStore = usageStore ?? LauncherUsageStore()
        self.experienceMetrics = experienceMetrics
        self.applicationIndex = applicationIndex

        clipboardCancellable = clipboard.$items
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.state.mode == .clipboard else { return }
                self.publishClipboard(query: self.state.query)
            }

        refreshApplications(force: true, showsInitialIndexingState: true)
    }

    var query: String {
        get { state.query }
        set { processQuery(newValue) }
    }

    var mode: LauncherMode { state.mode }
    var contentKind: LauncherContentKind { state.content.presentationKind }

    var selectedIndex: Int {
        get { state.selectedIndex }
        set {
            let clamped = max(0, newValue)
            guard clamped != state.selectedIndex else { return }
            var next = state
            next.selectedIndex = clamped
            state = next
        }
    }

    var filteredApplications: [ApplicationRecord] {
        guard case .applications(_, let items, _, _) = state.content else { return [] }
        return items
    }

    var filteredClipboard: [ClipboardItem] {
        guard case .clipboard(let items) = state.content else { return [] }
        return items
    }

    var calculation: String? {
        guard case .calculation(let value) = state.content else { return nil }
        return value
    }

    var currencyResult: String? {
        guard case .currency(let result, _, _) = state.content else { return nil }
        return result
    }

    var currencyError: String? {
        guard case .currency(_, let error, _) = state.content else { return nil }
        return error
    }

    var isConvertingCurrency: Bool {
        guard case .currency(_, _, let isLoading) = state.content else { return false }
        return isLoading
    }

    var graphExpression: MathExpression? {
        guard case .graph(let expression, _, _, _) = state.content else { return nil }
        return expression
    }

    var graphPlot: FunctionPlotData? {
        guard case .graph(_, let plot, _, _) = state.content else { return nil }
        return plot
    }

    var graphError: String? {
        guard case .graph(_, _, let error, _) = state.content else { return nil }
        return error
    }

    var isPlottingGraph: Bool {
        guard case .graph(_, _, _, let isLoading) = state.content else { return false }
        return isLoading
    }

    var unicodeResults: [UnicodeSymbol] {
        guard case .unicode(_, let items, _) = state.content else { return [] }
        return items
    }

    var isSearchingUnicode: Bool {
        guard case .unicode(_, _, let isSearching) = state.content else { return false }
        return isSearching
    }

    var unicodeQuery: UnicodeSearchQuery? {
        guard case .unicode(let query, _, _) = state.content else { return nil }
        return query
    }

    var isUnicodeQuery: Bool { unicodeQuery != nil }

    var generatedPassword: GeneratedPassword? {
        guard case .password(_, let result, _) = state.content else { return nil }
        return result
    }

    var passwordRequest: PasswordRequest? {
        guard case .password(let request, _, _) = state.content else { return nil }
        return request
    }

    var passwordCrackEstimateText: String? {
        guard let request = passwordRequest else { return nil }
        return PasswordCrackEstimate.localizedSummary(for: request)
    }

    var passwordGenerationError: String? {
        guard case .password(_, _, let error) = state.content else { return nil }
        return error
    }

    var isPasswordQuery: Bool {
        if case .password = state.content { return true }
        return false
    }

    var componentItems: [ComponentResultItem] {
        if case .component(_, _, let results, _) = state.content { return results }
        return []
    }

    var componentIsLoading: Bool {
        if case .component(_, _, _, let isLoading) = state.content { return isLoading }
        return false
    }

    var isComponentQuery: Bool {
        if case .component = state.content { return true }
        return false
    }

    var isGraphQuery: Bool {
        if case .graph = state.content { return true }
        return false
    }

    var systemOperations: [SystemOperation] {
        guard case .systemOperations(let operations) = state.content else { return [] }
        return operations
    }

    var isSystemOperationQuery: Bool { !systemOperations.isEmpty }

    var fallbackActions: [LauncherFallbackAction] {
        guard case .fallback(_, let actions) = state.content else { return [] }
        return actions
    }

    var selectedFallbackAction: LauncherFallbackAction? {
        guard fallbackActions.indices.contains(state.selectedIndex) else { return nil }
        return fallbackActions[state.selectedIndex]
    }

    var isFallbackQuery: Bool {
        if case .fallback = state.content { return true }
        return false
    }

    var isAIAnswer: Bool {
        if case .aiAnswer = state.content { return true }
        return false
    }

    /// Set when the user presses Tab after the first launcher AI answer
    /// completes, which commits the exchange to the chat component and unlocks
    /// ⌘J as the launcher-local shortcut that opens the chat window.
    private(set) var aiAnswerCommittedToChat = false

    var canOpenChatAfterCommittedAIAnswer: Bool {
        aiAnswerCommittedToChat
    }

    @discardableResult
    func commitAIAnswerToChat() -> Bool {
        guard case .aiAnswer(_, _, let result, _, let isLoading) = state.content,
              !isLoading,
              !result.isEmpty else { return false }
        if !aiAnswerCommittedToChat {
            let question = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
            aiAnswerCommittedToChat = true
            onCommitAIAnswerToChat?(question, result)
        }
        return true
    }

    var aiAnswerResult: String {
        guard case .aiAnswer(_, _, let result, _, _) = state.content else { return "" }
        return result
    }

    var aiAnswerError: String? {
        guard case .aiAnswer(_, _, _, let error, _) = state.content else { return nil }
        return error
    }

    var isLoadingAIAnswer: Bool {
        guard case .aiAnswer(_, _, _, _, let isLoading) = state.content else { return false }
        return isLoading
    }

    var canCopyAIAnswer: Bool { !isLoadingAIAnswer && !aiAnswerResult.isEmpty }

    var aiAnswerProviderSummary: String? {
        guard case .aiAnswer(let provider, let model, _, _, _) = state.content else { return nil }
        return "\(provider.title) · \(model)"
    }

    func fallbackTitle(for action: LauncherFallbackAction) -> String {
        action.title(for: state.query)
    }

    var quickActions: [LauncherQuickAction] {
        guard case .applications(let actions, _, _, _) = state.content else { return [] }
        return actions
    }

    var hasInferredContent: Bool {
        switch state.content {
        case .calculation, .currency, .graph, .unicode, .password, .aiAnswer, .component: return true
        case .idle, .systemOperations, .fallback, .applications, .clipboard: return false
        }
    }

    var resultCount: Int {
        switch state.content {
        case .idle, .graph: return 0
        case .systemOperations(let operations): return operations.count
        case .fallback(_, let actions): return actions.count
        case .aiAnswer(_, _, let result, _, let isLoading):
            return !result.isEmpty && !isLoading ? 1 : 0
        case .applications(let actions, let items, _, _): return actions.count + items.count
        case .clipboard(let items): return items.count
        case .calculation, .currency, .password: return 1
        case .unicode(_, let items, _): return items.count
        case .component(_, _, let results, _): return results.count
        }
    }

    var shouldShowResults: Bool {
        state.mode == .clipboard
            || state.mode == .password
            || !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectionIsActionable: Bool {
        if isPasswordQuery { return generatedPassword != nil }
        return !isGraphQuery && resultCount > 0
    }

    var showsNoteAction: Bool { quickActions.contains(.note) }

    func switchMode(_ newMode: LauncherMode) {
        cancelPendingWork()
        experienceMetrics?.cancelActiveQuery()
        metricsQueryToken = nil
        metricsQueryText = ""
        rankedApplications = []
        applicationResultLimit = 8
        switch newMode {
        case .clipboard:
            state = LauncherState(
                query: "",
                mode: .clipboard,
                selectedIndex: 0,
                content: .clipboard(Array(clipboard.items.prefix(7)))
            )
        case .password:
            publishPassword(PasswordRequest(), query: "")
        case .apps:
            state = LauncherState(
                query: "",
                mode: .apps,
                selectedIndex: 0,
                content: .idle
            )
        }
    }

    func reset(for mode: LauncherMode) {
        switchMode(mode)
    }

    /// Kept as an explicit hook for tests and external state changes. Normal text
    /// input calls `processQuery` directly through the query binding.
    func refreshQuery() {
        processQuery(state.query, force: true)
    }

    /// Called whenever the launcher becomes visible. The index service performs
    /// a cheap root metadata check and only rescans application directories that
    /// changed, so newly installed apps appear without slowing down the panel.
    func refreshApplications() {
        refreshApplications(force: false, showsInitialIndexingState: false)
    }

    func moveSelection(by offset: Int) {
        guard resultCount > 0 else { return }
        if offset > 0,
           state.selectedIndex == resultCount - 1,
           case .applications(let actions, _, let hasMore, _) = state.content,
           hasMore {
            let nextSelection = resultCount
            applicationResultLimit += 8
            let items = Array(rankedApplications.prefix(applicationResultLimit))
            var next = state
            next.content = .applications(
                actions: actions,
                items: items,
                hasMore: items.count < rankedApplications.count,
                isSearching: false
            )
            next.selectedIndex = min(nextSelection, actions.count + items.count - 1)
            state = next
            return
        }

        var next = state
        next.selectedIndex = min(max(0, state.selectedIndex + offset), resultCount - 1)
        state = next
    }

    func moveUnicodeSelection(rows: Int, columns: Int) {
        guard isUnicodeQuery, resultCount > 0, columns > 0 else { return }
        let currentColumn = state.selectedIndex % columns
        let currentRow = state.selectedIndex / columns
        let rowCount = (resultCount + columns - 1) / columns
        let targetRow = min(max(0, currentRow + rows), rowCount - 1)
        selectedIndex = min(targetRow * columns + currentColumn, resultCount - 1)
    }

    @discardableResult
    func activateSelection() -> Bool {
        switch state.content {
        case .systemOperations(let operations):
            guard operations.indices.contains(state.selectedIndex) else { return false }
            usageStore.record("system:\(operations[state.selectedIndex].rawValue)")
            recordSuccessfulActivation()
            onPerformSystemOperation?(operations[state.selectedIndex])
            return true
        case .fallback(let query, let actions):
            guard actions.indices.contains(state.selectedIndex) else { return false }
            let action = actions[state.selectedIndex]
            usageStore.record("fallback:\(action.rawValue)")
            switch action {
            case .googleSearch:
                guard let url = action.destinationURL(for: query) else { return false }
                recordSuccessfulActivation()
                NSWorkspace.shared.open(url)
                return true
            case .askAI:
                startAIAnswer(query: query)
                return false
            }
        case .aiAnswer(_, _, let result, _, let isLoading):
            guard !isLoading, !result.isEmpty else { return false }
            recordSuccessfulActivation()
            copyText(result)
            return true
        case .unicode(_, let items, _):
            guard items.indices.contains(state.selectedIndex) else { return false }
            recordSuccessfulActivation()
            copyText(items[state.selectedIndex].symbol)
            return true
        case .password(_, let result?, _):
            recordSuccessfulActivation()
            copyText(result.value)
            return true
        case .currency(let result?, _, _):
            recordSuccessfulActivation()
            copyText(result)
            return true
        case .calculation(let result):
            recordSuccessfulActivation()
            copyText(result)
            return true
        case .applications(let actions, let items, _, _):
            if actions.indices.contains(state.selectedIndex) {
                let action = actions[state.selectedIndex]
                usageStore.record("quick:\(action.rawValue)")
                switch action {
                case .note:
                    recordSuccessfulActivation()
                    onOpenNote?()
                    return true
                case .clipboard:
                    switchMode(.clipboard)
                    return false
                case .translation:
                    recordSuccessfulActivation()
                    onOpenTranslation?()
                    return true
                case .password:
                    publishPassword(
                        PasswordRequest.parseOptions(from: state.query),
                        query: PasswordRequest.parameterText(from: state.query)
                    )
                    return false
                case .chat:
                    recordSuccessfulActivation()
                    onOpenChat?()
                    return true
                }
            }
            let applicationOffset = state.selectedIndex - actions.count
            guard items.indices.contains(applicationOffset) else { return false }
            let application = items[applicationOffset]
            usageStore.record("app:\(application.id)")
            recordSuccessfulActivation()
            applicationIndex.launch(application)
            return true
        case .clipboard(let items):
            guard items.indices.contains(state.selectedIndex) else { return false }
            recordSuccessfulActivation()
            clipboard.copy(items[state.selectedIndex])
            return true
        case .component(let componentID, _, let results, let isLoading):
            guard !isLoading, results.indices.contains(state.selectedIndex) else { return false }
            let item = results[state.selectedIndex]
            guard let action = item.actions.first else { return false }
            recordSuccessfulActivation()
            switch action {
            case .copy(let text):
                copyText(text)
                return true
            case .openURL(let url):
                NSWorkspace.shared.open(url)
                return true
            case .callback:
                Task { [weak self] in
                    try? await self?.componentManager.component(id: componentID)?.perform(action)
                }
                return false
            case .openPanel:
                return false
            }
        case .idle, .currency, .graph, .password:
            return false
        }
    }

    @discardableResult
    func regeneratePassword() -> Bool {
        guard case .password(let request, _, _) = state.content else { return false }
        publishPassword(request, query: state.query)
        return true
    }

    func selectedClipboardItem() -> ClipboardItem? {
        guard case .clipboard(let items) = state.content,
              items.indices.contains(state.selectedIndex) else { return nil }
        return items[state.selectedIndex]
    }

    var clipboardHistoryCount: Int { clipboard.items.count }
    var clipboardStorageError: String? { clipboard.storageError }

    func removeSelectedClipboardItem() {
        guard let item = selectedClipboardItem() else { return }
        clipboard.remove(item)
    }

    func removeClipboardItem(_ item: ClipboardItem) {
        clipboard.remove(item)
    }

    func clearClipboardHistory() {
        clipboard.clear()
    }

    func revealClipboardStorage() {
        clipboard.revealStorage()
    }

    nonisolated static func applicationScore(
        query: String,
        application: ApplicationRecord
    ) -> Int? {
        SearchScorer.score(
            query: query,
            candidate: SearchCandidateBuilder.build(for: application)
        )
    }

    static func rankApplicationsForPresentation(
        query: String,
        searchedResults: [ApplicationRecord],
        usageStore: LauncherUsageStore
    ) -> [ApplicationRecord] {
        // Match quality dominates. Recent usage adds a bounded bonus so it
        // breaks near-ties but can never bridge a real quality gap (for
        // example initials-exact vs bundle-exact).
        let scored = searchedResults.enumerated().map { index, application in
            (
                application: application,
                score: SearchScorer.score(
                    query: query,
                    candidate: SearchCandidateBuilder.build(for: application)
                ) ?? 0,
                order: index
            )
        }
        return scored.sorted { lhs, rhs in
            let lhsFinal = lhs.score + usageBonus(usageStore, application: lhs.application)
            let rhsFinal = rhs.score + usageBonus(usageStore, application: rhs.application)
            if lhsFinal != rhsFinal { return lhsFinal > rhsFinal }
            return lhs.order < rhs.order
        }.map(\.application)
    }

    private static func usageBonus(
        _ usageStore: LauncherUsageStore,
        application: ApplicationRecord
    ) -> Int {
        guard let position = usageStore.position(of: "app:\(application.id)") else { return 0 }
        return max(0, 250 - position * 25)
    }

    nonisolated static func isNoteQuery(_ query: String) -> Bool {
        LauncherQuickAction.matching(query).contains(.note)
    }

    private func processQuery(
        _ newQuery: String,
        force: Bool = false,
        recordsMetrics: Bool = true
    ) {
        guard force || newQuery != state.query else { return }
        if newQuery != state.query {
            aiAnswerCommittedToChat = false
        }
        let oldState = state
        cancelPendingWork()
        applicationResultLimit = 8

        let trimmedQuery = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if recordsMetrics {
            if oldState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !trimmedQuery.isEmpty {
                experienceMetrics?.markFirstInput()
            }
            if trimmedQuery.isEmpty {
                experienceMetrics?.cancelActiveQuery()
                metricsQueryToken = nil
                metricsQueryText = ""
            } else {
                metricsQueryToken = experienceMetrics?.beginQuery()
                metricsQueryText = newQuery
            }
        }

        if oldState.mode == .clipboard {
            publishClipboard(query: newQuery)
            return
        }

        if oldState.mode == .password {
            let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                publishPassword(PasswordRequest(), query: "")
                return
            }
            if PasswordRequest.isParameterText(trimmed) {
                publishPassword(
                    PasswordRequest.parseOptions(from: trimmed),
                    query: newQuery
                )
                return
            }
            // Not a parameter: leave the component and treat the text as a
            // normal launcher query below.
        }

        guard !trimmedQuery.isEmpty else {
            rankedApplications = []
            state = LauncherState(query: newQuery, mode: .apps, selectedIndex: 0, content: .idle)
            return
        }

        var intent = LauncherQueryClassifier.classify(newQuery)
        if case .systemOperations = intent,
           !componentManager.isEnabled(ComponentID.systemOperations) {
            intent = .applications(actions: LauncherQuickAction.matching(newQuery))
        }
        switch intent {
        case .systemOperations(let operations):
            rankedApplications = []
            let rankedOperations = usageStore.sorted(operations) { "system:\($0.rawValue)" }
            state = LauncherState(
                query: newQuery,
                mode: .apps,
                selectedIndex: 0,
                content: .systemOperations(rankedOperations)
            )

        case .applications(let actions):
            if let installedComponent = componentManager.installedMatch(newQuery, mode: .apps) {
                startComponentResults(component: installedComponent, query: newQuery)
                return
            }
            let enabledActions = actions.filter { action in
                guard let componentID = Self.componentID(for: action) else { return true }
                return componentManager.isEnabled(componentID)
            }
            let rankedActions = usageStore.sorted(enabledActions) { "quick:\($0.rawValue)" }
            let previousItems: [ApplicationRecord]
            if case .applications(_, let items, _, _) = oldState.content {
                previousItems = items
            } else {
                previousItems = []
            }
            state = LauncherState(
                query: newQuery,
                mode: .apps,
                selectedIndex: 0,
                content: .applications(
                    actions: rankedActions,
                    items: previousItems,
                    hasMore: false,
                    isSearching: true
                )
            )
            guard !isIndexing else { return }
            startApplicationSearch(query: newQuery, actions: rankedActions)

        case .calculation(let result):
            rankedApplications = []
            state = LauncherState(
                query: newQuery,
                mode: .apps,
                selectedIndex: 0,
                content: .calculation(result)
            )

        case .graph(let expression, let error):
            rankedApplications = []
            state = LauncherState(
                query: newQuery,
                mode: .apps,
                selectedIndex: 0,
                content: .graph(
                    expression: expression,
                    plot: nil,
                    error: error,
                    isLoading: expression != nil
                )
            )
            if let expression {
                startGraphPlot(expression, requestedText: newQuery)
            }

        case .unicode(let unicodeQuery):
            rankedApplications = []
            let previousItems: [UnicodeSymbol]
            if case .unicode(_, let items, _) = oldState.content {
                previousItems = items
            } else {
                previousItems = []
            }
            state = LauncherState(
                query: newQuery,
                mode: .apps,
                selectedIndex: 0,
                content: .unicode(query: unicodeQuery, items: previousItems, isSearching: true)
            )
            startUnicodeSearch(query: unicodeQuery, requestedText: newQuery)

        case .password(let request):
            rankedApplications = []
            publishPassword(
                request,
                query: PasswordRequest.parameterText(from: newQuery)
            )

        case .currency(let conversion):
            rankedApplications = []
            state = LauncherState(
                query: newQuery,
                mode: .apps,
                selectedIndex: 0,
                content: .currency(result: nil, error: nil, isLoading: true)
            )
            startCurrencyConversion(conversion, requestedText: newQuery)
        }
    }

    private func startComponentResults(
        component: any RiffComponent,
        query: String
    ) {
        componentTask?.cancel()
        rankedApplications = []
        state = LauncherState(
            query: query,
            mode: .apps,
            selectedIndex: 0,
            content: .component(
                componentID: component.id,
                query: query,
                results: [],
                isLoading: true
            )
        )
        componentTask = Task { [weak self] in
            do {
                let results = try await component.results(for: query)
                try Task.checkCancellation()
                guard let self, self.state.query == query else { return }
                self.state = LauncherState(
                    query: query,
                    mode: .apps,
                    selectedIndex: 0,
                    content: .component(
                        componentID: component.id,
                        query: query,
                        results: results.items,
                        isLoading: !results.isComplete
                    )
                )
            } catch is CancellationError {
                // Obsolete work; the current snapshot stays.
            } catch {
                guard let self, self.state.query == query else { return }
                self.state = LauncherState(
                    query: query,
                    mode: .apps,
                    selectedIndex: 0,
                    content: .component(
                        componentID: component.id,
                        query: query,
                        results: [],
                        isLoading: false
                    )
                )
            }
        }
    }

    nonisolated static func componentID(for action: LauncherQuickAction) -> String? {
        switch action {
        case .note: return ComponentID.note
        case .clipboard: return ComponentID.clipboard
        case .translation: return ComponentID.translation
        case .password: return ComponentID.password
        case .chat: return ComponentID.chat
        }
    }

    private func publishPassword(_ request: PasswordRequest, query: String) {
        do {
            let generated = try PasswordGenerator.generate(request)
            state = LauncherState(
                query: query,
                mode: .password,
                selectedIndex: 0,
                content: .password(request: request, result: generated, error: nil)
            )
        } catch {
            state = LauncherState(
                query: query,
                mode: .password,
                selectedIndex: 0,
                content: .password(
                    request: request,
                    result: nil,
                    error: error.localizedDescription
                )
            )
        }
    }

    private func startApplicationSearch(query: String, actions: [LauncherQuickAction]) {
        applicationSearchTask = Task { [weak self] in
            guard let self else { return }
            let searchedResults = await applicationSearch.search(query)
            guard !Task.isCancelled,
                  state.mode == .apps,
                  state.query == query,
                  case .applications = state.content else { return }
            let results = Self.rankApplicationsForPresentation(
                query: query,
                searchedResults: searchedResults,
                usageStore: usageStore
            )
            rankedApplications = results
            if actions.isEmpty, results.isEmpty {
                let fallbackActions = usageStore.sorted(LauncherFallbackAction.allCases) {
                    "fallback:\($0.rawValue)"
                }
                state = LauncherState(
                    query: query,
                    mode: .apps,
                    selectedIndex: 0,
                    content: .fallback(query: query, actions: fallbackActions)
                )
                return
            }
            let items = Array(results.prefix(applicationResultLimit))
            var next = state
            next.selectedIndex = 0
            next.content = .applications(
                actions: actions,
                items: items,
                hasMore: items.count < results.count,
                isSearching: false
            )
            state = next
        }
    }

    private func startAIAnswer(query: String) {
        guard let settings else {
            state = LauncherState(
                query: query,
                mode: .apps,
                selectedIndex: 0,
                content: .aiAnswer(
                    provider: .openAI,
                    model: "",
                    result: "",
                    error: "无法读取 AI Provider 设置",
                    isLoading: false
                )
            )
            return
        }

        let provider = settings.provider
        let model = settings.model
        let apiKey = settings.apiKeyForCurrentProvider()
        let tavilyKey = settings.tavilyAPIKey()
        aiAnswerTask?.cancel()
        aiStreamBuffer = ""
        lastAIStreamPublish = .distantPast
        state = LauncherState(
            query: query,
            mode: .apps,
            selectedIndex: 0,
            content: .aiAnswer(
                provider: provider,
                model: model,
                result: "",
                error: nil,
                isLoading: true
            )
        )

        aiAnswerTask = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await aiService.answerWithTools(
                    query: query,
                    tools: RiffToolRegistry.tools(
                        provider: provider,
                        model: model,
                        apiKey: apiKey,
                        tavilyAPIKey: tavilyKey,
                        noteModel: noteModel
                    ),
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    onDelta: { [weak self] delta in
                        self?.receiveAIStreamDelta(
                            delta,
                            query: query,
                            provider: provider,
                            model: model
                        )
                    }
                )
                guard !Task.isCancelled, state.query == query else { return }
                state = LauncherState(
                    query: query,
                    mode: .apps,
                    selectedIndex: 0,
                    content: .aiAnswer(
                        provider: provider,
                        model: model,
                        result: answer,
                        error: nil,
                        isLoading: false
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                guard state.query == query else { return }
                state = LauncherState(
                    query: query,
                    mode: .apps,
                    selectedIndex: 0,
                    content: .aiAnswer(
                        provider: provider,
                        model: model,
                        result: aiStreamBuffer,
                        error: error.localizedDescription,
                        isLoading: false
                    )
                )
            }
        }
    }

    private func receiveAIStreamDelta(
        _ delta: String,
        query: String,
        provider: AIProvider,
        model: String
    ) {
        guard state.query == query, !Task.isCancelled else { return }
        let isFirstChunk = aiStreamBuffer.isEmpty
        aiStreamBuffer.append(delta)
        let now = Date()
        guard isFirstChunk
                || delta.contains("\n")
                || now.timeIntervalSince(lastAIStreamPublish) >= 0.035
        else { return }

        lastAIStreamPublish = now
        var next = state
        next.content = .aiAnswer(
            provider: provider,
            model: model,
            result: aiStreamBuffer,
            error: nil,
            isLoading: true
        )
        state = next
    }

    private func refreshApplications(
        force: Bool,
        showsInitialIndexingState: Bool
    ) {
        guard applicationRefreshTask == nil else { return }
        if showsInitialIndexingState { isIndexing = true }

        applicationRefreshTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await applicationIndex.load(force: force)
            guard !Task.isCancelled else {
                applicationRefreshTask = nil
                return
            }

            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let needsReplacement = loaded != indexedApplications
                || running != indexedRunningBundleIdentifiers

            if needsReplacement {
                let sorted = await applicationSearch.replaceApplications(
                    loaded,
                    runningBundleIdentifiers: running
                )
                guard !Task.isCancelled else {
                    applicationRefreshTask = nil
                    return
                }
                indexedApplications = loaded
                indexedRunningBundleIdentifiers = running
                rankedApplications = sorted
            }

            isIndexing = false
            applicationRefreshTask = nil
            if needsReplacement {
                // Mark indexing complete before replaying text entered during
                // startup. Otherwise the replay exits at the indexing guard and
                // the user's first query remains permanently unresolved.
                processQuery(state.query, force: true, recordsMetrics: false)
            }
        }
    }

    private func startUnicodeSearch(query: UnicodeSearchQuery, requestedText: String) {
        let nativeLanguage = settings?.nativeLanguage ?? .simplifiedChinese
        unicodeSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self else { return }
            let results = await UnicodeSearchIndex.shared.search(
                query,
                nativeLanguage: nativeLanguage,
                limit: 64
            )
            guard !Task.isCancelled, state.query == requestedText else { return }
            var next = state
            next.selectedIndex = 0
            next.content = .unicode(query: query, items: results, isSearching: false)
            state = next
        }
    }

    private func startGraphPlot(_ expression: MathExpression, requestedText: String) {
        graphTask = Task { [weak self] in
            guard let plot = await FunctionPlotter.plot(expression),
                  !Task.isCancelled,
                  let self,
                  state.query == requestedText else { return }
            var next = state
            next.content = .graph(
                expression: expression,
                plot: plot,
                error: nil,
                isLoading: false
            )
            state = next
        }
    }

    private func startCurrencyConversion(_ conversion: CurrencyQuery, requestedText: String) {
        currencyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let self else { return }
            do {
                let result = try await currencyConverter.convert(conversion)
                guard !Task.isCancelled, state.query == requestedText else { return }
                var next = state
                next.content = .currency(result: result, error: nil, isLoading: false)
                state = next
            } catch {
                guard !Task.isCancelled, state.query == requestedText else { return }
                var next = state
                next.content = .currency(result: nil, error: error.localizedDescription, isLoading: false)
                state = next
            }
        }
    }

    private func publishClipboard(query: String) {
        let items = Array(clipboard.filtered(by: query).prefix(7))
        state = LauncherState(
            query: query,
            mode: .clipboard,
            selectedIndex: 0,
            content: .clipboard(items)
        )
    }

    private func cancelPendingWork() {
        applicationSearchTask?.cancel()
        currencyTask?.cancel()
        graphTask?.cancel()
        unicodeSearchTask?.cancel()
        aiAnswerTask?.cancel()
        componentTask?.cancel()
    }

    private func recordSettledQueryIfNeeded() {
        guard let token = metricsQueryToken,
              state.query == metricsQueryText,
              state.content.isSettledForExperienceMetrics else { return }
        experienceMetrics?.resolveQuery(
            token: token,
            producedResults: state.content.producedResultsForExperienceMetrics
        )
        metricsQueryToken = nil
        metricsQueryText = ""
    }

    private func recordSuccessfulActivation() {
        experienceMetrics?.completeLauncherSession()
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
