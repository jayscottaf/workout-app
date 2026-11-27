import Foundation

/// One finished set, flattened for the spreadsheet export.
struct ExportSet: Equatable {
    var date: Date
    var workout: String
    var gym: String
    var exercise: String
    /// "Chest", "Mid back", ...
    var muscle: String
    var compound: Bool
    var equipment: String
    /// 1 for the first set of that exercise in that workout.
    var setNumber: Int
    /// Pounds, as saved. 0 is body weight.
    var weight: Double
    var reps: Int
    var pr: PRKind?
}

/// Your workout history as a CSV file that opens in Numbers, Excel or Google Sheets.
enum Export {
    static func header(_ unit: WeightUnit) -> [String] {
        ["Date", "Workout", "Gym", "Exercise", "Muscle", "Compound", "Equipment",
         "Set", "Weight (\(unit.symbol))", "Reps", "Volume (\(unit.symbol))", "Personal record"]
    }

    /// One row per set, oldest first, weights in `unit`. Dates are written as "2026-11-27 18:05" in `timeZone`.
    static func csv(_ sets: [ExportSet], unit: WeightUnit = Units.current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let rows = sets.sorted { ($0.date, $0.exercise, $0.setNumber) < ($1.date, $1.exercise, $1.setNumber) }.map { set in
            [formatter.string(from: set.date), set.workout, set.gym, set.exercise, set.muscle,
             set.compound ? "Yes" : "No", set.equipment, String(set.setNumber),
             set.weight > 0 ? Units.number(set.weight, in: unit) : "Body weight", String(set.reps),
             Units.number(set.weight * Double(set.reps), in: unit), set.pr.map(prText) ?? ""]
        }
        // CRLF line endings are what spreadsheet apps expect.
        return ([header(unit)] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// "Next Up workouts 2026-11-27.csv"
    static func fileName(on date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "Next Up workouts \(formatter.string(from: date)).csv"
    }

    private static func prText(_ kind: PRKind) -> String {
        switch kind {
        case .weight: return "Heaviest weight"
        case .reps: return "Most reps"
        case .strength: return "Best estimated strength"
        }
    }

    /// Quotes a value when it holds a comma, quote or line break. A name you typed that starts
    /// with = + - or @ gets a leading apostrophe so a spreadsheet shows it as text, not a formula.
    static func field(_ value: String) -> String {
        var v = value
        if let first = v.first, "=+-@".contains(first) { v = "'" + v }
        guard v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return v }
        return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
