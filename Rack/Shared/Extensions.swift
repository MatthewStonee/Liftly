import Foundation

enum PlannedRepTargetDefaults {
    static let exactReps = 8
    static let rangeLowerBound = 8
    static let rangeUpperBound = 12
}

enum WeightUnit: String {
    case lbs, kg

    var symbol: String { rawValue }

    /// The unit's name for VoiceOver, which would read the symbol "lbs" letter by letter.
    var spokenName: String { self == .kg ? "kilograms" : "pounds" }

    /// Convert a value stored in lbs to the display unit.
    func display(_ lbs: Double) -> Double {
        self == .kg ? lbs * 0.453592 : lbs
    }

    /// Convert a value entered in the display unit back to lbs for storage.
    func store(_ displayValue: Double) -> Double {
        self == .kg ? displayValue / 0.453592 : displayValue
    }
}

extension Double {
    /// Formats a weight value for display in the given unit, converting from lbs.
    /// Whole numbers show no decimal (e.g. 45.0 → "45").
    /// Fractional values show up to 2 decimal places (e.g. 2.5 → "2.5").
    func formattedWeight(unit: WeightUnit) -> String {
        let converted = unit.display(self)
        return Self.weightFormatter.string(from: NSNumber(value: converted))
            ?? String(format: "%.0f", converted)
    }

    private static let weightFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()
}

extension LoggedSet {
    /// How VoiceOver reads a set, such as "Sep 12, 225 pounds, 5 reps".
    func spokenSummary(unit: WeightUnit, dateStyle: Date.FormatStyle) -> String {
        let weightText = weight == 0
            ? "Bodyweight"
            : "\(weight.formattedWeight(unit: unit)) \(unit.spokenName)"
        return "\(completedAt.formatted(dateStyle)), \(weightText), \(reps) \(reps == 1 ? "rep" : "reps")"
    }
}

extension PlannedExercise {
    var formattedRepTarget: String {
        switch repTargetType {
        case .exact:
            return "\(exactRepTarget) reps"
        case .range:
            let repRange = repRange
            return "\(repRange.lowerBound)-\(repRange.upperBound) reps"
        case .failure:
            return "Failure"
        }
    }
}
