import Foundation

// The weight-and-reps suggestion rules.
//
//  - Work inside a rep range (say 8 to 12) at one weight.
//  - Hit the top of the range on every set  -> next time go up one real step on that equipment.
//  - Otherwise                              -> same weight, aim for one more rep per set.
//  - Two sessions in a row with no progress -> hold; if reps fell below the range, back off ~10%.
//  - Two weeks or more away                 -> start ~10% lighter.

struct SetTarget: Equatable {
    var weight: Double
    var reps: Int
    var lastWeight: Double?
    var lastReps: Int?

    /// One line shown next to the set, e.g. "Last time 120 × 10 · beat it with 11".
    var beatText: String {
        guard let lastWeight, let lastReps else { return "First time: find a weight that feels right" }
        let last = lastWeight > 0 ? "\(Fmt.weight(lastWeight)) × \(lastReps)" : "\(lastReps) reps"
        if weight > lastWeight { return "Up from \(last) · aim for \(reps) or more" }
        if weight < lastWeight { return "Lighter than \(last) · aim for \(reps)" }
        if reps > lastReps { return "Last time \(last) · beat it with \(reps)" }
        return "Last time \(last) · match it"
    }
}

enum SuggestionKind: String {
    case firstTime, progress, increase, hold, backOff, layoff
}

struct Suggestion {
    var kind: SuggestionKind
    var targets: [SetTarget]
    /// Plain-language reason, shown on the exercise card.
    var explanation: String
}

struct ProgressionConfig {
    var layoffDays = 14
    var layoffFactor = 0.9
    var backOffFactor = 0.9
}

enum Progression {

    static func suggest(sessions: [Session], range: ClosedRange<Int>, increment: Double, starterWeight: Double,
                        bodyweight: Bool, setCount: Int? = nil, now: Date = Date(),
                        config: ProgressionConfig = ProgressionConfig()) -> Suggestion {
        var suggestion = base(sessions: sessions, range: range, increment: increment, starterWeight: starterWeight,
                              bodyweight: bodyweight, now: now, config: config)
        if let setCount, setCount > 0, !suggestion.targets.isEmpty {
            var targets = Array(suggestion.targets.prefix(setCount))
            while targets.count < setCount, let last = targets.last { targets.append(last) }
            suggestion.targets = targets
        }
        return suggestion
    }

