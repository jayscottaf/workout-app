import Foundation

// The built-in catalog: muscles, equipment types, exercises and the 3-day routine.
// Everything in Core/ is plain Swift (no SwiftUI/SwiftData) so it can be unit-tested anywhere.

enum MuscleGroup: String, CaseIterable, Codable, Hashable {
    case chest, triceps, back, biceps, shoulders, legs, abs

    var title: String {
        switch self {
        case .chest: return "Chest"
        case .triceps: return "Triceps"
        case .back: return "Back"
        case .biceps: return "Biceps"
        case .shoulders: return "Shoulders"
        case .legs: return "Legs"
        case .abs: return "Abs"
        }
    }
}

enum Muscle: String, CaseIterable, Codable, Hashable {
    case chest, triceps, lats, upperBack, lowerBack, biceps, delts, rearDelts, quads, hamstrings, glutes, calves, abs

    var group: MuscleGroup {
        switch self {
        case .chest: return .chest
        case .triceps: return .triceps
        case .lats, .upperBack, .lowerBack: return .back
        case .biceps: return .biceps
        case .delts, .rearDelts: return .shoulders
        case .quads, .hamstrings, .glutes, .calves: return .legs
        case .abs: return .abs
        }
    }

    var title: String {
        switch self {
        case .chest: return "Chest"
        case .triceps: return "Triceps"
        case .lats: return "Lats"
        case .upperBack: return "Mid back"
        case .lowerBack: return "Lower back"
        case .biceps: return "Biceps"
        case .delts: return "Delts"
        case .rearDelts: return "Rear delts"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .abs: return "Abs"
        }
    }

    /// "Rear delts are due" vs "Chest is due".
    var isPlural: Bool {
        switch self {
        case .chest, .upperBack, .lowerBack: return false
        default: return true
        }
    }
}

enum EquipmentCategory: String, Codable {
    /// Dumbbells and barbells: a pound is a pound at every gym, so history is shared.
    case freeWeight
    /// Body weight moves (may need a bar or station, but history is shared).
    case bodyweight
    /// Stacks, cables and plate-loaded machines: each one feels different, so history is per machine.
    case machine
}

struct EquipmentType: Identifiable, Hashable {
    let id: String
    let name: String
    let category: EquipmentCategory
    let defaultIncrement: Double
    let loading: String
}

enum EquipmentCatalog {
    static let bodyweightID = "bodyweight"

    /// Machines you added yourself. Filled in from saved data when the app starts.
    static var custom: [EquipmentType] = []
    /// Ones you removed: no longer offered, but old workouts still know their names.
    static var retired: [EquipmentType] = []

    static var all: [EquipmentType] { builtIn + custom }

