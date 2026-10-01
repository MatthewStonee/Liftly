import XCTest
import UIKit

/// UI integration tests in the RackUITests target. Each test gets its own
/// local-only SwiftData store and can relaunch against the same fixture ID.
final class LiftlyUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureID: String!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        fixtureID = UUID().uuidString
        app = XCUIApplication()
    }

    override func tearDown() {
        if let run = testRun, !run.hasSucceeded, app.state == .runningForeground {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        super.tearDown()
    }

    private func launch(_ fixture: String, extraArguments: [String] = []) {
        app.launchArguments = ["-LiftlyUITestFixture", fixture, fixtureID] + extraArguments
        app.launch()
    }

    private func clearRunningWorkoutReference() {
        // ActivityKit survives app termination and failed UI tests. Each fixture
        // has the same link UUIDs, so explicitly clear a previous test's card.
        for suffix in ["006", "005", "004", "002", "001"] {
            app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000\(suffix)")!)
            let control = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.liveActivity.")).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10))
            let stop = app.buttons["workout.liveActivity.stop"]
            if stop.exists {
                stop.tap()
                XCTAssertTrue(app.buttons["workout.liveActivity.show"].waitForExistence(timeout: 10))
            }
        }
    }

    private func openHistory() {
        app.tabBars.buttons["Progress"].tap()
        let exercise = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "progress.exercise."))
            .firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 10))
        exercise.tap()
        let historyLink = app.buttons["progress.viewAllHistory"]
        XCTAssertTrue(historyLink.waitForExistence(timeout: 5))
        for _ in 0..<6 where !historyLink.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(historyLink.isHittable)
        historyLink.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    private func openReorderProgram() {
        let program = app.descendants(matching: .any)["program.row.UI Reorder"]
        XCTAssertTrue(program.waitForExistence(timeout: 10))
        program.tap()
        let days = app.segmentedControls.buttons["Days"]
        if days.exists { days.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["workout.row.Day A"].waitForExistence(timeout: 5))
    }

    private func openDayA() {
        app.descendants(matching: .any)["workout.row.Day A"].tap()
        XCTAssertTrue(exerciseRows.firstMatch.waitForExistence(timeout: 5))
    }

    private var exerciseRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "exercise.row."))
    }

    private func workoutOrder() -> [String] {
        ["Day A", "Day B", "Day C"].sorted {
            app.descendants(matching: .any)["workout.row.\($0)"].frame.midY
                < app.descendants(matching: .any)["workout.row.\($1)"].frame.midY
        }
    }

    private func exerciseOrder() -> [String] {
        exerciseRows.allElementsBoundByIndex.sorted { $0.frame.midY < $1.frame.midY }.map(\.identifier)
    }

    /// Touches and holds anywhere on `source` to lift it, then drops it on the lower part of `target`.
    private func drag(_ source: XCUIElement, below target: XCUIElement) {
        XCTAssertTrue(source.exists && target.exists)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 1.5, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)),
                   withVelocity: .slow, thenHoldForDuration: 1)
    }

    /// Waits for the drop animation to settle on `expected`.
    private func waitForOrder(_ expected: [String], _ order: @escaping () -> [String]) -> Bool {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in order() == expected }, object: nil)
        return XCTWaiter.wait(for: [settled], timeout: 5) == .completed
    }

    func testAcceptedDragPersistsAndCanceledDragKeepsOrder() {
        launch("reorder")
        openReorderProgram()
        XCTAssertEqual(workoutOrder(), ["Day A", "Day B", "Day C"])

        drag(app.descendants(matching: .any)["workout.row.Day A"],
             below: app.descendants(matching: .any)["workout.row.Day C"])
        let accepted = ["Day B", "Day C", "Day A"]
        XCTAssertTrue(waitForOrder(accepted, workoutOrder))
        XCTAssertFalse(app.navigationBars["Day A"].exists, "Dropping a row must not open it")

        // A drop outside the list cancels the move.
        app.descendants(matching: .any)["workout.row.Day B"]
            .press(forDuration: 1.5, thenDragTo: app.navigationBars.firstMatch)
        XCTAssertTrue(waitForOrder(accepted, workoutOrder))

        app.terminate()
        launch("reorder")
        openReorderProgram()
        XCTAssertEqual(workoutOrder(), accepted)

        // Reordering lives on the rows, so a tap still opens a day.
        openDayA()
        XCTAssertTrue(app.navigationBars["Day A"].exists)
    }

    func testExerciseDragPersists() {
        launch("reorder")
        openReorderProgram()
        openDayA()
        let initial = exerciseOrder()
        XCTAssertEqual(initial.count, 3)

        drag(app.descendants(matching: .any)[initial[0]], below: app.descendants(matching: .any)[initial[2]])
        let moved = [initial[1], initial[2], initial[0]]
        XCTAssertTrue(waitForOrder(moved, exerciseOrder))

        app.terminate()
        launch("reorder")
        openReorderProgram()
        openDayA()
        XCTAssertEqual(exerciseOrder(), moved)
    }

    func testDelayedDeletionFailureKeepsSheetDraftAndRestoresSet() {
        launch("history", extraArguments: ["-LiftlyDebugSaveFailures", "1", "-LiftlyUITestUndoSeconds", "30"])
        openHistory()
        let deleteButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "history.delete.")
        )
        let first = deleteButtons.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let deletedID = first.identifier.replacingOccurrences(of: "history.delete.", with: "")
        first.tap()

        let edit = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "history.edit.")
        ).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()
        let weight = app.textFields["editSet.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap()
        weight.typeText("7")
        let draft = weight.value as? String

        let alert = app.alerts["Couldn't Delete Items"]
        XCTAssertTrue(alert.waitForExistence(timeout: 35))
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Edit Set"].exists)
        XCTAssertEqual(weight.value as? String, draft)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["history.delete.\(deletedID)"].waitForExistence(timeout: 5))
    }

    func testHistorySelectionLoadMoreRetryAndUndoAcrossPages() {
        launch("history", extraArguments: ["-LiftlyDebugHistoryLoadFailures", "1"])
        openHistory()
        XCTAssertTrue(app.staticTexts["Your history couldn’t be loaded. Try again."].exists)
        app.buttons["history.initialRetry"].tap()

        let oneMonth = app.buttons["history.range.1M"]
        let allTime = app.buttons["history.range.All"]
        oneMonth.tap()
        XCTAssertTrue(oneMonth.isSelected)
        XCTAssertFalse(allTime.isSelected)
        allTime.tap()
        XCTAssertTrue(allTime.isSelected)
        XCTAssertEqual(app.descendants(matching: .any)["history.list"].value as? String,
                       "50 sets loaded")

        let loadMore = app.buttons["history.loadMore"]
        for _ in 0..<8 where !loadMore.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(loadMore.isHittable)
        loadMore.tap()
        XCTAssertEqual(app.descendants(matching: .any)["history.list"].value as? String,
                       "100 sets loaded")

        for _ in 0..<8 { app.scrollViews.firstMatch.swipeDown() }
        let firstDelete = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "history.delete.")
        ).firstMatch
        XCTAssertTrue(firstDelete.waitForExistence(timeout: 5))
        let deletedID = firstDelete.identifier
        firstDelete.tap()
        XCTAssertFalse(app.buttons[deletedID].exists)
        let undo = app.buttons["deletion.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.tap()
        XCTAssertTrue(app.buttons[deletedID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["history.list"].value as? String,
                       "100 sets loaded")
    }

    func testLiveActivityStartSwitchStopAndEmptyDay() {
        launch("liveActivity")
        clearRunningWorkoutReference()
        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000001")!)
        let show = app.buttons["workout.liveActivity.show"]
        let stop = app.buttons["workout.liveActivity.stop"]
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        XCTAssertTrue(show.isEnabled)
        show.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        let started = XCTAttachment(screenshot: app.screenshot())
        started.name = "Workout day with running Live Activity"
        started.lifetime = .keepAlways
        add(started)

        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000002")!)
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        let switchDay = app.buttons["Show Other Day"]
        XCTAssertTrue(switchDay.waitForExistence(timeout: 5))
        switchDay.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 10))

        app.terminate()
        launch("liveActivity")
        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000002")!)
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(show.waitForExistence(timeout: 10))

        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000003")!)
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        XCTAssertFalse(show.isEnabled)
    }

    func testWorkoutLinksColdLaunchAndMissingDay() {
        launch("liveActivity")
        clearRunningWorkoutReference()
        app.terminate()
        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000001")!)
        XCTAssertTrue(app.buttons["workout.liveActivity.show"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Push Day"].exists)
        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000099")!)
        let unavailable = app.alerts["Workout Unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        unavailable.buttons["OK"].tap()
        XCTAssertTrue(app.tabBars.buttons["Programs"].exists)
    }

    private func showWorkoutDay(_ suffix: String) {
        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000\(suffix)")!)
        let show = app.buttons["workout.liveActivity.show"]
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        show.tap()
        let dayName = ["004": "Nine Exercises", "005": "Ten Exercises", "006": "Eleven Exercises"][suffix] ?? "Push Day"
        let switchButton = app.buttons["Show \(dayName)"]
        if app.buttons["Cancel"].exists && switchButton.exists { switchButton.tap() }
        XCTAssertTrue(app.buttons["workout.liveActivity.stop"].waitForExistence(timeout: 10))
    }

    private func openNotificationCenter() -> XCUIApplication {
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        // Permission belongs to the isolated fixture, not location access.
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Always Allow"])).firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        return springboard
    }

    private func keepScreenshot(_ springboard: XCUIApplication, name: String) {
        // SpringBoard updates its accessibility tree before the crossfade ends.
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: springboard.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func stopWorkoutReference() {
        app.activate()
        let stop = app.buttons["workout.liveActivity.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(app.buttons["workout.liveActivity.show"].waitForExistence(timeout: 10))
    }

    func testNineAndTenExerciseOverviewsWithoutPaging() {
        launch("liveActivity")
        clearRunningWorkoutReference()
        for (suffix, count) in [("004", 9), ("005", 10)] {
            showWorkoutDay(suffix)
            let springboard = openNotificationCenter()
            let last = springboard.staticTexts["workout.activity.exercise.\(count - 1)"]
            XCTAssertTrue(last.waitForExistence(timeout: 10))
            for index in 0..<count {
                let exercise = springboard.staticTexts["workout.activity.exercise.\(index)"]
                XCTAssertTrue(exercise.exists && exercise.isHittable)
                XCTAssertTrue(exercise.label.contains("exercise \(index + 1) of \(count)"))
                XCTAssertFalse(exercise.label.contains("reps"))
                XCTAssertFalse(exercise.label.contains("lbs"))
            }
            XCTAssertFalse(springboard.buttons["Next exercises"].exists)
            XCTAssertFalse(springboard.buttons["Previous exercises"].exists)
            keepScreenshot(springboard, name: "Names-only Lock Screen \(count) exercises")
            XCUIDevice.shared.press(.home)
            keepScreenshot(springboard, name: "Names-only compact Dynamic Island \(count) exercises")
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.037)).press(forDuration: 1)
            XCTAssertTrue(last.waitForExistence(timeout: 10))
            for index in 0..<count { XCTAssertTrue(springboard.staticTexts["workout.activity.exercise.\(index)"].isHittable) }
            XCTAssertFalse(springboard.buttons["Next exercises"].exists)
            keepScreenshot(springboard, name: "Names-only expanded Dynamic Island \(count) exercises")
            stopWorkoutReference()
        }
    }

    func testLiveActivityPagesOnNotificationCenter() {
        launch("liveActivity")
        clearRunningWorkoutReference()
        showWorkoutDay("006")
        let springboard = openNotificationCenter()
        let next = springboard.buttons["Next exercises"]
        let previous = springboard.buttons["Previous exercises"]
        XCTAssertTrue(springboard.staticTexts["1–6 of 11 exercises"].waitForExistence(timeout: 10))
        // A disabled control falls through to the card's content deep link.
        // Return to Notification Center and verify it did not navigate pages.
        previous.tap()
        XCTAssertTrue(app.navigationBars["Eleven Exercises"].waitForExistence(timeout: 10))
        _ = openNotificationCenter()
        XCTAssertTrue(springboard.staticTexts["1–6 of 11 exercises"].exists)
        for index in 0..<6 { XCTAssertTrue(springboard.staticTexts["workout.activity.exercise.\(index)"].exists) }
        keepScreenshot(springboard, name: "Names-only overflow first page")
        next.tap()
        XCTAssertTrue(springboard.staticTexts["7–11 of 11 exercises"].waitForExistence(timeout: 10))
        for index in 6..<11 { XCTAssertTrue(springboard.staticTexts["workout.activity.exercise.\(index)"].exists) }
        next.tap()
        XCTAssertTrue(app.navigationBars["Eleven Exercises"].waitForExistence(timeout: 10))
        _ = openNotificationCenter()
        XCTAssertTrue(springboard.staticTexts["7–11 of 11 exercises"].exists)
        keepScreenshot(springboard, name: "Names-only overflow last page")
        previous.tap()
        XCTAssertTrue(springboard.staticTexts["1–6 of 11 exercises"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.037)).press(forDuration: 1)
        XCTAssertTrue(springboard.staticTexts["1–6 of 11 exercises"].waitForExistence(timeout: 10))
        XCTAssertTrue(next.isHittable && previous.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        keepScreenshot(springboard, name: "Names-only overflow expanded Dynamic Island")
        stopWorkoutReference()
    }

    @MainActor
    func testLiveActivityLargerTextSingleColumn() throws {
        let category = UIApplication.shared.preferredContentSizeCategory
        guard category == .extraExtraExtraLarge || category.isAccessibilityCategory else {
            throw XCTSkip("Run this scenario with simulator content_size extra-extra-extra-large or an accessibility size.")
        }
        launch("liveActivity")
        clearRunningWorkoutReference()
        showWorkoutDay("005")
        let springboard = openNotificationCenter()
        let next = springboard.buttons["Next exercises"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        var reached = Set<Int>()
        var checkedFirstPage = false
        for _ in 0..<10 {
            let names = springboard.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.activity.exercise."))
                .allElementsBoundByIndex.sorted { $0.identifier < $1.identifier }
            XCTAssertFalse(names.isEmpty)
            let indices = names.compactMap { Int($0.identifier.components(separatedBy: ".").last ?? "") }
            XCTAssertEqual(indices.count, names.count)
            reached.formUnion(indices)
            for name in names { XCTAssertTrue(name.isHittable) }
            if names.count > 1 { XCTAssertLessThan(names[0].frame.maxY, names[1].frame.maxY) }
            if !checkedFirstPage {
                XCTAssertLessThan(names.count, 10)
                XCTAssertGreaterThanOrEqual(next.frame.height, 44)
                keepScreenshot(springboard, name: "Names-only larger-text single-column Lock Screen")
                checkedFirstPage = true
            }
            if indices.max() == 9 { break }
            let expectedFirst = try XCTUnwrap(indices.max()) + 1
            next.tap()
            XCTAssertTrue(springboard.staticTexts["workout.activity.exercise.\(expectedFirst)"].waitForExistence(timeout: 10))
        }
        XCTAssertEqual(reached, Set(0..<10))
        keepScreenshot(springboard, name: "Names-only larger-text final page")
        stopWorkoutReference()
    }
}