    private static func base(sessions: [Session], range: ClosedRange<Int>, increment: Double, starterWeight: Double,
                             bodyweight: Bool, now: Date, config: ProgressionConfig) -> Suggestion {
        let low = range.lowerBound, high = range.upperBound

        guard let last = sessions.first, !last.sets.isEmpty else {
            let weight = bodyweight ? 0 : roundTo(starterWeight, increment)
            let targets = Array(repeating: SetTarget(weight: weight, reps: low), count: 3)
            let text = bodyweight
                ? "First time logging this. Aim for \(low) clean reps per set."
                : "First time on this equipment. \(Fmt.lb(weight)) is a light starting guess: adjust until \(low) to \(high) reps feels challenging."
            return Suggestion(kind: .firstTime, targets: targets, explanation: text)
        }

        // Body weight moves count as weighted once you hold a plate or dumbbell.
        let weightless = last.topWeight == 0
        let days = daysBetween(last.date, now)

        // Layoff: ease back in.
        if days >= config.layoffDays {
            let targets = last.sets.map { set -> SetTarget in
                let weight = weightless ? set.weight : reduced(set.weight, factor: config.layoffFactor, increment: increment)
                return SetTarget(weight: weight, reps: clamp(set.reps, low, high), lastWeight: set.weight, lastReps: set.reps)
            }
            let text = weightless
                ? "It has been \(days) days. Ease back in: match what you did last time."
                : "It has been \(days) days, so today starts about 10% lighter at \(Fmt.lb(targets.map(\.weight).max() ?? 0)). You will be back up quickly."
            return Suggestion(kind: .layoff, targets: targets, explanation: text)
        }

        // Body weight moves progress by reps only.
        if weightless {
            let targets = last.sets.map { SetTarget(weight: $0.weight, reps: $0.reps + 1, lastWeight: $0.weight, lastReps: $0.reps) }
            let text = bodyweight && last.sets.allSatisfy({ $0.reps >= high })
                ? "You hit \(high) reps on every set. Aim for one more, or hold a plate and tap + to add its weight."
                : "Body weight move: aim for one more rep on each set than last time."
            return Suggestion(kind: .progress, targets: targets, explanation: text)
        }

        // Top of the range on every set: go up one step.
        if last.sets.allSatisfy({ $0.reps >= high }) {
            let targets = last.sets.map {
                SetTarget(weight: roundTo($0.weight + increment, increment), reps: low, lastWeight: $0.weight, lastReps: $0.reps)
            }
            let newTop = targets.map(\.weight).max() ?? 0
            return Suggestion(kind: .increase, targets: targets,
                              explanation: "You hit \(high) reps on every set last time, so today moves up to \(Fmt.lb(newTop)). Aim for \(low) or more.")
        }

        // Two misses in a row: hold, or back off if reps fell under the range.
        if missStreak(sessions, low: low) >= 2 {
            if last.sets.contains(where: { $0.reps < low }) {
                let targets = last.sets.map { set -> SetTarget in
                    let weight = reduced(set.weight, factor: config.backOffFactor, increment: increment)
                    return SetTarget(weight: weight, reps: clamp(set.reps + 2, low, high), lastWeight: set.weight, lastReps: set.reps)
                }
                let newTop = targets.map(\.weight).max() ?? 0
                return Suggestion(kind: .backOff, targets: targets,
                                  explanation: "Two tough sessions in a row at \(Fmt.lb(last.topWeight)), with reps under \(low). Dropping to \(Fmt.lb(newTop)) to rebuild, then climbing again.")
            }
            let targets = last.sets.map { SetTarget(weight: $0.weight, reps: $0.reps, lastWeight: $0.weight, lastReps: $0.reps) }
            return Suggestion(kind: .hold, targets: targets,
                              explanation: "Two sessions without progress at \(Fmt.lb(last.topWeight)). Hold here today: match last time with clean reps before pushing on.")
        }

        // Normal case: same weight, one more rep.
        let targets = last.sets.map {
            SetTarget(weight: $0.weight, reps: clamp($0.reps + 1, low, high), lastWeight: $0.weight, lastReps: $0.reps)
        }
        return Suggestion(kind: .progress, targets: targets,
                          explanation: "Same weight as last time. Add a rep where you can: \(high) on every set earns the next weight up.")
    }

    /// How many of the most recent sessions (up to 2) were "misses".
    /// A miss: any set under the bottom of the range, or no more total reps than the session before at the same weight.
    static func missStreak(_ sessions: [Session], low: Int) -> Int {
        var streak = 0
        for i in 0..<min(2, sessions.count) {
            let session = sessions[i]
            var miss = session.sets.contains { $0.reps < low }
            if !miss, i + 1 < sessions.count {
                let previous = sessions[i + 1]
                miss = abs(session.topWeight - previous.topWeight) < 0.01 && session.totalReps <= previous.totalReps
            }
            if miss { streak += 1 } else { break }
        }
        return streak
    }

    /// Shown while logging: what earns the next step up.
    static func lookAhead(weight: Double, range: ClosedRange<Int>, increment: Double, bodyweight: Bool) -> String {
        if weight <= 0 { return "Beat last time by one rep per set." }
        return "Get \(range.upperBound) on every set and next time moves up to \(Fmt.lb(roundTo(weight + increment, increment)))."
    }

    // MARK: helpers

    static func roundTo(_ value: Double, _ increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }

    /// About `factor` of the weight, rounded down to a real step, and always at least one step lighter.
    static func reduced(_ weight: Double, factor: Double, increment: Double) -> Double {
        guard weight > 0, increment > 0 else { return weight }
        let rounded = ((weight * factor) / increment + 1e-9).rounded(.down) * increment
        let atLeastOneStepDown = min(rounded, weight - increment)
        return max(min(increment, weight), atLeastOneStepDown)
    }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        max(0, Int(to.timeIntervalSince(from) / 86_400))
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { min(max(value, low), high) }
}
