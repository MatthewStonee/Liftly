import XCTest

/// Add this source to a Rack UI-testing target in Xcode. Each test gets its own
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

    private func launch(_ fixture: String, extraArguments: [String] = []) {
        app.launchArguments = ["-LiftlyUITestFixture", fixture, fixtureID] + extraArguments
        app.launch()
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
        handle.press(forDuration: 1, thenDragTo: target)
        let accepted = workoutOrder()
        XCTAssertNotEqual(accepted, initial)

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
        launch("history", extraArguments: ["-LiftlyDebugSaveFailures", "1"])
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
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
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
}
