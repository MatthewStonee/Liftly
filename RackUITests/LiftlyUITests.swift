import XCTest

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
        for suffix in ["002", "001"] {
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

    private func enableReorder() {
        app.buttons["Program Options"].tap()
        app.buttons["Reorder"].tap()
        XCTAssertTrue(app.buttons["Done Reordering"].waitForExistence(timeout: 5))
    }

    private func workoutOrder() -> [String] {
        ["Day A", "Day B", "Day C"].sorted {
            app.descendants(matching: .any)["workout.row.\($0)"].frame.midY
                < app.descendants(matching: .any)["workout.row.\($1)"].frame.midY
        }
    }

    func testAcceptedDragPersistsAndCanceledDragKeepsOrder() {
        launch("reorder")
        openReorderProgram()
        enableReorder()
        let initial = workoutOrder()

        let handle = app.descendants(matching: .any)["workout.drag.Day A"]
        let target = app.descendants(matching: .any)["workout.row.Day C"]
        XCTAssertTrue(handle.exists && target.exists)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 2, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)),
                   withVelocity: .slow, thenHoldForDuration: 2)
        // The system transfers the drag payload asynchronously after release.
        let reordered = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                workoutOrder() == ["Day B", "Day C", "Day A"]
            }, object: nil
        )
        let result = XCTWaiter.wait(for: [reordered], timeout: 5)
        XCTAssertEqual(result, .completed)
        let accepted = workoutOrder()
        XCTAssertEqual(initial, ["Day A", "Day B", "Day C"])
        XCTAssertEqual(accepted, ["Day B", "Day C", "Day A"])

        let cancelHandle = app.descendants(matching: .any)["workout.drag.Day B"]
        cancelHandle.press(forDuration: 1, thenDragTo: app.navigationBars.firstMatch)
        XCTAssertEqual(workoutOrder(), accepted)
        app.buttons["Done Reordering"].tap()

        app.terminate()
        launch("reorder")
        openReorderProgram()
        XCTAssertEqual(workoutOrder(), accepted)
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

    func testLiveActivityPagesOnNotificationCenter() {
        launch("liveActivity")
        clearRunningWorkoutReference()
        app.open(URL(string: "liftly://workout/00000000-0000-0000-0000-000000000001")!)
        let stop = app.buttons["workout.liveActivity.stop"]
        XCTAssertTrue(app.buttons["workout.liveActivity.show"].waitForExistence(timeout: 10))
        app.buttons["workout.liveActivity.show"].tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        let next = springboard.buttons["Next exercises"]
        let previous = springboard.buttons["Previous exercises"]
        let openedCenter = XCTAttachment(screenshot: springboard.screenshot())
        openedCenter.name = "Notification Center before workout paging"
        openedCenter.lifetime = .keepAlways
        add(openedCenter)
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(springboard.staticTexts["1–2 of 5 exercises"].waitForExistence(timeout: 10))
        // A fresh test simulator shows iOS's first-use Live Activity choice.
        // This permission belongs to the isolated app test, not location access.
        let allow = springboard.buttons["Allow"]
        if allow.exists { allow.tap() }
        let screenshot = XCTAttachment(screenshot: springboard.screenshot())
        screenshot.name = "Native workout Live Activity"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: springboard.debugDescription)
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        next.tap()
        XCTAssertTrue(springboard.staticTexts["3–4 of 5 exercises"].waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(springboard.staticTexts["5 of 5 exercises"].waitForExistence(timeout: 10))
        // The remote accessibility tree updates before SpringBoard's crossfade
        // completes. Let the system animation finish before keeping evidence.
        Thread.sleep(forTimeInterval: 1)
        let lastPage = XCTAttachment(screenshot: springboard.screenshot())
        lastPage.name = "Native workout Live Activity last page"
        lastPage.lifetime = .keepAlways
        add(lastPage)
        XCTAssertTrue(previous.waitForExistence(timeout: 10))
        previous.tap()
        XCTAssertTrue(springboard.staticTexts["3–4 of 5 exercises"].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        let compactIsland = XCTAttachment(screenshot: springboard.screenshot())
        compactIsland.name = "Compact workout Dynamic Island"
        compactIsland.lifetime = .keepAlways
        add(compactIsland)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.037))
            .press(forDuration: 1)
        XCTAssertTrue(springboard.staticTexts["3–4 of 5 exercises"].waitForExistence(timeout: 10))
        XCTAssertTrue(springboard.buttons["Next exercises"].isHittable)
        XCTAssertTrue(springboard.buttons["Previous exercises"].isHittable)
        XCTAssertGreaterThanOrEqual(springboard.buttons["Next exercises"].frame.height, 44)
        Thread.sleep(forTimeInterval: 1)
        let expandedIsland = XCTAttachment(screenshot: springboard.screenshot())
        expandedIsland.name = "Expanded workout Dynamic Island"
        expandedIsland.lifetime = .keepAlways
        add(expandedIsland)
        app.activate()
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(app.buttons["workout.liveActivity.show"].waitForExistence(timeout: 10))
    }
}
