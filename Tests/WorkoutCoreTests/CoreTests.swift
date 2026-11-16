import XCTest
@testable import WorkoutCore

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_794_700_000) // fixed "today" so tests never drift

private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * day) }

private func session(_ daysAgo: Double, _ weight: Double, _ reps: [Int]) -> Session {
    Session(date: ago(daysAgo), sets: reps.map { SetRecord(weight: weight, reps: $0) })
}

private func suggest(_ sessions: [Session], increment: Double = 5, bodyweight: Bool = false, setCount: Int? = nil) -> Suggestion {
    Progression.suggest(sessions: sessions, range: 8...12, increment: increment, starterWeight: 30,
                        bodyweight: bodyweight, setCount: setCount, now: now)
}

private func workout(_ daysAgo: Double, _ dayType: DayType?, gym: UUID? = nil, _ entries: [EntryRecord]) -> WorkoutRecord {
    WorkoutRecord(date: ago(daysAgo), day: dayType, gymID: gym, entries: entries)
}

private func entry(_ id: String, key: String? = nil, slot: String? = nil, _ weight: Double, _ reps: [Int]) -> EntryRecord {
    EntryRecord(exerciseID: id, historyKey: key ?? id, slotID: slot, sets: reps.map { SetRecord(weight: weight, reps: $0) })
}

final class ProgressionTests: XCTestCase {

    func testFirstTimeUsesStarterWeightAndBottomOfRange() {
        let s = suggest([])
        XCTAssertEqual(s.kind, .firstTime)
        XCTAssertEqual(s.targets.count, 3)
        XCTAssertEqual(s.targets[0], SetTarget(weight: 30, reps: 8))
    }

    func testNormalSessionKeepsWeightAndAsksForOneMoreRep() {
        let s = suggest([session(3, 120, [11, 10, 9])])
        XCTAssertEqual(s.kind, .progress)
        XCTAssertEqual(s.targets.map(\.weight), [120, 120, 120])
        XCTAssertEqual(s.targets.map(\.reps), [12, 11, 10])
        XCTAssertEqual(s.targets[1].beatText, "Last time 120 × 10 · beat it with 11")
    }

    func testTopOfRangeOnAllSetsMovesUpOneIncrement() {
        let s = suggest([session(3, 120, [12, 12, 12])])
        XCTAssertEqual(s.kind, .increase)
        XCTAssertEqual(s.targets.map(\.weight), [125, 125, 125])
        XCTAssertEqual(s.targets.map(\.reps), [8, 8, 8])
        XCTAssertTrue(s.explanation.contains("125 lb"))
    }

    func testIncreaseUsesTheEquipmentsRealIncrement() {
        XCTAssertEqual(suggest([session(3, 120, [12, 12, 12])], increment: 10).targets[0].weight, 130)
        XCTAssertEqual(suggest([session(3, 20, [12, 12, 12])], increment: 2.5).targets[0].weight, 22.5)
    }

    func testTopOfRangeOnOnlySomeSetsDoesNotIncrease() {
        let s = suggest([session(3, 120, [12, 12, 11])])
        XCTAssertEqual(s.kind, .progress)
        XCTAssertEqual(s.targets.map(\.reps), [12, 12, 12])
    }

    func testOneStalledSessionIsNotYetAHold() {
        let s = suggest([session(3, 100, [10, 9, 8]), session(6, 100, [10, 9, 8])])
        XCTAssertEqual(s.kind, .progress)
    }

    func testTwoStalledSessionsInRangeHold() {
        let s = suggest([session(3, 100, [10, 9, 8]), session(6, 100, [10, 9, 8]), session(9, 100, [10, 9, 8])])
        XCTAssertEqual(s.kind, .hold)
        XCTAssertEqual(s.targets.map(\.weight), [100, 100, 100])
        XCTAssertEqual(s.targets.map(\.reps), [10, 9, 8])
    }

