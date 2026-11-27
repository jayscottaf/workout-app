import Foundation

/// Pounds or kilograms, chosen in Settings.
///
/// Every weight is still saved in pounds, so history never changes when you switch.
/// Only what is shown and typed changes, and the weight steps move to a kilogram grid
/// (1.25, 2.5 and 5 kg) so suggestions land on real kilogram weights.
enum WeightUnit: String, CaseIterable, Codable {
    case lb, kg

    var symbol: String { rawValue }
    var spoken: String { self == .kg ? "kilograms" : "pounds" }
}

enum Units {
    static let key = "weightUnit"
    static let lbPerKg = 2.204_622_621_8

    static var current: WeightUnit {
        get { WeightUnit(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .lb }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static var isKg: Bool { current == .kg }
    static var symbol: String { current.symbol }
    static var spoken: String { current.spoken }

    /// A saved weight (pounds) in the unit shown.
    static func shown(_ pounds: Double, in unit: WeightUnit = current) -> Double {
        unit == .kg ? pounds / lbPerKg : pounds
    }

    /// A weight in the unit shown, back to pounds for saving.
    static func pounds(_ value: Double, from unit: WeightUnit = current) -> Double {
        unit == .kg ? value * lbPerKg : value
    }

    /// "120", "122.5"; in kilograms also "61.25" for a real plate step, else one decimal ("61.2").
    static func number(_ pounds: Double, in unit: WeightUnit = current) -> String {
        let value = shown(pounds, in: unit)
        if unit == .kg {
            let quarter = (value * 4).rounded() / 4
            if abs(value - quarter) < 0.01 { return trimmed(quarter) }
        }
        let tenth = (value * 10).rounded() / 10
        return trimmed(tenth)
    }

    /// The weight step for a built-in piece of equipment whose pound step is `pounds`
    /// (2.5, 5 or 10 lb become 1.25, 2.5 or 5 kg).
    static func step(_ pounds: Double, in unit: WeightUnit = current) -> Double {
        unit == .kg ? pounds / 2 * lbPerKg : pounds
    }

    /// A saved step moved to the other unit's grid when you switch (5 lb ↔ 2.5 kg).
    static func convertStep(_ saved: Double, from old: WeightUnit, to new: WeightUnit) -> Double {
        guard old != new else { return saved }
        return new == .kg ? saved / 2 * lbPerKg : ((saved / lbPerKg * 2) * 100).rounded() / 100
    }

    /// The steps offered in a workout and when adding a machine, in pounds.
    static func stepChoices(in unit: WeightUnit = current) -> [Double] {
        [2.5, 5, 10].map { step($0, in: unit) }
    }

    private static func trimmed(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
