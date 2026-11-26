import Foundation
import SwiftData

// Glue between saved data (SwiftData models) and the rules engine in Core/.

enum Store {

    // MARK: reading

    static func finished(_ workouts: [Workout]) -> [Workout] {
        workouts.filter { $0.endedAt != nil }
    }

    static func history(_ workouts: [Workout]) -> History {
        History(finished(workouts).map(\.record))
    }

    static func rangeOverrides(_ prefs: [ExercisePrefs]) -> [String: ClosedRange<Int>] {
        var result: [String: ClosedRange<Int>] = [:]
        for pref in prefs where pref.repLow >= 1 && pref.repHigh > pref.repLow {
            result[pref.exerciseID] = pref.repLow...pref.repHigh
        }
        return result
    }

    // MARK: starting and editing a workout

    @discardableResult
    static func start(plan: [PlannedExercise], day: DayType?, quick: Bool, gym: Gym?, context: ModelContext,
                      startedAt: Date = Date()) -> Workout {
        let workout = Workout(day: day, isQuick: quick, gymID: gym?.id, gymName: gym?.name ?? "", startedAt: startedAt)
        context.insert(workout)
        for (order, planned) in plan.enumerated() {
            addEntry(planned, order: order, to: workout, context: context)
        }
        try? context.save()
        return workout
    }

    @discardableResult
    static func addEntry(_ planned: PlannedExercise, order: Int, to workout: Workout, context: ModelContext) -> ExerciseEntry {
        let entry = ExerciseEntry(exerciseID: planned.exercise.id, order: order)
        context.insert(entry)
        entry.workout = workout
        configure(entry, with: planned, context: context)
        return entry
    }

    /// Fill in (or re-fill) an entry from a plan: equipment, history key, range and fresh sets.
    private static func configure(_ entry: ExerciseEntry, with planned: PlannedExercise, context: ModelContext) {
        entry.exerciseID = planned.exercise.id
        entry.slotID = planned.slotID
        entry.equipmentID = planned.equipment?.id
        entry.equipmentName = planned.equipment?.name ?? planned.exercise.equipmentType.name
        entry.historyKey = planned.historyKey
        entry.repLow = planned.range.lowerBound
        entry.repHigh = planned.range.upperBound
        entry.increment = planned.increment
        entry.restSeconds = planned.restSeconds
        entry.explanation = planned.suggestion.explanation
        entry.kindRaw = planned.suggestion.kind.rawValue
        for (index, target) in planned.suggestion.targets.enumerated() {
            let set = SetEntry(index: index, target: target)
            context.insert(set)
            set.entry = entry
        }
    }

    /// Add an extra exercise to the end of a workout in progress.
    static func add(_ exercise: ExerciseDef, to workout: Workout, gym: Gym?, history: History,
                    overrides: [String: ClosedRange<Int>], context: ModelContext) {
        let planned = Planner.planExercise(exercise, slotID: nil, gym: gym?.info, history: history,
                                           rangeOverrides: overrides, quick: workout.isQuick)
        let order = (workout.entries.map(\.order).max() ?? -1) + 1
        addEntry(planned, order: order, to: workout, context: context)
        try? context.save()
    }

    /// One-tap swap. Sets already logged stay; the rest of the exercise is replaced.
    static func swap(_ entry: ExerciseEntry, to exercise: ExerciseDef, in workout: Workout, gym: Gym?, history: History,
                     overrides: [String: ClosedRange<Int>], context: ModelContext) {
        var planned = Planner.planExercise(exercise, slotID: entry.slotID, gym: gym?.info, history: history,
                                           rangeOverrides: overrides, quick: workout.isQuick)
        for set in entry.sets.filter({ $0.completedAt == nil }) {
            context.delete(set)
        }
        if entry.completedSets.isEmpty {
            configure(entry, with: planned, context: context)
        } else {
            // Keep what was logged on the old exercise, and continue on the new one right after it.
            let remaining = max(1, planned.suggestion.targets.count - entry.completedSets.count)
            planned.suggestion.targets = Array(planned.suggestion.targets.prefix(remaining))
            planned.slotID = nil
            for other in workout.entries where other.order > entry.order { other.order += 1 }
            addEntry(planned, order: entry.order + 1, to: workout, context: context)
        }
        try? context.save()
    }

