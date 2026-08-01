import Foundation

enum CalculatorError: Error {
    case invalidExpression
    case divisionByZero
}

enum Calculator {
    static func evaluate(_ expression: String) throws -> Double {
        var parser = Parser(expression)
        let value = try parser.parseExpression()
        parser.skipWhitespace()
        guard parser.isAtEnd, value.isFinite else { throw CalculatorError.invalidExpression }
        return value
    }

    static func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        private let characters: [Character]
        private(set) var position = 0

        init(_ source: String) { characters = Array(source) }
        var isAtEnd: Bool { position >= characters.count }

        mutating func skipWhitespace() {
            while !isAtEnd && characters[position].isWhitespace { position += 1 }
        }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                skipWhitespace()
                if consume("+") { value += try parseTerm() }
                else if consume("-") { value -= try parseTerm() }
                else { return value }
            }
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parsePower()
            while true {
                skipWhitespace()
                if consume("*") { value *= try parsePower() }
                else if consume("/") {
                    let divisor = try parsePower()
                    guard divisor != 0 else { throw CalculatorError.divisionByZero }
                    value /= divisor
                } else { return value }
            }
        }

        private mutating func parsePower() throws -> Double {
            var value = try parseUnary()
            skipWhitespace()
            if consume("^") { value = Foundation.pow(value, try parsePower()) }
            return value
        }

        private mutating func parseUnary() throws -> Double {
            skipWhitespace()
            if consume("-") { return -(try parseUnary()) }
            if consume("+") { return try parseUnary() }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            if consume("(") {
                let value = try parseExpression()
                skipWhitespace()
                guard consume(")") else { throw CalculatorError.invalidExpression }
                return value
            }

            let start = position
            var hasDot = false
            while !isAtEnd {
                let character = characters[position]
                if character.isNumber { position += 1 }
                else if character == "." && !hasDot { hasDot = true; position += 1 }
                else { break }
            }
            guard start != position,
                  let value = Double(String(characters[start..<position])) else {
                throw CalculatorError.invalidExpression
            }
            return value
        }

        private mutating func consume(_ character: Character) -> Bool {
            guard !isAtEnd, characters[position] == character else { return false }
            position += 1
            return true
        }
    }
}
