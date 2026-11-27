import Foundation

/// One workout read from another app's export, before it is saved.
struct ImportedWorkout: Equatable {
    var title: String
    var start: Date
    var end: Date
    var exercises: [ImportedExercise]
}

struct ImportedExercise: Equatable {
    /// The name as the other app wrote it, e.g. "Bench Press (Barbell)".
    var name: String
    var sets: [ImportedSet]
}

struct ImportedSet: Equatable {
    /// Pounds, like everything saved in Next Up. 0 is body weight.
    var weight: Double
    var reps: Int
}

/// What an imported exercise name becomes in Next Up.
enum ImportMatch: Equatable {
    /// A built-in exercise.
    case builtIn(String)
    /// No good match: make your own exercise with this muscle and equipment.
    case custom(name: String, muscle: Muscle, equipmentID: String)
}

/// Reads the CSV export of Strong or Hevy.
enum Import {
    enum Source: String { case strong = "Strong", hevy = "Hevy" }

    enum Problem: Error, Equatable {
        /// The file is not a Strong or Hevy export.
        case unknownFormat
        /// It is, but no sets with reps were found.
        case empty
    }

    /// The workouts in the file, oldest first. `unit` is used when the file does not say
    /// (Strong writes weights in the unit chosen in Strong, without saying which).
    static func read(_ text: String, unit: WeightUnit = Units.current, timeZone: TimeZone = .current) throws -> (Source, [ImportedWorkout]) {
        let rows = parse(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { throw Problem.unknownFormat }
        let col = { (name: String) in header.firstIndex(of: name) }

        let source: Source
        let workoutKey: [Int], titleCol: Int, exerciseCol: Int, repsCol: Int, weightCol: Int
        var endCol: Int?, durationCol: Int?, setTypeCol: Int?, setOrderCol: Int?, unitCol: Int?
        var weightUnit = unit

        if let date = col("date"), let name = col("workout name"), let exercise = col("exercise name"),
           let reps = col("reps"), let weight = col("weight") {
            source = .strong
            workoutKey = [date, name]; titleCol = name; exerciseCol = exercise; repsCol = reps; weightCol = weight
            durationCol = col("duration"); setOrderCol = col("set order"); unitCol = col("weight unit")
        } else if let start = col("start_time"), let title = col("title"), let exercise = col("exercise_title"),
                  let reps = col("reps"), let weight = col("weight_lbs") ?? col("weight_kg") {
            source = .hevy
            workoutKey = [start, title]; titleCol = title; exerciseCol = exercise; repsCol = reps; weightCol = weight
            endCol = col("end_time"); setTypeCol = col("set_type")
            weightUnit = col("weight_lbs") != nil ? .lb : .kg
        } else {
            throw Problem.unknownFormat
        }
        let startCol = workoutKey[0]

        var order: [String] = []
        var byKey: [String: ImportedWorkout] = [:]
        for row in rows.dropFirst() {
            func value(_ i: Int?) -> String {
                guard let i, i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespaces)
            }
            // Warm-ups and Strong's rest-timer rows are not working sets.
            if let setOrderCol, Int(value(setOrderCol)) == nil, value(setOrderCol).uppercased() != "F",
               value(setOrderCol).uppercased() != "D" { continue }
            if value(setTypeCol).lowercased() == "warmup" { continue }

            let exercise = value(exerciseCol)
            let reps = Int(Double(value(repsCol)) ?? 0)
            guard !exercise.isEmpty, reps > 0, let start = date(value(startCol), timeZone: timeZone) else { continue }
            let rowUnit = WeightUnit(rawValue: value(unitCol).lowercased().replacingOccurrences(of: "lbs", with: "lb")) ?? weightUnit
            let raw = Double(value(weightCol).replacingOccurrences(of: ",", with: ".")) ?? 0
            let pounds = max(0, rowUnit == .kg ? (raw * Units.lbPerKg * 10).rounded() / 10 : raw)

            let key = workoutKey.map(value).joined(separator: "|")
            if byKey[key] == nil {
                var end = date(value(endCol), timeZone: timeZone) ?? start
                if end <= start, let minutes = durationMinutes(value(durationCol)) { end = start.addingTimeInterval(minutes * 60) }
                if end <= start { end = start.addingTimeInterval(3600) }
                let title = value(titleCol)
                byKey[key] = ImportedWorkout(title: title.isEmpty ? "Workout" : title, start: start, end: end, exercises: [])
                order.append(key)
            }
            let set = ImportedSet(weight: pounds, reps: reps)
            if let i = byKey[key]!.exercises.firstIndex(where: { $0.name == exercise }) {
                byKey[key]!.exercises[i].sets.append(set)
            } else {
                byKey[key]!.exercises.append(ImportedExercise(name: exercise, sets: [set]))
            }
        }
        let workouts = order.compactMap { byKey[$0] }.sorted { $0.start < $1.start }
        guard !workouts.isEmpty else { throw Problem.empty }
        return (source, workouts)
    }

