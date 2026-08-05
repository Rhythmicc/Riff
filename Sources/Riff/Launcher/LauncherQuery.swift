import Foundation

enum LauncherQueryIntent {
    case calculation(String)
    case currency(CurrencyQuery)
    case graph(expression: MathExpression?, error: String?)
    case unicode(UnicodeSearchQuery)
    case password(PasswordRequest)
    /// Search-like query: apps, quick actions, and system operations compete
    /// in one pool instead of one category pre-empting the others.
    case search
}

enum LauncherQueryClassifier {
    static func classify(_ query: String) -> LauncherQueryIntent {
        if MathExpression.isFunctionCandidate(query) {
            let expression = MathExpression(query)
            let error = expression == nil && query.trimmingCharacters(in: .whitespacesAndNewlines).count > 2
                ? "无法解析这个函数；可以试试 f(x)=sinx、z=x+1 或 x^2=y"
                : nil
            return .graph(expression: expression, error: error)
        }

        if let unicodeQuery = UnicodeSearchQuery.parse(query) {
            return .unicode(unicodeQuery)
        }

        if let passwordRequest = PasswordRequest.parse(query) {
            return .password(passwordRequest)
        }

        if let calculation = calculation(for: query) {
            return .calculation(calculation)
        }

        if let conversion = CurrencyQuery.parse(query) {
            return .currency(conversion)
        }

        return .search
    }

    static func calculation(for query: String) -> String? {
        let source = query.hasPrefix("=") ? String(query.dropFirst()) : query
        guard source.rangeOfCharacter(from: .decimalDigits) != nil,
              source.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^()")) != nil,
              let result = try? Calculator.evaluate(source) else { return nil }
        return Calculator.formatted(result)
    }
}

enum LauncherContent {
    case idle
    case fallback(query: String, actions: [LauncherFallbackAction])
    case aiAnswer(
        provider: AIProvider,
        model: String,
        result: String,
        error: String?,
        isLoading: Bool
    )
    case search(
        items: [LauncherSearchItem],
        hasMore: Bool,
        isSearching: Bool
    )
    case clipboard([ClipboardItem])
    case calculation(String)
    case currency(result: String?, error: String?, isLoading: Bool)
    case graph(
        expression: MathExpression?,
        plot: FunctionPlotData?,
        error: String?,
        isLoading: Bool
    )
    case unicode(query: UnicodeSearchQuery, items: [UnicodeSymbol], isSearching: Bool)
    case password(request: PasswordRequest, result: GeneratedPassword?, error: String?)
    case component(
        componentID: String,
        query: String,
        results: [ComponentResultItem],
        isLoading: Bool
    )

    var presentationKind: LauncherContentKind {
        switch self {
        case .idle: return .idle
        case .fallback: return .fallback
        case .aiAnswer: return .aiAnswer
        case .search: return .search
        case .clipboard: return .clipboard
        case .calculation: return .calculation
        case .currency: return .currency
        case .graph: return .graph
        case .unicode: return .unicode
        case .password: return .password
        case .component: return .component
        }
    }

    var isSettledForExperienceMetrics: Bool {
        switch self {
        case .idle: return false
        case .search(_, _, let isSearching): return !isSearching
        case .currency(_, _, let isLoading): return !isLoading
        case .graph(_, _, _, let isLoading): return !isLoading
        case .unicode(_, _, let isSearching): return !isSearching
        case .aiAnswer(_, _, _, _, let isLoading): return !isLoading
        case .component(_, _, _, let isLoading): return !isLoading
        case .fallback, .clipboard, .calculation, .password: return true
        }
    }

    var producedResultsForExperienceMetrics: Bool {
        switch self {
        case .idle: return false
        case .fallback(_, let actions): return !actions.isEmpty
        case .aiAnswer(_, _, let result, let error, _): return !result.isEmpty || error != nil
        case .search(let items, _, _): return !items.isEmpty
        case .clipboard(let items): return !items.isEmpty
        case .calculation: return true
        case .currency(let result, let error, _): return result != nil || error != nil
        case .graph(let expression, _, let error, _): return expression != nil || error != nil
        case .unicode(_, let items, _): return !items.isEmpty
        case .password(_, let result, let error): return result != nil || error != nil
        case .component(_, _, let results, _): return !results.isEmpty
        }
    }
}

enum LauncherContentKind: Hashable {
    case idle
    case fallback
    case aiAnswer
    case search
    case clipboard
    case calculation
    case currency
    case graph
    case unicode
    case password
    case component
}

struct LauncherState {
    var query = ""
    var mode: LauncherMode = .apps
    var selectedIndex = 0
    var content: LauncherContent = .idle
}
