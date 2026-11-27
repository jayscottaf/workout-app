import Foundation

// Builds today's workout: which exercise fills each slot at this gym, on which
// equipment, and what weight and reps to aim for.

struct PlannedExercise {
    var exercise: ExerciseDef
    var slotID: String?
    var equipment: EquipmentInfo?
    var historyKey: String
    var range: ClosedRange<Int>
    var increment: Double
    var restSeconds: Int
    var suggestion: Suggestion
}

struct SwapOption {
    var exercise: ExerciseDef
    var equipment: EquipmentInfo?
    var historyKey: String
    var isBestMatch: Bool
    /// e.g. "Plate-loaded · last time here 90 lb × 10"
    var detail: String
}

struct ExerciseIdea {
    var exercise: ExerciseDef
    var muscle: Muscle
    var title: String
    var detail: String
}

enum Rotation {
    /// The day after the one trained most recently. No fixed schedule.
    static func nextDay(history: History) -> DayType {
        history.lastDay?.next ?? Routine.days.first ?? .chestTriceps
    }

    /// Abs is an add-on, offered again once it has been `everyDays` days.
    static func absDue(history: History, everyDays: Int, now: Date = Date()) -> Bool {
        guard let last = history.lastAbsDate else { return true }
        return Progression.daysBetween(last, now) >= everyDays
    }
}

enum Planner {

    // MARK: availability

    static func isAvailable(_ exercise: ExerciseDef, gym: GymInfo?) -> Bool {
        guard let gym else { return true }
        return exercise.equipment == EquipmentCatalog.bodyweightID || gym.typeIDs.contains(exercise.equipment)
    }

    /// Which piece of equipment at this gym the exercise would use (prefers one you already have history on).
    static func equipment(for exercise: ExerciseDef, gym: GymInfo?, history: History) -> EquipmentInfo? {
        guard let gym else { return nil }
        let matches = gym.equipment.filter { $0.typeID == exercise.equipment }
        return matches.first { history.hasHistory(HistoryKey.make(exerciseID: exercise.id, equipment: $0)) } ?? matches.first
    }

    // MARK: planning

    static func plan(day: DayType, includeAbs: Bool, quick: Bool, gym: GymInfo?, history: History,
                     rangeOverrides: [String: ClosedRange<Int>] = [:], now: Date = Date()) -> [PlannedExercise] {
        var result: [PlannedExercise] = []
        let indexes = quick ? day.quickSlotIndexes : Array(day.slots.indices)
        for index in indexes {
            let slotID = day.slotID(index)
            guard let exercise = choose(defaultID: day.slots[index], slotID: slotID, gym: gym, history: history,
                                        excluding: Set(result.map(\.exercise.id))) else { continue }
            result.append(planExercise(exercise, slotID: slotID, gym: gym, history: history,
                                       rangeOverrides: rangeOverrides, quick: quick, now: now))
        }
        if includeAbs {
            result += absPlan(quick: quick, gym: gym, history: history, rangeOverrides: rangeOverrides, now: now,
                              excluding: Set(result.map(\.exercise.id)))
        }
        return result
    }

    static func absPlan(quick: Bool, gym: GymInfo?, history: History, rangeOverrides: [String: ClosedRange<Int>] = [:],
                        now: Date = Date(), excluding: Set<String> = []) -> [PlannedExercise] {
        var result: [PlannedExercise] = []
        let indexes = quick ? [0] : Array(AbsAddOn.slots.indices)
        for index in indexes {
            let slotID = AbsAddOn.slotID(index)
            let taken = excluding.union(result.map(\.exercise.id))
            guard let exercise = choose(defaultID: AbsAddOn.slots[index], slotID: slotID, gym: gym, history: history,
                                        excluding: taken) else { continue }
            result.append(planExercise(exercise, slotID: slotID, gym: gym, history: history,
                                       rangeOverrides: rangeOverrides, quick: quick, now: now))
        }
        return result
    }

    /// Slot choice: what you last did for this slot at this gym, else the default, else the closest thing this gym has.
    static func choose(defaultID: String, slotID: String, gym: GymInfo?, history: History, excluding: Set<String>) -> ExerciseDef? {
        if let lastID = history.lastExercise(slotID: slotID, gymID: gym?.id), !excluding.contains(lastID), !ExerciseCatalog.isRetired(lastID),
           let last = ExerciseCatalog.exercise(lastID), isAvailable(last, gym: gym) {
            return last
        }
        guard let standard = ExerciseCatalog.exercise(defaultID) else { return nil }
        if isAvailable(standard, gym: gym), !excluding.contains(standard.id), !ExerciseCatalog.isRetired(standard.id) { return standard }
        return swapOptions(for: standard, gym: gym, history: history, excluding: excluding).first?.exercise
    }

    static func planExercise(_ exercise: ExerciseDef, slotID: String?, gym: GymInfo?, history: History,
                             rangeOverrides: [String: ClosedRange<Int>] = [:], quick: Bool = false,
                             now: Date = Date()) -> PlannedExercise {
        let equipment = equipment(for: exercise, gym: gym, history: history)
        let key = HistoryKey.make(exerciseID: exercise.id, equipment: equipment)
        let range = rangeOverrides[exercise.id] ?? exercise.range
        let increment = equipment?.increment ?? exercise.equipmentType.step
        let suggestion = Progression.suggest(sessions: history.sessions(for: key), range: range, increment: increment,
                                             starterWeight: exercise.starterWeight, bodyweight: exercise.isBodyweight,
                                             setCount: quick ? 2 : nil, now: now)
        return PlannedExercise(exercise: exercise, slotID: slotID, equipment: equipment, historyKey: key, range: range,
                               increment: increment, restSeconds: quick ? 60 : exercise.restSeconds, suggestion: suggestion)
    }

