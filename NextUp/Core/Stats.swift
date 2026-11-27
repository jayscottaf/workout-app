import Foundation

// Records, estimated strength, weekly goal streak, weekly volume and the monthly recap.

enum PRKind: String, Codable {
    case weight, reps, strength

    func text(weight: Double, reps: Int) -> String {
        switch self {
        case .weight: return "Heaviest weight yet"
        case .reps: return weight > 0 ? "Most reps at \(Fmt.lb(weight))" : "Most reps yet"
        case .strength: return "Best estimated strength"
        }
    }
}

enum Stats {

    /// Estimated one-rep max (Epley formula): the most you could likely lift once.
    static func e1RM(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// Is this set a personal record compared with everything logged before it on the same equipment?
    /// The very first session never counts (there is nothing to beat yet).
    static func detectPR(weight: Double, reps: Int, prior: [SetRecord]) -> PRKind? {
        guard !prior.isEmpty, reps > 0 else { return nil }
        let maxWeight = prior.map(\.weight).max() ?? 0
        if weight > 0, weight > maxWeight { return .weight }
        let bestRepsAtThisWeightOrMore = prior.filter { $0.weight >= weight }.map(\.reps).max() ?? 0
        if reps > bestRepsAtThisWeightOrMore { return .reps }
        let bestStrength = prior.map { e1RM(weight: $0.weight, reps: $0.reps) }.max() ?? 0
        if weight > 0, e1RM(weight: weight, reps: reps) > bestStrength + 0.01 { return .strength }
        return nil
    }

    /// One exercise inside one workout, for `recordKinds`.
    struct RecordInput {
        var historyKey: String
        var sets: [SetRecord]
    }

    /// Work out again which sets were personal records, after a past workout was edited.
    /// `workouts` is oldest first. The result has the same shape: one value per set.
    /// Each set is compared with every earlier workout plus the earlier sets of its own exercise.
    static func recordKinds(_ workouts: [[RecordInput]]) -> [[[PRKind?]]] {
        var past: [String: [SetRecord]] = [:]
        var result: [[[PRKind?]]] = []
        for workout in workouts {
            var kinds: [[PRKind?]] = []
            for entry in workout {
                let before = past[entry.historyKey] ?? []
                var earlier: [SetRecord] = []
                var entryKinds: [PRKind?] = []
                for set in entry.sets {
                    entryKinds.append(before.isEmpty ? nil : detectPR(weight: set.weight, reps: set.reps, prior: before + earlier))
                    earlier.append(set)
                }
                kinds.append(entryKinds)
            }
            for entry in workout { past[entry.historyKey, default: []] += entry.sets }
            result.append(kinds)
        }
        return result
    }

    /// Best estimated strength per session, oldest first (for the chart).
    static func strengthSeries(_ sessions: [Session]) -> [(date: Date, value: Double)] {
        sessions.reversed().compactMap { session in
            let best = session.sets.map { e1RM(weight: $0.weight, reps: $0.reps) }.max() ?? 0
            return best > 0 ? (session.date, best) : nil
        }
    }

    /// Sets per muscle group in the week containing `date`. A full set for the main muscle's group and half a set
    /// for each other group a helper muscle belongs to (a bench press adds half a set to triceps and shoulders).
    static func weeklySets(_ workouts: [WorkoutRecord], weekOf date: Date, calendar: Calendar = .current) -> [MuscleGroup: Double] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [:] }
        var result: [MuscleGroup: Double] = [:]
        for workout in workouts where week.contains(workout.date) {
            for entry in workout.entries {
                guard let exercise = ExerciseCatalog.exercise(entry.exerciseID) else { continue }
                let count = Double(entry.sets.count)
                let main = exercise.muscle.group
                result[main, default: 0] += count
                for group in Set(exercise.secondary.map(\.group)) where group != main {
                    result[group, default: 0] += count * MuscleMap.helperCredit
                }
            }
        }
        return result
    }
}

struct WeekStatus: Equatable {
    var thisWeek: Int
    var goal: Int
    /// Weeks in a row that reached the goal. The current week counts once it is reached,
    /// and an unfinished current week never breaks the streak.
    var streak: Int

    var goalReached: Bool { thisWeek >= goal }
    var remaining: Int { max(0, goal - thisWeek) }
}

