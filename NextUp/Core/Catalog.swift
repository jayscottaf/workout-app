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
    case chest, triceps, lats, upperBack, biceps, delts, rearDelts, quads, hamstrings, glutes, calves, abs

    var group: MuscleGroup {
        switch self {
        case .chest: return .chest
        case .triceps: return .triceps
        case .lats, .upperBack: return .back
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
        case .upperBack: return "Upper back"
        case .biceps: return "Biceps"
        case .delts: return "Shoulders"
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
        case .chest, .upperBack: return false
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

    static let all: [EquipmentType] = [
        EquipmentType(id: "dumbbells", name: "Dumbbells", category: .freeWeight, defaultIncrement: 5, loading: "Free weight"),
        EquipmentType(id: "barbell", name: "Barbell and plates", category: .freeWeight, defaultIncrement: 5, loading: "Free weight"),
        EquipmentType(id: "pullupBar", name: "Pull-up bar", category: .bodyweight, defaultIncrement: 5, loading: "Body weight"),
        EquipmentType(id: "dipStation", name: "Dip station", category: .bodyweight, defaultIncrement: 5, loading: "Body weight"),
        EquipmentType(id: "cable", name: "Cable station", category: .machine, defaultIncrement: 5, loading: "Weight stack"),
        EquipmentType(id: "latPulldown", name: "Lat pulldown", category: .machine, defaultIncrement: 5, loading: "Weight stack"),
        EquipmentType(id: "seatedRow", name: "Seated cable row", category: .machine, defaultIncrement: 5, loading: "Weight stack"),
        EquipmentType(id: "rowMachine", name: "Row machine", category: .machine, defaultIncrement: 5, loading: "Plate-loaded"),
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

    private static let index: [String: EquipmentType] = Dictionary(uniqueKeysWithValues: (all + [bodyweight]).map { ($0.id, $0) })

    static func type(_ id: String) -> EquipmentType? { index[id] }

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

    static let all: [ExerciseDef] = [
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
        ex("tri_machine", "Triceps extension machine", .triceps, [], "tricepsMachine", "tri_ext", 10, 15, start: 40),
        ex("db_overhead_ext", "Overhead dumbbell extension", .triceps, [], "dumbbells", "tri_oh", 10, 15, start: 25),
        ex("cable_overhead_ext", "Overhead cable extension", .triceps, [], "cable", "tri_oh", 10, 15, start: 25),
        ex("skullcrusher", "Skull crusher", .triceps, [], "barbell", "tri_oh", 8, 12, start: 40),
        ex("bench_dip", "Bench dip", .triceps, [.chest], "bodyweight", "dip", 10, 20),
        ex("dip", "Dip", .triceps, [.chest, .delts], "dipStation", "dip", 6, 12, compound: true),
        // Back
        ex("lat_pulldown", "Lat pulldown", .lats, [.biceps, .upperBack], "latPulldown", "vpull", 8, 12, compound: true, start: 80),
        ex("pullup", "Pull-up", .lats, [.biceps, .upperBack], "pullupBar", "vpull", 5, 10, compound: true),
        ex("assisted_pullup", "Assisted pull-up", .lats, [.biceps, .upperBack], "assistedPullup", "vpull", 6, 10, compound: true, start: 60),
        ex("cable_row", "Seated cable row", .upperBack, [.lats, .biceps], "seatedRow", "row", 8, 12, compound: true, start: 80),
        ex("db_row", "One-arm dumbbell row", .upperBack, [.lats, .biceps], "dumbbells", "row", 8, 12, compound: true, start: 35),
        ex("bb_row", "Barbell row", .upperBack, [.lats, .biceps], "barbell", "row", 6, 10, compound: true, start: 85),
        ex("machine_row", "Row machine", .upperBack, [.lats, .biceps], "rowMachine", "row", 8, 12, compound: true, start: 70),
        ex("db_pullover", "Dumbbell pullover", .lats, [.chest], "dumbbells", "pullover", 10, 15, start: 30),
        ex("straight_arm", "Straight-arm pulldown", .lats, [], "cable", "pullover", 10, 15, start: 30),
        ex("face_pull", "Face pull", .rearDelts, [.upperBack], "cable", "rear", 12, 15, start: 25),
        ex("reverse_fly", "Reverse dumbbell fly", .rearDelts, [.upperBack], "dumbbells", "rear", 12, 15, start: 10),
        ex("reverse_pec_deck", "Reverse pec deck", .rearDelts, [.upperBack], "pecDeck", "rear", 12, 15, start: 40),
        // Biceps
        ex("db_curl", "Dumbbell curl", .biceps, [], "dumbbells", "curl", 8, 12, start: 20),
        ex("bb_curl", "Barbell curl", .biceps, [], "barbell", "curl", 8, 12, start: 45),
        ex("cable_curl", "Cable curl", .biceps, [], "cable", "curl", 10, 15, start: 30),
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
        ex("bb_squat", "Barbell squat", .quads, [.glutes, .hamstrings], "barbell", "squat", 5, 8, compound: true, start: 135),
        ex("smith_squat", "Smith machine squat", .quads, [.glutes], "smith", "squat", 8, 12, compound: true, start: 90),
        ex("goblet_squat", "Goblet squat", .quads, [.glutes], "dumbbells", "squat", 10, 15, compound: true, start: 35),
        ex("leg_ext", "Leg extension", .quads, [], "legExtension", "knee_ext", 10, 15, start: 70),
        ex("db_lunge", "Dumbbell lunge", .quads, [.glutes], "dumbbells", "knee_ext", 10, 12, compound: true, start: 20),
        ex("leg_curl", "Leg curl", .hamstrings, [], "legCurl", "knee_flex", 10, 15, start: 60),
        ex("db_rdl", "Dumbbell Romanian deadlift", .hamstrings, [.glutes], "dumbbells", "knee_flex", 8, 12, compound: true, start: 35),
        ex("bb_rdl", "Barbell Romanian deadlift", .hamstrings, [.glutes], "barbell", "knee_flex", 8, 12, compound: true, start: 95),
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

    private static let index: [String: ExerciseDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func exercise(_ id: String) -> ExerciseDef? { index[id] }
}

/// The three rotating days.
enum DayType: String, CaseIterable, Codable, Hashable {
    case chestTriceps, backBiceps, shouldersLegs

    var title: String {
        switch self {
        case .chestTriceps: return "Chest & triceps"
        case .backBiceps: return "Back & biceps"
        case .shouldersLegs: return "Shoulders & legs"
        }
    }

    var number: Int { (DayType.allCases.firstIndex(of: self) ?? 0) + 1 }

    var next: DayType {
        let all = DayType.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }

    var groups: [MuscleGroup] {
        switch self {
        case .chestTriceps: return [.chest, .triceps]
        case .backBiceps: return [.back, .biceps]
        case .shouldersLegs: return [.shoulders, .legs]
        }
    }

    /// Default exercise for each slot of the full workout, in order.
    var slots: [String] {
        switch self {
        case .chestTriceps: return ["db_bench", "incline_db_press", "cable_fly", "pushdown", "db_overhead_ext", "bench_dip"]
        case .backBiceps: return ["lat_pulldown", "cable_row", "db_row", "face_pull", "db_curl", "hammer_curl"]
        case .shouldersLegs: return ["db_ohp", "lateral_raise", "leg_press", "leg_curl", "leg_ext", "calf_raise_machine"]
        }
    }

    /// Which slots make up the 20-minute version (biggest moves, both muscle groups).
    var quickSlotIndexes: [Int] {
        switch self {
        case .chestTriceps: return [0, 1, 3, 4]
        case .backBiceps: return [0, 1, 4, 5]
        case .shouldersLegs: return [0, 2, 1, 3]
        }
    }

    func slotID(_ index: Int) -> String { "\(rawValue).\(index)" }
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
}
