import Foundation
import SwiftData
import Testing
@testable import Rack

@MainActor
private final class ManualDeletionClock {
    var date = Date(timeIntervalSince1970: 2_000_000_000)
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}

@MainActor
struct P2RegressionTests {
    private let container: ModelContainer
    private let clock = ManualDeletionClock()
    private let alerts = PersistenceAlertCenter()

    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try TestStore.makeInMemoryContainer()
    }

    private func coordinator(runner: PersistenceCommandRunner = PersistenceCommandRunner()) -> DeletionCoordinator {
        DeletionCoordinator(
            context: context,
            alertCenter: alerts,
            commandRunner: runner,
            now: { clock.date },
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
    }

    @Test func consecutiveDeletesRestartAndStaleTimerCannotCommit() throws {
        let first = try Fixtures.savedProgram(in: context, name: "First")
        let second = try Fixtures.savedProgram(in: context, name: "Second")
        let batch = coordinator()

        batch.request(first)
        let oldGeneration = try #require(batch.generation)
        batch.request(first)
        #expect(batch.pendingCount == 1)
        #expect(batch.generation == oldGeneration)
        clock.advance(3)
        batch.request(second)
        #expect(batch.pendingCount == 2)
        #expect(batch.generation != oldGeneration)
        batch.expire(generation: oldGeneration)
        #expect(try TestStore.savedModels(Program.self, in: container).count == 2)

        batch.undo()
        #expect(batch.pendingCount == 0)
        #expect(try TestStore.savedModels(Program.self, in: container).count == 2)
    }

    @Test func backgroundPauseAndResumeRetainsBatch() throws {
        let program = try Fixtures.savedProgram(in: context)
        let batch = coordinator()
        batch.request(program)
        let oldGeneration = try #require(batch.generation)
        clock.advance(1)
        batch.setActive(false)
        clock.advance(60)
        batch.expire(generation: oldGeneration)
        #expect(try TestStore.savedModels(Program.self, in: container).count == 1)

        batch.setActive(true)
        let resumedGeneration = try #require(batch.generation)
        batch.expire(generation: resumedGeneration)
        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
    }

    @Test func undoWhileInactiveDoesNotLeaveFutureBatchesPaused() throws {
        let program = try Fixtures.savedProgram(in: context)
        let batch = coordinator()
        batch.request(program)
        batch.setActive(false)
        batch.undo()
        batch.setActive(true)
        #expect(!batch.isPaused)

        batch.request(program)
        batch.expire(generation: try #require(batch.generation))
        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
    }

    @Test func requestsWhileInactiveWaitForResume() throws {
        let program = try Fixtures.savedProgram(in: context)
        let batch = coordinator()
        batch.setActive(false)
        batch.request(program)
        batch.expire(generation: try #require(batch.generation))
        #expect(try TestStore.savedModels(Program.self, in: container).count == 1)
        batch.setActive(true)
        batch.expire(generation: try #require(batch.generation))
        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
    }

    @Test func parentChildRequestsCollapseAndMixedBatchCommits() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push"])
        let workout = try #require(program.workoutsList.first)
        let exercise = try Fixtures.savedExercise(in: context)
        let planned = PlannedExercise(exercise: exercise)
        planned.workoutTemplate = workout
        context.insert(planned)
        try context.save()
        let set = try Fixtures.savedSet(for: exercise, reps: 5, weight: 100, daysAgo: 1, isPersonalRecord: true, in: context)
        let batch = coordinator()

        batch.request(planned)
        batch.request(workout)
        batch.request(program)
        #expect(batch.pendingCount == 1)
        batch.request(set)
        #expect(batch.pendingCount == 2)
        batch.expire(generation: try #require(batch.generation))

        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).isEmpty)
        #expect(try TestStore.savedModels(PlannedExercise.self, in: container).isEmpty)
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).isEmpty)
    }

    @Test func pendingSetKeepsPRAndCommitPromotesSessionlessSet() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let oldPR = try Fixtures.savedSet(for: exercise, reps: 5, weight: 200, daysAgo: 1, isPersonalRecord: true, in: context)
        let next = try Fixtures.savedSet(for: exercise, reps: 5, weight: 190, daysAgo: 2, isPersonalRecord: false, in: context)
        let otherReps = try Fixtures.savedSet(for: exercise, reps: 8, weight: 100, daysAgo: 2, isPersonalRecord: true, in: context)
        let batch = coordinator()

        batch.request(oldPR)
        #expect(oldPR.isPersonalRecord)
        #expect(!next.isPersonalRecord)
        batch.undo()
        #expect(oldPR.isPersonalRecord)

        batch.request(oldPR)
        batch.expire(generation: try #require(batch.generation))
        #expect(next.session == nil)
        #expect(next.isPersonalRecord)
        #expect(otherReps.isPersonalRecord)
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).count == 2)
    }

    @Test func failedBatchRestoresVisibilityAndPersistedModels() throws {
        let program = try Fixtures.savedProgram(in: context)
        let saves = SaveSwitch(isFailing: true)
        let batch = coordinator(runner: saves.runner)
        batch.request(program)
        batch.expire(generation: try #require(batch.generation))

        #expect(batch.pendingCount == 0)
        #expect(try TestStore.savedModels(Program.self, in: container).count == 1)
        #expect(alerts.currentAlert?.title == "Couldn't Delete Items")
    }

    @Test func frontmostAlertHostPresentsAndAlertsWaitForAcknowledgment() {
        let root = UUID(), sheet = UUID(), nestedSheet = UUID()
        alerts.registerHost(root)
        alerts.registerHost(sheet)
        alerts.registerHost(nestedSheet)
        #expect(alerts.activeHostID == nestedSheet)
        alerts.unregisterHost(nestedSheet)
        #expect(alerts.activeHostID == sheet)
        alerts.registerHost(root) // Reappearing moves a host back to the top.
        #expect(alerts.hostIDs == [sheet, root])
        alerts.unregisterHost(root)
        #expect(alerts.activeHostID == sheet)

        let first = PersistenceAlert(title: "Couldn't Delete Items", error: .failed("first"))
        let second = PersistenceAlert(title: "Couldn't Delete Items", error: .failed("second"))
        alerts.report(first)
        alerts.report(second)
        alerts.unregisterHost(sheet) // A sheet torn down mid-alert doesn't acknowledge it.
        #expect(alerts.activeHostID == nil)
        #expect(alerts.currentAlert == first)
        alerts.registerHost(root)
        #expect(alerts.currentAlert == first)
        alerts.dismiss(first)
        #expect(alerts.currentAlert == second)
        alerts.dismiss(second)
        #expect(alerts.currentAlert == nil)
    }

    @Test func emptyProgramDeletionFetchesOnlyRequestedPrograms() throws {
        let program = try Fixtures.savedProgram(in: context)
        var fetched: [DeletionCoordinator.FetchKind] = []
        let batch = DeletionCoordinator(
            context: context, alertCenter: alerts,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
            onFetch: { fetched.append($0) }
        )
        batch.request(program)
        batch.expire(generation: try #require(batch.generation))
        #expect(fetched == [.requestedPrograms])
        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
    }

    @Test func missingRequestedItemDoesNotBlockTheBatch() throws {
        let first = try Fixtures.savedProgram(in: context, name: "First")
        let second = try Fixtures.savedProgram(in: context, name: "Second")
        let batch = coordinator()
        batch.request(first)
        batch.request(second)
        context.delete(first)
        try context.save()
        batch.expire(generation: try #require(batch.generation))
        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
        #expect(alerts.currentAlert == nil)
    }

    @Test func batchNormalizesOnlySurvivingSiblings() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["One", "Two", "Three"])
        let other = try Fixtures.savedProgram(in: context, workoutNames: ["Other"])
        let middle = program.sortedWorkouts[1]
        let batch = coordinator()
        batch.request(middle)
        batch.expire(generation: try #require(batch.generation))
        #expect(program.sortedWorkouts.map(\.orderIndex) == [0, 1])
        #expect(other.sortedWorkouts.map(\.orderIndex) == [0])
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).count == 3)
    }

    @Test func failedMixedBatchRollsBackRowsOrderAndRecords() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["One", "Two", "Three"])
        let exercise = try Fixtures.savedExercise(in: context)
        let record = try Fixtures.savedSet(
            for: exercise, reps: 5, weight: 200, daysAgo: 1,
            isPersonalRecord: true, in: context
        )
        let runnerUp = try Fixtures.savedSet(
            for: exercise, reps: 5, weight: 180, daysAgo: 2,
            isPersonalRecord: false, in: context
        )
        let saves = SaveSwitch(isFailing: true)
        let batch = coordinator(runner: saves.runner)
        batch.request(program.sortedWorkouts[1])
        batch.request(record)
        batch.expire(generation: try #require(batch.generation))

        #expect(saves.saveAttempts == 1)
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).count == 3)
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).count == 2)
        #expect(program.sortedWorkouts.map(\.orderIndex) == [0, 1, 2])
        #expect(record.isPersonalRecord)
        #expect(!runnerUp.isPersonalRecord)
        #expect(alerts.currentAlert?.title == "Couldn't Delete Items")
    }

    @Test func batchNotifiesOnlyAfterSuccessfulSetDeletion() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let record = try Fixtures.savedSet(
            for: exercise, reps: 5, weight: 100, daysAgo: 1,
            isPersonalRecord: true, in: context
        )
        let runnerUp = try Fixtures.savedSet(
            for: exercise, reps: 5, weight: 90, daysAgo: 2,
            isPersonalRecord: false, in: context
        )
        let exerciseID = exercise.id
        var notifications = 0
        let token = NotificationCenter.default.addObserver(
            forName: LoggedSetChange.didCommit, object: nil, queue: nil
        ) { notification in
            if LoggedSetChange.affects(exerciseID, notification: notification) {
                notifications += 1
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let saves = SaveSwitch(isFailing: true)
        let failedBatch = coordinator(runner: saves.runner)
        failedBatch.request(record)
        failedBatch.expire(generation: try #require(failedBatch.generation))
        #expect(notifications == 0)
        #expect(!runnerUp.isPersonalRecord)

        saves.isFailing = false
        let retriedBatch = coordinator(runner: saves.runner)
        retriedBatch.request(record)
        retriedBatch.expire(generation: try #require(retriedBatch.generation))
        #expect(notifications == 1)
        #expect(runnerUp.isPersonalRecord)
    }

    @Test func duplicateIndexesNormalizeOnAddAndSurviveMiddleDeletion() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["One", "Two", "Three"])
        let ordered = program.sortedWorkouts
        ordered[0].orderIndex = 7
        ordered[1].orderIndex = 7
        ordered[2].orderIndex = 20
        try context.save()

        let model = ProgramDetailViewModel()
        let added = try model.addWorkout(named: "Four", to: program, context: context).get()
        #expect(program.sortedWorkouts.map(\.orderIndex) == [0, 1, 2, 3])
        #expect(added.orderIndex == 3)

        let middle = program.sortedWorkouts[1]
        #expect(model.deleteWorkout(middle, context: context).failure == nil)
        #expect(program.sortedWorkouts.map(\.orderIndex) == [0, 1, 2])
        let afterDelete = try model.addWorkout(named: "Five", to: program, context: context).get()
        #expect(afterDelete.orderIndex == 3)
        #expect(program.sortedWorkouts.map(\.orderIndex) == [0, 1, 2, 3])
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).count == 4)
    }

    @Test func addingDuringPendingDeletionKeepsHiddenSiblingPosition() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["One", "Two"])
        let batch = coordinator()
        batch.request(program.sortedWorkouts[0])
        let added = try ProgramDetailViewModel().addWorkout(named: "Three", to: program, context: context).get()
        #expect(added.orderIndex == 2)
        batch.undo()
        #expect(program.sortedWorkouts.map(\.name) == ["One", "Two", "Three"])
    }

    @Test func plannedExerciseIndexesNormalizeWhenAdding() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push"])
        let workout = try #require(program.workoutsList.first)
        let exercise = try Fixtures.savedExercise(in: context)
        let first = PlannedExercise(exercise: exercise, orderIndex: 9)
        first.workoutTemplate = workout
        context.insert(first)
        let second = PlannedExercise(exercise: exercise, orderIndex: 9)
        second.workoutTemplate = workout
        context.insert(second)
        try context.save()

        let added = try WorkoutTemplateDetailViewModel()
            .addExercise(exercise, to: workout, repTargetType: .exact, context: context).get()
        #expect(added.orderIndex == 2)
        #expect(workout.sortedExercises.map(\.orderIndex) == [0, 1, 2])
    }

    @Test func reorderedIndexesPersistAfterReopening() throws {
        let directory = try TestStore.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Liftly.store")

        do {
            let disk = try TestStore.makeOnDiskContainer(at: storeURL)
            let diskContext = disk.mainContext
            let program = try Fixtures.savedProgram(in: diskContext, workoutNames: ["One", "Two", "Three"])
            let reversed = program.sortedWorkouts.reversed().map(\.id)
            #expect(ProgramDetailViewModel().reorderWorkouts(in: program, orderedIDs: reversed, context: diskContext).failure == nil)
        }

        let reopened = try TestStore.makeOnDiskContainer(at: storeURL)
        let workouts = try reopened.mainContext.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(SiblingOrder.workouts(workouts).map(\.name) == ["Three", "Two", "One"])
        #expect(SiblingOrder.workouts(workouts).map(\.orderIndex) == [0, 1, 2])
    }

    @Test func dragAcceptsOnlyCurrentCollectionAndNoOp() {
        let drag = ReorderDropSession(activeID: 2, initialIDs: [1, 2, 3])
        #expect(drag.acceptedOrder(payloadID: 1, currentIDs: [1, 2, 3], rawIndex: 3) == nil)
        #expect(drag.acceptedOrder(payloadID: 2, currentIDs: [1, 2, 3, 4], rawIndex: 3) == nil)
        #expect(drag.acceptedOrder(payloadID: 2, currentIDs: [1, 2, 3], rawIndex: 2) == [1, 2, 3])
        #expect(drag.acceptedOrder(payloadID: 2, currentIDs: [1, 2, 3], rawIndex: 0) == [2, 1, 3])

        var state = ReorderDragState<Int>()
        state.begin(id: 2, collection: [1, 2, 3])
        state.cancel() // Preview disappeared or the drop landed outside a target.
        #expect(state.accept(payloadID: 2, collection: [1, 2, 3], rawIndex: 0) == nil)
        state.begin(id: 2, collection: [1, 2, 3])
        #expect(state.accept(payloadID: 2, collection: [1, 2, 3], rawIndex: 0) == [2, 1, 3])
        #expect(state.session == nil)
    }

    @Test func chartUsesSelectedUnitForEveryMarkAndInvalidatesEquality() {
        let point = ExerciseProgressChartPoint(date: .now, weight: 100)
        #expect(point.displayWeight(unit: .lbs) == 100)
        #expect(abs(point.displayWeight(unit: .kg) - 45.3592) < 0.0001)
        #expect(ExerciseProgressChartCard(chartPoints: [point], weightUnit: .lbs)
            != ExerciseProgressChartCard(chartPoints: [point], weightUnit: .kg))
    }
}

