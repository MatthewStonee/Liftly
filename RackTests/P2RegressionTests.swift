import Foundation
import SwiftData
import Testing
@testable import Rack

@MainActor
private final class ManualDeletionClock {
    var date = Date(timeIntervalSince1970: 2_000_000_000)
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}

private struct InjectedHistoryFailure: Error {}

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

    @Test func historyOrdersTiesAndIncludesOlderRows() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        for index in 0..<55 {
            let set = LoggedSet(exercise: exercise, reps: 5, weight: Double(index + 1))
            set.completedAt = date.addingTimeInterval(Double(index / 2))
            context.insert(set)
        }
        try context.save()
        let model = ProgressViewModel()
        let history = try model.fetchHistory(for: exercise, context: context).get()
        #expect(history.count == 55)
        #expect(history[0].completedAt >= history[50].completedAt)
        for pair in zip(history, history.dropFirst()) where pair.0.completedAt == pair.1.completedAt {
            #expect(pair.0.id.uuidString < pair.1.id.uuidString)
        }
        #expect(ProgressViewModel.history(history, in: .allTime).count == 55)
    }

    @Test func historyLoadingFailureCanRetryAndOlderSetCanBeEdited() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let old = try Fixtures.savedSet(for: exercise, reps: 5, weight: 100, daysAgo: 400, isPersonalRecord: true, in: context)
        let failing = ProgressViewModel(historyLoader: { _, _ in throw InjectedHistoryFailure() })
        #expect(failing.fetchHistory(for: exercise, context: context).failure != nil)

        let model = ProgressViewModel()
        #expect(ProgressViewModel.history(try model.fetchHistory(for: exercise, context: context).get(), in: .oneMonth).isEmpty)
        #expect(model.updateSet(old, reps: 6, weight: 110, completedAt: old.completedAt, context: context).failure == nil)
        #expect(try model.fetchHistory(for: exercise, context: context).get().first?.reps == 6)
        #expect(model.deleteSet(old, context: context).failure == nil)
        #expect(try model.fetchHistory(for: exercise, context: context).get().isEmpty)
    }
}
