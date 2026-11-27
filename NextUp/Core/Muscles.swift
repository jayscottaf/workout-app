import Foundation

// Which muscles a workout works, which ones the week has missed, and when two exercises
// in one workout do the same job.

/// Sets for one muscle: as the main target, and as a helper (secondary muscle).
struct MuscleWork: Equatable {
    var muscle: Muscle
    var mainSets: Int
    var helperSets: Int
}

/// A muscle with no main sets yet this week, and something to train it with here.
struct MissedMuscle {
    var muscle: Muscle
    /// Set when the muscle was trained but one part of it was not, for example "Upper" chest.
    var part: String? = nil
    var suggestion: ExerciseDef?

    /// "Hamstrings", or "Upper chest".
    var title: String { part.map { MuscleParts.label($0, of: muscle) } ?? muscle.title }
}

enum MuscleMap {
    /// The main muscles of these exercises, in workout order, without repeats.
    static func targets(_ exerciseIDs: [String]) -> [Muscle] {
        var seen: [Muscle] = []
        for id in exerciseIDs {
            guard let muscle = ExerciseCatalog.exercise(id)?.muscle, !seen.contains(muscle) else { continue }
            seen.append(muscle)
        }
        return seen
    }

    /// Main and helper sets per muscle. Muscles with main sets come first (most sets first), then helpers only.
    static func work(_ items: [(exerciseID: String, sets: Int)]) -> [MuscleWork] {
        var main: [Muscle: Int] = [:]
        var helper: [Muscle: Int] = [:]
        for item in items where item.sets > 0 {
            guard let exercise = ExerciseCatalog.exercise(item.exerciseID) else { continue }
            main[exercise.muscle, default: 0] += item.sets
            for muscle in exercise.secondary where muscle != exercise.muscle {
                helper[muscle, default: 0] += item.sets
            }
        }
        let muscles = Set(main.keys).union(helper.keys)
        let order = Muscle.allCases
        return muscles.map { MuscleWork(muscle: $0, mainSets: main[$0] ?? 0, helperSets: helper[$0] ?? 0) }
            .sorted {
                if $0.mainSets != $1.mainSets { return $0.mainSets > $1.mainSets }
                if $0.helperSets != $1.helperSets { return $0.helperSets > $1.helperSets }
                return order.firstIndex(of: $0.muscle)! < order.firstIndex(of: $1.muscle)!
            }
    }

    /// How much a set counts for a muscle that only helps (for example lower back on a deadlift).
    static let helperCredit = 0.5

    /// Sets per muscle in the week containing `date`: a full set for the main muscle,
    /// half a set for each helper.
    static func weeklySets(_ workouts: [WorkoutRecord], weekOf date: Date, calendar: Calendar = .current) -> [Muscle: Double] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [:] }
        var result: [Muscle: Double] = [:]
        for workout in workouts where week.contains(workout.date) {
            for entry in workout.entries {
                guard let exercise = ExerciseCatalog.exercise(entry.exerciseID) else { continue }
                let count = Double(entry.sets.count)
                result[exercise.muscle, default: 0] += count
                for helper in Set(exercise.secondary) where helper != exercise.muscle {
                    result[helper, default: 0] += count * helperCredit
                }
            }
        }
        return result
    }

    /// Muscles with less than one set's worth this week (abs left out: they have their own reminder),
    /// each with an exercise this gym can do, preferring one you have done before.
    static func missedThisWeek(history: History, gym: GymInfo?, now: Date = Date(), calendar: Calendar = .current) -> [MissedMuscle] {
        let done = weeklySets(history.workouts, weekOf: now, calendar: calendar)
        let parts = weeklyPartSets(history.workouts, weekOf: now, calendar: calendar)
        var result: [MissedMuscle] = []
        for muscle in Muscle.allCases where muscle != .abs {
            // Counts as hit with at least one set's worth: one main set, or two helping sets.
            if (done[muscle] ?? 0) < 1 {
                result.append(MissedMuscle(muscle: muscle, suggestion: pick(gym: gym, history: history) { $0.muscle == muscle }))
                continue
            }
            // Trained, but a key part of it was not (for example no incline work for the upper chest).
            for part in MuscleParts.parts(of: muscle) where MuscleParts.isKey(part, of: muscle) {
                guard (parts[MusclePart(muscle: muscle, name: part)] ?? 0) == 0 else { continue }
                let suggestion = pick(gym: gym, history: history) {
                    MuscleParts.parts(for: $0).contains(MusclePart(muscle: muscle, name: part))
                }
                result.append(MissedMuscle(muscle: muscle, part: part, suggestion: suggestion))
            }
        }
        return result
    }

    /// Sets per muscle part in the week containing `date`.
    static func weeklyPartSets(_ workouts: [WorkoutRecord], weekOf date: Date, calendar: Calendar = .current) -> [MusclePart: Int] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [:] }
        var result: [MusclePart: Int] = [:]
        for workout in workouts where week.contains(workout.date) {
            for entry in workout.entries {
                guard let exercise = ExerciseCatalog.exercise(entry.exerciseID) else { continue }
                for part in MuscleParts.parts(for: exercise) { result[part, default: 0] += entry.sets.count }
            }
        }
        return result
    }

    /// An exercise this gym can do, preferring one you have done before.
    private static func pick(gym: GymInfo?, history: History, where matches: (ExerciseDef) -> Bool) -> ExerciseDef? {
        let candidates = ExerciseCatalog.all.filter { matches($0) && Planner.isAvailable($0, gym: gym) }
        let familiar = candidates.first {
            history.hasHistory(HistoryKey.make(exerciseID: $0.id, equipment: Planner.equipment(for: $0, gym: gym, history: history)))
        }
        return familiar ?? candidates.first
    }
}

