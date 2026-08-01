import Darwin
import Foundation

struct MathExpression {
    let source: String
    private let root: MathNode

    init?(_ input: String) {
        var normalized = input
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "π", with: "pi")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
        guard normalized.hasPrefix("y=") else { return nil }
        normalized.removeFirst(2)
        guard !normalized.isEmpty else { return nil }

        var parser = MathParser(normalized)
        guard let root = try? parser.parse(), parser.isAtEnd else { return nil }
        self.source = normalized
        self.root = root
    }

    func evaluate(x: Double) -> Double {
        root.evaluate(x: x)
    }
}

private indirect enum MathNode {
    case number(Double)
    case variable
    case negate(MathNode)
    case add(MathNode, MathNode)
    case subtract(MathNode, MathNode)
    case multiply(MathNode, MathNode)
    case divide(MathNode, MathNode)
    case power(MathNode, MathNode)
    case function(MathFunction, MathNode)

    func evaluate(x: Double) -> Double {
        switch self {
        case .number(let value): return value
        case .variable: return x
        case .negate(let value): return -value.evaluate(x: x)
        case .add(let lhs, let rhs): return lhs.evaluate(x: x) + rhs.evaluate(x: x)
        case .subtract(let lhs, let rhs): return lhs.evaluate(x: x) - rhs.evaluate(x: x)
        case .multiply(let lhs, let rhs): return lhs.evaluate(x: x) * rhs.evaluate(x: x)
        case .divide(let lhs, let rhs): return lhs.evaluate(x: x) / rhs.evaluate(x: x)
        case .power(let lhs, let rhs): return pow(lhs.evaluate(x: x), rhs.evaluate(x: x))
        case .function(let function, let value): return function.apply(value.evaluate(x: x))
        }
    }
}

private enum MathFunction: String, CaseIterable {
    case sqrt
    case sin
    case cos
    case tan
    case abs
    case log
    case ln
    case exp

    func apply(_ value: Double) -> Double {
        switch self {
        case .sqrt: return Darwin.sqrt(value)
        case .sin: return Darwin.sin(value)
        case .cos: return Darwin.cos(value)
        case .tan: return Darwin.tan(value)
        case .abs: return Swift.abs(value)
        case .log: return Darwin.log10(value)
        case .ln: return Darwin.log(value)
        case .exp: return Darwin.exp(value)
        }
    }
}

private enum MathParseError: Error {
    case invalid
}

private struct MathParser {
    private let characters: [Character]
    private(set) var position = 0

    init(_ source: String) {
        characters = Array(source)
    }

    var isAtEnd: Bool { position == characters.count }

    mutating func parse() throws -> MathNode {
        try parseExpression()
    }

    private mutating func parseExpression() throws -> MathNode {
        var node = try parseTerm()
        while true {
            if consume("+") { node = .add(node, try parseTerm()) }
            else if consume("-") { node = .subtract(node, try parseTerm()) }
            else { return node }
        }
    }

    private mutating func parseTerm() throws -> MathNode {
        var node = try parseUnary()
        while true {
            if consume("*") {
                node = .multiply(node, try parseUnary())
            } else if consume("/") {
                node = .divide(node, try parseUnary())
            } else if startsImplicitFactor {
                node = .multiply(node, try parseUnary())
            } else {
                return node
            }
        }
    }

    private mutating func parseUnary() throws -> MathNode {
        if consume("+") { return try parseUnary() }
        if consume("-") { return .negate(try parseUnary()) }
        return try parsePower()
    }

    private mutating func parsePower() throws -> MathNode {
        let base = try parsePrimary()
        if consume("^") {
            return .power(base, try parseUnary())
        }
        return base
    }

    private mutating func parsePrimary() throws -> MathNode {
        if consume("(") {
            let node = try parseExpression()
            guard consume(")") else { throw MathParseError.invalid }
            return node
        }

        if let number = parseNumber() { return .number(number) }

        for function in MathFunction.allCases.sorted(by: { $0.rawValue.count > $1.rawValue.count }) {
            if consume(function.rawValue) {
                let argument: MathNode
                if consume("(") {
                    argument = try parseExpression()
                    guard consume(")") else { throw MathParseError.invalid }
                } else {
                    argument = try parseUnary()
                }
                return .function(function, argument)
            }
        }

        if consume("pi") { return .number(Double.pi) }
        if consume("e") { return .number(M_E) }
        if consume("x") { return .variable }
        throw MathParseError.invalid
    }

    private mutating func parseNumber() -> Double? {
        let start = position
        var hasDot = false
        while position < characters.count {
            let character = characters[position]
            if character.isNumber {
                position += 1
            } else if character == ".", !hasDot {
                hasDot = true
                position += 1
            } else {
                break
            }
        }
        guard start != position else { return nil }
        return Double(String(characters[start..<position]))
    }

    private var startsImplicitFactor: Bool {
        guard position < characters.count else { return false }
        let character = characters[position]
        if character.isNumber || character == "." || character == "(" || character == "x" { return true }
        if remainingHasPrefix("pi") || remainingHasPrefix("e") { return true }
        return MathFunction.allCases.contains { remainingHasPrefix($0.rawValue) }
    }

    private mutating func consume(_ expected: Character) -> Bool {
        guard position < characters.count, characters[position] == expected else { return false }
        position += 1
        return true
    }

    private mutating func consume(_ expected: String) -> Bool {
        guard remainingHasPrefix(expected) else { return false }
        position += expected.count
        return true
    }

    private func remainingHasPrefix(_ expected: String) -> Bool {
        guard position + expected.count <= characters.count else { return false }
        return String(characters[position..<(position + expected.count)]) == expected
    }
}