private struct HistoryTestFailure: Error {}

@MainActor
private final class HistoryFailureSwitch {
    var failOffset: Int?
    var shouldFail = false
    var cutoffs: [Date] = []
}

@MainActor
struct ExerciseHistoryViewModelTests {
    /// Sets one second apart, so a loaded window lists them newest first.
    private func historyFixture(rowCount: Int) throws -> (ModelContainer, Exercise) {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        for index in 0..<rowCount {
            let set = LoggedSet(exercise: exercise, reps: 5, weight: Double(index))
            set.completedAt = Date(timeIntervalSince1970: 1_900_000_000 + Double(index))
            context.insert(set)
        }
        try context.save()
        return (container, exercise)
    }

    private func pendingDeletionCoordinator(for context: ModelContext) -> DeletionCoordinator {
        DeletionCoordinator(
            context: context, alertCenter: PersistenceAlertCenter(),
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
    }

    @Test func survivingAnchorPrefersTheNextRowThenThePreviousOne() {
        let ids = (0..<4).map { _ in UUID() }
        #expect(ExerciseHistoryViewModel.survivingAnchor(
            for: ids[1], previousIDs: ids, currentIDs: ids) == ids[1])
        #expect(ExerciseHistoryViewModel.survivingAnchor(
            for: ids[1], previousIDs: ids, currentIDs: [ids[0], ids[2], ids[3]]) == ids[2])
        #expect(ExerciseHistoryViewModel.survivingAnchor(
            for: ids[3], previousIDs: ids, currentIDs: [ids[0], ids[1]]) == ids[1])
        #expect(ExerciseHistoryViewModel.survivingAnchor(
            for: ids[1], previousIDs: ids, currentIDs: []) == nil)
    }

    @Test func anchorFollowsTheNextRowAndUndoBringsTheUserBack() throws {
        let (container, exercise) = try historyFixture(rowCount: 52)
        let context = container.mainContext
        let coordinator = pendingDeletionCoordinator(for: context)
        let model = ExerciseHistoryViewModel()
        model.loadInitial(exerciseID: exercise.id, context: context, excluding: [])
        let anchored = model.rows[10]
        let next = model.rows[11]
        model.scrollAnchorID = anchored.id

        coordinator.request(anchored)
        model.refresh(exerciseID: exercise.id, context: context,
                      excluding: coordinator.pendingLoggedSetIDs(for: exercise.id))
        #expect(!model.rows.contains { $0.id == anchored.id })
        #expect(model.scrollAnchorID == next.id)

        coordinator.undo()
        model.refresh(exerciseID: exercise.id, context: context,
                      excluding: coordinator.pendingLoggedSetIDs(for: exercise.id))
        #expect(model.scrollAnchorID == anchored.id)
    }

    @Test func scrollingAwayBeforeUndoKeepsTheUsersNewPlace() throws {
        let (container, exercise) = try historyFixture(rowCount: 52)
        let context = container.mainContext
        let coordinator = pendingDeletionCoordinator(for: context)
        let model = ExerciseHistoryViewModel()
        model.loadInitial(exerciseID: exercise.id, context: context, excluding: [])
        let anchored = model.rows[10]
        model.scrollAnchorID = anchored.id

        coordinator.request(anchored)
        model.refresh(exerciseID: exercise.id, context: context,
                      excluding: coordinator.pendingLoggedSetIDs(for: exercise.id))
        let elsewhere = model.rows[30]
        model.scrollAnchorID = elsewhere.id // The user scrolled on.

        coordinator.undo()
        model.refresh(exerciseID: exercise.id, context: context,
                      excluding: coordinator.pendingLoggedSetIDs(for: exercise.id))
        #expect(model.scrollAnchorID == elsewhere.id)
    }

    @Test func returningToHistoryRefreshesTheLoadedWindowInsteadOfResetting() throws {
        let (container, exercise) = try historyFixture(rowCount: 120)
        let context = container.mainContext
        var requests: [HistoryPageRequest] = []
        let model = ExerciseHistoryViewModel(pageLoader: { request, context in
            requests.append(request)
            return try ExerciseHistoryViewModel.fetchPage(request, in: context)
        })
        model.appear(exerciseID: exercise.id, context: context, excluding: [])
        model.loadMore(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 100)

        model.appear(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 100)
        #expect(requests.last?.offset == 0)
        #expect(requests.last?.limit == 100)
    }

    @Test func sqlitePagesEveryTiedRowExactlyOnce() throws {
        let directory = try TestStore.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TestStore.makeOnDiskContainer(at: directory.appending(path: "History.store"))
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)
        var inserted: [LoggedSet] = []
        for index in 0..<125 {
            let set = LoggedSet(exercise: exercise, reps: 5, weight: Double(index))
            set.completedAt = timestamp
            context.insert(set)
            inserted.append(set)
        }
        try context.save()

        let requests = HistoryFailureSwitch()
        let model = ExerciseHistoryViewModel(pageLoader: { request, context in
            requests.cutoffs.append(request.cutoff)
            return try ExerciseHistoryViewModel.fetchPage(request, in: context)
        })
        model.selectRange(
            .oneMonth, exerciseID: exercise.id, context: context,
            excluding: [], now: timestamp.addingTimeInterval(1)
        )
        #expect(model.initialError == nil)
        #expect(model.rows.count == 50)
        #expect(model.hasMore)
        model.loadMore(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 100)
        model.loadMore(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 125)
        #expect(!model.hasMore)
        let expected = inserted.map(\.id).sorted { $0.uuidString < $1.uuidString }
        #expect(model.rows.map(\.id) == expected)
        #expect(Set(model.rows.map(\.id)).count == 125)
        #expect(Set(requests.cutoffs).count == 1)
    }

    @Test func rangeBoundaryAndRefreshKeepLoadedWindow() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let cutoff = try #require(Calendar.current.date(byAdding: .day, value: -30, to: now))
        let boundary = LoggedSet(exercise: exercise, reps: 5, weight: 90)
        boundary.completedAt = cutoff
        let older = LoggedSet(exercise: exercise, reps: 5, weight: 80)
        older.completedAt = cutoff.addingTimeInterval(-1)
        let newest = LoggedSet(exercise: exercise, reps: 5, weight: 100)
        newest.completedAt = now
        for set in [boundary, older, newest] { context.insert(set) }
        try context.save()

        let model = ExerciseHistoryViewModel()
        model.selectRange(.oneMonth, exerciseID: exercise.id, context: context, excluding: [], now: now)
        #expect(model.rows.map(\.id) == [newest.id, boundary.id])
        #expect(model.hasAnyHistory)

        #expect(ProgressViewModel().updateSet(
            boundary, reps: 5, weight: 90, completedAt: now.addingTimeInterval(1), context: context
        ).failure == nil)
        model.refresh(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.map(\.id) == [boundary.id, newest.id])

        model.selectRange(.threeMonths, exerciseID: exercise.id, context: context, excluding: [], now: now)
        #expect(model.rows.count == 3)
        model.selectRange(.oneMonth, exerciseID: exercise.id, context: context, excluding: [], now: now)
        #expect(model.rows.count == 2)
    }

    @Test func olderSetShowsOnlyInAllTimeAndCanBeEditedThenDeleted() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        let old = try Fixtures.savedSet(
            for: exercise, reps: 5, weight: 100, daysAgo: 400,
            isPersonalRecord: true, in: context
        )
        let model = ExerciseHistoryViewModel()
        model.selectRange(.oneYear, exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.isEmpty)
        #expect(model.hasAnyHistory)
        model.selectRange(.allTime, exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.map(\.id) == [old.id])

        let progress = ProgressViewModel()
        #expect(progress.updateSet(
            old, reps: 6, weight: 110, completedAt: old.completedAt, context: context
        ).failure == nil)
        model.refresh(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.map(\.id) == [old.id])
        #expect(model.rows.first?.reps == 6)

        #expect(progress.deleteSet(old, context: context).failure == nil)
        model.refresh(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.isEmpty)
        #expect(!model.hasAnyHistory)
    }

    @Test func pendingDeletionUndoAndCommitRestoreCorrectRows() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        var sets: [LoggedSet] = []
        for index in 0..<52 {
            let set = LoggedSet(exercise: exercise, reps: 5, weight: Double(index))
            set.completedAt = Date(timeIntervalSince1970: 1_900_000_000 + Double(index))
            context.insert(set)
            sets.append(set)
        }
        try context.save()
        let alerts = PersistenceAlertCenter()
        let coordinator = DeletionCoordinator(
            context: context, alertCenter: alerts,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        let model = ExerciseHistoryViewModel()
        model.loadInitial(exerciseID: exercise.id, context: context, excluding: [])
        let first = try #require(model.rows.first)
        coordinator.request(first)
        model.refresh(exerciseID: exercise.id, context: context,
                      excluding: coordinator.pendingLoggedSetIDs(for: exercise.id))
        #expect(model.rows.count == 50)
        #expect(!model.rows.contains(where: { $0.id == first.id }))
        coordinator.undo()
        model.refresh(exerciseID: exercise.id, context: context,
                      excluding: coordinator.pendingLoggedSetIDs(for: exercise.id))
        #expect(model.rows.first?.id == first.id)

        coordinator.request(first)
        coordinator.expire(generation: try #require(coordinator.generation))
        model.refresh(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 50)
        #expect(!model.rows.contains(where: { $0.id == first.id }))
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).count == 51)
    }

    @Test func failedLaterPageAndRefreshRetainRowsAndRetry() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        for index in 0..<55 {
            let set = LoggedSet(exercise: exercise, reps: 5, weight: Double(index))
            context.insert(set)
        }
        try context.save()
        let failure = HistoryFailureSwitch()
        var requestCount = 0
        let model = ExerciseHistoryViewModel(pageLoader: { request, context in
            requestCount += 1
            if failure.failOffset == request.offset { throw HistoryTestFailure() }
            return try ExerciseHistoryViewModel.fetchPage(request, in: context)
        })
        model.loadInitial(exerciseID: exercise.id, context: context, excluding: [])
        let firstPageIDs = model.rows.map(\.id)
        failure.failOffset = 50
        model.loadMore(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.map(\.id) == firstPageIDs)
        #expect(model.inlineError?.message == "Your history couldn’t be loaded. Try again.")
        failure.failOffset = nil
        model.retry(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 55)
        #expect(model.inlineError == nil)

        failure.failOffset = 0
        model.refresh(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 55)
        #expect(model.inlineError != nil)
        failure.failOffset = nil
        model.retry(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.rows.count == 55)
        #expect(model.inlineError == nil)
        #expect(requestCount == 5)
    }

    @Test func unrelatedChangeSkipsQueryAndInitialFailureRetries() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        let other = try Fixtures.savedExercise(in: context, name: "Other")
        let failure = HistoryFailureSwitch()
        failure.shouldFail = true
        var requests = 0
        let model = ExerciseHistoryViewModel(pageLoader: { request, context in
            requests += 1
            if failure.shouldFail { throw HistoryTestFailure() }
            return try ExerciseHistoryViewModel.fetchPage(request, in: context)
        })
        model.loadInitial(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.initialError != nil)
        failure.shouldFail = false
        model.retry(exerciseID: exercise.id, context: context, excluding: [])
        #expect(model.initialError == nil)
        #expect(!model.hasAnyHistory)

        let unrelated = Notification(name: LoggedSetChange.didCommit,
                                     userInfo: [LoggedSetChange.exerciseIDsKey: Set([other.id])])
        model.handleCommittedChange(unrelated, exerciseID: exercise.id, context: context, excluding: [])
        #expect(requests == 2)
        let relevant = Notification(name: LoggedSetChange.didCommit,
                                    userInfo: [LoggedSetChange.exerciseIDsKey: Set([exercise.id])])
        model.handleCommittedChange(relevant, exerciseID: exercise.id, context: context, excluding: [])
        #expect(requests == 3)
    }
}

