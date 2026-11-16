import Foundation

// What the iPhone and the Apple Watch send each other.
// The iPhone keeps all the data. The Watch shows a copy (a "snapshot") and sends back what you do on it.

/// Everything the Watch needs to draw its screens.
struct WatchSnapshot: Codable, Equatable {
    /// The workout the phone would offer next. nil while one is in progress.
    var next: WatchNext?
    /// The workout in progress, if any.
    var active: WatchWorkout?
    /// The last workout finished today, if any.
    var summary: WatchSummary?
    /// Rest between sets chosen in Settings, in seconds. 0 means automatic.
    var restOverride: Int = 0
    var sentAt: Date = Date()
}

struct WatchNext: Codable, Equatable {
    var dayNumber: Int
    var title: String
    var exerciseCount: Int
    var minutes: Int
}

struct WatchWorkout: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var startedAt: Date
    /// false when this workout already has an Apple Health entry (it was finished, then reopened).
    var trackHealth: Bool = true
    var entries: [WatchEntry]

    var doneSets: [WatchSet] { entries.flatMap { $0.sets.filter(\.done) } }
    var setsLeft: Int { entries.reduce(0) { $0 + $1.sets.filter { !$0.done }.count } }
    var firstOpenIndex: Int? { entries.firstIndex { !$0.isDone } }
}

struct WatchEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var restSeconds: Int
    var increment: Double
    var isBodyweight: Bool
    /// The bar weight when this exercise is loaded with plates (0 for a plate-loaded machine), else nil.
    var bar: Double? = nil
    var sets: [WatchSet]

    var nextSet: WatchSet? { sets.first { !$0.done } }
    var isDone: Bool { !sets.isEmpty && nextSet == nil }
}

struct WatchSet: Codable, Equatable, Identifiable {
    var id: UUID
    var index: Int
    var weight: Double
    var reps: Int
    var lastWeight: Double?
    var lastReps: Int?
    var done: Bool
    var isRecord: Bool = false
}

struct WatchSummary: Codable, Equatable {
    var workoutID: UUID
    var title: String
    var endedAt: Date
    var minutes: Int
    var sets: Int
    var records: Int
}

struct WatchSwapOption: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var isBestMatch: Bool
}

/// What the Watch asks the iPhone to do.
enum WatchCommand: Codable, Equatable {
    case refresh
    case start(quick: Bool)
    case log(setID: UUID, weight: Double, reps: Int, at: Date)
    case finish(workoutID: UUID, at: Date, savedToHealth: Bool)
    case swapOptions(entryID: UUID)
    case swap(entryID: UUID, exerciseID: String)
    /// The Watch is recording heart rate for this workout and will save it to Apple Health itself.
    case tracking(workoutID: UUID)
    /// The Watch saved this workout to Apple Health.
    case healthSaved(workoutID: UUID)
}

/// Keys of the dictionaries sent over the phone-to-Watch connection.
enum WatchWire {
    static let command = "cmd"
    static let snapshot = "snapshot"
    static let swaps = "swaps"
    static let record = "record"

    static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Any?) -> T? {
        guard let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension WatchSnapshot {
    /// Mark a set as logged, the same way the phone does it. Returns false if the set is not there.
    @discardableResult
    mutating func markLogged(setID: UUID, weight: Double, reps: Int) -> Bool {
        guard var workout = active else { return false }
        for e in workout.entries.indices {
            guard let s = workout.entries[e].sets.firstIndex(where: { $0.id == setID }) else { continue }
            let changed = workout.entries[e].sets[s].weight != weight
            workout.entries[e].sets[s].weight = weight
            workout.entries[e].sets[s].reps = reps
            workout.entries[e].sets[s].done = true
            if changed {
                // A changed weight carries to the sets still to come.
                for later in workout.entries[e].sets.indices where later > s && !workout.entries[e].sets[later].done {
                    workout.entries[e].sets[later].weight = weight
                }
            }
            active = workout
            return true
        }
        return false
    }
}
