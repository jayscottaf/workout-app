import Foundation

// Plate maths and warm-up sets. Plain rules with no app or screen code,
// so the iPhone, the Apple Watch and the unit tests all use the same file.

enum Plates {
    /// A standard Olympic bar, in pounds.
    static let barWeight: Double = 45
    /// The plates most gyms have, heaviest first.
    static let standard: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// What to load on each side of the bar to reach `total`.
    /// `leftover` is what is still missing per side when the plates cannot make the exact weight.
    struct Load: Equatable {
        var perSide: [Double]
        var leftover: Double
    }

    /// The weight of the bar (or 0 for a plate-loaded machine) when plates apply to this equipment,
    /// nil when they do not (dumbbells, weight stacks, body weight).
    static func bar(forEquipment typeID: String) -> Double? {
        switch typeID {
        case "barbell": return barWeight
        case "legPress", "hackSquat", "rowMachine": return 0
        default: return nil
        }
    }

    /// nil when the weight is lighter than the bar itself (a lighter bar is being used).
    static func load(total: Double, bar: Double = barWeight, plates: [Double] = standard) -> Load? {
        guard total > 0, total >= bar else { return nil }
        var remaining = (total - bar) / 2
        var result: [Double] = []
        for plate in plates.sorted(by: >) {
            while remaining >= plate - 0.001 {
                result.append(plate)
                remaining -= plate
            }
        }
        return Load(perSide: result, leftover: max(0, (remaining * 100).rounded() / 100))
    }

    /// "Each side: 45 + 10 + 2.5", "Just the bar", or nil when plates do not apply.
    static func text(total: Double, bar: Double = barWeight) -> String? {
        guard let load = load(total: total, bar: bar) else { return nil }
        if load.perSide.isEmpty && load.leftover == 0 { return bar > 0 ? "Just the bar" : nil }
        var parts: [String] = []
        var index = 0
        while index < load.perSide.count {
            let plate = load.perSide[index]
            var count = 0
            while index < load.perSide.count, load.perSide[index] == plate {
                count += 1
                index += 1
            }
            parts.append(count > 1 ? "\(count) × \(number(plate))" : number(plate))
        }
        if load.leftover > 0 { parts.append("\(number(load.leftover)) more") }
        return "Each side: " + parts.joined(separator: " + ")
    }

    static func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        let text = String(format: "%.2f", value)
        return text.hasSuffix("0") ? String(text.dropLast()) : text
    }
}

struct WarmUpSet: Equatable {
    var weight: Double
    var reps: Int
}

enum WarmUp {
    /// Lighter sets to do before the first working set: about half, 70% and 85% of the working weight.
    /// `bar` is the lightest weight possible (the empty bar), 0 when there is none.
    /// Nothing is suggested when the working weight is too light to need it.
    static func sets(target: Double, step: Double, bar: Double = 0) -> [WarmUpSet] {
        let step = step > 0 ? step : 5
        guard target > 0, target >= max(bar * 1.4, step * 4) else { return [] }
        var result: [WarmUpSet] = []
        for (fraction, reps) in [(0.5, 8), (0.7, 5), (0.85, 3)] {
            let weight = max(bar, ((target * fraction) / step).rounded() * step)
            guard weight > 0, weight <= target - step else { continue }
            if let last = result.last, weight <= last.weight { continue }
            result.append(WarmUpSet(weight: weight, reps: reps))
        }
        return result
    }
}