@MainActor
struct LargeStoreBenchmarkTests {
    /// Prints measurements for a repeatable SQLite fixture. Timing is diagnostic,
    /// while fetched-row counts capture the intended query reduction.
    @Test func deletionAndInitialHistoryFetch() throws {
        let directory = try TestStore.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TestStore.makeOnDiskContainer(at: directory.appending(path: "Benchmark.store"))
        let context = container.mainContext
        let exercise = try Fixtures.savedExercise(in: context)
        let target = Program(name: "Benchmark deletion target")
        context.insert(target)
        for index in 0..<49 {
            let program = Program(name: "Benchmark \(index)")
            let workout = WorkoutTemplate(name: "Day", orderIndex: 0)
            workout.program = program
            let planned = PlannedExercise(exercise: exercise)
            planned.workoutTemplate = workout
            context.insert(program)
            context.insert(workout)
            context.insert(planned)
        }
        for index in 0..<1_200 {
            let set = LoggedSet(exercise: exercise, reps: 5, weight: Double(index + 1))
            set.completedAt = Date(timeIntervalSince1970: 1_900_000_000 + Double(index))
            context.insert(set)
        }
        try context.save()

        let clock = ContinuousClock()
        let baselineDeletionStart = clock.now
        let allPrograms = try context.fetch(FetchDescriptor<Program>())
        let allWorkouts = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let allPlanned = try context.fetch(FetchDescriptor<PlannedExercise>())
        let allSets = try context.fetch(FetchDescriptor<LoggedSet>())
        let baselineDeletionTime = baselineDeletionStart.duration(to: clock.now)
        let baselineDeletionRows = allPrograms.count + allWorkouts.count
            + allPlanned.count + allSets.count

        let baselineHistoryStart = clock.now
        let exerciseID = exercise.id
        let fullHistory = try context.fetch(FetchDescriptor<LoggedSet>(
            predicate: #Predicate<LoggedSet> { $0.exercise?.id == exerciseID }
        ))
        let baselineHistoryTime = baselineHistoryStart.duration(to: clock.now)

        let boundedHistoryStart = clock.now
        let page = try ExerciseHistoryViewModel.fetchPage(HistoryPageRequest(
            exerciseID: exerciseID, cutoff: .distantPast, offset: 0, limit: 50,
            excludedPendingDeletionIDs: []
        ), in: context)
        let boundedHistoryTime = boundedHistoryStart.duration(to: clock.now)

        var fetched: [DeletionCoordinator.FetchKind] = []
        let batch = DeletionCoordinator(
            context: context, alertCenter: PersistenceAlertCenter(),
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
            onFetch: { fetched.append($0) }
        )
        let boundedDeletionStart = clock.now
        batch.request(target)
        batch.expire(generation: try #require(batch.generation))
        let boundedDeletionTime = boundedDeletionStart.duration(to: clock.now)

        #expect(fullHistory.count == 1_200)
        #expect(page.rows.count == 50 && page.hasMore)
        #expect(fetched == [.requestedPrograms])
        #expect(baselineDeletionRows == 1_348)
        let report = """
        Deletion baseline full fetch: \(baselineDeletionTime), \(baselineDeletionRows) rows
        Deletion targeted commit: \(boundedDeletionTime), 1 requested row
        History baseline full fetch: \(baselineHistoryTime), \(fullHistory.count) rows
        History first page: \(boundedHistoryTime), at most 51 rows
        """
        Attachment.record(report, named: "large-store-query-benchmark.txt")
    }
}