    // MARK: matching names

    /// The built-in exercise that fits a name like "Bench Press (Barbell)", or what your own one should be.
    static func match(_ name: String) -> ImportMatch {
        let (base, hint) = split(name)
        let mine = words(base)
        let hinted = equipment(for: hint, base: base)
        let named = rawWords(name)
        var best: (score: Double, id: String)?
        for candidate in ExerciseCatalog.builtIn {
            if let hinted, !hinted.contains(candidate.equipment) { continue }
            let theirs = words(candidate.name).subtracting(equipmentWords)
            guard !theirs.isEmpty else { continue }
            let shared = Double(mine.intersection(theirs).count)
            var score = shared / Double(mine.union(theirs).count)
            // "Incline bench press" is not the flat bench press.
            if mine.intersection(modifiers) != theirs.intersection(modifiers) { score -= 0.3 }
            // "Crunch" is the plain crunch, not the cable crunch.
            if !rawWords(candidate.name).intersection(equipmentWords).isSubset(of: named) { score -= 0.1 }
            if score > (best?.score ?? 0) { best = (score, candidate.id) }
        }
        if let best, best.score > 0.5 { return .builtIn(best.id) }
        return .custom(name: tidy(name), muscle: guessMuscle(base), equipmentID: hinted?.first ?? guessEquipment(base))
    }

    /// "Bench Press (Barbell)" → ("Bench Press", "barbell").
    static func split(_ name: String) -> (String, String) {
        guard let open = name.lastIndex(of: "("), name.hasSuffix(")") else { return (name, "") }
        let hint = name[name.index(after: open)..<name.index(before: name.endIndex)]
        return (String(name[..<open]).trimmingCharacters(in: .whitespaces), hint.lowercased())
    }

    private static let equipmentWords: Set<String> = ["dumbbell", "barbell", "cable", "machine", "smith", "ez", "bar"]
    private static let modifiers: Set<String> = ["incline", "decline", "reverse", "overhead", "hammer", "preacher", "front",
                                                 "romanian", "sumo", "close", "wide", "one", "single", "calf", "rear"]
    /// Words that name the muscle rather than the movement ("Bicep Curl" is the dumbbell curl).
    private static let filler: Set<String> = ["bicep", "tricep", "the", "a", "with", "on", "seated", "standing", "lever", "bent", "over"]

