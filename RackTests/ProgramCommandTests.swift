import Foundation
import ActivityKit
import SwiftData
import Testing
@testable import Rack

@MainActor
struct ProgramCommandTests {
    private let container: ModelContainer
    private let saves = SaveSwitch(isFailing: true)

    private var context: ModelContext {
        container.mainContext
    }

    init() throws {
        container = try TestStore.makeInMemoryContainer()
    }

    // MARK: Programs

    @Test func failedProgramCreationSavesNothingAndRetryCreatesOne() throws {
        let viewModel = ProgramsViewModel(commandRunner: saves.runner)

        #expect(viewModel.createProgram(name: "Strength", description: "", context: context).isRolledBackSaveFailure)
        #expect(try context.fetch(FetchDescriptor<Program>()).isEmpty)

        saves.isFailing = false
        let program = try viewModel.createProgram(name: "  Strength ", description: " Notes ", context: context).get()

        #expect(program.name == "Strength")
        #expect(program.programDescription == "Notes")
        #expect(try TestStore.savedModels(Program.self, in: container).count == 1)
    }

    @Test func blankProgramNamesAreRejectedBeforeWriting() {
        let viewModel = ProgramsViewModel(commandRunner: saves.runner)

        #expect(viewModel.createProgram(name: "   ", description: "", context: context).failure == .invalidInput)
        #expect(saves.saveAttempts == 0)
    }

    @Test func namesAndDescriptionsDropSurroundingNewlines() throws {
        saves.isFailing = false
        let viewModel = ProgramsViewModel(commandRunner: saves.runner)

        // The description field is multi-line, so Return can leave newlines behind.
        let program = try viewModel.createProgram(name: " PPL\n", description: "Heavy days\n\n", context: context).get()
        #expect(program.name == "PPL")
        #expect(program.programDescription == "Heavy days")
        #expect(viewModel.createProgram(name: "\n\n", description: "", context: context).failure == .invalidInput)

        let workout = try ProgramDetailViewModel(commandRunner: saves.runner)
            .addWorkout(named: "Push\n", to: program, context: context).get()
        #expect(workout.name == "Push")
        try WorkoutTemplateDetailViewModel(commandRunner: saves.runner)
            .renameWorkout(workout, to: " Pull\n", context: context).get()
        #expect(workout.name == "Pull")
    }

    @Test func theFirstProgramBecomesActiveAndLaterOnesDoNot() throws {
        saves.isFailing = false
        let viewModel = ProgramsViewModel(commandRunner: saves.runner)

        let first = try viewModel.createProgram(name: "First", description: "", context: context).get()
        let second = try viewModel.createProgram(name: "Second", description: "", context: context).get()

        #expect(first.isActive)
        #expect(!second.isActive)
        #expect(try TestStore.savedModels(Program.self, in: container).filter(\.isActive).map(\.name) == ["First"])
    }

    @Test func programListKeepsEveryActiveProgramVisible() throws {
        let older = try Fixtures.savedProgram(in: context, name: "Older", isActive: true)
        let newer = try Fixtures.savedProgram(in: context, name: "Newer", isActive: true)
        let inactive = try Fixtures.savedProgram(in: context, name: "Inactive")

        // Newest first, like ProgramsView's query. Two devices can each activate one.
        let sections = ProgramListSections(programs: [inactive, newer, older])

        #expect(sections.active?.id == newer.id)
        #expect(sections.others.map(\.name) == ["Inactive", "Older"])
    }

    @Test func programListWithoutAnActiveProgramListsEveryProgram() throws {
        let first = try Fixtures.savedProgram(in: context, name: "First")
        let second = try Fixtures.savedProgram(in: context, name: "Second")

        let sections = ProgramListSections(programs: [second, first])

        #expect(sections.active == nil)
        #expect(sections.others.map(\.name) == ["Second", "First"])
    }

    @Test func failedProgramEditRestoresTheProgram() throws {
        let program = try Fixtures.savedProgram(in: context, name: "Strength")
        let viewModel = ProgramsViewModel(commandRunner: saves.runner)

        let result = viewModel.updateProgram(program, name: "Hypertrophy", description: "New", context: context)

        #expect(result.isRolledBackSaveFailure)
        #expect(program.name == "Strength")
        #expect(program.programDescription.isEmpty)
        #expect(try TestStore.savedModels(Program.self, in: container).map(\.name) == ["Strength"])
    }