    func testTwoMissesBelowRangeBackOffAboutTenPercent() {
        let s = suggest([session(3, 100, [8, 7, 6]), session(6, 100, [8, 7, 6]), session(9, 100, [9, 8, 8])])
        XCTAssertEqual(s.kind, .backOff)
        XCTAssertEqual(s.targets.map(\.weight), [90, 90, 90])
        XCTAssertTrue(s.targets.allSatisfy { $0.reps >= 8 })
    }

    func testProgressAfterAMissResetsTheCount() {
        // Newest session improved, so the earlier stall no longer counts.
        let s = suggest([session(3, 100, [11, 9, 8]), session(6, 100, [10, 9, 8]), session(9, 100, [10, 9, 8])])
        XCTAssertEqual(s.kind, .progress)
    }

    func testLayoffStartsAboutTenPercentLighter() {
        let s = suggest([session(16, 120, [10, 10, 9])])
        XCTAssertEqual(s.kind, .layoff)
        XCTAssertEqual(s.targets.map(\.weight), [105, 105, 105]) // 108 rounded down to a real 5 lb step
        XCTAssertTrue(s.explanation.contains("16 days"))
    }

    func testLayoffBeatsIncrease() {
        XCTAssertEqual(suggest([session(20, 120, [12, 12, 12])]).kind, .layoff)
    }

    func testThirteenDaysIsNotALayoff() {
        XCTAssertEqual(suggest([session(13, 120, [10, 10, 9])]).kind, .progress)
    }

    func testReducedAlwaysDropsAtLeastOneStepButNeverToZero() {
        XCTAssertEqual(Progression.reduced(20, factor: 0.9, increment: 5), 15)
        XCTAssertEqual(Progression.reduced(5, factor: 0.9, increment: 5), 5)
        XCTAssertEqual(Progression.reduced(100, factor: 0.9, increment: 10), 90)
    }

    func testBodyweightProgressesByRepsOnly() {
        let s = suggest([session(3, 0, [12, 12, 12])], bodyweight: true)
        XCTAssertEqual(s.kind, .progress)
        XCTAssertEqual(s.targets.map(\.weight), [0, 0, 0])
        XCTAssertEqual(s.targets.map(\.reps), [13, 13, 13])
    }

    func testQuickVersionTrimsToTwoSets() {
        XCTAssertEqual(suggest([session(3, 120, [11, 10, 9])], setCount: 2).targets.count, 2)
        XCTAssertEqual(suggest([], setCount: 2).targets.count, 2)
    }

    func testLookAheadNamesTheNextWeight() {
        XCTAssertEqual(Progression.lookAhead(weight: 120, range: 8...12, increment: 5, bodyweight: false),
                       "Get 12 on every set and next time moves up to 125 lb.")
    }
}

final class RotationTests: XCTestCase {

    func testStartsWithChestWhenThereIsNoHistory() {
        XCTAssertEqual(Rotation.nextDay(history: History([])), .chestTriceps)
    }

    func testOffersTheDayAfterTheLastOneHoweverLongAgo() {
        let h = History([workout(30, .chestTriceps, [entry("db_bench", 60, [10])]),
                         workout(12, .backBiceps, [entry("db_curl", 25, [10])])])
        XCTAssertEqual(Rotation.nextDay(history: h), .shouldersLegs)
    }

    func testWrapsAround() {
        let h = History([workout(2, .shouldersLegs, [entry("db_ohp", 40, [10])])])
        XCTAssertEqual(Rotation.nextDay(history: h), .chestTriceps)
    }

    func testAbsOfferedEveryFewDays() {
        XCTAssertTrue(Rotation.absDue(history: History([]), everyDays: 3, now: now))
        let recent = History([workout(1, .backBiceps, [entry("crunch", 0, [20])])])
        XCTAssertFalse(Rotation.absDue(history: recent, everyDays: 3, now: now))
        let old = History([workout(4, .backBiceps, [entry("crunch", 0, [20])])])
        XCTAssertTrue(Rotation.absDue(history: old, everyDays: 3, now: now))
    }
}

