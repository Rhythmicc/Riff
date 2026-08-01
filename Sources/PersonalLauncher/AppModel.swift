import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var query = ""
    @Published var mode: LauncherMode = .apps
    @Published var selectedIndex = 0
    @Published private(set) var applications: [ApplicationRecord] = []
    @Published private(set) var isIndexing = true
    @Published private(set) var currencyResult: String?
    @Published private(set) var currencyError: String?
    @Published private(set) var isConvertingCurrency = false
    @Published private(set) var graphExpression: MathExpression?
    @Published private(set) var graphError: String?

    let clipboard: ClipboardStore
    var onOpenNote: (() -> Void)?
    private let applicationIndex = ApplicationIndex()
    private let currencyConverter = CurrencyConverter()
    private var currencyTask: Task<Void, Never>?

    init(clipboard: ClipboardStore) {
        self.clipboard = clipboard
        Task {
            let loaded = await applicationIndex.load()
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            applications = loaded.sorted { lhs, rhs in
                let lhsRunning = lhs.bundleIdentifier.map(running.contains) ?? false
                let rhsRunning = rhs.bundleIdentifier.map(running.contains) ?? false
                if lhsRunning != rhsRunning { return lhsRunning }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            isIndexing = false
        }
    }

    var filteredApplications: [ApplicationRecord] {
        guard !query.isEmpty else { return Array(applications.prefix(8)) }
        var ranked: [(application: ApplicationRecord, score: Int)] = []
        for application in applications {
            var combined = application.name
            if let bundleIdentifier = application.bundleIdentifier {
                combined.append(" ")
                combined.append(contentsOf: bundleIdentifier)
            }
            if let score = FuzzyMatcher.score(query: query, candidate: combined) {
                ranked.append((application: application, score: score))
            }
        }
        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.application.name < rhs.application.name }
            return lhs.score > rhs.score
        }
        return ranked.prefix(8).map { $0.application }
    }

    var filteredClipboard: [ClipboardItem] {
        Array(clipboard.filtered(by: query).prefix(7))
    }

    var calculation: String? {
        let source = query.hasPrefix("=") ? String(query.dropFirst()) : query
        guard source.rangeOfCharacter(from: .decimalDigits) != nil,
              source.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^()")) != nil,
              let result = try? Calculator.evaluate(source) else { return nil }
        return Calculator.formatted(result)
    }

    var resultCount: Int {
        if isGraphQuery { return 0 }
        if calculation != nil || currencyResult != nil || isConvertingCurrency { return 1 }
        switch mode {
        case .apps: return filteredApplications.count + (showsNoteAction ? 1 : 0)
        case .clipboard: return filteredClipboard.count
        }
    }

    func switchMode(_ newMode: LauncherMode) {
        mode = newMode
        selectedIndex = 0
        query = ""
    }

    func moveSelection(by offset: Int) {
        guard resultCount > 0 else { return }
        selectedIndex = (selectedIndex + offset + resultCount) % resultCount
    }

    func activateSelection() {
        guard !isGraphQuery else { return }
        if let currencyResult {
            copyText(currencyResult)
            return
        }
        if let calculation {
            copyText(calculation)
            return
        }
        switch mode {
        case .apps:
            if showsNoteAction, selectedIndex == 0 {
                onOpenNote?()
                return
            }
            let applicationIndexValue = selectedIndex - (showsNoteAction ? 1 : 0)
            if filteredApplications.indices.contains(applicationIndexValue) {
                applicationIndex.launch(filteredApplications[applicationIndexValue])
            }
        case .clipboard:
            if filteredClipboard.indices.contains(selectedIndex) {
                clipboard.copy(filteredClipboard[selectedIndex])
            }
        }
    }

    func selectedClipboardItem() -> ClipboardItem? {
        guard mode == .clipboard, filteredClipboard.indices.contains(selectedIndex) else { return nil }
        return filteredClipboard[selectedIndex]
    }

    func reset(for mode: LauncherMode) {
        self.mode = mode
        query = ""
        selectedIndex = 0
        refreshQuery()
    }

    func refreshQuery() {
        selectedIndex = 0
        currencyTask?.cancel()
        currencyResult = nil
        currencyError = nil
        isConvertingCurrency = false
        graphExpression = nil
        graphError = nil

        if isGraphQuery {
            graphExpression = MathExpression(query)
            if graphExpression == nil, query.trimmingCharacters(in: .whitespacesAndNewlines).count > 2 {
                graphError = "无法解析这个函数；可以试试 y=sinx 或 y=x^2-2x"
            }
            return
        }

        guard let conversion = CurrencyQuery.parse(query) else { return }
        isConvertingCurrency = true
        currencyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                self.currencyResult = try await self.currencyConverter.convert(conversion)
            } catch {
                self.currencyError = error.localizedDescription
            }
            self.isConvertingCurrency = false
        }
    }

    var isGraphQuery: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("y=")
    }

    var hasInferredContent: Bool {
        isGraphQuery || calculation != nil || currencyResult != nil || isConvertingCurrency
    }

    var selectionIsActionable: Bool {
        !isGraphQuery && resultCount > 0
    }

    var showsNoteAction: Bool {
        mode == .apps && Self.isNoteQuery(query)
    }

    nonisolated static func isNoteQuery(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let keywords = ["笔记", "便笺", "记事", "note", "notes", "markdown", "md"]
        return keywords.contains { keyword in
            keyword.hasPrefix(normalized) || normalized.hasPrefix(keyword)
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
