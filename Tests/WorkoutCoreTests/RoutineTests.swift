import XCTest
@testable import WorkoutCore

/// The routine is data: days can be renamed, reordered, added, removed or replaced by a ready-made one.
final class RoutineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() { Routine.days = Presets.classic.days }

    private func done(_ day: DayType, daysAgo: Double) -> WorkoutRecord {
        WorkoutRecord(id: UUID(), date: now.addingTimeInterval(-daysAgo * 86_400), day: day, gymID: nil,
                      durationMinutes: 45, entries: [])
    }

    func testEveryReadyMadeRoutineUsesRealExercisesOnce() {
        for preset in Presets.all {
            XCTAssertFalse(preset.days.isEmpty)
            for day in preset.days {
                XCTAssertEqual(Set(day.slots).count, day.slots.count, "\(day.title): no exercise twice")
                for id in day.slots { XCTAssertNotNil(ExerciseCatalog.exercise(id), id) }
            }
        }
        let ids = Presets.all.flatMap(\.days).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "day ids are unique across routines")
    }

    func testRotationFollowsTheRoutineInUse() {
        Routine.days = Presets.pushPullLegs.days
        XCTAssertEqual(Rotation.nextDay(history: History([])).title, "Push")
        let afterPush = History([done(Routine.days[0], daysAgo: 1)])
        XCTAssertEqual(Rotation.nextDay(history: afterPush).title, "Pull")
        let afterLegs = History([done(Routine.days[2], daysAgo: 1)])
        XCTAssertEqual(Rotation.nextDay(history: afterLegs).title, "Push")
    }

    func testSwitchingRoutineStartsAtItsFirstDay() {
        // The last workout was a day from the old routine.
        let history = History([done(.backBiceps, daysAgo: 1)])
        Routine.days = Presets.upperLower.days
        XCTAssertEqual(Rotation.nextDay(history: history).title, "Upper body")
    }

    func testAFourDayRoutineOfYourOwn() {
        Routine.days = [
            DayType(title: "Chest", exercises: ["db_bench", "cable_fly"]),
            DayType(title: "Back", exercises: ["lat_pulldown", "cable_row"]),
            DayType(title: "Arms", exercises: ["db_curl", "pushdown", "hammer_curl"]),
            DayType(title: "Legs", exercises: ["leg_press", "leg_curl"]),
        ]
        XCTAssertEqual(Routine.days[2].number, 3)
        XCTAssertEqual(Routine.days[3].next.title, "Chest")
        let plan = Planner.plan(day: Routine.days[2], includeAbs: false, quick: false, gym: nil, history: History([]), now: now)
        XCTAssertEqual(plan.map(\.exercise.id), ["db_curl", "pushdown", "hammer_curl"])
    }

    func testQuickVersionOfAnyDayTakesTurnsBetweenMuscles() {
        for preset in Presets.all {
            for day in preset.days {
                let quick = Planner.plan(day: day, includeAbs: false, quick: true, gym: nil, history: History([]), now: now)
                XCTAssertEqual(quick.count, 4, day.title)
                XCTAssertLessThanOrEqual(Planner.estimateMinutes(quick), 20, day.title)
            }
        }
        let push = Presets.pushPullLegs.days[0]
        let groups = Set(push.quickSlotIndexes.compactMap { ExerciseCatalog.exercise(push.slots[$0])?.muscle.group })
        XCTAssertTrue(groups.count >= 2, "more than one muscle group")
    }

    func testReorderingADayKeepsWhatYouSwappedIn() {
        var day = DayType.chestTriceps
        let slotForFly = day.slotID(2)
        XCTAssertEqual(slotForFly, "chestTriceps.2")
        day.move(from: 2, to: 0)
        XCTAssertEqual(day.slots.first, "cable_fly")
        XCTAssertEqual(day.slotID(0), slotForFly, "the position keeps its identity")
        day.add("dip")
        XCTAssertEqual(day.slots.last, "dip")
        XCTAssertNotEqual(day.slotID(day.items.count - 1), slotForFly)
        day.remove(at: 0)
        XCTAssertFalse(day.slots.contains("cable_fly"))
        XCTAssertEqual(day.quickSlotIndexes.count, 4)
    }

    func testRoutineSavesAndLoads() throws {
        var day = DayType(title: "My day", exercises: ["db_bench"])
        day.add("pushdown")
        let data = try JSONEncoder().encode([day, .backBiceps])
        XCTAssertEqual(try JSONDecoder().decode([DayType].self, from: data), [day, .backBiceps])
    }
}
