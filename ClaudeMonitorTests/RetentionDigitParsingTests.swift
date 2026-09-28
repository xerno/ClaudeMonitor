import Foundation
import Testing
@testable import ClaudeMonitor

/// `isDecimalDigit` (keystroke guard) and `parsedYears` (commit) must agree: `NSTextField.integerValue`
/// reads ASCII only, so `٩٩` would otherwise commit as 0 and clamp to a stored 1.
@Suite struct RetentionDigitParsingTests {
    // MARK: - isDecimalDigit

    @Test(arguments: ["0", "5", "9", "٠", "٥", "٩", "०", "५", "९", "๐", "๙", "５", "𝟿"])
    func decimalDigitsFromAnyNumberingSystemAreAccepted(character: String) {
        let scalar = Character(character)
        #expect(RetentionDisplay.isDecimalDigit(scalar))
    }

    /// Roman numerals and vulgar fractions are `isNumber` but not decimal digits: accepting them
    /// would let the guard admit text `parsedYears` rejects.
    @Test(arguments: ["a", "Z", " ", "-", ".", ",", "+", "½", "Ⅳ", "①"])
    func nonDecimalCharactersAreRejected(character: String) {
        let scalar = Character(character)
        #expect(!RetentionDisplay.isDecimalDigit(scalar))
    }

    @Test func multiScalarGraphemeIsRejected() {
        #expect(!RetentionDisplay.isDecimalDigit("7\u{FE0F}"))
        #expect(!RetentionDisplay.isDecimalDigit("👍"))
    }

    // MARK: - parsedYears

    @Test func parsesASCIIDigits() {
        #expect(RetentionDisplay.parsedYears(fromFieldText: "0") == 0)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "00") == 0)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "1") == 1)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "42") == 42)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "99") == 99)
    }

    @Test func parsesNonASCIIDecimalDigits() {
        #expect(RetentionDisplay.parsedYears(fromFieldText: "٩٩") == 99)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "٤٢") == 42)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "९९") == 99)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "๙") == 9)
    }

    @Test func nonASCIIParseAgreesWithASCIIForEveryValueInRange() {
        let arabicIndic = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        for value in 0...99 {
            let ascii = String(value)
            let translated = String(ascii.map { character in
                Character(arabicIndic[character.wholeNumberValue!])
            })
            #expect(RetentionDisplay.parsedYears(fromFieldText: translated)
                    == RetentionDisplay.parsedYears(fromFieldText: ascii))
        }
    }

    @Test func returnsNilRatherThanZeroForEmptyOrNonDigitText() {
        #expect(RetentionDisplay.parsedYears(fromFieldText: "") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "abc") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "1a") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "a1") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: " 1") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "1 ") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "-1") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "1.5") == nil)
    }

    /// A parser returning 0 for `"abc"` would pass garbage off as a deliberate zero.
    @Test func emptyAndNonDigitAreNilWhileLiteralZeroParses() {
        #expect(RetentionDisplay.parsedYears(fromFieldText: "") == nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "0") != nil)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "0") == 0)
    }

    // MARK: - Composition with the clamp

    @Test func commitRuleAppliesEqualPerNumberingSystem() {
        func committed(_ text: String) -> Int {
            RetentionDisplay.clampedYears(RetentionDisplay.parsedYears(fromFieldText: text) ?? 0)
        }
        #expect(committed("0") == Constants.History.minRetentionYears)
        #expect(committed("00") == Constants.History.minRetentionYears)
        #expect(committed("") == Constants.History.minRetentionYears)
        #expect(committed("٠") == Constants.History.minRetentionYears)
        #expect(committed("99") == 99)
        #expect(committed("٩٩") == 99)
    }
}