/// Two exercises in one workout that do the same job.
struct Overlap: Equatable {
    enum Kind: Equatable {
        /// Same main muscle and the same movement: one of them is probably wasted time.
        case sameMovement
        /// Same main muscle, but one is your own exercise so the movement is unknown.
        case sameMuscle
    }

    var other: ExerciseDef
    var kind: Kind

    /// "Same job as Dumbbell bench press: both flat presses for chest."
    var message: String {
        switch kind {
        case .sameMovement:
            let what = Overlap.movementName(other.pattern).map { "both \($0)" } ?? "same movement"
            return "Same job as \(other.name): \(what) for \(other.muscle.title.lowercased())."
        case .sameMuscle:
            return "Also works \(other.muscle.title.lowercased()), like \(other.name)."
        }
    }

    /// The first exercise in `others` that does the same job as `exercise`.
    /// Same main muscle with a different movement (flat and incline press, pushdown and overhead
    /// extension) is fine: it works the muscle from another angle, so it is not flagged.
    static func find(_ exercise: ExerciseDef, among others: [ExerciseDef], kept: Set<String> = []) -> Overlap? {
        for other in others where other.id != exercise.id && other.muscle == exercise.muscle {
            if kept.contains(pairKey(exercise.id, other.id)) { continue }
            let ownMade = exercise.pattern.hasPrefix("custom.") || other.pattern.hasPrefix("custom.")
            if ownMade { return Overlap(other: other, kind: .sameMuscle) }
            if other.pattern == exercise.pattern { return Overlap(other: other, kind: .sameMovement) }
        }
        return nil
    }

    /// The first exercise in the list that repeats the job of an earlier one.
    static func firstPair(_ exercises: [ExerciseDef], kept: Set<String> = []) -> (exercise: ExerciseDef, overlap: Overlap)? {
        for (index, exercise) in exercises.enumerated() {
            if let overlap = find(exercise, among: Array(exercises.prefix(index)), kept: kept) { return (exercise, overlap) }
        }
        return nil
    }

    // Pairs you chose to keep ("Keep both"), saved as one line per pair.

