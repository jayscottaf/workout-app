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
        shot("02-logging")

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