    private static func rawWords(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix("s") && $0.count > 3 ? String($0.dropLast()) : $0 })
    }

    private static func words(_ text: String) -> Set<String> {
        rawWords(text).filter { !filler.contains($0) && !equipmentWords.contains($0) }
    }

    /// Equipment ids a hint like "Barbell", "Machine" or "Cable - Straight Bar" allows. nil means any.
    private static func equipment(for hint: String, base: String) -> [String]? {
        if hint.contains("smith") { return ["smith"] }
        if hint.contains("ez") { return ["ezBar"] }
        if hint.contains("dumbbell") { return ["dumbbells"] }
        if hint.contains("barbell") { return ["barbell"] }
        if hint.contains("cable") { return ["cable", "latPulldown", "seatedRow"] }
        if hint.contains("assisted") { return ["assistedPullup"] }
        if hint.contains("bodyweight") || hint.contains("weighted") {
            return [EquipmentCatalog.bodyweightID, "pullupBar", "dipStation", "backExtension"]
        }
        if hint.contains("machine") || hint.contains("plate") {
            return EquipmentCatalog.builtIn.filter { $0.category == .machine && $0.id != "cable" }.map(\.id)
        }
        return nil
    }

    private static func guessEquipment(_ base: String) -> String {
        let text = base.lowercased()
        if text.contains("dumbbell") { return "dumbbells" }
        if text.contains("barbell") { return "barbell" }
        if text.contains("cable") { return "cable" }
        return EquipmentCatalog.bodyweightID
    }

    /// The main muscle from words in the name. Chest when nothing fits.
    static func guessMuscle(_ base: String) -> Muscle {
        let text = base.lowercased()
        let rules: [(String, Muscle)] = [
            ("calf", .calves), ("calves", .calves), ("hamstring", .hamstrings), ("leg curl", .hamstrings),
            ("romanian", .hamstrings), ("glute", .glutes), ("hip thrust", .glutes), ("deadlift", .glutes),
            ("squat", .quads), ("lunge", .quads), ("leg press", .quads), ("leg extension", .quads), ("step up", .quads),
            ("crunch", .abs), ("plank", .abs), ("sit up", .abs), ("leg raise", .abs), ("ab ", .abs), ("oblique", .abs),
            ("face pull", .rearDelts), ("rear delt", .rearDelts), ("reverse fly", .rearDelts),
            ("shoulder", .delts), ("overhead press", .delts), ("lateral", .delts), ("front raise", .delts),
            ("arnold", .delts), ("shrug", .upperBack), ("upright row", .delts),
            ("tricep", .triceps), ("skull", .triceps), ("pushdown", .triceps), ("dip", .triceps), ("kickback", .triceps),
            ("curl", .biceps), ("pulldown", .lats), ("pull up", .lats), ("pull-up", .lats), ("chin", .lats), ("pullover", .lats),
            ("row", .upperBack), ("back extension", .lowerBack), ("hyperextension", .lowerBack), ("good morning", .lowerBack),
            ("bench", .chest), ("chest", .chest), ("fly", .chest), ("push up", .chest), ("push-up", .chest), ("press", .chest),
        ]
        return rules.first { text.contains($0.0) }?.1 ?? .chest
    }

    /// "Bench Press (Barbell)" → "Barbell bench press", in the app's sentence case.
    static func tidy(_ name: String) -> String {
        let (base, hint) = split(name)
        let words = (hint.isEmpty || hint.contains("other") ? base : hint + " " + base).lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: dates and CSV

    private static let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "d MMM yyyy, HH:mm", "d MMM yyyy HH:mm",
                                  "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "M/d/yyyy H:mm", "M/d/yyyy, h:mm a"]

    static func date(_ text: String, timeZone: TimeZone) -> Date? {
        guard !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// Strong writes "1h 5m", "45m" or "3900" (seconds).
    static func durationMinutes(_ text: String) -> Double? {
        if let seconds = Double(text) { return seconds > 0 ? seconds / 60 : nil }
        var minutes = 0.0, number = ""
        for c in text {
            if c.isNumber { number.append(c); continue }
            if c == "h" { minutes += (Double(number) ?? 0) * 60 } else if c == "m" { minutes += Double(number) ?? 0 }
            if c != " " { number = "" }
        }
        return minutes > 0 ? minutes : nil
    }

    /// Splits CSV text into rows of fields. Handles quoted fields, doubled quotes, and `;` files.
    static func parse(_ text: String) -> [[String]] {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let delimiter: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","

        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" {
                quoted = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
