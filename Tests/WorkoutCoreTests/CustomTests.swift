import XCTest
@testable import WorkoutCore

/// Exercises and machines you add yourself behave like the built-in ones.
final class CustomTests: XCTestCase {
    private let machine = EquipmentType(id: "custom-m1", name: "Matrix glute machine", category: .machine,
                                        defaultIncrement: 10, loading: "Weight stack")
    private let kickback = ExerciseDef(id: "custom-e1", name: "Glute kickback", muscle: .glutes, secondary: [],
                                       equipment: "custom-m1", pattern: "custom.glutes", repLow: 10, repHigh: 15,
                                       compound: false, starterWeight: 20)

    override func setUp() {
        EquipmentCatalog.custom = [machine]
        ExerciseCatalog.custom = [kickback]
    }

    override func tearDown() {
        EquipmentCatalog.custom = []
        EquipmentCatalog.retired = []
        ExerciseCatalog.custom = []
        ExerciseCatalog.retired = []
    }

    private func gym(_ typeIDs: [String]) -> GymInfo {
        GymInfo(id: UUID(), name: "Gym", equipment: typeIDs.map {
            EquipmentInfo(id: UUID(), typeID: $0, name: $0, increment: 10)
        })
    }

    func testCustomEntriesJoinTheCatalog() {
        XCTAssertEqual(ExerciseCatalog.exercise("custom-e1")?.name, "Glute kickback")
        XCTAssertEqual(EquipmentCatalog.type("custom-m1")?.name, "Matrix glute machine")
        XCTAssertTrue(ExerciseCatalog.all.contains(kickback))
        XCTAssertEqual(kickback.equipmentType.category, .machine)
    }

    func testOnlyOfferedWhereTheGymHasTheMachine() {
        XCTAssertTrue(Planner.isAvailable(kickback, gym: gym(["custom-m1"])))
        XCTAssertFalse(Planner.isAvailable(kickback, gym: gym(["legPress"])))
    }

    func testPlansLikeABuiltInWithItsOwnMachineHistory() {
        let here = gym(["custom-m1"])
        let planned = Planner.planExercise(kickback, slotID: nil, gym: here, history: History([]))
        XCTAssertEqual(planned.increment, 10)
        XCTAssertEqual(planned.suggestion.targets.first?.weight, 20)
        XCTAssertTrue(planned.historyKey.contains(here.equipment[0].id.uuidString))
    }

    func testShowsUpAsASwapForTheSameMuscle() {
        let hipThrustLike = ExerciseCatalog.builtIn.first { $0.muscle == .glutes }
        guard let other = hipThrustLike else { return }
        let options = Planner.swapOptions(for: other, gym: gym(["custom-m1"]), history: History([]))
        XCTAssertTrue(options.contains { $0.exercise.id == "custom-e1" })
    }

    func testRemovedOnesKeepTheirNameButAreNotOffered() {
        ExerciseCatalog.custom = []
        ExerciseCatalog.retired = [kickback]
        XCTAssertEqual(ExerciseCatalog.exercise("custom-e1")?.name, "Glute kickback")
        XCTAssertFalse(ExerciseCatalog.all.contains(kickback))
        XCTAssertTrue(ExerciseCatalog.isRetired("custom-e1"))
    }
}

final class NewEquipmentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testEZBarPlatesStartFromTheLighterBar() {
        XCTAssertEqual(Plates.bar(forEquipment: "ezBar"), 20)
        // 70 lb on a 20 lb EZ bar is 25 a side.
        XCTAssertEqual(Plates.load(total: 70, bar: 20)?.perSide, [25])
        XCTAssertEqual(ExerciseCatalog.exercise("ez_preacher")?.equipmentType.category, .freeWeight)
    }

    func testBackExtensionIsBodyWeightWithNoPlateMaths() {
        let ext = ExerciseCatalog.exercise("back_ext")!
        XCTAssertTrue(ext.isBodyweight)
        XCTAssertNil(Plates.bar(forEquipment: ext.equipment))
        XCTAssertEqual(ext.muscle.group, .back)
    }

    func testHoldingAPlateProgressesLikeAWeightedLift() {
        let held = [Session(date: now.addingTimeInterval(-3 * 86_400), sets: [15, 15, 15].map { SetRecord(weight: 25, reps: $0) })]
        let s = Progression.suggest(sessions: held, range: 10...15, increment: 5, starterWeight: 0, bodyweight: true, now: now)
        XCTAssertEqual(s.kind, .increase)
        XCTAssertEqual(s.targets.map(\.weight), [30, 30, 30])

        let bare = [Session(date: now.addingTimeInterval(-3 * 86_400), sets: [15, 15, 15].map { SetRecord(weight: 0, reps: $0) })]
        let b = Progression.suggest(sessions: bare, range: 10...15, increment: 5, starterWeight: 0, bodyweight: true, now: now)
        XCTAssertEqual(b.targets.map(\.weight), [0, 0, 0])
        XCTAssertTrue(b.explanation.contains("hold a plate"))
    }
}