    /// Same key whichever order the two come in.
    static func pairKey(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "|") }

    static func keptPairs(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map(String.init))
    }

    static func keeping(_ a: String, _ b: String, in raw: String) -> String {
        var pairs = keptPairs(raw)
        pairs.insert(pairKey(a, b))
        return pairs.sorted().joined(separator: "\n")
    }

    static func movementName(_ pattern: String) -> String? {
        switch pattern {
        case "hpress": return "flat presses"
        case "ipress": return "incline presses"
        case "fly": return "flys"
        case "tri_ext": return "pushdowns"
        case "tri_oh": return "overhead extensions"
        case "dip": return "dips"
        case "vpull": return "pulldowns"
        case "row": return "rows"
        case "pullover": return "straight-arm pulls"
        case "back_ext": return "back extensions"
        case "rear": return "rear delt raises"
        case "curl": return "curls"
        case "hammer": return "hammer curls"
        case "vpress": return "overhead presses"
        case "lateral": return "lateral raises"
        case "squat": return "squats"
        case "knee_ext": return "leg extensions"
        case "lunge": return "lunges"
        case "knee_flex": return "leg curls"
        case "hinge": return "hip hinges"
        case "calf": return "calf raises"
        case "abs_flex": return "crunches"
        case "abs_leg": return "leg raises"
        case "abs_rot": return "twisting crunches"
        default: return nil
        }
    }
}

/// One part of a muscle that some exercises work harder than others, for example the upper chest.
struct MusclePart: Hashable {
    var muscle: Muscle
    var name: String
}

/// Parts of a muscle that the choice of exercise shifts the work toward. Not isolation: a flat press
/// still works the upper chest some. Muscles without parts (lats, quads...) are already split finely enough.
enum MuscleParts {
    /// Part names for a muscle, in display order. Empty if it is not split.
    static func parts(of muscle: Muscle) -> [String] {
        switch muscle {
        case .chest: return ["Upper", "Middle", "Lower"]
        case .triceps: return ["Long head", "Outer heads"]
        case .biceps: return ["Main biceps", "Brachialis"]
        case .delts: return ["Front", "Side"]
        default: return []
        }
    }

    static func hasParts(_ muscle: Muscle) -> Bool { !parts(of: muscle).isEmpty }

    /// Parts worth a reminder when missed. Lower chest is optional: dips are the only thing here that targets it.
    static func isKey(_ part: String, of muscle: Muscle) -> Bool { !(muscle == .chest && part == "Lower") }

    /// "Upper chest", "Triceps long head", "Brachialis", "Side delts".
    static func label(_ part: String, of muscle: Muscle) -> String {
        switch muscle {
        case .chest: return "\(part) chest"
        case .triceps: return "Triceps \(part.lowercased())"
        case .delts: return "\(part) delts"
        default: return part
        }
    }

    /// Which parts an exercise works hardest, from its movement.
    static func parts(for exercise: ExerciseDef) -> [MusclePart] {
        switch exercise.pattern {
        case "ipress": return [MusclePart(muscle: .chest, name: "Upper")]
        case "hpress", "fly": return [MusclePart(muscle: .chest, name: "Middle")]
        case "dip": return [MusclePart(muscle: .triceps, name: "Outer heads"), MusclePart(muscle: .chest, name: "Lower")]
        case "tri_ext": return [MusclePart(muscle: .triceps, name: "Outer heads")]
        case "tri_oh": return [MusclePart(muscle: .triceps, name: "Long head")]
        case "curl": return [MusclePart(muscle: .biceps, name: "Main biceps")]
        case "hammer": return [MusclePart(muscle: .biceps, name: "Brachialis")]
        case "vpress": return [MusclePart(muscle: .delts, name: "Front")]
        case "lateral": return [MusclePart(muscle: .delts, name: "Side")]
        default: return []
        }
    }

    /// For one muscle: each part with the exercises (by name) that focus on it. Parts nothing works are included with none.
    static func breakdown(_ exerciseIDs: [String], muscle: Muscle) -> [(part: String, exercises: [String])] {
        let exercises = exerciseIDs.compactMap { ExerciseCatalog.exercise($0) }
        return parts(of: muscle).map { part in
            let names = exercises.filter { parts(for: $0).contains(MusclePart(muscle: muscle, name: part)) }.map(\.name)
            return (part, names)
        }
    }

    /// For one muscle: sets per part from (exercise, set count) pairs.
    static func sets(_ items: [(exerciseID: String, sets: Int)], muscle: Muscle) -> [(part: String, sets: Int)] {
        parts(of: muscle).map { part in
            let total = items.reduce(0) { sum, item in
                guard let exercise = ExerciseCatalog.exercise(item.exerciseID),
                      parts(for: exercise).contains(MusclePart(muscle: muscle, name: part)) else { return sum }
                return sum + item.sets
            }
            return (part, total)
        }
    }
}
