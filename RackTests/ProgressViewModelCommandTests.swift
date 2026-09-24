import Combine
import Foundation
import SwiftData
import Testing
@testable import Rack

@MainActor
struct ProgressViewModelCommandTests {
    private let container: ModelContainer
    private let saves = SaveSwitch()
    private let viewModel: ProgressViewModel

    private var context: ModelContext {
        container.mainContext
    }

    init() throws {
        container = try TestStore.makeInMemoryContainer()
        viewModel = ProgressViewModel(commandRunner: saves.runner)
    }

    // MARK: Logging

    @Test func loggingAHeavierSetMovesTheRecord() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let previous = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 2, isRecord: true)

        let logged = try viewModel.logSet(for: exercise, reps: 5, weight: 110, completedAt: .now, context: context).get()

        #expect(logged.isPersonalRecord)
        #expect(!previous.isPersonalRecord)
        #expect(!context.hasChanges)
        viewModel.refreshExerciseMetrics(for: exercise, context: context)
        #expect(viewModel.exerciseMetrics.personalRecord?.id == logged.id)
        #expect(try savedRecordIDs() == [logged.id])
    }

    @Test func loggingATiedSetKeepsTheExistingRecord() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let previous = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 2, isRecord: true)

        let tied = try viewModel.logSet(for: exercise, reps: 5, weight: 100, completedAt: .now, context: context).get()
        let backdated = try viewModel.logSet(
            for: exercise,
            reps: 5,
            weight: 100,
            completedAt: previous.completedAt.addingTimeInterval(-86_400),
            context: context
        ).get()

        #expect(previous.isPersonalRecord)
        #expect(!tied.isPersonalRecord)
        #expect(!backdated.isPersonalRecord)
        #expect(try savedRecordIDs() == [previous.id])
    }

    @Test func recordsAreTrackedPerRepCount() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let fiveRepRecord = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 2, isRecord: true)

        let threeRepSet = try viewModel.logSet(for: exercise, reps: 3, weight: 90, completedAt: .now, context: context).get()

        #expect(threeRepSet.isPersonalRecord)
        #expect(fiveRepRecord.isPersonalRecord)
        #expect(try savedRecordIDs() == [fiveRepRecord.id, threeRepSet.id])
    }

    @Test func zeroWeightSetsAreNeverRecords() throws {
        let exercise = try Fixtures.savedExercise(in: context, name: "Pull-Up", equipment: .bodyweight)

        let logged = try viewModel.logSet(for: exercise, reps: 8, weight: 0, completedAt: .now, context: context).get()

        #expect(logged.weight == 0)
        #expect(!logged.isPersonalRecord)
    }

    @Test func invalidLogInputsNeverCreateOrSaveASet() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let record = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 1, isRecord: true)
        let invalidInputs: [(Int, Double)] = [
            (0, 100), (-1, 100), (5, -1), (5, .nan),
            (5, .infinity), (5, -.infinity)
        ]

        for (reps, weight) in invalidInputs {
            let result = viewModel.logSet(
                for: exercise, reps: reps, weight: weight, completedAt: .now, context: context
            )
            #expect(result.failure == .invalidInput)
            #expect(saves.saveAttempts == 0)
            #expect(!context.hasChanges)
            #expect(try TestStore.savedModels(LoggedSet.self, in: container).map(\.id) == [record.id])
            #expect(record.isPersonalRecord)
        }
    }

    @Test func invalidEditInputsLeaveValuesAndRecordsUntouched() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let record = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 1, isRecord: true)
        let invalidInputs: [(Int, Double)] = [
            (0, 90), (-1, 90), (5, -1), (5, .nan),
            (5, .infinity), (5, -.infinity)
        ]

        for (reps, weight) in invalidInputs {
            let result = viewModel.updateSet(
                record, reps: reps, weight: weight,
                completedAt: record.completedAt.addingTimeInterval(10), context: context
            )
            #expect(result.failure == .invalidInput)
            #expect(saves.saveAttempts == 0)
            #expect(!context.hasChanges)
            #expect(record.reps == 5)
            #expect(record.weight == 100)
            #expect(record.isPersonalRecord)
            #expect(try savedRecordIDs() == [record.id])
        }
    }

    @Test func changeNotificationsRequireSuccessfulCommits() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let exerciseID = exercise.id
        var events: [Set<UUID>] = []
        let token = NotificationCenter.default.addObserver(
            forName: LoggedSetChange.didCommit, object: nil, queue: nil
        ) { notification in
            if let ids = notification.userInfo?[LoggedSetChange.exerciseIDsKey] as? Set<UUID>,
               ids.contains(exerciseID) {
                events.append(ids)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        #expect(viewModel.logSet(for: exercise, reps: 0, weight: 100,
                                 completedAt: .now, context: context).failure == .invalidInput)
        saves.isFailing = true
        #expect(viewModel.logSet(for: exercise, reps: 5, weight: 100,
                                 completedAt: .now, context: context).failure != nil)
        #expect(events.isEmpty)

        saves.isFailing = false
        let set = try viewModel.logSet(for: exercise, reps: 5, weight: 100,
                                       completedAt: .now, context: context).get()
        #expect(events.count == 1)
        saves.isFailing = true
        #expect(viewModel.updateSet(set, reps: 5, weight: 110,
                                    completedAt: set.completedAt, context: context).failure != nil)
        #expect(events.count == 1)
        saves.isFailing = false
        #expect(viewModel.updateSet(set, reps: 5, weight: 110,
                                    completedAt: set.completedAt, context: context).failure == nil)
        #expect(events.count == 2)
        let savesBeforeNoOp = saves.saveAttempts
        #expect(viewModel.updateSet(set, reps: 5, weight: 110,
                                    completedAt: set.completedAt, context: context).failure == nil)
        #expect(saves.saveAttempts == savesBeforeNoOp)
        #expect(events.count == 2)
        try deleteAfterUndoWindow(set)
        #expect(events.count == 3)
    }

    @Test func failedLogLeavesNoSetAndRetryLogsOnce() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let previous = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 2, isRecord: true)
        saves.isFailing = true

        let failed = viewModel.logSet(for: exercise, reps: 5, weight: 110, completedAt: .now, context: context)

        #expect(failed.isRolledBackSaveFailure)
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<LoggedSet>()).map(\.id) == [previous.id])
        #expect(previous.isPersonalRecord)
        viewModel.refreshExerciseMetrics(for: exercise, context: context)
        #expect(viewModel.exerciseMetrics.personalRecord?.id == previous.id)
        #expect(viewModel.exerciseMetrics.latestSet?.id == previous.id)

        saves.isFailing = false
        let retried = try viewModel.logSet(for: exercise, reps: 5, weight: 110, completedAt: .now, context: context).get()

        #expect(try TestStore.savedModels(LoggedSet.self, in: container).count == 2)
        #expect(try savedRecordIDs() == [retried.id])
        #expect(retried.modelContext === context)
        #expect(!previous.isPersonalRecord)
        #expect(Set(exercise.loggedSetsList.map(\.id)) == [previous.id, retried.id])
        viewModel.refreshExerciseMetrics(for: exercise, context: context)
        #expect(viewModel.exerciseMetrics.personalRecord?.id == retried.id)
    }

    @Test func setCommandsRefuseADirtyContextWithoutDiscardingIt() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        context.insert(Program(name: "Unsaved"))

        let result = viewModel.logSet(for: exercise, reps: 5, weight: 100, completedAt: .now, context: context)

        #expect(result.failure == .pendingChanges)
        #expect(context.insertedModelsArray.count == 1)
        #expect(try context.fetch(FetchDescriptor<LoggedSet>()).isEmpty)
    }

    // MARK: Editing

    @Test func failedEditRestoresTheSetAndRecordFlags() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let record = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 3, isRecord: true)
        let other = try savedSet(exercise, reps: 5, weight: 90, daysAgo: 1, isRecord: false)
        saves.isFailing = true

        let failed = viewModel.updateSet(other, reps: 5, weight: 120, completedAt: other.completedAt, context: context)

        #expect(failed.isRolledBackSaveFailure)
        #expect(other.weight == 90)
        #expect(record.isPersonalRecord)
        #expect(!other.isPersonalRecord)
        viewModel.refreshExerciseMetrics(for: exercise, context: context)
        #expect(viewModel.exerciseMetrics.personalRecord?.id == record.id)

        saves.isFailing = false
        let retried = viewModel.updateSet(other, reps: 5, weight: 120, completedAt: other.completedAt, context: context)

        #expect(retried.failure == nil)
        #expect(try savedRecordIDs() == [other.id])
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).count == 2)
    }

    @Test func movingARecordToAnotherRepCountUpdatesBothRepCounts() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let movingRecord = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 3, isRecord: true)
        let nextFiveRepSet = try savedSet(exercise, reps: 5, weight: 80, daysAgo: 2, isRecord: false)
        let threeRepRecord = try savedSet(exercise, reps: 3, weight: 100, daysAgo: 1, isRecord: true)

        let result = viewModel.updateSet(
            movingRecord,
            reps: 3,
            weight: 100,
            completedAt: movingRecord.completedAt,
            context: context
        )

        // The five-rep record passes to the next best set; the tie at three reps keeps its record.
        #expect(result.failure == nil)
        #expect(nextFiveRepSet.isPersonalRecord)
        #expect(threeRepRecord.isPersonalRecord)
        #expect(!movingRecord.isPersonalRecord)
        #expect(try savedRecordIDs() == [nextFiveRepSet.id, threeRepRecord.id])
    }

    // MARK: Deleting

    @Test func deletingARecordPromotesTheNextBestSet() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let record = try savedSet(exercise, reps: 5, weight: 110, daysAgo: 2, isRecord: true)
        let runnerUp = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 1, isRecord: false)

        saves.isFailing = true
        try deleteAfterUndoWindow(record)
        #expect(saves.saveAttempts == 1)
        #expect(!record.isDeleted)
        #expect(record.isPersonalRecord)
        #expect(!runnerUp.isPersonalRecord)
        #expect(try context.fetch(FetchDescriptor<LoggedSet>()).count == 2)
        viewModel.refreshExerciseMetrics(for: exercise, context: context)
        #expect(viewModel.exerciseMetrics.personalRecord?.id == record.id)

        saves.isFailing = false
        try deleteAfterUndoWindow(record)
        #expect(runnerUp.isPersonalRecord)
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).map(\.id) == [runnerUp.id])
        #expect(try savedRecordIDs() == [runnerUp.id])
        viewModel.refreshExerciseMetrics(for: exercise, context: context)
        #expect(viewModel.exerciseMetrics.personalRecord?.id == runnerUp.id)
    }

    // MARK: Metrics

    @Test func setCommandsLeaveMetricsToTheScreen() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let metricsLoads = MetricsLoadCounter()
        let model = ProgressViewModel(commandRunner: saves.runner, metricsLoader: metricsLoads.loader)

        let set = try model.logSet(for: exercise, reps: 5, weight: 100, completedAt: .now, context: context).get()
        #expect(model.updateSet(set, reps: 5, weight: 110, completedAt: set.completedAt, context: context).failure == nil)
        saves.isFailing = true
        #expect(model.logSet(for: exercise, reps: 5, weight: 120, completedAt: .now, context: context).failure != nil)
        #expect(model.updateSet(set, reps: 6, weight: 110, completedAt: set.completedAt, context: context).failure != nil)
        try deleteAfterUndoWindow(set)
        saves.isFailing = false
        try deleteAfterUndoWindow(set)
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).isEmpty)
        #expect(metricsLoads.count == 0)
        #expect(model.exerciseMetrics.latestSet == nil)

        model.refreshExerciseMetrics(for: exercise, context: context)
        #expect(metricsLoads.count == 1)
    }

    @Test func detailScreenRefreshesOnlyWhileShowing() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let other = try Fixtures.savedExercise(in: context, name: "Squat")
        let metricsLoads = MetricsLoadCounter()
        let screen = ProgressViewModel(commandRunner: saves.runner, metricsLoader: metricsLoads.loader)
        var committed: [Notification] = []
        let subscription = NotificationCenter.default.publisher(for: LoggedSetChange.didCommit)
            .sink { committed.append($0) }
        defer { subscription.cancel() }
        /// Hands saved changes to the screen, as its `onReceive` does.
        func deliverChanges() {
            for notification in committed {
                screen.handleCommittedChange(notification, exercise: exercise, context: context)
            }
            committed.removeAll()
        }

        screen.exerciseDetailAppeared(exercise, context: context)
        #expect(metricsLoads.count == 1)

        // Quick Log: the screen refreshes as soon as the set saves, so reopening it prefills this set.
        let logged = try screen.logSet(for: exercise, reps: 5, weight: 100, completedAt: .now, context: context).get()
        deliverChanges()
        #expect(metricsLoads.count == 2)
        #expect(screen.exerciseMetrics.latestSet?.id == logged.id)

        _ = try ProgressViewModel().logSet(for: other, reps: 5, weight: 200, completedAt: .now, context: context).get()
        deliverChanges()
        #expect(metricsLoads.count == 2)

        // While History covers the screen, its edits and foreground returns wait.
        screen.exerciseDetailDisappeared()
        #expect(ProgressViewModel().updateSet(
            logged, reps: 5, weight: 120, completedAt: logged.completedAt, context: context
        ).failure == nil)
        deliverChanges()
        screen.refreshVisibleExerciseMetrics(for: exercise, context: context)
        #expect(metricsLoads.count == 2)

        // Returning from History refreshes once, with the edit in the chart and totals.
        screen.exerciseDetailAppeared(exercise, context: context)
        #expect(metricsLoads.count == 3)
        #expect(screen.exerciseMetrics.personalRecord?.weight == 120)
        #expect(screen.exerciseMetrics.totalVolume == 600)
        #expect(screen.exerciseMetrics.chartPoints.map(\.weight) == [120])

        screen.refreshVisibleExerciseMetrics(for: exercise, context: context) // Back in the foreground.
        #expect(metricsLoads.count == 4)
    }

    // MARK: Weight precision

    @Test func repsOnlyAndDateOnlyEditsKeepTheExactStoredWeight() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let set = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 3, isRecord: true)
        let kilograms = WeightInput(unit: .kg, locale: Locale(identifier: "en_US"))

        let repsOnlyWeight = try #require(
            try WeightDraft(input: kilograms, pounds: set.weight).resolvedPounds(whenBlank: .required).get()
        )
        #expect(viewModel.updateSet(set, reps: 6, weight: repsOnlyWeight, completedAt: set.completedAt, context: context).failure == nil)
        #expect(set.weight == 100)
        #expect(set.reps == 6)

        let dateOnlyWeight = try #require(
            try WeightDraft(input: kilograms, pounds: set.weight).resolvedPounds(whenBlank: .required).get()
        )
        let earlierDate = set.completedAt.addingTimeInterval(-86_400)
        #expect(viewModel.updateSet(set, reps: 6, weight: dateOnlyWeight, completedAt: earlierDate, context: context).failure == nil)
        #expect(set.weight == 100)
        #expect(set.completedAt == earlierDate)
        #expect(try TestStore.savedModels(LoggedSet.self, in: container).first?.weight == 100)
    }

    @Test func quickLogPrefillKeepsTheExactPreviousWeight() throws {
        let exercise = try Fixtures.savedExercise(in: context)
        let previous = try savedSet(exercise, reps: 5, weight: 100, daysAgo: 1, isRecord: true)
        let draft = WeightDraft(input: WeightInput(unit: .kg, locale: Locale(identifier: "de_DE")), pounds: previous.weight)
        let weight = try #require(try draft.resolvedPounds(whenBlank: .required).get())

        let logged = try viewModel.logSet(for: exercise, reps: 5, weight: weight, completedAt: .now, context: context).get()

        #expect(logged.weight == 100)
        #expect(previous.isPersonalRecord)
        #expect(!logged.isPersonalRecord)
    }

    // MARK: Helpers

    /// Deletes the way the app does: a batch request whose Undo window runs out.
    private func deleteAfterUndoWindow(_ set: LoggedSet) throws {
        let batch = DeletionCoordinator(
            context: context,
            alertCenter: PersistenceAlertCenter(),
            commandRunner: saves.runner,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        batch.request(set)
        batch.expire(generation: try #require(batch.generation))
    }

    private func savedSet(
        _ exercise: Exercise,
        reps: Int,
        weight: Double,
        daysAgo: Int,
        isRecord: Bool
    ) throws -> LoggedSet {
        try Fixtures.savedSet(
            for: exercise,
            reps: reps,
            weight: weight,
            daysAgo: daysAgo,
            isPersonalRecord: isRecord,
            in: context
        )
    }

    /// IDs of saved sets flagged as personal records, read through a fresh context.
    private func savedRecordIDs() throws -> Set<UUID> {
        Set(try TestStore.savedModels(LoggedSet.self, in: container).filter(\.isPersonalRecord).map(\.id))
    }
}