final class PlannerTests: XCTestCase {
    private let ironWorks = GymInfo(id: UUID(), name: "Iron Works", equipment: [
        EquipmentInfo(id: UUID(), typeID: "dumbbells", name: "Dumbbells", increment: 5),
        EquipmentInfo(id: UUID(), typeID: "latPulldown", name: "Lat pulldown", increment: 5),
        EquipmentInfo(id: UUID(), typeID: "seatedRow", name: "Seated cable row", increment: 5),
        EquipmentInfo(id: UUID(), typeID: "cable", name: "Cable station", increment: 5),
        EquipmentInfo(id: UUID(), typeID: "pullupBar", name: "Pull-up bar", increment: 5),
    ])
    private let harbor = GymInfo(id: UUID(), name: "Harbor", equipment: [
        EquipmentInfo(id: UUID(), typeID: "dumbbells", name: "Dumbbells", increment: 2.5),
        EquipmentInfo(id: UUID(), typeID: "latPulldown", name: "Lat pulldown", increment: 10),
    ])

    func testMachineHistoryIsSeparatePerGymButFreeWeightsAreShared() {
        let ironPulldown = HistoryKey.make(exerciseID: "lat_pulldown", equipment: ironWorks.equipment[1])
        let harborPulldown = HistoryKey.make(exerciseID: "lat_pulldown", equipment: harbor.equipment[1])
        XCTAssertNotEqual(ironPulldown, harborPulldown)
        XCTAssertEqual(HistoryKey.make(exerciseID: "db_curl", equipment: ironWorks.equipment[0]),
                       HistoryKey.make(exerciseID: "db_curl", equipment: harbor.equipment[0]))

        let h = History([workout(3, .backBiceps, gym: ironWorks.id, [
            entry("lat_pulldown", key: ironPulldown, 120, [10, 10, 9]),
            entry("db_curl", 30, [10, 9, 8]),
        ])])
        let pulldown = ExerciseCatalog.exercise("lat_pulldown")!
        let curl = ExerciseCatalog.exercise("db_curl")!

        // Same machine: picks up where you left off.
        XCTAssertEqual(Planner.planExercise(pulldown, slotID: nil, gym: ironWorks, history: h, now: now).suggestion.targets[0].weight, 120)
        // Different gym's machine: no history, so start light.
        let atHarbor = Planner.planExercise(pulldown, slotID: nil, gym: harbor, history: h, now: now)
        XCTAssertEqual(atHarbor.suggestion.kind, .firstTime)
        XCTAssertEqual(atHarbor.increment, 10)
        // Dumbbells: history follows you, increment comes from this gym's rack.
        let curlAtHarbor = Planner.planExercise(curl, slotID: nil, gym: harbor, history: h, now: now)
        XCTAssertEqual(curlAtHarbor.suggestion.targets[0].weight, 30)
        XCTAssertEqual(curlAtHarbor.increment, 2.5)
    }

    func testPlanOnlyUsesWhatTheGymHas() {
        let plan = Planner.plan(day: .backBiceps, includeAbs: false, quick: false, gym: harbor, history: History([]), now: now)
        XCTAssertFalse(plan.isEmpty)
        for item in plan { XCTAssertTrue(Planner.isAvailable(item.exercise, gym: harbor), item.exercise.name) }
        XCTAssertEqual(Set(plan.map(\.exercise.id)).count, plan.count, "no exercise twice")
        // Harbor has no seated row, so that slot falls back to another row it can do.
        XCTAssertEqual(plan.first { $0.slotID == "backBiceps.1" }?.exercise.pattern, "row")
    }

    func testFullPlanHasSixExercisesAndAbsAddsThree() {
        let full = Planner.plan(day: .chestTriceps, includeAbs: false, quick: false, gym: nil, history: History([]), now: now)
        XCTAssertEqual(full.map(\.exercise.id), DayType.chestTriceps.slots)
        let withAbs = Planner.plan(day: .chestTriceps, includeAbs: true, quick: false, gym: nil, history: History([]), now: now)
        XCTAssertEqual(withAbs.count, 9)
        XCTAssertEqual(withAbs.suffix(3).map(\.exercise.muscle), [.abs, .abs, .abs])
    }

