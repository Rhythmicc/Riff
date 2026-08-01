import XCTest
@testable import PersonalLauncher

final class CalculatorTests: XCTestCase {
    func testOperatorPrecedenceAndParentheses() throws {
        XCTAssertEqual(try Calculator.evaluate("12 * (8 + 2)"), 120)
        XCTAssertEqual(try Calculator.evaluate("2 + 3 * 4"), 14)
    }

    func testPowerIsRightAssociative() throws {
        XCTAssertEqual(try Calculator.evaluate("2 ^ 3 ^ 2"), 512)
    }

    func testDivisionByZeroFails() {
        XCTAssertThrowsError(try Calculator.evaluate("10 / 0"))
    }

    func testCurrencyQueryParsing() {
        XCTAssertEqual(
            CurrencyQuery.parse("100 usd to cny"),
            CurrencyQuery(amount: 100, source: "USD", target: "CNY")
        )
        XCTAssertEqual(
            CurrencyQuery.parse("25.5 EUR GBP"),
            CurrencyQuery(amount: 25.5, source: "EUR", target: "GBP")
        )
    }
}

final class DoubleTapDetectorTests: XCTestCase {
    func testTriggersInsideThreshold() {
        var detector = DoubleTapDetector(maximumInterval: 0.36)
        XCTAssertFalse(detector.registerTap(at: 1.0))
        XCTAssertTrue(detector.registerTap(at: 1.3))
        XCTAssertFalse(detector.registerTap(at: 1.5))
    }

    func testDoesNotTriggerWhenTooSlow() {
        var detector = DoubleTapDetector(maximumInterval: 0.36)
        XCTAssertFalse(detector.registerTap(at: 2.0))
        XCTAssertFalse(detector.registerTap(at: 2.5))
    }

    func testResetCancelsPendingTap() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(detector.registerTap(at: 3.0))
        detector.reset()
        XCTAssertFalse(detector.registerTap(at: 3.1))
    }
}

final class MathExpressionTests: XCTestCase {
    func testFunctionWithoutParentheses() throws {
        let expression = try XCTUnwrap(MathExpression("y=sinx"))
        XCTAssertEqual(expression.evaluate(x: .pi / 2), 1, accuracy: 0.000_001)
    }

    func testImplicitMultiplicationAndPower() throws {
        let expression = try XCTUnwrap(MathExpression("y=2x^2 + 3x - 1"))
        XCTAssertEqual(expression.evaluate(x: 2), 13, accuracy: 0.000_001)
    }

    func testConstantsAndNestedFunctions() throws {
        let expression = try XCTUnwrap(MathExpression("y=sqrt(abs(x))+cos(pi)"))
        XCTAssertEqual(expression.evaluate(x: -9), 2, accuracy: 0.000_001)
    }

    func testInvalidExpressionFails() {
        XCTAssertNil(MathExpression("y=sin("))
        XCTAssertNil(MathExpression("sinx"))
    }
}
