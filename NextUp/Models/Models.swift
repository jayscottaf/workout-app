import Foundation
import SwiftData

// What the app saves on the phone (SwiftData).

@Model
final class Gym {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \Equipment.gym) var equipment: [Equipment] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var sortedEquipment: [Equipment] { equipment.sorted { $0.createdAt < $1.createdAt } }

    var info: GymInfo {
        GymInfo(id: id, name: name, equipment: sortedEquipment.map(\.info))
    }
}

@Model
final class Equipment {
    var id: UUID = UUID()
    var typeID: String = ""
    var name: String = ""
    /// The real jump between weights on this piece of equipment, in pounds.
    var increment: Double = 5
    var createdAt: Date = Date()
    var gym: Gym?

    init(typeID: String, name: String, increment: Double) {
        self.id = UUID()
        self.typeID = typeID
        self.name = name
        self.increment = increment
        self.createdAt = Date()
    }

    var type: EquipmentType? { EquipmentCatalog.type(typeID) }
    var info: EquipmentInfo { EquipmentInfo(id: id, typeID: typeID, name: name, increment: increment) }
}

@Model
final class Workout {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    /// nil while the workout is still in progress.
    var endedAt: Date?
    var dayRaw: String?
    /// The day's name when the workout was started, so it still reads right after the routine changes.
    var dayTitle: String = ""
    var isQuick: Bool = false
    var gymID: UUID?
    var gymName: String = ""
    var savedToHealth: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.workout) var entries: [ExerciseEntry] = []

    init(day: DayType?, isQuick: Bool, gymID: UUID?, gymName: String, startedAt: Date = Date()) {
        self.id = UUID()
        self.startedAt = startedAt
        self.dayRaw = day?.rawValue
        self.dayTitle = day?.title ?? ""
        self.isQuick = isQuick
        self.gymID = gymID
        self.gymName = gymName
    }

    var day: DayType? { dayRaw.map { Routine.day($0) ?? DayType(id: $0, title: dayTitle, exercises: []) } }
    var title: String {
        if !dayTitle.isEmpty { return dayTitle }
        if let title = day?.title, !title.isEmpty { return title }
        return "Workout"
    }
    var sortedEntries: [ExerciseEntry] { entries.sorted { $0.order < $1.order } }
    var completedSets: [SetEntry] { entries.flatMap(\.completedSets) }
    var durationMinutes: Int { Int(((endedAt ?? Date()).timeIntervalSince(startedAt) / 60).rounded()) }
    var totalVolume: Double { completedSets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var prSets: [SetEntry] { completedSets.filter { $0.prKindRaw != nil } }

    /// "Next: Bench press · 135 lb × 8", for the Lock Screen card: the next set of `entry`, else of the first unfinished exercise.
    func nextUpText(after entry: ExerciseEntry?) -> String {
        let upcoming = entry.flatMap { e in e.nextSet.map { (e, $0) } }
            ?? sortedEntries.first { !$0.isDone }.flatMap { other in other.nextSet.map { (other, $0) } }
        guard let (nextEntry, set) = upcoming else { return "" }
        let amount = set.weight > 0 ? "\(Fmt.lb(set.weight)) × \(set.reps)" : "\(set.reps) reps"
        return "Next: \(nextEntry.name) · \(amount)"
    }

    /// Snapshot for the rules engine (completed sets only).
    var record: WorkoutRecord {
        WorkoutRecord(id: id, date: startedAt, day: day, gymID: gymID, durationMinutes: durationMinutes,
                      entries: sortedEntries.map(\.record))
    }
}

@Model
final class ExerciseEntry {
    var id: UUID = UUID()
    var exerciseID: String = ""
    var order: Int = 0
    var slotID: String?
    var equipmentID: UUID?
    var equipmentName: String = ""
    var historyKey: String = ""
    var repLow: Int = 8
    var repHigh: Int = 12
    var increment: Double = 5
    var restSeconds: Int = 90
    /// Plain-language reason for today's targets.
    var explanation: String = ""
    var kindRaw: String = ""
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.entry) var sets: [SetEntry] = []
    var workout: Workout?

    init(exerciseID: String, order: Int) {
        self.id = UUID()
        self.exerciseID = exerciseID
        self.order = order
    }

    var exercise: ExerciseDef? { ExerciseCatalog.exercise(exerciseID) }
    var name: String { exercise?.name ?? exerciseID }
    var range: ClosedRange<Int> { repLow...max(repLow, repHigh) }
    var isBodyweight: Bool { exercise?.isBodyweight ?? false }
    /// The bar weight when this exercise is loaded with plates (0 for a plate-loaded machine), else nil.
    var plateBar: Double? {
        guard let exercise else { return nil }
        if let bar = Plates.bar(forEquipment: exercise.equipment) { return bar }
        // A plate-loaded machine you added yourself.
        return exercise.equipment.hasPrefix(CustomEquipment.prefix) && exercise.equipmentType.loading == CustomEquipment.plateLoading ? 0 : nil
    }
    var sortedSets: [SetEntry] { sets.sorted { $0.index < $1.index } }
    var completedSets: [SetEntry] { sortedSets.filter { $0.completedAt != nil } }
    var nextSet: SetEntry? { sortedSets.first { $0.completedAt == nil } }
    var isDone: Bool { !sets.isEmpty && nextSet == nil }

    var record: EntryRecord {
        EntryRecord(exerciseID: exerciseID, historyKey: historyKey, slotID: slotID,
                    sets: completedSets.map { SetRecord(weight: $0.weight, reps: $0.reps, isPR: $0.prKindRaw != nil) })
    }
}

