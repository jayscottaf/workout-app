import Foundation

/// Finds exercises as you type, forgiving typos and shorthand:
/// "dumbell" finds dumbbell exercises, "lat pull down" finds Lat pulldown, "db press" and "ohp" work too.
enum ExerciseSearch {
    /// Exercises that match every word of `query`, best match first. An empty query returns nothing.
    static func matches(_ query: String, in exercises: [ExerciseDef]) -> [ExerciseDef] {
        let words = tokens(expand(query))
        guard !words.isEmpty else { return [] }
        let compactQuery = compact(expand(query))
        return exercises
            .compactMap { exercise -> (Double, ExerciseDef)? in
                score(words, compactQuery: compactQuery, exercise).map { ($0, exercise) }
            }
            // Equal scores: the closest name first ("Lat pulldown" before "Close-grip lat pulldown").
            .sorted {
                if $0.0 != $1.0 { return $0.0 > $1.0 }
                if $0.1.name.count != $1.1.name.count { return $0.1.name.count < $1.1.name.count }
                return $0.1.name < $1.1.name
            }
            .map(\.1)
    }

    /// nil when some word matches nothing.
    static func score(_ words: [String], compactQuery: String, _ exercise: ExerciseDef) -> Double? {
        let name = tokens(exercise.name)
        let extra = tokens("\(exercise.muscle.title) \(exercise.muscle.group.title) \(exercise.equipmentType.name)")
        // Words typed together or apart: "pulldown" / "pull down", "pullup" / "pull-up".
        if compactQuery.count >= 4, compact(exercise.name).contains(compactQuery) {
            return 10 + (compact(exercise.name).hasPrefix(compactQuery) ? 2 : 0)
        }
        var total = 0.0
        for word in words {
            let best = max(wordScore(word, in: name), wordScore(word, in: extra) * 0.6)
            guard best > 0 else { return nil }
            total += best
        }
        // Prefer names that start with what you typed.
        if let first = name.first, let typed = words.first, first.hasPrefix(typed) { total += 0.5 }
        return total
    }

    /// 1 for a whole word or the start of one, 0.8 for a close spelling, else 0.
    private static func wordScore(_ word: String, in candidates: [String]) -> Double {
        var best = 0.0
        for candidate in candidates {
            if candidate == word || candidate.hasPrefix(word) { return 1 }
            let allowed = word.count >= 7 ? 2 : word.count >= 4 ? 1 : 0
            if allowed > 0 {
                let prefix = String(candidate.prefix(word.count + 1))
                if distance(word, candidate) <= allowed || distance(word, prefix) <= allowed
                    || distance(word, String(candidate.prefix(word.count))) <= allowed { best = max(best, 0.8) }
            }
        }
        return best
    }

    /// Shorthand gym-goers type, spelled out.
    private static let shorthand: [String: String] = [
        "db": "dumbbell", "dbs": "dumbbell", "bb": "barbell", "ohp": "overhead press", "rdl": "romanian deadlift",
        "rdls": "romanian deadlift", "tri": "triceps", "tris": "triceps", "bi": "biceps", "bis": "biceps",
        "ez": "ez-bar", "lats": "lat", "pec": "pec", "delts": "delts", "quad": "quads", "ham": "hamstrings",
        "hams": "hamstrings", "ab": "abs", "chinup": "pull-up", "chin": "pull-up",
    ]

    private static func expand(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0 == " " }).map { shorthand[String($0)] ?? String($0) }.joined(separator: " ")
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.count > 3 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }
    }

    private static func compact(_ text: String) -> String {
        tokens(text).joined()
    }

    /// Edit distance (insert, delete, change, or swap two neighbouring letters).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }
}