enum Streak {
    static func status(dates: [Date], goal: Int, now: Date = Date(), calendar: Calendar = .current) -> WeekStatus {
        let goal = max(1, goal)
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return WeekStatus(thisWeek: 0, goal: goal, streak: 0)
        }
        var counts: [Date: Int] = [:]
        for date in dates {
            if let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start { counts[start, default: 0] += 1 }
        }
        let thisWeek = counts[thisWeekStart] ?? 0
        var streak = thisWeek >= goal ? 1 : 0
        var cursor = thisWeekStart
        while let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor),
              (counts[previous] ?? 0) >= goal {
            streak += 1
            cursor = previous
        }
        return WeekStatus(thisWeek: thisWeek, goal: goal, streak: streak)
    }
}

struct MonthlyRecap {
    var monthTitle: String
    var workouts: Int
    var sets: Int
    var volume: Double
    var records: Int
    var topGroup: MuscleGroup?
    /// Exercise with the biggest estimated-strength gain inside the month.
    var bestGain: (name: String, gain: Double)?
    var cardioSessions: Int
    var cardioMiles: Double

    /// The recap as plain sentences.
    var lines: [String] {
        guard workouts > 0 || cardioSessions > 0 else { return ["No workouts logged this month yet."] }
        var lines: [String] = []
        if workouts > 0 {
            lines.append("You lifted \(workouts) time\(workouts == 1 ? "" : "s") for \(sets) sets in total.")
            lines.append("That is \(Int(volume).formatted()) lb moved.")
        }
        if records > 0 { lines.append("You set \(records) personal record\(records == 1 ? "" : "s").") }
        if let bestGain, bestGain.gain >= 1 {
            lines.append("Biggest gain: \(bestGain.name), up about \(Int(bestGain.gain.rounded())) lb in estimated strength.")
        }
        if let topGroup { lines.append("Most-trained area: \(topGroup.title.lowercased()).") }
        if cardioSessions > 0 {
            lines.append("Cardio: \(cardioSessions) session\(cardioSessions == 1 ? "" : "s"), \(String(format: "%.1f", cardioMiles)) miles.")
        }
        return lines
    }
}

enum Recap {
    static func make(for month: Date, history: History, cardioSessions: Int = 0, cardioMiles: Double = 0,
                     calendar: Calendar = .current) -> MonthlyRecap {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        let title = formatter.string(from: month)
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return MonthlyRecap(monthTitle: title, workouts: 0, sets: 0, volume: 0, records: 0, topGroup: nil,
                                bestGain: nil, cardioSessions: cardioSessions, cardioMiles: cardioMiles)
        }
        let inMonth = history.workouts.filter { interval.contains($0.date) }

        var groupSets: [MuscleGroup: Int] = [:]
        var firstAndLast: [String: (first: Double, last: Double, exerciseID: String)] = [:]
        for workout in inMonth.reversed() { // oldest first
            for entry in workout.entries where !entry.sets.isEmpty {
                if let group = ExerciseCatalog.exercise(entry.exerciseID)?.muscle.group {
                    groupSets[group, default: 0] += entry.sets.count
                }
                let best = entry.sets.map { Stats.e1RM(weight: $0.weight, reps: $0.reps) }.max() ?? 0
                guard best > 0 else { continue }
                if let existing = firstAndLast[entry.historyKey] {
                    firstAndLast[entry.historyKey] = (existing.first, best, entry.exerciseID)
                } else {
                    firstAndLast[entry.historyKey] = (best, best, entry.exerciseID)
                }
            }
        }
        let gain = firstAndLast.values
            .map { (name: ExerciseCatalog.exercise($0.exerciseID)?.name ?? $0.exerciseID, gain: $0.last - $0.first) }
            .max { $0.gain < $1.gain }

        return MonthlyRecap(
            monthTitle: title,
            workouts: inMonth.count,
            sets: inMonth.reduce(0) { $0 + $1.totalSets },
            volume: inMonth.reduce(0) { $0 + $1.totalVolume },
            records: inMonth.reduce(0) { $0 + $1.prCount },
            topGroup: groupSets.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }?.key,
            bestGain: gain.flatMap { $0.gain > 0 ? $0 : nil },
            cardioSessions: cardioSessions,
            cardioMiles: cardioMiles
        )
    }
}