    /// "Do it later": move an exercise to the end of the workout, for when its machine is busy.
    static func moveToEnd(_ entry: ExerciseEntry, in workout: Workout, context: ModelContext) {
        let others = workout.sortedEntries.filter { $0.id != entry.id }
        for (order, other) in others.enumerated() { other.order = order }
        entry.order = others.count
        try? context.save()
    }

    /// Weight steps to choose from during a workout.
    static let stepChoices: [Double] = [2.5, 5, 10]

    /// Change how far one step moves the weight for this exercise. The gym's equipment remembers it for next time.
    static func setIncrement(_ value: Double, for entry: ExerciseEntry, gym: Gym?, context: ModelContext) {
        guard value > 0 else { return }
        entry.increment = value
        if let id = entry.equipmentID, let equipment = gym?.equipment.first(where: { $0.id == id }) {
            equipment.increment = value
        }
        try? context.save()
    }

    /// Turn a kind of equipment on or off for a gym. Off removes every piece of that kind.
    static func setHas(_ type: EquipmentType, _ has: Bool, gym: Gym, context: ModelContext) {
        let current = gym.equipment.filter { $0.typeID == type.id }
        if has, current.isEmpty {
            let item = Equipment(typeID: type.id, name: type.name, increment: type.defaultIncrement)
            context.insert(item)
            item.gym = gym
        } else if !has {
            for item in current { context.delete(item) }
        }
        try? context.save()
    }

    // MARK: your own exercises and machines