    static let builtIn: [EquipmentType] = [
        EquipmentType(id: "dumbbells", name: "Dumbbells", category: .freeWeight, defaultIncrement: 5, loading: "Free weight"),
        EquipmentType(id: "barbell", name: "Barbell and plates", category: .freeWeight, defaultIncrement: 5, loading: "Free weight"),
        EquipmentType(id: "ezBar", name: "EZ curl bar (bent bar)", category: .freeWeight, defaultIncrement: 5,
                      loading: "Free weight · bar about 20 lb"),
        EquipmentType(id: "pullupBar", name: "Pull-up bar", category: .bodyweight, defaultIncrement: 5, loading: "Body weight"),
        EquipmentType(id: "dipStation", name: "Dip station", category: .bodyweight, defaultIncrement: 5, loading: "Body weight"),
        EquipmentType(id: "backExtension", name: "Back extension bench", category: .bodyweight, defaultIncrement: 5,
                      loading: "Body weight · hold a plate for more"),
        EquipmentType(id: "cable", name: "Cable station", category: .machine, defaultIncrement: 5, loading: "Weight stack"),
        EquipmentType(id: "latPulldown", name: "Lat pulldown", category: .machine, defaultIncrement: 5, loading: "Weight stack"),
        EquipmentType(id: "seatedRow", name: "Seated cable row", category: .machine, defaultIncrement: 5, loading: "Weight stack"),
        EquipmentType(id: "rowMachine", name: "Row machine", category: .machine, defaultIncrement: 5, loading: "Plate-loaded"),
        EquipmentType(id: "tBarRow", name: "T-bar row", category: .machine, defaultIncrement: 10, loading: "Plate-loaded"),
        EquipmentType(id: "assistedPullup", name: "Assisted pull-up machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "chestPress", name: "Chest press machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "pecDeck", name: "Pec deck", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "shoulderPress", name: "Shoulder press machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "lateralMachine", name: "Lateral raise machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "tricepsMachine", name: "Triceps extension machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "preacherMachine", name: "Preacher curl machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "smith", name: "Smith machine", category: .machine, defaultIncrement: 5, loading: "Plate-loaded"),
        EquipmentType(id: "legPress", name: "Leg press", category: .machine, defaultIncrement: 10, loading: "Plate-loaded"),
        EquipmentType(id: "hackSquat", name: "Hack squat", category: .machine, defaultIncrement: 10, loading: "Plate-loaded"),
        EquipmentType(id: "legExtension", name: "Leg extension", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "legCurl", name: "Leg curl", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "calfRaise", name: "Calf raise machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
        EquipmentType(id: "abMachine", name: "Ab crunch machine", category: .machine, defaultIncrement: 10, loading: "Weight stack"),
    ]

    static let bodyweight = EquipmentType(id: bodyweightID, name: "Body weight", category: .bodyweight, defaultIncrement: 5, loading: "Body weight")

    private static let index: [String: EquipmentType] = Dictionary(uniqueKeysWithValues: (builtIn + [bodyweight]).map { ($0.id, $0) })

    static func type(_ id: String) -> EquipmentType? {
        index[id] ?? custom.first { $0.id == id } ?? retired.first { $0.id == id }
    }

    /// What a typical commercial gym has. Used to pre-tick the list when adding a gym.
    static let commonIDs: [String] = [
        "dumbbells", "barbell", "pullupBar", "cable", "latPulldown", "seatedRow",
        "chestPress", "pecDeck", "legPress", "legExtension", "legCurl", "calfRaise",
    ]
}

struct ExerciseDef: Identifiable, Hashable {
    let id: String
    let name: String
    let muscle: Muscle
    let secondary: [Muscle]
    /// EquipmentType id.
    let equipment: String
    /// Movement pattern. Two exercises with the same pattern are the closest substitutes.
    let pattern: String
    let repLow: Int
    let repHigh: Int
    let compound: Bool
    /// A deliberately light first-time weight.
    let starterWeight: Double

    var range: ClosedRange<Int> { repLow...repHigh }
    var equipmentType: EquipmentType { EquipmentCatalog.type(equipment) ?? EquipmentCatalog.bodyweight }
    var isBodyweight: Bool { equipmentType.category == .bodyweight }
    var restSeconds: Int { compound ? 120 : 75 }
}

enum ExerciseCatalog {
    private static func ex(_ id: String, _ name: String, _ muscle: Muscle, _ secondary: [Muscle], _ equipment: String,
                           _ pattern: String, _ low: Int, _ high: Int, compound: Bool = false, start: Double = 0) -> ExerciseDef {
        ExerciseDef(id: id, name: name, muscle: muscle, secondary: secondary, equipment: equipment, pattern: pattern,
                    repLow: low, repHigh: high, compound: compound, starterWeight: start)
    }

    /// Exercises you made yourself. Filled in from saved data when the app starts.
    static var custom: [ExerciseDef] = []
    /// Ones you removed: no longer offered, but old workouts still know their names.
    static var retired: [ExerciseDef] = []

    static var all: [ExerciseDef] { builtIn + custom }