    @Test func failedActivationKeepsThePreviousActiveProgram() throws {
        let current = try Fixtures.savedProgram(in: context, name: "Current", isActive: true)
        let next = try Fixtures.savedProgram(in: context, name: "Next")
        let listViewModel = ProgramsViewModel(commandRunner: saves.runner)
        let detailViewModel = ProgramDetailViewModel(commandRunner: saves.runner)

        #expect(listViewModel.setActive(next, context: context).isRolledBackSaveFailure)
        #expect(detailViewModel.setActive(next, context: context).isRolledBackSaveFailure)
        #expect(current.isActive)
        #expect(!next.isActive)

        saves.isFailing = false
        #expect(detailViewModel.setActive(next, context: context).failure == nil)
        #expect(!current.isActive)
        #expect(next.isActive)
        #expect(try TestStore.savedModels(Program.self, in: container).filter(\.isActive).map(\.name) == ["Next"])
    }

    @Test func failedProgramDeletionKeepsTheProgramAndItsWorkouts() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push", "Pull"])

        try deleteAfterUndoWindow { $0.request(program) }
        #expect(saves.saveAttempts == 1)
        #expect(!program.isDeleted)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 2)

        saves.isFailing = false
        try deleteAfterUndoWindow { $0.request(program) }
        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).isEmpty)
    }

    // MARK: Workout days

    @Test func failedWorkoutReorderRestoresThePersistedOrder() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push", "Pull", "Legs"])
        let viewModel = ProgramDetailViewModel(commandRunner: saves.runner)
        let reversedIDs = program.sortedWorkouts.reversed().map(\.id)

        #expect(viewModel.reorderWorkouts(in: program, orderedIDs: reversedIDs, context: context).isRolledBackSaveFailure)
        #expect(program.sortedWorkouts.map(\.name) == ["Push", "Pull", "Legs"])

        saves.isFailing = false
        #expect(viewModel.reorderWorkouts(in: program, orderedIDs: reversedIDs, context: context).failure == nil)
        #expect(program.sortedWorkouts.map(\.name) == ["Legs", "Pull", "Push"])
        #expect(
            try TestStore.savedModels(WorkoutTemplate.self, in: container)
                .sorted { $0.orderIndex < $1.orderIndex }
                .map(\.name) == ["Legs", "Pull", "Push"]
        )
    }

    @Test func failedWorkoutAdditionAddsNothing() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push"])
        let viewModel = ProgramDetailViewModel(commandRunner: saves.runner)

        #expect(viewModel.addWorkout(named: "Pull", to: program, context: context).isRolledBackSaveFailure)
        #expect(program.workoutsList.map(\.name) == ["Push"])
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 1)

        saves.isFailing = false
        let workout = try viewModel.addWorkout(named: "Pull", to: program, context: context).get()

        #expect(workout.orderIndex == 1)
        #expect(workout.modelContext === context)
        #expect(program.workoutsList.map(\.name).sorted() == ["Pull", "Push"])
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).count == 2)
    }

    @Test func failedWorkoutDeletionKeepsTheDayInItsProgram() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push", "Pull"])
        let workout = try #require(program.sortedWorkouts.first)

        try deleteAfterUndoWindow { $0.request(workout) }
        #expect(saves.saveAttempts == 1)
        #expect(!workout.isDeleted)
        #expect(workout.program?.id == program.id)
        #expect(program.workoutsList.count == 2)

        saves.isFailing = false
        try deleteAfterUndoWindow { $0.request(workout) }
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).map(\.name) == ["Pull"])
    }

    // MARK: Planned exercises

    @Test func failedExerciseAdditionAddsNothing() throws {
        let workout = try savedWorkout()
        let exercise = try Fixtures.savedExercise(in: context)
        let viewModel = WorkoutTemplateDetailViewModel(commandRunner: saves.runner)

        #expect(viewModel.addExercise(exercise, to: workout, repTargetType: .range, context: context).isRolledBackSaveFailure)
        #expect(workout.plannedExercisesList.isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlannedExercise>()).isEmpty)

        saves.isFailing = false
        let planned = try viewModel.addExercise(exercise, to: workout, repTargetType: .range, context: context).get()

        #expect(planned.repTargetType == .range)
        #expect(planned.modelContext === context)
        #expect(workout.plannedExercisesList.map(\.id) == [planned.id])
        #expect(exercise.plannedExercisesList.map(\.id) == [planned.id])
        #expect(try TestStore.savedModels(PlannedExercise.self, in: container).count == 1)
    }

    @Test func failedExerciseReorderAndRenameRestoreTheWorkout() throws {
        let workout = try savedWorkout(name: "Push")
        let first = try savedPlannedExercise(in: workout, name: "Bench Press", orderIndex: 0)
        let second = try savedPlannedExercise(in: workout, name: "Overhead Press", orderIndex: 1)
        let viewModel = WorkoutTemplateDetailViewModel(commandRunner: saves.runner)

        let reorder = viewModel.reorderExercises(in: workout, orderedIDs: [second.id, first.id], context: context)
        #expect(reorder.isRolledBackSaveFailure)
        #expect(workout.sortedExercises.map(\.id) == [first.id, second.id])

        #expect(viewModel.renameWorkout(workout, to: "Upper", context: context).isRolledBackSaveFailure)
        #expect(workout.name == "Push")
    }

    @Test func failedPlannedExerciseEditRestoresTheTarget() throws {
        let workout = try savedWorkout()
        let planned = try savedPlannedExercise(in: workout, name: "Bench Press", orderIndex: 0, targetWeight: 135)
        let viewModel = WorkoutTemplateDetailViewModel(commandRunner: saves.runner)

        let result = viewModel.updatePlannedExercise(
            planned,
            sets: 5,
            repTargetType: .range,
            exactReps: 5,
            rangeLowerBound: 6,
            rangeUpperBound: 10,
            targetWeight: nil,
            context: context
        )

        #expect(result.isRolledBackSaveFailure)
        #expect(planned.sets == 3)
        #expect(planned.repTargetType == .exact)
        #expect(planned.targetWeight == 135)
    }

    @Test func untouchedTargetWeightKeepsTheExactStoredValue() throws {
        let workout = try savedWorkout()
        let planned = try savedPlannedExercise(in: workout, name: "Bench Press", orderIndex: 0, targetWeight: 100)
        let viewModel = WorkoutTemplateDetailViewModel(commandRunner: saves.runner)
        saves.isFailing = false
        let kilograms = WeightInput(unit: .kg, locale: Locale(identifier: "en_US"))
        let targetWeight = try WeightDraft(input: kilograms, pounds: planned.targetWeight)
            .resolvedPounds(whenBlank: .noWeight)
            .get()

        let result = viewModel.updatePlannedExercise(
            planned,
            sets: 4,
            repTargetType: planned.repTargetType,
            exactReps: planned.exactRepTarget,
            rangeLowerBound: planned.repRange.lowerBound,
            rangeUpperBound: planned.repRange.upperBound,
            targetWeight: targetWeight,
            context: context
        )

        #expect(result.failure == nil)
        #expect(planned.sets == 4)
        #expect(planned.targetWeight == 100)
        #expect(try TestStore.savedModels(PlannedExercise.self, in: container).first?.targetWeight == 100)
    }

    @Test func savingAnUntouchedPlannedExerciseWritesNothing() throws {
        saves.isFailing = false
        let workout = try savedWorkout()
        let planned = try savedPlannedExercise(in: workout, name: "Bench Press", orderIndex: 0, targetWeight: 100)
        let viewModel = WorkoutTemplateDetailViewModel(commandRunner: saves.runner)

        // What the Edit Exercise sheet submits when nothing was changed.
        let result = viewModel.updatePlannedExercise(
            planned,
            sets: planned.sets,
            repTargetType: planned.repTargetType,
            exactReps: planned.exactRepTarget,
            rangeLowerBound: planned.repRange.lowerBound,
            rangeUpperBound: planned.repRange.upperBound,
            targetWeight: planned.targetWeight,
            context: context
        )

        #expect(result.failure == nil)
        #expect(saves.saveAttempts == 0)
        #expect(!context.hasChanges)
    }

    @Test func failedPlannedExerciseDeletionKeepsItInTheWorkout() throws {
        let workout = try savedWorkout()
        let planned = try savedPlannedExercise(in: workout, name: "Bench Press", orderIndex: 0)

        try deleteAfterUndoWindow { $0.request(planned) }
        #expect(saves.saveAttempts == 1)
        #expect(!planned.isDeleted)
        #expect(planned.workoutTemplate?.id == workout.id)

        saves.isFailing = false
        try deleteAfterUndoWindow { $0.request(planned) }
        #expect(try TestStore.savedModels(PlannedExercise.self, in: container).isEmpty)
    }

    // MARK: Exercises

    @Test func failedExerciseCreationSavesNothing() throws {
        let viewModel = CreateExerciseViewModel(commandRunner: saves.runner)

        let failed = viewModel.createExercise(name: "Zercher Squat", muscleGroup: .quads, equipment: .barbell, context: context)
        #expect(failed.isRolledBackSaveFailure)
        #expect(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)

        saves.isFailing = false
        let exercise = try viewModel.createExercise(
            name: " Zercher Squat ",
            muscleGroup: .quads,
            equipment: .barbell,
            context: context
        ).get()

        #expect(exercise.name == "Zercher Squat")
        #expect(try TestStore.savedModels(Exercise.self, in: container).count == 1)
    }

    // MARK: Helpers

    /// Deletes the way the app does: a batch request whose Undo window runs out.
    private func deleteAfterUndoWindow(_ request: (DeletionCoordinator) -> Void) throws {
        let batch = DeletionCoordinator(
            context: context,
            alertCenter: PersistenceAlertCenter(),
            commandRunner: saves.runner,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        request(batch)
        batch.expire(generation: try #require(batch.generation))
    }

    private func savedWorkout(name: String = "Push") throws -> WorkoutTemplate {
        let program = try Fixtures.savedProgram(in: context, workoutNames: [name])
        return try #require(program.workoutsList.first)
    }

    private func savedPlannedExercise(
        in workout: WorkoutTemplate,
        name: String,
        orderIndex: Int,
        targetWeight: Double? = nil
    ) throws -> PlannedExercise {
        let exercise = try Fixtures.savedExercise(in: context, name: name)
        let planned = PlannedExercise(exercise: exercise, targetWeight: targetWeight, orderIndex: orderIndex)
        planned.workoutTemplate = workout
        context.insert(planned)
        try context.save()
        return planned
    }
}

// MARK: Workout reference Live Activities

@MainActor
private final class TestWorkoutActivityClient: WorkoutActivityClient {
    var isEnabled = true
    var records: [WorkoutActivityRecord] = []
    var startFailure = false
    private(set) var startCount = 0
    private(set) var endCount = 0

    func start(state: WorkoutActivityAttributes.ContentState) throws {
        if startFailure { throw WorkoutActivityError.startFailed }
        startCount += 1
        records.append(.init(id: UUID().uuidString, state: state))
    }

    func update(id: String, state: WorkoutActivityAttributes.ContentState) async {
        await Task.yield() // Exercise MainActor reentrancy in paging tests.
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index] = .init(id: id, state: state)
        }
    }

    func end(id: String) async {
        await Task.yield()
        records.removeAll { $0.id == id }
        endCount += 1
    }
}