    func testTwentyMinuteVersionFitsInTwentyMinutes() {
        for dayType in DayType.allCases {
            let quick = Planner.plan(day: dayType, includeAbs: false, quick: true, gym: nil, history: History([]), now: now)
            XCTAssertEqual(quick.count, 4)
            XCTAssertTrue(quick.allSatisfy { $0.suggestion.targets.count == 2 })
            XCTAssertEqual(Set(quick.map(\.exercise.muscle.group)), Set(dayType.groups), "covers both muscle groups")
            XCTAssertLessThanOrEqual(Planner.estimateMinutes(quick), 20)
        }
    }

    func testSwapOffersSameMuscleUsingAvailableEquipmentBestFirst() {
        let pulldown = ExerciseCatalog.exercise("lat_pulldown")!
        let options = Planner.swapOptions(for: pulldown, gym: ironWorks, history: History([]))
        XCTAssertEqual(options.first?.exercise.id, "pullup") // same movement, and the gym has a bar
        XCTAssertTrue(options[0].isBestMatch)
        XCTAssertTrue(options.allSatisfy { Planner.isAvailable($0.exercise, gym: ironWorks) })
        XCTAssertFalse(options.contains { $0.exercise.id == "assisted_pullup" }) // gym has no such machine
        XCTAssertTrue(Planner.unavailableSwaps(for: pulldown, gym: ironWorks).contains { $0.id == "assisted_pullup" })
    }

    func testASwapIsRememberedForThatGymOnly() {
        let h = History([workout(3, .backBiceps, gym: ironWorks.id, [entry("pullup", slot: "backBiceps.0", 0, [7, 6, 6])])])
        let atIron = Planner.plan(day: .backBiceps, includeAbs: false, quick: false, gym: ironWorks, history: h, now: now)
        XCTAssertEqual(atIron.first?.exercise.id, "pullup")
        let atHarbor = Planner.plan(day: .backBiceps, includeAbs: false, quick: false, gym: harbor, history: h, now: now)
        XCTAssertEqual(atHarbor.first?.exercise.id, "lat_pulldown")
    }

    func testIdeasPointAtMusclesNotTrainedRecently() {
        let h = History([
            workout(9, .backBiceps, [entry("face_pull", 30, [12]), entry("lat_pulldown", 100, [10])]),
            workout(2, .chestTriceps, [entry("db_bench", 60, [10]), entry("pushdown", 40, [12])]),
        ])
        let todaysPlan: Set<String> = ["db_ohp", "lateral_raise", "leg_press", "leg_curl", "leg_ext", "calf_raise_machine"]
        let ideas = Planner.ideas(history: h, gym: ironWorks, plannedExerciseIDs: todaysPlan, now: now)
        XCTAssertFalse(ideas.isEmpty)
        XCTAssertTrue(ideas.allSatisfy { Planner.isAvailable($0.exercise, gym: ironWorks) })
        XCTAssertFalse(ideas.contains { [.chest, .triceps, .delts, .quads].contains($0.muscle) }, "recent or planned muscles are not suggested")
        let rearDelts = ideas.first { $0.muscle == .rearDelts }
        XCTAssertEqual(rearDelts?.exercise.id, "face_pull")
        XCTAssertEqual(rearDelts?.title, "Rear delts are due")
        XCTAssertEqual(rearDelts?.detail, "Not trained in 9 days · Face pull is here")
    }

    func testNoIdeasBeforeAnyHistory() {
        XCTAssertTrue(Planner.ideas(history: History([]), gym: ironWorks, plannedExerciseIDs: [], now: now).isEmpty)
    }

    func testCatalogIsConsistent() {
        XCTAssertEqual(Set(ExerciseCatalog.all.map(\.id)).count, ExerciseCatalog.all.count)
        for exercise in ExerciseCatalog.all {
            XCTAssertNotNil(EquipmentCatalog.type(exercise.equipment), exercise.id)
            XCTAssertLessThan(exercise.repLow, exercise.repHigh, exercise.id)
        }
        for id in DayType.allCases.flatMap(\.slots) + AbsAddOn.slots { XCTAssertNotNil(ExerciseCatalog.exercise(id), id) }
    }
}