    static let builtIn: [ExerciseDef] = [
        // Chest
        ex("db_bench", "Dumbbell bench press", .chest, [.triceps, .delts], "dumbbells", "hpress", 8, 12, compound: true, start: 30),
        ex("bb_bench", "Barbell bench press", .chest, [.triceps, .delts], "barbell", "hpress", 6, 10, compound: true, start: 95),
        ex("machine_chest_press", "Chest press machine", .chest, [.triceps, .delts], "chestPress", "hpress", 8, 12, compound: true, start: 60),
        ex("smith_bench", "Smith machine bench press", .chest, [.triceps, .delts], "smith", "hpress", 8, 12, compound: true, start: 70),
        ex("pushup", "Push-up", .chest, [.triceps, .delts], "bodyweight", "hpress", 10, 20, compound: true),
        ex("incline_db_press", "Incline dumbbell press", .chest, [.delts, .triceps], "dumbbells", "ipress", 8, 12, compound: true, start: 25),
        ex("incline_bb_press", "Incline barbell press", .chest, [.delts, .triceps], "barbell", "ipress", 6, 10, compound: true, start: 75),
        ex("smith_incline", "Smith machine incline press", .chest, [.delts, .triceps], "smith", "ipress", 8, 12, compound: true, start: 60),
        ex("cable_fly", "Cable fly", .chest, [], "cable", "fly", 10, 15, start: 20),
        ex("pec_deck", "Pec deck fly", .chest, [], "pecDeck", "fly", 10, 15, start: 50),
        ex("db_fly", "Dumbbell fly", .chest, [], "dumbbells", "fly", 10, 15, start: 15),
        // Triceps
        ex("pushdown", "Triceps pushdown", .triceps, [], "cable", "tri_ext", 10, 15, start: 30),
        ex("one_arm_pulldown", "One-arm triceps pulldown", .triceps, [], "cable", "tri_ext", 10, 15, start: 15),
        ex("tri_machine", "Triceps extension machine", .triceps, [], "tricepsMachine", "tri_ext", 10, 15, start: 40),
        ex("db_overhead_ext", "Overhead dumbbell extension", .triceps, [], "dumbbells", "tri_oh", 10, 15, start: 25),
        ex("cable_overhead_ext", "Overhead cable extension", .triceps, [], "cable", "tri_oh", 10, 15, start: 25),
        ex("ez_skullcrusher", "EZ-bar skull crusher", .triceps, [], "ezBar", "tri_oh", 8, 12, start: 30),
        ex("skullcrusher", "Skull crusher", .triceps, [], "barbell", "tri_oh", 8, 12, start: 40),
        ex("bench_dip", "Bench dip", .triceps, [.chest], "bodyweight", "dip", 10, 20),
        ex("dip", "Dip", .triceps, [.chest, .delts], "dipStation", "dip", 6, 12, compound: true),
        // Back
        ex("lat_pulldown", "Lat pulldown", .lats, [.biceps, .upperBack], "latPulldown", "vpull", 8, 12, compound: true, start: 80),
        ex("pullup", "Pull-up", .lats, [.biceps, .upperBack], "pullupBar", "vpull", 5, 10, compound: true),
        ex("assisted_pullup", "Assisted pull-up", .lats, [.biceps, .upperBack], "assistedPullup", "vpull", 6, 10, compound: true, start: 60),
        ex("cable_row", "Seated cable row", .upperBack, [.lats, .biceps, .rearDelts], "seatedRow", "row", 8, 12, compound: true, start: 80),
        ex("db_row", "One-arm dumbbell row", .upperBack, [.lats, .biceps, .rearDelts], "dumbbells", "row", 8, 12, compound: true, start: 35),
        ex("bb_row", "Barbell row", .upperBack, [.lats, .biceps, .rearDelts, .lowerBack], "barbell", "row", 6, 10, compound: true, start: 85),
        ex("chest_supported_row", "Chest-supported dumbbell row", .upperBack, [.lats, .biceps, .rearDelts], "dumbbells", "row", 8, 12, compound: true, start: 25),
        ex("tbar_row", "T-bar row", .upperBack, [.lats, .biceps, .rearDelts, .lowerBack], "tBarRow", "row", 8, 12, compound: true, start: 45),
        ex("inverted_row", "Inverted row", .upperBack, [.lats, .biceps, .rearDelts], "bodyweight", "row", 8, 15, compound: true),
        ex("machine_row", "Row machine", .upperBack, [.lats, .biceps, .rearDelts], "rowMachine", "row", 8, 12, compound: true, start: 70),
        ex("db_pullover", "Dumbbell pullover", .lats, [.chest], "dumbbells", "pullover", 10, 15, start: 30),
        ex("straight_arm", "Straight-arm pulldown", .lats, [], "cable", "pullover", 10, 15, start: 30),
        ex("back_ext", "Back extension", .lowerBack, [.glutes, .hamstrings], "backExtension", "back_ext", 10, 15),
        ex("face_pull", "Face pull", .rearDelts, [.upperBack], "cable", "rear", 12, 15, start: 25),
        ex("reverse_fly", "Reverse dumbbell fly", .rearDelts, [.upperBack], "dumbbells", "rear", 12, 15, start: 10),
        ex("reverse_pec_deck", "Reverse pec deck", .rearDelts, [.upperBack], "pecDeck", "rear", 12, 15, start: 40),
        // Biceps
        ex("db_curl", "Dumbbell curl", .biceps, [], "dumbbells", "curl", 8, 12, start: 20),
        ex("bb_curl", "Barbell curl", .biceps, [], "barbell", "curl", 8, 12, start: 45),
        ex("cable_curl", "Cable curl", .biceps, [], "cable", "curl", 10, 15, start: 30),
        ex("ez_preacher", "EZ-bar preacher curl", .biceps, [], "ezBar", "curl", 8, 12, start: 40),
        ex("ez_curl", "EZ-bar curl", .biceps, [], "ezBar", "curl", 8, 12, start: 40),
        ex("preacher", "Preacher curl machine", .biceps, [], "preacherMachine", "curl", 10, 12, start: 40),
        ex("hammer_curl", "Hammer curl", .biceps, [], "dumbbells", "hammer", 10, 12, start: 20),
        ex("rope_hammer", "Rope hammer curl", .biceps, [], "cable", "hammer", 10, 15, start: 30),
        // Shoulders
        ex("db_ohp", "Dumbbell shoulder press", .delts, [.triceps], "dumbbells", "vpress", 8, 12, compound: true, start: 25),
        ex("bb_ohp", "Overhead press", .delts, [.triceps], "barbell", "vpress", 6, 10, compound: true, start: 65),
        ex("machine_ohp", "Shoulder press machine", .delts, [.triceps], "shoulderPress", "vpress", 8, 12, compound: true, start: 50),
        ex("smith_ohp", "Smith machine shoulder press", .delts, [.triceps], "smith", "vpress", 8, 12, compound: true, start: 50),
        ex("lateral_raise", "Lateral raise", .delts, [], "dumbbells", "lateral", 12, 15, start: 10),
        ex("cable_lateral", "Cable lateral raise", .delts, [], "cable", "lateral", 12, 15, start: 10),
        ex("machine_lateral", "Lateral raise machine", .delts, [], "lateralMachine", "lateral", 12, 15, start: 40),
        // Legs
        ex("leg_press", "Leg press", .quads, [.glutes, .hamstrings], "legPress", "squat", 10, 15, compound: true, start: 180),
        ex("hack_squat", "Hack squat", .quads, [.glutes], "hackSquat", "squat", 8, 12, compound: true, start: 90),
        ex("bb_squat", "Barbell squat", .quads, [.glutes, .hamstrings, .lowerBack], "barbell", "squat", 5, 8, compound: true, start: 135),
        ex("smith_squat", "Smith machine squat", .quads, [.glutes], "smith", "squat", 8, 12, compound: true, start: 90),
        ex("goblet_squat", "Goblet squat", .quads, [.glutes], "dumbbells", "squat", 10, 15, compound: true, start: 35),
        ex("leg_ext", "Leg extension", .quads, [], "legExtension", "knee_ext", 10, 15, start: 70),
        ex("db_lunge", "Dumbbell lunge", .quads, [.glutes], "dumbbells", "lunge", 10, 12, compound: true, start: 20),
        ex("leg_curl", "Leg curl", .hamstrings, [], "legCurl", "knee_flex", 10, 15, start: 60),
        ex("db_rdl", "Dumbbell Romanian deadlift", .hamstrings, [.glutes, .lowerBack], "dumbbells", "hinge", 8, 12, compound: true, start: 35),
        ex("bb_rdl", "Barbell Romanian deadlift", .hamstrings, [.glutes, .lowerBack], "barbell", "hinge", 8, 12, compound: true, start: 95),
        ex("bb_deadlift", "Deadlift", .glutes, [.hamstrings, .lowerBack, .upperBack, .quads, .lats], "barbell", "hinge", 5, 8, compound: true, start: 135),
        ex("calf_raise_machine", "Calf raise machine", .calves, [], "calfRaise", "calf", 12, 15, start: 90),
        ex("leg_press_calf", "Leg press calf raise", .calves, [], "legPress", "calf", 12, 20, start: 90),
        ex("db_calf_raise", "Dumbbell calf raise", .calves, [], "dumbbells", "calf", 12, 20, start: 25),
        // Abs
        ex("cable_crunch", "Cable crunch", .abs, [], "cable", "abs_flex", 12, 15, start: 50),
        ex("ab_machine", "Ab crunch machine", .abs, [], "abMachine", "abs_flex", 12, 15, start: 50),
        ex("crunch", "Crunch", .abs, [], "bodyweight", "abs_flex", 15, 25),
        ex("hanging_knee_raise", "Hanging knee raise", .abs, [], "pullupBar", "abs_leg", 10, 15),
        ex("lying_leg_raise", "Lying leg raise", .abs, [], "bodyweight", "abs_leg", 10, 15),
        ex("bicycle_crunch", "Bicycle crunch", .abs, [], "bodyweight", "abs_rot", 15, 25),
    ]

