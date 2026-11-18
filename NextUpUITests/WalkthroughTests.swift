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

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
