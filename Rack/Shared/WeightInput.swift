import Foundation

/// Why weight text couldn't be accepted.
enum WeightInputError: Error, Equatable {
    /// The field is blank, but this form needs a weight.
    case missing
    /// The text isn't a complete, ungrouped decimal in the form's locale.
    case malformed
    case negative
    /// The value isn't a finite number once converted to pounds.
    case outOfRange
}

/// Parses and formats weights typed in a form's display unit and locale.
///
/// Accepts a complete, ungrouped decimal that uses the locale's decimal separator,
/// such as "102.5" in en_US or "102,5" in de_DE. Grouping separators, mixed
/// separators, signs, exponents, and any other characters are rejected instead of
/// being read as zero.
struct WeightInput: Equatable {
    let unit: WeightUnit
    let locale: Locale

    private static let minusSigns: Set<Character> = ["-", "\u{2212}", "\u{FE63}", "\u{FF0D}"]

    var decimalSeparator: Character {
        locale.decimalSeparator?.first ?? "."
    }

    /// Returns the value to store, in pounds, or `nil` when the text is blank.
    func pounds(from text: String) -> Result<Double?, WeightInputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }

        var remainder = Substring(trimmed)
        let isNegative = remainder.first.map { Self.minusSigns.contains($0) } ?? false
        if isNegative {
            remainder = remainder.dropFirst()
        }

        var integerDigits = ""
        var fractionDigits: String?
        for character in remainder {
            if let digit = Self.asciiDigit(for: character) {
                if fractionDigits == nil {
                    integerDigits.append(digit)
                } else {
                    fractionDigits?.append(digit)
                }
            } else if character == decimalSeparator, fractionDigits == nil {
                fractionDigits = ""
            } else {
                return .failure(.malformed)
            }
        }

        // Require at least one digit, and a digit after any decimal separator.
        let hasDigits = !integerDigits.isEmpty || !(fractionDigits ?? "").isEmpty
        guard hasDigits, fractionDigits?.isEmpty != true else {
            return .failure(.malformed)
        }
        guard !isNegative else { return .failure(.negative) }

        var decimalText = integerDigits.isEmpty ? "0" : integerDigits
        if let fractionDigits {
            decimalText += "." + fractionDigits
        }

        guard let displayValue = Double(decimalText), displayValue.isFinite else {
            return .failure(.outOfRange)
        }
        let pounds = unit.store(displayValue)
        guard pounds.isFinite else { return .failure(.outOfRange) }
        return .success(pounds)
    }

    /// Formats a stored pounds value in this unit and locale, without grouping.
    func text(forPounds pounds: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let displayValue = unit.display(pounds)
        return formatter.string(from: NSNumber(value: displayValue)) ?? String(displayValue)
    }

    func message(for error: WeightInputError) -> String {
        switch error {
        case .missing:
            return "Enter a weight."
        case .malformed:
            return "Enter a number like 102\(decimalSeparator)5."
        case .negative:
            return "Weight can't be negative."
        case .outOfRange:
            return "That weight is too large."
        }
    }

    /// Maps any Unicode decimal digit (such as Arabic-Indic digits) to its ASCII digit.
    private static func asciiDigit(for character: Character) -> Character? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.properties.numericType == .decimal,
              let numericValue = scalar.properties.numericValue,
              let digit = Int(exactly: numericValue),
              (0...9).contains(digit) else {
            return nil
        }
        return Character(String(digit))
    }
}

/// A weight being edited in a form, tied to the stored value it started from.
///
/// If the submitted text still matches the text the form opened with, the original
/// pounds value is reused exactly. Saving a form without touching its weight therefore
/// never rewrites that weight through a rounded display value.
struct WeightDraft: Equatable {
    /// What a blank field means for a form.
    enum BlankValue {
        /// Blank means zero, as for bodyweight sets.
        case zero
        /// Blank means no weight, as for an optional target.
        case noWeight
        /// Blank isn't allowed.
        case required
    }

    let input: WeightInput
    var text: String
    private let initialText: String
    private let initialPounds: Double?

    /// - Parameters:
    ///   - pounds: The stored value the form starts from, or `nil` for an empty field.
    ///   - blankWhenZero: Shows a stored zero as an empty field.
    init(input: WeightInput, pounds: Double?, blankWhenZero: Bool = false) {
        let text: String
        if let pounds, !(blankWhenZero && pounds == 0) {
            text = input.text(forPounds: pounds)
        } else {
            text = ""
        }

        self.input = input
        self.text = text
        initialText = text
        initialPounds = pounds
    }

    /// The pounds value to submit, or why the current text can't be submitted.
    func resolvedPounds(whenBlank blankValue: BlankValue) -> Result<Double?, WeightInputError> {
        if let initialPounds, isUnchanged {
            return .success(initialPounds)
        }

        switch input.pounds(from: text) {
        case .success(let pounds?):
            return .success(pounds)
        case .success(nil):
            switch blankValue {
            case .zero:
                return .success(0)
            case .noWeight:
                return .success(nil)
            case .required:
                return .failure(.missing)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    /// An inline message for the current text. A blank required field is only flagged
    /// after the user changes it, since the submit action is already unavailable.
    func validationMessage(whenBlank blankValue: BlankValue) -> String? {
        guard case .failure(let error) = resolvedPounds(whenBlank: blankValue) else { return nil }
        if error == .missing && isUnchanged {
            return nil
        }
        return input.message(for: error)
    }

    private var isUnchanged: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            == initialText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