    private static let index: [String: ExerciseDef] = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.id, $0) })

    static func exercise(_ id: String) -> ExerciseDef? {
        index[id] ?? custom.first { $0.id == id } ?? retired.first { $0.id == id }
    }

    static func isRetired(_ id: String) -> Bool { retired.contains { $0.id == id } }

    /// A deliberately light first weight for an exercise you made yourself.
    static func starterWeight(equipment: String) -> Double {
        switch equipment {
        case EquipmentCatalog.bodyweightID, "pullupBar", "dipStation": return 0
        case "dumbbells": return 10
        case "barbell": return 45
        default: return 20
        }
    }
}

/// One exercise position in a day. `key` stays the same when the day is reordered, so the app
/// still remembers what you swapped in for that position at each gym.
struct DaySlot: Codable, Hashable {
    var key: String
    var exercise: String
}

/// One day of the routine, for example "Chest & triceps". Days rotate in order and can be edited.
struct DayType: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var items: [DaySlot]
    /// Which positions make up the 20-minute version. nil = worked out from the exercises.
    var quick: [Int]?

    init(id: String = "day-" + UUID().uuidString, title: String, exercises: [String], quick: [Int]? = nil) {
        self.id = id
        self.title = title
        self.items = exercises.enumerated().map { DaySlot(key: String($0.offset), exercise: $0.element) }
        self.quick = quick
    }

    var rawValue: String { id }

    /// Default exercise for each position of the full workout, in order.
    var slots: [String] { items.map(\.exercise) }

    static var allCases: [DayType] { Routine.days }

    var number: Int { (Routine.days.firstIndex { $0.id == id } ?? 0) + 1 }

    /// The day after this one. A day that is no longer in the routine leads back to the first day.
    var next: DayType {
        let all = Routine.days
        guard let index = all.firstIndex(where: { $0.id == id }) else { return all.first ?? self }
        return all[(index + 1) % all.count]
    }

    /// The muscle groups this day is mainly about (two or more exercises), in order of appearance.
    var groups: [MuscleGroup] {
        var counts: [MuscleGroup: Int] = [:]
        var order: [MuscleGroup] = []
        for id in slots {
            guard let group = ExerciseCatalog.exercise(id)?.muscle.group else { continue }
            if counts[group] == nil { order.append(group) }
            counts[group, default: 0] += 1
        }
        let main = order.filter { (counts[$0] ?? 0) >= 2 }
        return main.isEmpty ? order : main
    }

    /// Which positions make up the 20-minute version: up to four, taking turns between the main muscle groups.
    var quickSlotIndexes: [Int] {
        if let quick, quick.allSatisfy({ items.indices.contains($0) }) { return quick }
        var byGroup: [[Int]] = groups.map { group in
            items.indices.filter { ExerciseCatalog.exercise(items[$0].exercise)?.muscle.group == group }
        }
        var picks: [Int] = []
        while picks.count < 4, byGroup.contains(where: { !$0.isEmpty }) {
            for index in byGroup.indices where picks.count < 4 && !byGroup[index].isEmpty {
                picks.append(byGroup[index].removeFirst())
            }
        }
        for index in items.indices where picks.count < 4 && !picks.contains(index) { picks.append(index) }
        return picks
    }

    func slotID(_ index: Int) -> String { "\(id).\(items[index].key)" }

    // Editing. Any change to the list drops the hand-picked 20-minute version.

    mutating func add(_ exercise: String) {
        items.append(DaySlot(key: String(UUID().uuidString.prefix(8)), exercise: exercise))
        quick = nil
    }

    mutating func remove(at index: Int) {
        items.remove(at: index)
        quick = nil
    }

    mutating func move(from source: Int, to destination: Int) {
        let item = items.remove(at: source)
        items.insert(item, at: min(destination, items.count))
        quick = nil
    }

    // The original three days.
    static let chestTriceps = DayType(id: "chestTriceps", title: "Chest & triceps",
        exercises: ["db_bench", "incline_db_press", "cable_fly", "pushdown", "db_overhead_ext", "bench_dip"], quick: [0, 1, 3, 4])
    static let backBiceps = DayType(id: "backBiceps", title: "Back & biceps",
        exercises: ["lat_pulldown", "cable_row", "db_row", "face_pull", "db_curl", "hammer_curl"], quick: [0, 1, 4, 5])
    static let shouldersLegs = DayType(id: "shouldersLegs", title: "Shoulders & legs",
        exercises: ["db_ohp", "lateral_raise", "leg_press", "leg_curl", "leg_ext", "calf_raise_machine"], quick: [0, 2, 1, 3])
}