@Model
final class SetEntry {
    var id: UUID = UUID()
    var index: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var targetWeight: Double = 0
    var targetReps: Int = 0
    var lastWeight: Double?
    var lastReps: Int?
    var completedAt: Date?
    var prKindRaw: String?
    var entry: ExerciseEntry?

    init(index: Int, target: SetTarget) {
        self.id = UUID()
        self.index = index
        self.weight = target.weight
        self.reps = target.reps
        self.targetWeight = target.weight
        self.targetReps = target.reps
        self.lastWeight = target.lastWeight
        self.lastReps = target.lastReps
    }

    var target: SetTarget { SetTarget(weight: targetWeight, reps: targetReps, lastWeight: lastWeight, lastReps: lastReps) }
    var prKind: PRKind? { prKindRaw.flatMap { PRKind(rawValue: $0) } }

    /// Did this set beat the same set last time?
    var beatLastTime: Bool {
        guard let lastWeight, let lastReps else { return false }
        return weight > lastWeight || (weight == lastWeight && reps > lastReps)
    }
}

/// Your own rep range for an exercise, when you change it from the default.
@Model
final class ExercisePrefs {
    var exerciseID: String = ""
    var repLow: Int = 8
    var repHigh: Int = 12

    init(exerciseID: String, repLow: Int, repHigh: Int) {
        self.exerciseID = exerciseID
        self.repLow = repLow
        self.repHigh = repHigh
    }
}

/// A kind of machine you added yourself (one that is not on the built-in list).
@Model
final class CustomEquipment {
    static let prefix = "custom-"
    static let plateLoading = "Plate-loaded"

    var id: String = ""
    var name: String = ""
    var plateLoaded: Bool = false
    /// "stack", "plates" or "bodyweight". Empty on machines made before body weight was an option.
    var kindRaw: String = ""
    var increment: Double = 5
    /// Removed by you: no longer offered, but old workouts still show its name.
    var retired: Bool = false
    var createdAt: Date = Date()

    enum Kind: String, CaseIterable {
        case stack, plates, bodyweight

        var title: String {
            switch self {
            case .stack: return "Weight stack (pin)"
            case .plates: return "Plates you load on it"
            case .bodyweight: return "Body weight (hold a plate if you like)"
            }
        }
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? (plateLoaded ? .plates : .stack) }

    init(name: String, kind: Kind, increment: Double) {
        self.id = CustomEquipment.prefix + UUID().uuidString
        self.name = name
        self.kindRaw = kind.rawValue
        self.plateLoaded = kind == .plates
        self.increment = increment
        self.createdAt = Date()
    }

    var type: EquipmentType {
        switch kind {
        case .bodyweight:
            return EquipmentType(id: id, name: name, category: .bodyweight, defaultIncrement: increment,
                                 loading: "Body weight · hold a plate for more")
        case .plates:
            return EquipmentType(id: id, name: name, category: .machine, defaultIncrement: increment, loading: CustomEquipment.plateLoading)
        case .stack:
            return EquipmentType(id: id, name: name, category: .machine, defaultIncrement: increment, loading: "Weight stack")
        }
    }
}

/// An exercise you made yourself. It behaves like a built-in one.
@Model
final class CustomExercise {
    var id: String = ""
    var name: String = ""
    var muscleRaw: String = ""
    /// EquipmentType id (built-in or one of your own machines).
    var equipmentID: String = ""
    var repLow: Int = 10
    var repHigh: Int = 15
    var compound: Bool = false
    var retired: Bool = false
    var createdAt: Date = Date()

    init(name: String, muscle: Muscle, equipmentID: String, repLow: Int, repHigh: Int, compound: Bool) {
        self.id = "custom-" + UUID().uuidString
        self.name = name
        self.muscleRaw = muscle.rawValue
        self.equipmentID = equipmentID
        self.repLow = repLow
        self.repHigh = repHigh
        self.compound = compound
        self.createdAt = Date()
    }

    var def: ExerciseDef {
        // Its own pattern per muscle: swaps offer it alongside the other exercises for that muscle.
        ExerciseDef(id: id, name: name, muscle: Muscle(rawValue: muscleRaw) ?? .chest, secondary: [], equipment: equipmentID,
                    pattern: "custom.\(muscleRaw)", repLow: repLow, repHigh: max(repLow + 1, repHigh), compound: compound,
                    starterWeight: ExerciseCatalog.starterWeight(equipment: equipmentID))
    }
}