@MainActor
struct WorkoutActivityTests {
    private let container: ModelContainer
    private let store: AppDataStore
    private let client = TestWorkoutActivityClient()
    private let workout: WorkoutTemplate
    private let other: WorkoutTemplate

    init() throws {
        let container = try TestStore.makeInMemoryContainer()
        self.container = container
        store = AppDataStore(openContainer: { _ in container }, prepareContainer: { $0.mainContext.autosaveEnabled = false })
        let context = container.mainContext
        let program = Program(name: "Strength")
        context.insert(program)
        workout = WorkoutTemplate(name: "Push Day")
        workout.program = program
        context.insert(workout)
        other = WorkoutTemplate(name: "Push Day", orderIndex: 1)
        other.program = program
        context.insert(other)
        for day in [workout, other] {
            for index in 0..<5 {
                let exercise = Exercise(name: "Exercise \(index)", muscleGroup: .chest, equipment: .barbell)
                context.insert(exercise)
                let planned = PlannedExercise(
                    exercise: exercise, sets: index + 1, reps: 8,
                    repTargetType: index == 1 ? .range : index == 4 ? .failure : .exact,
                    targetWeight: index == 4 ? nil : 45.125, orderIndex: index
                )
                planned.workoutTemplate = day
                context.insert(planned)
            }
        }
        try context.save()
    }