/// A ready-made routine to start from.
struct RoutinePreset: Identifiable {
    let id: String
    let name: String
    let summary: String
    let days: [DayType]
}

enum Presets {
    static let classic = RoutinePreset(id: "classic", name: "Chest & tri · Back & bi · Shoulders & legs",
        summary: "3 days. Two muscle groups each day.",
        days: [.chestTriceps, .backBiceps, .shouldersLegs])

    static let pushPullLegs = RoutinePreset(id: "ppl", name: "Push · Pull · Legs",
        summary: "3 days. Pushing muscles, pulling muscles, then legs.",
        days: [
            DayType(id: "push", title: "Push",
                    exercises: ["db_bench", "incline_db_press", "db_ohp", "lateral_raise", "pushdown", "db_overhead_ext"]),
            DayType(id: "pull", title: "Pull",
                    exercises: ["lat_pulldown", "cable_row", "db_row", "face_pull", "db_curl", "hammer_curl"]),
            DayType(id: "legs", title: "Legs",
                    exercises: ["leg_press", "db_rdl", "leg_ext", "leg_curl", "db_lunge", "calf_raise_machine"]),
        ])

    static let upperLower = RoutinePreset(id: "upperLower", name: "Upper · Lower",
        summary: "2 days. Upper body one day, lower body the next.",
        days: [
            DayType(id: "upper", title: "Upper body",
                    exercises: ["db_bench", "lat_pulldown", "db_ohp", "cable_row", "db_curl", "pushdown"]),
            DayType(id: "lower", title: "Lower body",
                    exercises: ["leg_press", "db_rdl", "leg_ext", "leg_curl", "goblet_squat", "calf_raise_machine"]),
        ])

