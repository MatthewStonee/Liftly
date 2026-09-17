import Foundation
import Testing
@testable import Rack

@MainActor
struct WeightInputParsingTests {
    private let decimalPoint = WeightInput(unit: .lbs, locale: Locale(identifier: "en_US"))
    private let decimalComma = WeightInput(unit: .lbs, locale: Locale(identifier: "de_DE"))

    @Test func acceptsDecimalsWithTheLocaleSeparator() {
        #expect(decimalPoint.pounds(from: "102.5") == .success(102.5))
        #expect(decimalComma.pounds(from: "102,5") == .success(102.5))
        #expect(decimalPoint.pounds(from: "135") == .success(135))
        #expect(decimalPoint.pounds(from: ".5") == .success(0.5))
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(decimalPoint.pounds(from: "  102.5\n") == .success(102.5))
        #expect(decimalComma.pounds(from: "\t102,5 ") == .success(102.5))
    }

    @Test func treatsBlankTextAsNoValue() {
        #expect(decimalPoint.pounds(from: "") == .success(nil))
        #expect(decimalComma.pounds(from: "   ") == .success(nil))
    }

    @Test func acceptsExplicitZero() {
        #expect(decimalPoint.pounds(from: "0") == .success(0))
        #expect(decimalComma.pounds(from: "0,0") == .success(0))
    }

    @Test(arguments: ["1,000", "1,000.5", "1.000,5", "1 000", "102,5"])
    func rejectsGroupingAndMixedSeparatorsWithDecimalPoint(text: String) {
        #expect(decimalPoint.pounds(from: text) == .failure(.malformed))
    }

    @Test(arguments: ["1.000", "1.000,5", "102.5", "1,000.5"])
    func rejectsGroupingAndMixedSeparatorsWithDecimalComma(text: String) {
        #expect(decimalComma.pounds(from: text) == .failure(.malformed))
    }

    @Test(arguments: [
        "abc", "12abc", "1.2.3", "5.", ".", "-", "+5", "1e3", "0x10",
        "nan", "NaN", "inf", "-inf", "Infinity", "5 5", "\u{00BD}"
    ])
    func rejectsMalformedText(text: String) {
        #expect(decimalPoint.pounds(from: text) == .failure(.malformed))
    }

    @Test(arguments: ["-5", "-0.5", "-0", "\u{2212}5"])
    func rejectsNegativeValues(text: String) {
        #expect(decimalPoint.pounds(from: text) == .failure(.negative))
    }

    @Test func rejectsValuesThatOverflow() {
        let hugeValue = String(repeating: "9", count: 400)
        #expect(decimalPoint.pounds(from: hugeValue) == .failure(.outOfRange))

        // Finite in kilograms, but not once converted to pounds.
        let kilograms = WeightInput(unit: .kg, locale: Locale(identifier: "en_US"))
        let nearMaximum = "1" + String(repeating: "0", count: 308)
        #expect(kilograms.pounds(from: nearMaximum) == .failure(.outOfRange))
    }

    @Test func convertsKilogramsToStoredPounds() {
        let kilograms = WeightInput(unit: .kg, locale: Locale(identifier: "de_DE"))
        #expect(kilograms.pounds(from: "45,5") == .success(WeightUnit.kg.store(45.5)))
    }

    @Test func acceptsNonLatinDecimalDigits() {
        let input = WeightInput(unit: .lbs, locale: Locale(identifier: "ar_EG"))
        let text = "\u{0661}\u{0660}\u{0662}\(input.decimalSeparator)\u{0665}"
        #expect(input.pounds(from: text) == .success(102.5))
    }

    @Test(arguments: ["en_US", "de_DE", "fr_FR", "pt_BR", "hi_IN", "ar_EG"])
    func formattedTextParsesInTheSameLocale(localeIdentifier: String) throws {
        for unit in [WeightUnit.lbs, .kg] {
            let input = WeightInput(unit: unit, locale: Locale(identifier: localeIdentifier))
            for pounds in [0, 2.5, 100, 12_345.5] {
                let text = input.text(forPounds: pounds)
                let parsed = try #require(try input.pounds(from: text).get(), "\(text)")
                #expect(abs(unit.display(parsed) - unit.display(pounds)) < 0.01, "\(text)")
            }
        }
    }

    @Test func formatsWithoutGroupingSeparators() {
        #expect(decimalPoint.text(forPounds: 12_345.5) == "12345.5")
        #expect(decimalComma.text(forPounds: 12_345.5) == "12345,5")
    }

