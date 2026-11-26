import XCTest

/// Drives the real app in the iPhone simulator through the main flow and saves a
/// screenshot of every step. Uses sample data held in memory (`-demoData`).
final class WalkthroughTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMainFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()

        // Today: offers the next day in the rotation.
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["startWorkout"].exists)
        shot("01-today")

        // Start the workout: first set is pre-filled and ready to confirm.
        app.buttons["startWorkout"].tap()
        XCTAssertTrue(app.buttons["logSet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["WARM-UP FIRST"].exists)
        shot("02-logging")

        // Finer weight steps: 2.5 lb.
        app.buttons["stepMenu"].tap()
        let fine = app.buttons["2.5 lb steps"]
        XCTAssertTrue(fine.waitForExistence(timeout: 5))
        fine.tap()
        XCTAssertTrue(app.buttons["stepMenu"].label.contains("2.5"))

        // Machine busy: do this exercise later. The next one comes up and this one moves to the end.
        app.buttons["doLater"].tap()
        XCTAssertTrue(app.buttons["logSet"].waitForExistence(timeout: 5))
        shot("02a-later")

        // One-tap swap to an equivalent exercise.
        app.buttons["swapExercise"].tap()
        XCTAssertTrue(app.staticTexts["BEST MATCH"].waitForExistence(timeout: 5))
        shot("03-swap")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swap-'")).firstMatch.tap()

        // Log a set with one tap: the rest timer starts by itself.
        XCTAssertTrue(app.buttons["logSet"].waitForExistence(timeout: 5))
        app.buttons["One more rep"].tap()
        app.buttons["logSet"].tap()
        XCTAssertTrue(app.staticTexts["REST"].waitForExistence(timeout: 5))
        shot("04-rest-timer")
        app.buttons["Skip rest"].tap()
        app.buttons["logSet"].tap()

        // Finish early: summary explains the session in plain language.
        app.buttons["finishWorkout"].tap()
        let confirm = app.buttons["Finish workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["WHAT IT MEANS"].exists)
        shot("05-summary")

        // Fix a set after the fact: the summary updates.
        let edit = app.buttons["editWorkout"]
        if !edit.isHittable { app.swipeUp() }
        edit.tap()
        let firstSet = app.buttons.matching(identifier: "editSetRow").firstMatch
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        app.buttons["One more rep"].tap()
        shot("05a-edit")
        app.buttons["editSetOK"].tap()
        app.buttons["editDone"].tap()
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 5))

        // Keep going after Finish: the workout reopens to add more, then finishes again.
        let keepGoing = app.buttons["keepGoing"]
        if !keepGoing.isHittable { app.swipeUp() }
        keepGoing.tap()
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 10))
        shot("05b-reopened")
        app.buttons["finishWorkout"].tap()
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 10))
        app.buttons["summaryDone"].tap()

        // Today now offers the following day and counts the workout toward the week.
        XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 10))
        shot("06-today-after")

        // Progress: strength chart, weekly volume, records, calendar, recap.
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["ESTIMATED STRENGTH"].waitForExistence(timeout: 10))
        shot("07-progress")
        app.swipeUp()
        shot("08-progress-more")
        app.swipeUp()
        shot("09-progress-calendar")

        // Gyms: equipment per gym.
        app.tabBars.buttons["Gyms"].tap()
        XCTAssertTrue(app.buttons["Harbor Fitness"].waitForExistence(timeout: 10))
        shot("10-gyms")
        app.buttons["Harbor Fitness"].tap()
        shot("11-second-gym")
    }

    /// Make an exercise on a machine that is not on the built-in list, in the middle of a workout.
    @MainActor
    func testCreateOwnExerciseAndMachine() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()
        XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 30))
        app.buttons["startWorkout"].tap()
        XCTAssertTrue(app.buttons["logSet"].waitForExistence(timeout: 10))

        app.buttons["addMenu"].tap()
        app.buttons["Add an exercise"].tap()
        XCTAssertTrue(app.buttons["createExercise"].waitForExistence(timeout: 5))
        app.buttons["createExercise"].tap()

        let name = app.textFields["exerciseName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Glute kickback")

        // A machine that is not on the list.
        app.buttons["newMachine"].tap()
        let machine = app.textFields["machineName"]
        XCTAssertTrue(machine.waitForExistence(timeout: 5))
        machine.tap()
        machine.typeText("Matrix glute machine")
        shot("12-new-machine")
        app.buttons["saveMachine"].tap()

        XCTAssertTrue(app.buttons["saveExercise"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Matrix glute machine"].waitForExistence(timeout: 5))
        shot("13-new-exercise")
        app.buttons["saveExercise"].tap()

        // Straight into the workout, ready to log.
        XCTAssertTrue(app.staticTexts["Glute kickback"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["logSet"].exists)
        shot("14-own-exercise-in-workout")
        app.buttons["logSet"].tap()

        // The gym now lists the new machine.
        app.buttons["Skip rest"].tap()
        app.buttons["addMenu"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Equipment at'")).firstMatch.tap()
        // It is at the end of a long list.
        let row = app.staticTexts["Matrix glute machine"]
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.exists)
        shot("15-gym-has-new-machine")
    }

    /// Switch to a ready-made routine, then add a day of your own to it.
    @MainActor
    func testChangeRoutine() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()
        XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 30))

        app.buttons["Do a different day instead"].tap()
        app.buttons["Edit routine"].tap()
        XCTAssertTrue(app.buttons["preset-ppl"].waitForExistence(timeout: 5))
        shot("16-routine")
        app.buttons["preset-ppl"].tap()
        app.buttons["Use this routine"].tap()
        XCTAssertTrue(app.staticTexts["Push"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Legs"].exists)

        // A fourth day of your own, with one exercise.
        app.buttons["addDay"].tap()
        XCTAssertTrue(app.buttons["day-4"].waitForExistence(timeout: 5))
        app.buttons["day-4"].tap()
        let name = app.textFields["dayName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        name.typeText("Arms")
        app.buttons["addToDay"].tap()
        XCTAssertTrue(app.staticTexts["Dumbbell curl"].waitForExistence(timeout: 5))
        app.staticTexts["Dumbbell curl"].tap()
        XCTAssertTrue(app.buttons["addToDay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dumbbell curl"].exists)
        shot("17-day-editor")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        shot("18-routine-changed")
        app.buttons["Done"].tap()

        // Today now follows the new routine: four days, starting with Push.
        XCTAssertTrue(app.staticTexts["Push"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NEXT UP · DAY 1 OF 4"].exists || app.staticTexts["Next up · day 1 of 4"].exists)
        shot("19-today-new-routine")
        app.buttons["startWorkout"].tap()
        XCTAssertTrue(app.buttons["logSet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Push"].exists)
    }

    /// An exercise you made that the app now has built in: switch to the built-in one.
    @MainActor
    func testSwitchOwnExerciseToBuiltIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 30))
        app.buttons["Settings"].tap()

        let custom = app.buttons["customList"]
        for _ in 0..<6 where !custom.isHittable { app.swipeUp() }
        custom.tap()
        app.buttons["Create an exercise"].tap()
        let name = app.textFields["exerciseName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Preacher curl\n")
        let muscle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Main muscle'")).firstMatch
        XCTAssertTrue(muscle.waitForExistence(timeout: 5))
        muscle.tap()
        app.buttons["Biceps"].tap()
        app.buttons["saveExercise"].tap()

        let useBuiltIn = app.buttons["useBuiltIn-ez_preacher"]
        XCTAssertTrue(useBuiltIn.waitForExistence(timeout: 5))
        shot("20-switch-to-built-in")
        useBuiltIn.tap()
        app.buttons["Use built-in"].tap()
        XCTAssertFalse(useBuiltIn.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Preacher curl"].exists)
    }

    /// Mid-workout: see which gym this is, and use equipment that was not ticked for it before.
    @MainActor
    func testUseNewEquipmentMidWorkout() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()
        XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 30))
        app.buttons["startWorkout"].tap()
        XCTAssertTrue(app.buttons["logSet"].waitForExistence(timeout: 10))

        // The gym shows at the top and opens its equipment.
        XCTAssertTrue(app.buttons["gymButton"].exists)
        shot("21-gym-in-workout")
        app.buttons["gymButton"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Iron Works equipment"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // Add an exercise for equipment this gym does not have ticked yet: it is ticked and added.
        app.buttons["addMenu"].tap()
        app.buttons["Add an exercise"].tap()
        let preacher = app.buttons["addNew-ez_preacher"]
        for _ in 0..<8 where !preacher.isHittable { app.swipeUp() }
        shot("22-add-unticked")
        preacher.tap()
        XCTAssertTrue(app.staticTexts["EZ-bar preacher curl"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["logSet"].exists)
        shot("23-new-equipment-in-workout")
    }

    /// Two workouts on one day: the calendar asks which to open, and the chart's dates do not repeat.
    @MainActor
    func testTwoWorkoutsOneDay() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"]
        app.launch()
        for _ in 0..<2 {
            XCTAssertTrue(app.buttons["startWorkout"].waitForExistence(timeout: 30))
            app.buttons["startWorkout"].tap()
            XCTAssertTrue(app.buttons["logSet"].waitForExistence(timeout: 10))
            app.buttons["logSet"].tap()
            app.buttons["Skip rest"].tap()
            app.buttons["finishWorkout"].tap()
            let confirm = app.buttons["Finish workout"]
            if confirm.waitForExistence(timeout: 3) { confirm.tap() }
            XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 10))
            app.buttons["summaryDone"].tap()
        }
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["ESTIMATED STRENGTH"].waitForExistence(timeout: 10))
        shot("24-chart-dates")
        let today = app.buttons.matching(NSPredicate(format: "label CONTAINS '2 workouts'")).firstMatch
        for _ in 0..<6 where !today.isHittable { app.swipeUp() }
        shot("25-calendar-two-workouts")
        today.tap()
        XCTAssertTrue(app.staticTexts["Which workout?"].waitForExistence(timeout: 5))
        shot("26-which-workout")
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' set'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 5))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
