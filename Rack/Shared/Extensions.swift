import Foundation

enum WeightUnit: String {
    case lbs, kg

    var symbol: String { rawValue }

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

    /// Formats the raw value with no unit conversion (underlying formatter).
    var formattedWeight: String {
        Self.weightFormatter.string(from: NSNumber(value: self)) ?? String(format: "%.0f", self)
    }

    private static let weightFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()
}
