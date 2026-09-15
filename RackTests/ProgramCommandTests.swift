import Foundation
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
        let viewModel = ProgramsViewModel(commandRunner: saves.runner)

        #expect(viewModel.deleteProgram(program, context: context).isRolledBackSaveFailure)
        #expect(!program.isDeleted)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 2)

        saves.isFailing = false
        #expect(viewModel.deleteProgram(program, context: context).failure == nil)
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
        #expect(try TestStore.savedModels(WorkoutTemplate.self, in: container).count == 2)
    }

    @Test func failedWorkoutDeletionKeepsTheDayInItsProgram() throws {
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push", "Pull"])
        let workout = try #require(program.sortedWorkouts.first)
        let viewModel = ProgramDetailViewModel(commandRunner: saves.runner)

        #expect(viewModel.deleteWorkout(workout, context: context).isRolledBackSaveFailure)
        #expect(!workout.isDeleted)
        #expect(workout.program?.id == program.id)
        #expect(program.workoutsList.count == 2)

        saves.isFailing = false
        #expect(viewModel.deleteWorkout(workout, context: context).failure == nil)
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

    @Test func failedPlannedExerciseDeletionKeepsItInTheWorkout() throws {
        let workout = try savedWorkout()
        let planned = try savedPlannedExercise(in: workout, name: "Bench Press", orderIndex: 0)
        let viewModel = WorkoutTemplateDetailViewModel(commandRunner: saves.runner)

        #expect(viewModel.deletePlannedExercise(planned, context: context).isRolledBackSaveFailure)
        #expect(!planned.isDeleted)
        #expect(planned.workoutTemplate?.id == workout.id)

        saves.isFailing = false
        #expect(viewModel.deletePlannedExercise(planned, context: context).failure == nil)
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
