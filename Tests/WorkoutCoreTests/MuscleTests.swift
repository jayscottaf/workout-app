import XCTest
@testable import WorkoutCore

/// Muscles worked, muscles missed this week, two exercises doing the same job, and form tips.
final class MuscleTests: XCTestCase {
    private func ex(_ id: String) -> ExerciseDef { ExerciseCatalog.exercise(id)! }

    func testSameMovementIsFlagged() {
        let overlap = Overlap.find(ex("machine_chest_press"), among: [ex("db_bench"), ex("pushdown")])
        XCTAssertEqual(overlap?.other.id, "db_bench")
        XCTAssertEqual(overlap?.kind, .sameMovement)
        XCTAssertEqual(overlap?.message, "Same job as Dumbbell bench press: both flat presses for chest.")
    }

    func testDifferentAngleIsNotFlagged() {
        XCTAssertNil(Overlap.find(ex("incline_db_press"), among: [ex("db_bench")]))
        XCTAssertNil(Overlap.find(ex("db_overhead_ext"), among: [ex("pushdown")]))
        XCTAssertNil(Overlap.find(ex("db_rdl"), among: [ex("leg_curl")]))
        XCTAssertNil(Overlap.find(ex("db_lunge"), among: [ex("leg_ext")]))
        XCTAssertNil(Overlap.find(ex("db_bench"), among: [ex("db_bench")]))
    }

    func testOwnExerciseGetsASofterNote() {
        let own = ExerciseDef(id: "custom-x", name: "Plate press", muscle: .chest, secondary: [], equipment: "dumbbells",
                              pattern: "custom.chest", repLow: 8, repHigh: 12, compound: false, starterWeight: 10)
        let overlap = Overlap.find(own, among: [ex("db_bench")])
        XCTAssertEqual(overlap?.kind, .sameMuscle)
        XCTAssertEqual(overlap?.message, "Also works chest, like Dumbbell bench press.")
    }

    func testWorkCountsMainAndHelperSets() {
        let work = MuscleMap.work([("lat_pulldown", 3), ("cable_row", 3), ("db_curl", 2)])
        XCTAssertEqual(work.first { $0.muscle == .lats }, MuscleWork(muscle: .lats, mainSets: 3, helperSets: 3))
        XCTAssertEqual(work.first { $0.muscle == .upperBack }, MuscleWork(muscle: .upperBack, mainSets: 3, helperSets: 3))
        XCTAssertEqual(work.first { $0.muscle == .biceps }, MuscleWork(muscle: .biceps, mainSets: 2, helperSets: 6))
        XCTAssertNil(work.first { $0.muscle == .chest })
    }

    func testTargetsKeepOrderWithoutRepeats() {
        XCTAssertEqual(MuscleMap.targets(["db_bench", "incline_db_press", "pushdown", "lateral_raise"]), [.chest, .triceps, .delts])
    }

    func testMissedThisWeekSuggestsWhatTheGymHas() {
        let now = Date()
        let bench = EntryRecord(exerciseID: "db_bench", historyKey: "db_bench", slotID: nil,
                                sets: [SetRecord(weight: 30, reps: 10)])
        let history = History([WorkoutRecord(date: now, day: nil, gymID: nil, entries: [bench])])
        let gym = GymInfo(id: UUID(), name: "Gym", equipment: [EquipmentInfo(id: UUID(), typeID: "legCurl", name: "Leg curl", increment: 10)])
        let missed = MuscleMap.missedThisWeek(history: history, gym: gym, now: now)
        XCTAssertFalse(missed.contains { $0.muscle == .chest && $0.part == nil })
        XCTAssertFalse(missed.contains { $0.muscle == .abs })
        XCTAssertEqual(missed.first { $0.muscle == .hamstrings }?.suggestion?.id, "leg_curl")
        // Lats need a pulldown or bar this gym does not have.
        let lats = missed.first { $0.muscle == .lats }
        XCTAssertNotNil(lats)
        XCTAssertNil(lats?.suggestion)
    }