final class StatsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    func testEstimatedStrength() {
        XCTAssertEqual(Stats.e1RM(weight: 100, reps: 1), 100)
        XCTAssertEqual(Stats.e1RM(weight: 100, reps: 10), 133.33, accuracy: 0.01)
    }

    func testRecords() {
        let prior = [SetRecord(weight: 100, reps: 10), SetRecord(weight: 110, reps: 6)]
        XCTAssertNil(Stats.detectPR(weight: 100, reps: 10, prior: []), "first session is never a record")
        XCTAssertEqual(Stats.detectPR(weight: 115, reps: 3, prior: prior), .weight)
        XCTAssertEqual(Stats.detectPR(weight: 100, reps: 11, prior: prior), .reps)
        XCTAssertEqual(Stats.detectPR(weight: 110, reps: 7, prior: prior), .reps)
        XCTAssertNil(Stats.detectPR(weight: 100, reps: 10, prior: prior))
        XCTAssertNil(Stats.detectPR(weight: 90, reps: 10, prior: prior))
    }

    func testWeeklyStreakCountsWeeksNotDays() {
        // "now" is Sunday 2026-11-15 UTC. Weeks start Monday.
        let goal3 = Streak.status(dates: [ago(1), ago(3), ago(8), ago(9), ago(10), ago(15), ago(16), ago(17)],
                                  goal: 3, now: now, calendar: calendar)
        XCTAssertEqual(goal3.thisWeek, 2)
        XCTAssertEqual(goal3.streak, 2, "two full weeks before this one; this week is not finished and does not break it")
        XCTAssertEqual(goal3.remaining, 1)

        let reached = Streak.status(dates: [ago(0), ago(1), ago(3), ago(8), ago(9), ago(10)], goal: 3, now: now, calendar: calendar)
        XCTAssertEqual(reached.streak, 2, "this week counts once the goal is reached")

        let broken = Streak.status(dates: [ago(1), ago(15), ago(16), ago(17)], goal: 3, now: now, calendar: calendar)
        XCTAssertEqual(broken.streak, 0, "a missed week resets the streak")
    }

    func testWeeklySetsPerMuscleGroup() {
        let workouts = [
            workout(1, .chestTriceps, [entry("db_bench", 60, [10, 9, 8]), entry("pushdown", 40, [12, 12])]),
            workout(9, .backBiceps, [entry("db_curl", 30, [10, 10, 10])]),
        ]
        let sets = Stats.weeklySets(workouts, weekOf: now, calendar: calendar)
        XCTAssertEqual(sets[.chest], 3)
        XCTAssertEqual(sets[.triceps], 2)
        XCTAssertNil(sets[.biceps], "last week's work is not counted")
    }

    func testMonthlyRecapReadsInPlainLanguage() {
        var first = workout(10, .chestTriceps, [entry("db_bench", 60, [10, 10, 10])])
        first.entries[0].sets[0].isPR = true
        let h = History([first, workout(2, .chestTriceps, [entry("db_bench", 65, [10, 10, 10])])])
        let recap = Recap.make(for: now, history: h, cardioSessions: 2, cardioMiles: 5.5, calendar: calendar)
        XCTAssertEqual(recap.workouts, 2)
        XCTAssertEqual(recap.sets, 6)
        XCTAssertEqual(recap.records, 1)
        XCTAssertEqual(recap.topGroup, .chest)
        XCTAssertEqual(recap.bestGain?.name, "Dumbbell bench press")
        XCTAssertEqual(recap.lines.first, "You lifted 2 times for 6 sets in total.")
        XCTAssertTrue(recap.lines.contains("Cardio: 2 sessions, 5.5 miles."))
    }
}

final class PlatesTests: XCTestCase {

    func testCommonBarbellWeights() {
        XCTAssertEqual(Plates.text(total: 135), "Each side: 45")
        XCTAssertEqual(Plates.text(total: 160), "Each side: 45 + 10 + 2.5")
        XCTAssertEqual(Plates.text(total: 225), "Each side: 2 × 45")
        XCTAssertEqual(Plates.text(total: 185), "Each side: 45 + 25")
        XCTAssertEqual(Plates.text(total: 45), "Just the bar")
    }