    static let fullBody = RoutinePreset(id: "fullBody", name: "Full body A · B",
        summary: "2 days. Everything each time, with different exercises.",
        days: [
            DayType(id: "fullA", title: "Full body A",
                    exercises: ["leg_press", "db_bench", "lat_pulldown", "db_ohp", "db_curl", "pushdown"]),
            DayType(id: "fullB", title: "Full body B",
                    exercises: ["goblet_squat", "incline_db_press", "cable_row", "db_rdl", "lateral_raise", "hammer_curl"]),
        ])

    static let all: [RoutinePreset] = [classic, pushPullLegs, upperLower, fullBody]
}

/// The routine in use: the days, in the order they rotate. Filled in from saved data when the app starts.
enum Routine {
    static var days: [DayType] = Presets.classic.days

    /// A day by id: from the routine in use, else from the ready-made ones (so old workouts keep their names).
    static func day(_ id: String) -> DayType? {
        days.first { $0.id == id } ?? Presets.all.flatMap(\.days).first { $0.id == id }
    }
}

enum AbsAddOn {
    static let slots = ["cable_crunch", "hanging_knee_raise", "bicycle_crunch"]
    static func slotID(_ index: Int) -> String { "abs.\(index)" }
}

enum Fmt {
    /// 120 -> "120", 122.5 -> "122.5"
    static func weight(_ w: Double) -> String {
        if w == w.rounded() { return String(Int(w)) }
        return String(format: "%.1f", w)
    }

    static func lb(_ w: Double) -> String { "\(weight(w)) lb" }

    /// A weight the lifter typed, in pounds: "225", "122.5", "122,5" or "225 lb".
    /// Rounded to one decimal place, the precision the app shows. Nil for anything that isn't
    /// a weight from 0 (body weight) to 2,000 lb, so a stray typo leaves the set unchanged.
    static func parseWeight(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["lbs", "lb"] where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        t = t.replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let value = Double(t), value.isFinite, value >= 0, value <= 2000 else { return nil }
        return (value * 10).rounded() / 10
    }
}