    private func coordinator() -> WorkoutActivityCoordinator {
        WorkoutActivityCoordinator(store: store, client: client)
    }

    @Test func projectionPreservesOrderingAndContainsNamesOnly() throws {
        let original = workout.sortedExercises.map(\.targetWeight)
        let snapshot = WorkoutActivitySnapshot(workout: workout)
        #expect(snapshot.exercises.map(\.name) == (0..<5).map { "Exercise \($0)" })
        let state = try snapshot.content()
        #expect(state.exercises.count == 5)
        let encoded = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!encoded.contains("spokenTarget"))
        #expect(!encoded.contains("target"))
        #expect(workout.sortedExercises.map(\.targetWeight) == original)
        #expect(!container.mainContext.hasChanges)
    }

    @Test func missingExerciseRelationshipsAreExcludedAndEmptyDayIsRejected() throws {
        for planned in workout.plannedExercisesList { planned.exercise = nil }
        let snapshot = WorkoutActivitySnapshot(workout: workout)
        #expect(throws: WorkoutActivityError.emptyWorkout) { try snapshot.content() }
    }

    @Test func unicodeAndEscapedNamesFitPayloadWithoutEditingModels() throws {
        workout.name = String(repeating: "\u{0001}💪", count: 2_000)
        for planned in workout.plannedExercisesList {
            planned.exercise?.name = String(repeating: "\u{0001}💪", count: 2_000)
        }
        let name = workout.name
        let snapshot = WorkoutActivitySnapshot(workout: workout)
        let state = try snapshot.content()
        let encoder = JSONEncoder()
        #expect(try encoder.encode(state).count + encoder.encode(WorkoutActivityAttributes(referenceID: UUID())).count <= 3_800)
        #expect(workout.name == name)
        #expect(state.workoutName.hasSuffix("…"))
    }

    @Test func pageClampingAnchoringAndRangeLabels() throws {
        let snapshot = WorkoutActivitySnapshot(workout: workout)
        #expect(try snapshot.content(startingIndex: -100).startingIndex == 0)
        let last = try snapshot.content(startingIndex: 100)
        #expect(last.startingIndex == 4)
        #expect(last.rangeLabel(visibleCount: 1) == "5 of 5 exercises")
        let anchor = try snapshot.content(startingIndex: 0, anchorID: snapshot.exercises[3].id)
        #expect(anchor.startingIndex == 3)
        #expect(try snapshot.content().rangeLabel(visibleCount: 2) == "1–2 of 5 exercises")
    }

    @Test func repeatedStartsAndConflictingAutomationDoNotDuplicateOrSwitch() async throws {
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id, automatic: true)
        try await coordinator.page(activityID: coordinator.current!.id, direction: 1, visibleCount: 2)
        try await coordinator.start(workoutID: workout.id, automatic: true)
        #expect(coordinator.current?.state.startingIndex == 2)
        #expect(try await coordinator.start(workoutID: other.id, automatic: true) == .preservedExisting)
        #expect(client.startCount == 1)
        #expect(coordinator.current?.state.workoutID == workout.id)
        #expect(client.records.count == 1)
        await #expect(throws: WorkoutActivityError.missingWorkout) {
            try await coordinator.start(workoutID: UUID(), automatic: true)
        }
    }

    @Test func manualSwitchRequiresConfirmationAndReusesActivity() async throws {
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let activityID = coordinator.current?.id
        await #expect(throws: WorkoutActivityError.needsSwitch) { try await coordinator.start(workoutID: other.id) }
        try await coordinator.start(workoutID: other.id, allowSwitch: true)
        #expect(coordinator.current?.id == activityID)
        #expect(coordinator.current?.state.workoutID == other.id)
        #expect(client.startCount == 1)
    }

    @Test func rapidPagingSerializesAcrossActivityKitAwaits() async throws {
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let id = try #require(coordinator.current?.id)
        async let first: Void = coordinator.page(activityID: id, direction: 1, visibleCount: 2)
        async let second: Void = coordinator.page(activityID: id, direction: 1, visibleCount: 2)
        _ = try await (first, second)
        #expect(coordinator.current?.state.startingIndex == 4)
        #expect(coordinator.operationCount == 0)
    }

    @Test func pagingUsesNewerRenderAndIgnoresOlderQueuedRender() async throws {
        let initial = try WorkoutActivitySnapshot(workout: workout).content()
        client.records = [.init(id: "restored", state: initial)]
        let coordinator = coordinator()
        let snapshot = WorkoutActivitySnapshot(workout: workout)
        let newer = WorkoutActivityPageReference(workoutID: workout.id, startingIndex: 2,
                                                 anchorID: snapshot.exercises[2].id, revision: 1)
        try await coordinator.page(activityID: "restored", direction: 1, visibleCount: 2, displayedPage: newer)
        #expect(coordinator.current?.state.startingIndex == 4)
        #expect(coordinator.current?.state.revision == 2)
        try await coordinator.page(activityID: "restored", direction: -1, visibleCount: 2, displayedPage: newer)
        #expect(coordinator.current?.state.startingIndex == 2)
        #expect(coordinator.current?.state.revision == 3)
    }

    @Test func oldActivityPayloadDecodesTargetsAndDefaultsWindowAndVersion() throws {
        let snapshot = WorkoutActivitySnapshot(workout: workout)
        let state = try snapshot.content(startingIndex: 2)
        let legacy: [String: Any] = [
            "workoutID": workout.id.uuidString, "workoutName": workout.name,
            "totalExercises": 5, "startingIndex": 2,
            "exercises": snapshot.exercises.dropFirst(2).prefix(2).map {
                ["id": $0.id.uuidString, "name": $0.name, "target": "3 × 8 reps", "spokenTarget": "3 sets, 8 reps"]
            }
        ]
        let decoded = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self,
                                               from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.revision == 0)
        #expect(decoded.windowStartingIndex == 2)
        #expect(decoded.exercises == Array(state.exercises.dropFirst(2).prefix(2)))
        let layout = WorkoutActivityLayout(state: decoded, rowHeight: 18, columns: 2)
        #expect(layout.showsPaging)
        #expect(layout.startingIndex == 2)
        #expect(layout.navigationStep == 2)
        #expect(layout.exercises.count == 2)
    }

    private func addExercises(until count: Int) throws {
        let context = container.mainContext
        for index in workout.sortedExercises.count..<count {
            let exercise = Exercise(name: "Exercise \(index)", muscleGroup: .chest, equipment: .barbell)
            context.insert(exercise)
            let planned = PlannedExercise(exercise: exercise, orderIndex: index)
            planned.workoutTemplate = workout
            context.insert(planned)
        }
        try context.save()
    }

    @Test(arguments: [1, 9, 10]) func wholeDayFitsWithoutPaging(count: Int) throws {
        if count < 5 {
            for exercise in workout.sortedExercises.dropFirst(count) { container.mainContext.delete(exercise) }
            try container.mainContext.save()
        } else { try addExercises(until: count) }
        let state = try WorkoutActivitySnapshot(workout: workout).content(startingIndex: count - 1)
        #expect(state.windowStartingIndex == 0)
        #expect(state.exercises.count == count)
        let layout = WorkoutActivityLayout(state: state, rowHeight: 18, columns: 2)
        #expect(!layout.showsPaging)
        #expect(layout.startingIndex == 0)
        #expect(layout.exercises.count == count)
        #expect(layout.rowCount == (count + 1) / 2)
        #expect(Double(layout.rowCount) * 18 + Double(max(0, layout.rowCount - 1)) * 4 + 42 <= 160)
    }

    @Test func elevenExercisesPageBySixAndPreserveFinalPageBoundaries() async throws {
        try addExercises(until: 11)
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let id = try #require(coordinator.current?.id)
        let initial = try #require(coordinator.current?.state)
        #expect(initial.exercises.count == 10)
        let first = WorkoutActivityLayout(state: initial, rowHeight: 18, columns: 2)
        #expect(first.showsPaging && first.capacity == 6)
        #expect(first.exercises.map(\.name) == (0..<6).map { "Exercise \($0)" })
        try await coordinator.page(activityID: id, direction: -1, visibleCount: first.navigationStep)
        #expect(coordinator.current?.state == initial)
        try await coordinator.page(activityID: id, direction: 1, visibleCount: first.navigationStep)
        let final = try #require(coordinator.current?.state)
        #expect(final.startingIndex == 6 && final.windowStartingIndex == 6)
        let last = WorkoutActivityLayout(state: final, rowHeight: 18, columns: 2)
        #expect(last.exercises.map(\.name) == (6..<11).map { "Exercise \($0)" })
        #expect(last.navigationStep == 6)
        try await coordinator.page(activityID: id, direction: 1, visibleCount: last.navigationStep)
        #expect(coordinator.current?.state == final)
        try await coordinator.page(activityID: id, direction: -1, visibleCount: last.navigationStep)
        #expect(coordinator.current?.state.startingIndex == 0)
    }

    @Test func textSizeChangesRestoreWholeDayAndKeepEveryNameReachable() async throws {
        try addExercises(until: 10)
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let id = try #require(coordinator.current?.id)
        var reached = Set<UUID>()
        while let state = coordinator.current?.state {
            let large = WorkoutActivityLayout(state: state, rowHeight: 30, columns: 1)
            #expect(large.showsPaging && large.capacity == 2)
            reached.formUnion(large.exercises.map(\.id))
            let normal = WorkoutActivityLayout(state: state, rowHeight: 18, columns: 2)
            #expect(!normal.showsPaging && normal.exercises.count == 10)
            #expect(normal.startingIndex == 0)
            if large.startingIndex + large.exercises.count >= state.totalExercises { break }
            try await coordinator.page(activityID: id, direction: 1, visibleCount: large.navigationStep)
        }
        #expect(reached.count == 10)
        let largest = WorkoutActivityLayout(state: try #require(coordinator.current?.state), rowHeight: 56, columns: 1)
        #expect(largest.capacity == 1)
    }

    @Test func overviewPayloadContainsTenBoundedNamesAndNoTargets() throws {
        try addExercises(until: 10)
        workout.name = String(repeating: "\u{0001}💪", count: 2_000)
        for planned in workout.sortedExercises { planned.exercise?.name = String(repeating: "\u{0001}💪", count: 2_000) }
        let original = workout.sortedExercises.map { $0.exercise?.name }
        let state = try WorkoutActivitySnapshot(workout: workout).content()
        #expect(state.exercises.count == 10)
        let encoder = JSONEncoder()
        #expect(try encoder.encode(state).count + encoder.encode(WorkoutActivityAttributes(referenceID: UUID())).count <= 3_800)
        #expect(workout.sortedExercises.map { $0.exercise?.name } == original)
    }

    @Test func largerOverflowWindowsAndRapidTapsKeepSavedOrder() async throws {
        try addExercises(until: 22)
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let id = try #require(coordinator.current?.id)
        async let first: Void = coordinator.page(activityID: id, direction: 1, visibleCount: 6)
        async let second: Void = coordinator.page(activityID: id, direction: 1, visibleCount: 6)
        _ = try await (first, second)
        let state = try #require(coordinator.current?.state)
        #expect(state.startingIndex == 12 && state.windowStartingIndex == 12)
        #expect(state.exercises.map(\.name) == (12..<22).map { "Exercise \($0)" })
        #expect(state.pageAnchorID == workout.sortedExercises[12].id)
    }

    @Test func largerTextPagingReachesEveryExerciseAndStaleActivityIDsDoNothing() async throws {
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let id = try #require(coordinator.current?.id)
        for index in 1..<5 {
            try await coordinator.page(activityID: id, direction: 1, visibleCount: 1)
            #expect(coordinator.current?.state.startingIndex == index)
        }
        try await coordinator.page(activityID: "dismissed-activity", direction: -1, visibleCount: 1)
        #expect(coordinator.current?.state.startingIndex == 4)
        try await coordinator.page(activityID: id, direction: -1, visibleCount: 1)
        #expect(coordinator.current?.state.startingIndex == 3)
    }

    @Test func savedEditsAndReorderRefreshWhileDraftsDoNot() async throws {
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let id = try #require(coordinator.current?.id)
        try await coordinator.page(activityID: id, direction: 1, visibleCount: 2)
        let anchor = try #require(coordinator.current?.state.pageAnchorID)
        workout.name = "Draft"
        await coordinator.refresh()
        #expect(coordinator.current?.state.workoutName == "Push Day")
        try container.mainContext.save()
        let ordered = workout.sortedExercises
        for (index, planned) in ordered.reversed().enumerated() { planned.orderIndex = index }
        try container.mainContext.save()
        await coordinator.refresh()
        #expect(coordinator.current?.state.workoutName == "Draft")
        #expect(coordinator.current?.state.pageAnchorID == anchor)
    }

    @Test func targetOnlyEditsDoNotChangeNamesOrRewriteWeights() async throws {
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        let before = coordinator.current?.state
        let planned = try #require(workout.sortedExercises.first)
        planned.reps = 15
        planned.targetWeight = 123.456789
        try container.mainContext.save()
        await coordinator.refresh()
        #expect(coordinator.current?.state == before)
        #expect(planned.targetWeight == 123.456789)
        #expect(!container.mainContext.hasChanges)
    }

    @Test func pendingDeletionKeepsSavedReferenceAndUndoRestoresStartEligibility() async throws {
        let coordinator = coordinator()
        let deletions = DeletionCoordinator(context: container.mainContext, alertCenter: PersistenceAlertCenter())
        coordinator.deletionCoordinator = deletions
        try await coordinator.start(workoutID: workout.id)
        deletions.request(workout)
        await coordinator.refresh()
        #expect(coordinator.current?.state.workoutID == workout.id)
        await #expect(throws: WorkoutActivityError.pendingDeletion) { try await coordinator.start(workoutID: workout.id) }
        deletions.undo()
        try await coordinator.start(workoutID: workout.id)
        #expect(client.records.count == 1)
        deletions.request(workout)
        deletions.commitPendingNow()
        await coordinator.refresh()
        #expect(coordinator.current == nil)
    }

    @Test func emptyOrDeletedWorkoutEndsReference() async throws {
        let coordinator = coordinator()
        try await coordinator.start(workoutID: workout.id)
        for planned in workout.plannedExercisesList { container.mainContext.delete(planned) }
        try container.mainContext.save()
        await coordinator.refresh()
        #expect(coordinator.current == nil)
        container.mainContext.delete(workout)
        try container.mainContext.save()
        await #expect(throws: WorkoutActivityError.missingWorkout) { try await coordinator.start(workoutID: workout.id) }
    }

    @Test func failuresRetainLastPageAndSuccessfulRefreshClearsStatus() async throws {
        var failLoad = false
        let repository = WorkoutActivityRepository(store: store)
        let coordinator = WorkoutActivityCoordinator(store: store, client: client, loadSnapshot: { id, deletions in
            if failLoad { throw WorkoutActivityError.storeUnavailable }
            return try await repository.snapshot(id: id, hiding: deletions)
        })
        try await coordinator.start(workoutID: workout.id)
        let rows = coordinator.current?.state.exercises
        failLoad = true
        await coordinator.refresh()
        #expect(coordinator.current?.state.needsRefresh == true)
        #expect(coordinator.current?.state.exercises == rows)
        failLoad = false
        await coordinator.refresh()
        #expect(coordinator.current?.state.needsRefresh == false)
    }

    @Test func authorizationAndStartFailureLeaveWorkoutDataUntouched() async throws {
        let coordinator = coordinator()
        client.isEnabled = false
        await #expect(throws: WorkoutActivityError.disabled) { try await coordinator.start(workoutID: workout.id) }
        client.isEnabled = true
        client.startFailure = true
        await #expect(throws: WorkoutActivityError.startFailed) { try await coordinator.start(workoutID: workout.id) }
        #expect(client.records.isEmpty)
        #expect(!container.mainContext.hasChanges)
        #expect(workout.sessionsListForTests.isEmpty)
    }

    @Test func storeFailureIsReportedWithoutStartingActivity() async throws {
        let failedStore = AppDataStore(openContainer: { _ in throw InjectedSaveFailure() }, prepareContainer: { _ in })
        let coordinator = WorkoutActivityCoordinator(store: failedStore, client: client)
        await #expect(throws: WorkoutActivityError.storeUnavailable) { try await coordinator.start(workoutID: workout.id) }
        #expect(client.startCount == 0)
        #expect(failedStore.phase.isFailed)
    }

    @Test func restorationDeduplicatesAndDismissalDoesNotRestart() async throws {
        let state = try WorkoutActivitySnapshot(workout: workout).content()
        client.records = [.init(id: "first", state: state), .init(id: "second", state: state)]
        let coordinator = coordinator()
        await coordinator.refresh()
        #expect(client.records.count == 1)
        #expect(client.startCount == 0)
        client.records = [] // The system or user dismissed it.
        await coordinator.refresh()
        #expect(coordinator.current == nil)
        #expect(client.startCount == 0)
        await coordinator.stop()
        await coordinator.stop()
    }

    @Test func shortcutDayReferencesDisambiguateDuplicateNamesAndRemoveDeletedDays() async throws {
        let repository = WorkoutActivityRepository(store: store)
        let before = try await repository.days()
        #expect(before.count == 2)
        #expect(Set(before.map(\.id)).count == 2)
        #expect(before.allSatisfy { $0.programName == "Strength" })
        let entity = WorkoutDayEntity(reference: before[0])
        #expect(entity.id == before[0].id)
        #expect(entity.programName == "Strength")
        container.mainContext.delete(other)
        try container.mainContext.save()
        #expect(try await repository.days().count == 1)
    }

    @Test func deepLinksAcceptOnlyValidWorkoutURLs() {
        let id = UUID()
        #expect(WorkoutActivityLink.workoutID(from: URL(string: "liftly://workout/\(id.uuidString)")!) == id)
        for url in ["https://workout/\(id)", "liftly://other/\(id)", "liftly://workout/no-id", "liftly://workout/\(id)/extra", "liftly://workout/\(id)?action=delete"] {
            #expect(WorkoutActivityLink.workoutID(from: URL(string: url)!) == nil)
        }
    }
}

private extension WorkoutTemplate {
    var sessionsListForTests: [WorkoutSession] { sessions ?? [] }
}