    func testLighterThanTheBarShowsNothing() {
        XCTAssertNil(Plates.text(total: 40))
        XCTAssertNil(Plates.text(total: 0))
    }

    func testWeightThePlatesCannotMakeSaysWhatIsMissing() {
        XCTAssertEqual(Plates.load(total: 137.5), Plates.Load(perSide: [45], leftover: 1.25))
        XCTAssertEqual(Plates.text(total: 137.5), "Each side: 45 + 1.25 more")
    }

    func testPlateLoadedMachineHasNoBar() {
        XCTAssertEqual(Plates.text(total: 180, bar: 0), "Each side: 2 × 45")
        XCTAssertNil(Plates.text(total: 0, bar: 0))
        XCTAssertEqual(Plates.bar(forEquipment: "barbell"), 45)
        XCTAssertEqual(Plates.bar(forEquipment: "legPress"), 0)
        XCTAssertNil(Plates.bar(forEquipment: "dumbbells"))
    }

    func testLoadAlwaysAddsUp() {
        for total in stride(from: 45.0, through: 500, by: 2.5) {
            let load = Plates.load(total: total)!
            XCTAssertEqual(45 + 2 * (load.perSide.reduce(0, +) + load.leftover), total, accuracy: 0.001)
            XCTAssertLessThan(load.leftover, 2.5)
        }
    }

    func testWarmUpsClimbTowardTheWorkingWeight() {
        XCTAssertEqual(WarmUp.sets(target: 135, step: 5, bar: 45),
                       [WarmUpSet(weight: 70, reps: 8), WarmUpSet(weight: 95, reps: 5), WarmUpSet(weight: 115, reps: 3)])
        XCTAssertEqual(WarmUp.sets(target: 225, step: 5, bar: 45).map(\.weight), [115, 160, 190])
    }

    func testWarmUpsNeverReachTheWorkingWeightOrGoBelowTheBar() {
        for target in stride(from: 5.0, through: 400, by: 5) {
            let sets = WarmUp.sets(target: target, step: 5, bar: 45)
            XCTAssertEqual(sets.map(\.weight), sets.map(\.weight).sorted())
            XCTAssertEqual(Set(sets.map(\.weight)).count, sets.count)
            for set in sets {
                XCTAssertLessThan(set.weight, target)
                XCTAssertGreaterThanOrEqual(set.weight, 45)
            }
        }
    }

    func testLightWeightsNeedNoWarmUp() {
        XCTAssertTrue(WarmUp.sets(target: 15, step: 5).isEmpty)
        XCTAssertTrue(WarmUp.sets(target: 55, step: 5, bar: 45).isEmpty)
        XCTAssertTrue(WarmUp.sets(target: 0, step: 5).isEmpty)
    }
}

final class RecordRecountTests: XCTestCase {

    private func input(_ key: String, _ sets: [(Double, Int)]) -> Stats.RecordInput {
        Stats.RecordInput(historyKey: key, sets: sets.map { SetRecord(weight: $0.0, reps: $0.1) })
    }

    func testFirstWorkoutNeverHasRecords() {
        let kinds = Stats.recordKinds([[input("bench", [(100, 8), (105, 8)])]])
        XCTAssertEqual(kinds, [[[nil, nil]]])
    }

    func testLaterWorkoutsAreComparedWithEarlierOnes() {
        let kinds = Stats.recordKinds([
            [input("bench", [(100, 8), (100, 8)])],
            [input("bench", [(105, 8), (105, 8)]), input("curl", [(30, 10)])],
        ])
        XCTAssertEqual(kinds[1][0], [.weight, nil])
        XCTAssertEqual(kinds[1][1], [nil])
    }

    func testLoweringAnOldSetCanCreateALaterRecord() {
        let before = Stats.recordKinds([[input("bench", [(120, 8)])], [input("bench", [(110, 8)])]])
        let after = Stats.recordKinds([[input("bench", [(100, 8)])], [input("bench", [(110, 8)])]])
        XCTAssertEqual(before[1][0], [nil])
        XCTAssertEqual(after[1][0], [.weight])
    }
}