    /// Reads the exercises and machines you made into the catalog. Run at launch and after every change.
    static func loadCustom(_ context: ModelContext) {
        let machines = (try? context.fetch(FetchDescriptor<CustomEquipment>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        EquipmentCatalog.custom = machines.filter { !$0.retired }.map(\.type)
        EquipmentCatalog.retired = machines.filter(\.retired).map(\.type)
        let exercises = (try? context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        ExerciseCatalog.custom = exercises.filter { !$0.retired }.map(\.def)
        ExerciseCatalog.retired = exercises.filter(\.retired).map(\.def)
    }

    /// A new kind of machine. If you are at a gym, it is added there straight away.
    @discardableResult
    static func createMachine(name: String, kind: CustomEquipment.Kind, increment: Double, gym: Gym?, context: ModelContext) -> EquipmentType {
        let machine = CustomEquipment(name: name, kind: kind, increment: increment)
        context.insert(machine)
        try? context.save()
        loadCustom(context)
        if let gym { setHas(machine.type, true, gym: gym, context: context) }
        return machine.type
    }

    /// A new exercise. If you are at a gym that is not marked as having what it uses, that gets ticked too.
    @discardableResult
    static func createExercise(name: String, muscle: Muscle, equipmentID: String, compound: Bool, repLow: Int, repHigh: Int,
                               gym: Gym?, context: ModelContext) -> ExerciseDef {
        let exercise = CustomExercise(name: name, muscle: muscle, equipmentID: equipmentID, repLow: repLow, repHigh: repHigh,
                                      compound: compound)
        context.insert(exercise)
        try? context.save()
        loadCustom(context)
        if let gym, equipmentID != EquipmentCatalog.bodyweightID, let type = EquipmentCatalog.type(equipmentID),
           !gym.equipment.contains(where: { $0.typeID == equipmentID }) {
            setHas(type, true, gym: gym, context: context)
        }
        return exercise.def
    }

    /// Built-in exercises that look like one you made: same muscle group, and every word of one name is in the other
    /// ("Preacher curl" matches "EZ-bar preacher curl" and "Preacher curl machine"). Closest first, at most three.
    static func builtInMatches(for exercise: CustomExercise) -> [ExerciseDef] {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .map { $0.hasSuffix("s") && $0.count > 3 ? String($0.dropLast()) : $0 })
        }
        let mine = words(exercise.name)
        guard !mine.isEmpty else { return [] }
        let group = exercise.def.muscle.group
        return ExerciseCatalog.builtIn
            .filter { $0.muscle.group == group }
            .compactMap { candidate -> (Int, ExerciseDef)? in
                let theirs = words(candidate.name)
                guard mine.isSubset(of: theirs) || theirs.isSubset(of: mine) else { return nil }
                return (theirs.symmetricDifference(mine).count, candidate)
            }
            .sorted { $0.0 < $1.0 }
            .prefix(3)
            .map(\.1)
    }

    /// Use the built-in exercise instead of one you made: sets you logged move over to it, your routine
    /// days switch to it, and gyms that had your machine get the built-in equipment instead.
    static func replace(_ exercise: CustomExercise, with builtIn: ExerciseDef, context: ModelContext) {
        let oldID = exercise.id
        let newID = builtIn.id
        let entries = (try? context.fetch(FetchDescriptor<ExerciseEntry>(predicate: #Predicate { $0.exerciseID == oldID }))) ?? []
        for entry in entries {
            entry.exerciseID = newID
            entry.historyKey = HistoryKey.make(exerciseID: newID, equipment: nil)
            entry.equipmentID = nil
            entry.equipmentName = builtIn.equipmentType.name
        }
        for prefs in (try? context.fetch(FetchDescriptor<ExercisePrefs>(predicate: #Predicate { $0.exerciseID == oldID }))) ?? [] {
            prefs.exerciseID = newID
        }

        // Gyms that have your machine get the built-in equipment, and your machine goes if nothing else uses it.
        let machineID = exercise.equipmentID
        if machineID.hasPrefix(CustomEquipment.prefix) {
            for item in (try? context.fetch(FetchDescriptor<Equipment>(predicate: #Predicate { $0.typeID == machineID }))) ?? [] {
                if let gym = item.gym, !gym.equipment.contains(where: { $0.typeID == builtIn.equipment }) {
                    setHas(builtIn.equipmentType, true, gym: gym, context: context)
                }
            }
            let others = ((try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [])
                .filter { $0.id != oldID && !$0.retired && $0.equipmentID == machineID }
            if others.isEmpty,
               let machine = ((try? context.fetch(FetchDescriptor<CustomEquipment>())) ?? []).first(where: { $0.id == machineID }) {
                retire(machine, context: context)
            }
        }

        exercise.retired = true
        try? context.save()
        loadCustom(context)
        Task { @MainActor in
            RoutineStore.shared.days = RoutineStore.shared.days.map { day in
                var day = day
                for index in day.items.indices where day.items[index].exercise == oldID {
                    day.items[index].exercise = newID
                }
                return day
            }
        }
    }

    static func retire(_ exercise: CustomExercise, context: ModelContext) {
        exercise.retired = true
        try? context.save()
        loadCustom(context)
    }

    /// Removes the machine from every gym. Workouts already logged on it are kept.
    static func retire(_ machine: CustomEquipment, context: ModelContext) {
        machine.retired = true
        let id = machine.id
        for item in (try? context.fetch(FetchDescriptor<Equipment>(predicate: #Predicate { $0.typeID == id }))) ?? [] {
            context.delete(item)
        }
        try? context.save()
        loadCustom(context)
    }

    static func addSet(to entry: ExerciseEntry, context: ModelContext) {
        let last = entry.sortedSets.last
        let target = SetTarget(weight: last?.weight ?? 0, reps: last?.reps ?? entry.repLow, lastWeight: nil, lastReps: nil)
        let set = SetEntry(index: (last?.index ?? -1) + 1, target: target)
        context.insert(set)
        set.entry = entry
        try? context.save()
    }

    // MARK: logging

    /// Confirm a set. Returns the kind of personal record it set, if any.
    @discardableResult
    static func complete(_ set: SetEntry, in entry: ExerciseEntry, history: History, context: ModelContext,
                         at date: Date = Date()) -> PRKind? {
        let earlierToday = entry.completedSets.filter { $0.id != set.id }.map { SetRecord(weight: $0.weight, reps: $0.reps) }
        let past = history.allSets(for: entry.historyKey)
        // Only compare against earlier sessions plus today's earlier sets, and only once there is a past to beat.
        let kind = past.isEmpty ? nil : Stats.detectPR(weight: set.weight, reps: set.reps, prior: past + earlierToday)
        set.completedAt = date
        set.prKindRaw = kind?.rawValue
        // If the weight was changed, carry it to the sets still to come.
        if set.weight != set.targetWeight {
            for later in entry.sortedSets where later.completedAt == nil && later.index > set.index {
                later.weight = set.weight
            }
        }
        try? context.save()
        return kind
    }

    static func reopen(_ set: SetEntry, context: ModelContext) {
        set.completedAt = nil
        set.prKindRaw = nil
        try? context.save()
    }

    /// End the workout. Unlogged sets are dropped. Returns false if nothing was logged (workout discarded).
    @discardableResult
    static func finish(_ workout: Workout, context: ModelContext, at date: Date = Date()) -> Bool {
        guard !workout.completedSets.isEmpty else {
            context.delete(workout)
            try? context.save()
            return false
        }
        for entry in Array(workout.entries) {
            for set in entry.sets.filter({ $0.completedAt == nil }) { context.delete(set) }
            if entry.completedSets.isEmpty { context.delete(entry) }
        }
        workout.endedAt = date
        try? context.save()
        return true
    }

    /// Workouts started today can be reopened after Finish to add exercises or sets.
    static func canReopen(_ workout: Workout, now: Date = Date()) -> Bool {
        workout.endedAt != nil && Calendar.current.isDate(workout.startedAt, inSameDayAs: now)
    }

    /// Put a finished workout back in progress. Finishing again saves it (and replaces its Health entry).
    static func reopen(_ workout: Workout, context: ModelContext) {
        workout.endedAt = nil
        try? context.save()
    }

    // MARK: fixing a past workout

    /// Remove one logged set. An exercise left with no sets goes too.
    static func remove(_ set: SetEntry, from entry: ExerciseEntry, context: ModelContext) {
        entry.sets.removeAll { $0.id == set.id }
        context.delete(set)
        if entry.sets.isEmpty {
            entry.workout?.entries.removeAll { $0.id == entry.id }
            context.delete(entry)
        } else {
            for (index, remaining) in entry.sortedSets.enumerated() { remaining.index = index }
        }
        try? context.save()
    }

    /// Work out again which sets are personal records, across every finished workout.
    /// Called after a past workout was edited, because that can change records in later ones.
    static func recountRecords(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let done = finished(all)
        let entries = done.map(\.sortedEntries)
        let kinds = Stats.recordKinds(entries.map { list in
            list.map { entry in
                Stats.RecordInput(historyKey: entry.historyKey,
                                  sets: entry.completedSets.map { SetRecord(weight: $0.weight, reps: $0.reps) })
            }
        })
        for (w, list) in entries.enumerated() {
            for (e, entry) in list.enumerated() {
                for (s, set) in entry.completedSets.enumerated() {
                    let raw = kinds[w][e][s]?.rawValue
                    if set.prKindRaw != raw { set.prKindRaw = raw }
                }
            }
        }
        try? context.save()
    }

    // MARK: plain-language summary

    /// "You beat last time on 11 of 18 sets. Lat pulldown moves up to 125 lb next time..."
    static func summaryText(_ workout: Workout) -> String {
        let sets = workout.completedSets
        var parts: [String] = []
        let comparable = sets.filter { $0.lastReps != nil }
        if comparable.isEmpty {
            parts.append("First time logging these, so today set your starting point. Next time each set gets a target to beat.")
        } else {
            let beat = comparable.filter(\.beatLastTime).count
            parts.append("You beat last time on \(beat) of \(comparable.count) sets.")
        }
        var movingUp: [String] = []
        var staying: [String] = []
        for entry in workout.sortedEntries {
            let done = entry.completedSets
            guard let top = done.map(\.weight).max(), top > 0, !done.isEmpty else { continue }
            if done.allSatisfy({ $0.reps >= entry.repHigh }) {
                movingUp.append("\(entry.name) hit \(entry.repHigh) reps on every set, so next time it moves up to \(Fmt.lb(Progression.roundTo(top + entry.increment, entry.increment)))")
            } else {
                staying.append("\(entry.name) stays at \(Fmt.lb(top)) until every set reaches \(entry.repHigh)")
            }
        }
        if let first = movingUp.first {
            parts.append(first + (movingUp.count > 1 ? ", and \(movingUp.count - 1) more move up too." : "."))
        }
        if let first = staying.first { parts.append(first + ".") }
        return parts.joined(separator: " ")
    }

    // MARK: first launch

    /// Make sure there is at least one gym so the app works straight away.
    static func seedIfNeeded(_ context: ModelContext, demo: Bool) {
        let existing = (try? context.fetchCount(FetchDescriptor<Gym>())) ?? 0
        guard existing == 0 else { return }
        if demo {
            DemoData.seed(context)
        } else {
            makeGym(name: "My gym", typeIDs: EquipmentCatalog.commonIDs, context: context)
        }
        try? context.save()
    }

    @discardableResult
    static func makeGym(name: String, typeIDs: [String], context: ModelContext) -> Gym {
        let gym = Gym(name: name)
        context.insert(gym)
        for (offset, typeID) in typeIDs.enumerated() {
            guard let type = EquipmentCatalog.type(typeID) else { continue }
            let item = Equipment(typeID: type.id, name: type.name, increment: type.defaultIncrement)
            item.createdAt = Date().addingTimeInterval(Double(offset))
            context.insert(item)
            item.gym = gym
        }
        return gym
    }
}

/// Sample history used for screenshots and UI tests (launch with `-demoData`).
/// It is produced by "playing" the real suggestion rules for six weeks.
enum DemoData {
    static func seed(_ context: ModelContext, now: Date = Date()) {
        let iron = Store.makeGym(name: "Iron Works", typeIDs: EquipmentCatalog.commonIDs, context: context)
        let harbor = Store.makeGym(name: "Harbor Fitness",
                                   typeIDs: ["dumbbells", "barbell", "cable", "latPulldown", "smith", "legPress", "legCurl", "rowMachine"],
                                   context: context)
        harbor.createdAt = iron.createdAt.addingTimeInterval(1)

        let calendar = Calendar.current
        // Three workouts in each of the six previous calendar weeks (days 1, 3 and 5 of the week).
        var days: [Date] = []
        if let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start {
            for weeksBack in (1...6).reversed() {
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: thisWeek) else { continue }
                for dayOffset in [1, 3, 5] {
                    if let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) { days.append(day) }
                }
            }
        }
        var records: [WorkoutRecord] = []
        for (i, dayStart) in days.enumerated() {
            let start = dayStart.addingTimeInterval(18 * 3600)
            let history = History(records)
            let gym = (i % 5 == 3) ? harbor : iron
            let day = Rotation.nextDay(history: history)
            let plan = Planner.plan(day: day, includeAbs: i % 2 == 0, quick: false, gym: gym.info, history: history, now: start)
            let workout = Store.start(plan: plan, day: day, quick: false, gym: gym, context: context, startedAt: start)
            var clock = start
            for (k, entry) in workout.sortedEntries.enumerated() {
                for set in entry.sortedSets {
                    // Mostly hit the target, sometimes one more, and the last set often one short.
                    let bonus = (i + k) % 3 == 0 ? 1 : 0
                    let fade = (set.index == 2 && (i + k) % 2 == 0) ? 1 : 0
                    set.reps = max(1, set.targetReps + bonus - fade)
                    clock = clock.addingTimeInterval(150)
                    Store.complete(set, in: entry, history: history, context: context, at: clock)
                }
            }
            Store.finish(workout, context: context, at: clock)
            workout.savedToHealth = true
            records.append(workout.record)
        }
    }
}