    func testKeptPairIsNotFlagged() {
        let raw = Overlap.keeping("db_row", "cable_row", in: "")
        let kept = Overlap.keptPairs(raw)
        XCTAssertTrue(kept.contains(Overlap.pairKey("cable_row", "db_row")))
        XCTAssertNil(Overlap.find(ex("db_row"), among: [ex("cable_row")], kept: kept))
        XCTAssertNotNil(Overlap.find(ex("db_row"), among: [ex("cable_row")]))
        XCTAssertEqual(Overlap.firstPair([ex("lat_pulldown"), ex("cable_row"), ex("db_row")])?.exercise.id, "db_row")
    }

    func testChestDayBreakdown() {
        let ids = DayType.chestTriceps.slots
        let chest = MuscleParts.breakdown(ids, muscle: .chest)
        XCTAssertEqual(chest.map(\.part), ["Upper", "Middle", "Lower"])
        XCTAssertEqual(chest[0].exercises, ["Incline dumbbell press"])
        XCTAssertEqual(chest[1].exercises, ["Dumbbell bench press", "Cable fly"])
        XCTAssertEqual(chest[2].exercises, ["Bench dip"])
        let triceps = MuscleParts.sets([("pushdown", 3), ("db_overhead_ext", 2), ("bench_dip", 3)], muscle: .triceps)
        XCTAssertEqual(triceps.map(\.sets), [2, 6])
        XCTAssertEqual(MuscleParts.label("Long head", of: .triceps), "Triceps long head")
    }

    func testMissedPartWhenMuscleWasTrained() {
        let now = Date()
        let flat = EntryRecord(exerciseID: "db_bench", historyKey: "db_bench", slotID: nil, sets: [SetRecord(weight: 30, reps: 10)])
        let history = History([WorkoutRecord(date: now, day: nil, gymID: nil, entries: [flat])])
        let missed = MuscleMap.missedThisWeek(history: history, gym: nil, now: now)
        let upper = missed.first { $0.muscle == .chest && $0.part == "Upper" }
        XCTAssertEqual(upper?.title, "Upper chest")
        XCTAssertNotNil(upper?.suggestion)
        XCTAssertFalse(missed.contains { $0.muscle == .chest && $0.part == "Lower" })
        XCTAssertFalse(missed.contains { $0.muscle == .chest && $0.part == "Middle" })
    }

    func testHelperSetsCountHalf() {
        let now = Date()
        let deadlift = EntryRecord(exerciseID: "bb_deadlift", historyKey: "bb_deadlift", slotID: nil,
                                   sets: Array(repeating: SetRecord(weight: 135, reps: 5), count: 4))
        let history = History([WorkoutRecord(date: now, day: nil, gymID: nil, entries: [deadlift])])
        let sets = MuscleMap.weeklySets(history.workouts, weekOf: now)
        XCTAssertEqual(sets[.glutes], 4)
        XCTAssertEqual(sets[.lowerBack], 2)
        let missed = MuscleMap.missedThisWeek(history: history, gym: nil, now: now)
        XCTAssertFalse(missed.contains { $0.muscle == .lowerBack }, "4 deadlift sets count as 2 for the lower back")
        XCTAssertTrue(missed.contains { $0.muscle == .chest })
    }

    func testRenamedMuscles() {
        XCTAssertEqual(Muscle.upperBack.title, "Mid back")
        XCTAssertEqual(Muscle.delts.title, "Delts")
        XCTAssertEqual(MuscleParts.parts(of: .biceps), ["Main biceps", "Brachialis"])
    }

    func testEveryExerciseHasFormTips() {
        for exercise in ExerciseCatalog.builtIn {
            XCTAssertFalse(FormTips.tips(for: exercise.id).isEmpty, exercise.id)
        }
    }
}