    /// Rough length in minutes: about 40 seconds per set plus rest, and a minute to change stations.
    static func estimateMinutes(_ plan: [PlannedExercise]) -> Int {
        let seconds = plan.reduce(0) { $0 + $1.suggestion.targets.count * (40 + $1.restSeconds) + 60 }
        return max(5, Int((Double(seconds) / 60 / 5).rounded()) * 5)
    }

    // MARK: swapping

    /// Equivalent exercises for the same muscle using what this gym has, best first.
    static func swapOptions(for exercise: ExerciseDef, gym: GymInfo?, history: History, excluding: Set<String> = []) -> [SwapOption] {
        let scored: [(Int, SwapOption)] = ExerciseCatalog.all.compactMap { candidate in
            guard candidate.id != exercise.id, !excluding.contains(candidate.id), isAvailable(candidate, gym: gym) else { return nil }
            let samePattern = candidate.pattern == exercise.pattern
            let sameMuscle = candidate.muscle == exercise.muscle
            guard samePattern || sameMuscle else { return nil }
            let equipment = equipment(for: candidate, gym: gym, history: history)
            let key = HistoryKey.make(exerciseID: candidate.id, equipment: equipment)
            let lastSet = history.sessions(for: key).first?.sets.first
            var score = (samePattern ? 4 : 0) + (sameMuscle ? 2 : 0)
            if lastSet != nil { score += 1 }
            if candidate.compound == exercise.compound { score += 1 }
            let option = SwapOption(exercise: candidate, equipment: equipment, historyKey: key, isBestMatch: false,
                                    detail: swapDetail(candidate, lastSet: lastSet))
            return (score, option)
        }
        // Ties: the everyday exercises before the rest of the library, then by name.
        var options = scored.sorted {
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            let a = ExerciseCatalog.moreIDs.contains($0.1.exercise.id), b = ExerciseCatalog.moreIDs.contains($1.1.exercise.id)
            if a != b { return !a }
            return $0.1.exercise.name < $1.1.exercise.name
        }.map(\.1)
        if !options.isEmpty { options[0].isBestMatch = true }
        return options
    }

    /// Equivalent exercises this gym cannot do (shown greyed out).
    static func unavailableSwaps(for exercise: ExerciseDef, gym: GymInfo?) -> [ExerciseDef] {
        guard gym != nil else { return [] }
        // Everyday exercises first; a handful is enough to say what else would work.
        let all = ExerciseCatalog.all.filter {
            $0.id != exercise.id && ($0.pattern == exercise.pattern) && !isAvailable($0, gym: gym)
        }
        return Array((all.filter { !ExerciseCatalog.moreIDs.contains($0.id) } + all.filter { ExerciseCatalog.moreIDs.contains($0.id) }).prefix(6))
    }

    private static func swapDetail(_ exercise: ExerciseDef, lastSet: SetRecord?) -> String {
        let type = exercise.equipmentType
        switch type.category {
        case .machine:
            if let lastSet { return "\(type.loading) · last time here \(Fmt.lb(lastSet.weight)) × \(lastSet.reps)" }
            return "New machine for you · start light and learn it"
        case .freeWeight:
            if let lastSet { return "Free weight · same history at every gym · \(Fmt.lb(lastSet.weight)) × \(lastSet.reps)" }
            return "Free weight · no history yet"
        case .bodyweight:
            if let lastSet { return "Body weight · last time \(lastSet.reps) reps" }
            return "Body weight · no history yet"
        }
    }

    // MARK: ideas

    /// Extra exercises worth adding today: muscles that have gone longest without work,
    /// limited to what this gym has and not already in today's plan.
    static func ideas(history: History, gym: GymInfo?, plannedExerciseIDs: Set<String>, staleAfterDays: Int = 7,
                      limit: Int = 2, now: Date = Date()) -> [ExerciseIdea] {
        guard !history.workouts.isEmpty else { return [] }
        let planned = plannedExerciseIDs.compactMap { ExerciseCatalog.exercise($0) }
        let coveredToday = Set(planned.map(\.muscle))
        let lastTrained = history.lastTrained()

        let stale: [(Muscle, Int?)] = Muscle.allCases.compactMap { muscle in
            guard muscle != .abs, !coveredToday.contains(muscle) else { return nil }
            guard let date = lastTrained[muscle] else { return (muscle, nil) }
            let days = Progression.daysBetween(date, now)
            return days >= staleAfterDays ? (muscle, days) : nil
        }
        // Longest gap first; muscles never trained at all come after those.
        let ordered = stale.sorted { ($0.1 ?? -1) > ($1.1 ?? -1) }

        var ideas: [ExerciseIdea] = []
        for (muscle, days) in ordered {
            let candidates = ExerciseCatalog.all.filter {
                $0.muscle == muscle && !plannedExerciseIDs.contains($0.id) && isAvailable($0, gym: gym)
            }
            // Prefer something you have done before, then simple isolation moves.
            let pick = candidates.first { history.hasHistory(HistoryKey.make(exerciseID: $0.id, equipment: equipment(for: $0, gym: gym, history: history))) }
                ?? candidates.first { !$0.compound } ?? candidates.first
            guard let pick else { continue }
            let verb = muscle.isPlural ? "are" : "is"
            let when = days.map { "Not trained in \($0) days" } ?? "Not trained yet"
            let place = gym.map { _ in " · \(pick.name) is here" } ?? " · try \(pick.name)"
            ideas.append(ExerciseIdea(exercise: pick, muscle: muscle, title: "\(muscle.title) \(verb) due", detail: when + place))
            if ideas.count == limit { break }
        }
        return ideas
    }
}