    @Test func malformedMessageUsesTheLocaleSeparator() {
        #expect(decimalPoint.message(for: .malformed) == "Enter a number like 102.5.")
        #expect(decimalComma.message(for: .malformed) == "Enter a number like 102,5.")
    }
}

@MainActor
struct WeightDraftTests {
    private let kilograms = WeightInput(unit: .kg, locale: Locale(identifier: "en_US"))

    @Test func unchangedTextKeepsTheExactStoredPounds() {
        let draft = WeightDraft(input: kilograms, pounds: 100)

        #expect(draft.text == "45.36")
        // Parsing the rounded display text again would change the stored value.
        #expect(WeightUnit.kg.store(45.36) != 100)
        #expect(draft.resolvedPounds(whenBlank: .required) == .success(100))
    }

    @Test func whitespaceOnlyChangesCountAsUnchanged() {
        var draft = WeightDraft(input: kilograms, pounds: 100)
        draft.text = "  45.36 "
        #expect(draft.resolvedPounds(whenBlank: .required) == .success(100))
    }

    @Test func restoringTheInitialTextKeepsTheExactStoredPounds() {
        var draft = WeightDraft(input: kilograms, pounds: 100)

        draft.text = "50"
        #expect(draft.resolvedPounds(whenBlank: .required) == .success(WeightUnit.kg.store(50)))

        draft.text = "45.36"
        #expect(draft.resolvedPounds(whenBlank: .required) == .success(100))
    }

    @Test func decimalCommaDraftKeepsTheExactStoredPounds() {
        let draft = WeightDraft(input: WeightInput(unit: .kg, locale: Locale(identifier: "de_DE")), pounds: 100)

        #expect(draft.text == "45,36")
        #expect(draft.resolvedPounds(whenBlank: .required) == .success(100))
    }

    @Test func historicalValuesAreKeptWithoutRepair() {
        let historicalPounds = WeightUnit.kg.store(45.36)
        let draft = WeightDraft(input: kilograms, pounds: historicalPounds)
        #expect(draft.resolvedPounds(whenBlank: .required) == .success(historicalPounds))
    }

    @Test func blankMeaningDependsOnTheForm() {
        let empty = WeightDraft(input: kilograms, pounds: nil)

        #expect(empty.resolvedPounds(whenBlank: .zero) == .success(0))
        #expect(empty.resolvedPounds(whenBlank: .noWeight) == .success(nil))
        #expect(empty.resolvedPounds(whenBlank: .required) == .failure(.missing))
    }

    @Test func clearingATargetRemovesIt() {
        var draft = WeightDraft(input: kilograms, pounds: 100)
        draft.text = ""

        #expect(draft.resolvedPounds(whenBlank: .noWeight) == .success(nil))
        #expect(draft.resolvedPounds(whenBlank: .required) == .failure(.missing))
    }

    @Test func bodyweightZeroStartsBlankAndStaysZero() {
        let draft = WeightDraft(input: kilograms, pounds: 0, blankWhenZero: true)

        #expect(draft.text.isEmpty)
        #expect(draft.resolvedPounds(whenBlank: .zero) == .success(0))
    }

    @Test func explicitZeroIsAccepted() {
        var draft = WeightDraft(input: kilograms, pounds: nil)
        draft.text = "0"
        #expect(draft.resolvedPounds(whenBlank: .required) == .success(0))
    }

    @Test func invalidTextIsNeverReadAsZeroOrNoWeight() {
        var draft = WeightDraft(input: kilograms, pounds: 100)
        draft.text = "45,5"

        #expect(draft.resolvedPounds(whenBlank: .zero) == .failure(.malformed))
        #expect(draft.resolvedPounds(whenBlank: .noWeight) == .failure(.malformed))
    }

    @Test func blankRequiredFieldsAreFlaggedOnlyAfterEditing() {
        var empty = WeightDraft(input: kilograms, pounds: nil)
        #expect(empty.validationMessage(whenBlank: .required) == nil)

        empty.text = "abc"
        #expect(empty.validationMessage(whenBlank: .required) == "Enter a number like 102.5.")

        var cleared = WeightDraft(input: kilograms, pounds: 100)
        cleared.text = ""
        #expect(cleared.validationMessage(whenBlank: .required) == "Enter a weight.")
        #expect(cleared.validationMessage(whenBlank: .noWeight) == nil)
    }
}
