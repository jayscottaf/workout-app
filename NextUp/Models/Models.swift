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
    var isQuick: Bool = false
    var gymID: UUID?
    var gymName: String = ""
    var savedToHealth: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.workout) var entries: [ExerciseEntry] = []

    init(day: DayType?, isQuick: Bool, gymID: UUID?, gymName: String, startedAt: Date = Date()) {
        self.id = UUID()
        self.startedAt = startedAt
        self.dayRaw = day?.rawValue
        self.isQuick = isQuick
        self.gymID = gymID
        self.gymName = gymName
    }

    var day: DayType? { dayRaw.flatMap { DayType(rawValue: $0) } }
    var title: String { day?.title ?? "Workout" }
    var sortedEntries: [ExerciseEntry] { entries.sorted { $0.order < $1.order } }
    var completedSets: [SetEntry] { entries.flatMap(\.completedSets) }
    var durationMinutes: Int { Int(((endedAt ?? Date()).timeIntervalSince(startedAt) / 60).rounded()) }
    var totalVolume: Double { completedSets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var prSets: [SetEntry] { completedSets.filter { $0.prKindRaw != nil } }

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
    var plateBar: Double? { exercise.flatMap { Plates.bar(forEquipment: $0.equipment) } }
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
