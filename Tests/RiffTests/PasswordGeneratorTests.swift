import XCTest
@testable import Riff

final class PasswordGeneratorTests: XCTestCase {
    // MARK: Query parsing

    func testParsesChineseAndEnglishPasswordCommands() {
        for command in [
            "随机密码",
            "生成密码",
            "密码生成器",
            "生成随机密码",
            "random password",
            "generate password",
            "password generator",
            "pwgen",
        ] {
            XCTAssertNotNil(PasswordRequest.parse(command), command)
        }
    }

    func testParsesRequestedLength() {
        XCTAssertEqual(PasswordRequest.parse("随机密码 24")?.length, 24)
        XCTAssertEqual(PasswordRequest.parse("随机密码24")?.length, 24)
        XCTAssertEqual(PasswordRequest.parse("pwgen 32")?.length, 32)
        XCTAssertEqual(PasswordRequest.parse("生成密码 12 位")?.length, 12)
    }

    func testDefaultsToSixteenCharacters() {
        XCTAssertEqual(PasswordRequest.parse("随机密码")?.length, PasswordRequest.defaultLength)
        XCTAssertEqual(PasswordRequest.parse("pwgen")?.length, 16)
        XCTAssertEqual(PasswordRequest.defaultLength, 16)
    }

    func testClampsRequestedLengthToSupportedRange() {
        XCTAssertEqual(PasswordRequest(length: 4).length, 8)
        XCTAssertEqual(PasswordRequest(length: 300).length, 128)
        XCTAssertEqual(PasswordRequest.parse("随机密码 300")?.length, 128)
        XCTAssertEqual(PasswordRequest.parse("随机密码 4")?.length, 8)
    }

    func testDoesNotParseUnrelatedQueries() {
        XCTAssertNil(PasswordRequest.parse(""))
        XCTAssertNil(PasswordRequest.parse("密码学"))
        XCTAssertNil(PasswordRequest.parse("生成密码器"))
        XCTAssertNil(PasswordRequest.parse("random"))
        XCTAssertNil(PasswordRequest.parse("Safari"))
    }

    func testParsesNoSymbolRule() {
        XCTAssertEqual(PasswordRequest.parse("随机密码")?.includeSymbols, true)
        XCTAssertEqual(PasswordRequest.parse("随机密码 无符号")?.includeSymbols, false)
        XCTAssertEqual(PasswordRequest.parse("随机密码 不含符号")?.includeSymbols, false)
        XCTAssertEqual(PasswordRequest.parse("随机密码16无符号")?.length, 16)
        XCTAssertEqual(PasswordRequest.parse("随机密码16无符号")?.includeSymbols, false)
        XCTAssertEqual(PasswordRequest.parse("pwgen 24 nosymbols")?.length, 24)
        XCTAssertEqual(PasswordRequest.parse("pwgen 24 nosymbols")?.includeSymbols, false)
        XCTAssertEqual(PasswordRequest.parse("random password no symbols")?.includeSymbols, false)
    }

    func testQuickActionOptionsParseLengthAndRule() {
        XCTAssertEqual(PasswordRequest.parseOptions(from: "密码").length, 16)
        XCTAssertEqual(PasswordRequest.parseOptions(from: "密码").includeSymbols, true)
        XCTAssertEqual(PasswordRequest.parseOptions(from: "密码 24").length, 24)
        XCTAssertEqual(PasswordRequest.parseOptions(from: "密码 无符号").includeSymbols, false)
    }

    func testParameterTextStripsCommandsAndKeepsOptions() {
        XCTAssertEqual(PasswordRequest.parameterText(from: "随机密码"), "")
        XCTAssertEqual(PasswordRequest.parameterText(from: "随机密码 32"), "32")
        XCTAssertEqual(PasswordRequest.parameterText(from: "随机密码 24 无符号"), "24 无符号")
        XCTAssertEqual(PasswordRequest.parameterText(from: "pwgen 32"), "32")
        XCTAssertEqual(PasswordRequest.parameterText(from: "random password no symbols"), "no symbols")
        XCTAssertEqual(PasswordRequest.parameterText(from: "密码 24"), "24")
        XCTAssertEqual(PasswordRequest.parameterText(from: "pas"), "")
    }

    func testParameterTextClassification() {
        XCTAssertTrue(PasswordRequest.isParameterText("24"))
        XCTAssertTrue(PasswordRequest.isParameterText("24 无符号"))
        XCTAssertTrue(PasswordRequest.isParameterText("无符号"))
        XCTAssertTrue(PasswordRequest.isParameterText("nosymbols"))
        XCTAssertFalse(PasswordRequest.isParameterText(""))
        XCTAssertFalse(PasswordRequest.isParameterText("safari"))
    }

    // MARK: Generation

    func testGeneratesPasswordOfRequestedLength() throws {
        let generated = try PasswordGenerator.generate(PasswordRequest(length: 32))

        XCTAssertEqual(generated.length, 32)
        XCTAssertEqual(generated.value.count, 32)
    }

    func testGeneratedPasswordIncludesEveryCharacterGroup() throws {
        let generated = try PasswordGenerator.generate(PasswordRequest())
        let characters = Set(generated.value)

        XCTAssertFalse(characters.isDisjoint(with: Set("abcdefghijkmnopqrstuvwxyz")))
        XCTAssertFalse(characters.isDisjoint(with: Set("ABCDEFGHJKLMNPQRSTUVWXYZ")))
        XCTAssertFalse(characters.isDisjoint(with: Set("23456789")))
        XCTAssertFalse(characters.isDisjoint(with: Set("!@#$%^&*()-_=+[]{};:,.?")))
    }

    func testGeneratedPasswordOnlyUsesAllowedCharacters() throws {
        for _ in 0..<8 {
            let generated = try PasswordGenerator.generate(PasswordRequest(length: 64))
            XCTAssertTrue(Set(generated.value).isSubset(of: PasswordGenerator.allowedCharacters))
        }
    }

    func testNoSymbolPasswordExcludesSymbolsAndKeepsLettersAndDigits() throws {
        let symbols = Set("!@#$%^&*()-_=+[]{};:,.?")
        for _ in 0..<8 {
            let generated = try PasswordGenerator.generate(
                PasswordRequest(length: 32, includeSymbols: false)
            )
            let characters = Set(generated.value)

            XCTAssertTrue(characters.isDisjoint(with: symbols))
            XCTAssertFalse(characters.isDisjoint(with: Set("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ")))
            XCTAssertFalse(characters.isDisjoint(with: Set("23456789")))
        }
    }

    func testRegenerationProducesFreshPasswords() throws {
        let request = PasswordRequest()
        let first = try PasswordGenerator.generate(request)
        let second = try PasswordGenerator.generate(request)

        XCTAssertNotEqual(first.value, second.value)
    }
}
