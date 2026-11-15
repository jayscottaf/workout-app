import Foundation

// Plain snapshots of logged workouts. The app converts its saved data into these,
// and every rule (suggestions, rotation, streaks, records) reads only these.

struct SetRecord: Equatable {
    var weight: Double
    var reps: Int
    var isPR: Bool = false
}

struct EntryRecord {
    var exerciseID: String
    /// Which pile of history this belongs to. See `HistoryKey`.
    var historyKey: String
    var slotID: String?
    var sets: [SetRecord]
}

struct WorkoutRecord {
    var id: UUID = UUID()
    var date: Date
    var day: DayType?
    var gymID: UUID?
    var durationMinutes: Int = 0
    var entries: [EntryRecord]

    var totalSets: Int { entries.reduce(0) { $0 + $1.sets.count } }
    var totalVolume: Double { entries.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.weight * Double($1.reps) } } }
    var prCount: Int { entries.reduce(0) { $0 + $1.sets.filter(\.isPR).count } }
    var includesAbs: Bool {
        entries.contains { !$0.sets.isEmpty && ExerciseCatalog.exercise($0.exerciseID)?.muscle == .abs }
    }
}

/// One past session of one exercise on one piece of equipment.
struct Session {
    var date: Date
    var sets: [SetRecord]

    var topWeight: Double { sets.map(\.weight).max() ?? 0 }
    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
}

struct EquipmentInfo: Hashable {
    var id: UUID
    var typeID: String
    var name: String
    var increment: Double

    var type: EquipmentType? { EquipmentCatalog.type(typeID) }
}

struct GymInfo {
    var id: UUID
    var name: String
    var equipment: [EquipmentInfo]

    var typeIDs: Set<String> { Set(equipment.map(\.typeID)) }
}

enum HistoryKey {
    /// Machines get their own history per physical machine (weights on different machines
    /// are not comparable). Free weights and body weight share one history everywhere.
    static func make(exerciseID: String, equipment: EquipmentInfo?) -> String {
        if let equipment, equipment.type?.category == .machine {
            return "\(exerciseID)@\(equipment.id.uuidString)"
        }
        return exerciseID
    }
}

struct History {
    /// Newest first.
    let workouts: [WorkoutRecord]

    init(_ workouts: [WorkoutRecord]) {
        self.workouts = workouts.sorted { $0.date > $1.date }
    }

    /// Past sessions for one history key, newest first.
    func sessions(for key: String) -> [Session] {
        var result: [Session] = []
        for workout in workouts {
            for entry in workout.entries where entry.historyKey == key && !entry.sets.isEmpty {
                result.append(Session(date: workout.date, sets: entry.sets))
            }
        }
        return result
    }

    func hasHistory(_ key: String) -> Bool {
        workouts.contains { $0.entries.contains { $0.historyKey == key && !$0.sets.isEmpty } }
    }

    /// Every set ever logged under a key (for record checks).
    func allSets(for key: String) -> [SetRecord] {
        sessions(for: key).flatMap(\.sets)
    }

    /// The most recent rotation day that was trained.
    var lastDay: DayType? {
        workouts.first { $0.day != nil }?.day
    }

    var lastAbsDate: Date? {
        workouts.first { $0.includesAbs }?.date
    }

    /// When each muscle was last the main target of an exercise.
    func lastTrained() -> [Muscle: Date] {
        var result: [Muscle: Date] = [:]
        for workout in workouts {
            for entry in workout.entries where !entry.sets.isEmpty {
                guard let muscle = ExerciseCatalog.exercise(entry.exerciseID)?.muscle else { continue }
                if result[muscle] == nil { result[muscle] = workout.date }
            }
        }
        return result
    }

    /// What was done most recently for a routine slot at a given gym (so a swap sticks per gym).
    func lastExercise(slotID: String, gymID: UUID?) -> String? {
        for workout in workouts where workout.gymID == gymID {
            if let entry = workout.entries.first(where: { $0.slotID == slotID && !$0.sets.isEmpty }) {
                return entry.exerciseID
            }
        }
        return nil
    }
}
