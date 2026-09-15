import Foundation
import SwiftData
import Testing
@testable import Rack

extension Result where Failure == PersistenceCommandError {
    var failure: PersistenceCommandError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }

    /// Whether saving failed and the command's changes were rolled back.
    var isRolledBackSaveFailure: Bool {
        guard case .failure(.failed(_)) = self else { return false }
        return true
    }
}

@MainActor
struct PersistenceCommandRunnerTests {
    @Test func savesSuccessfulCommands() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let saves = SaveSwitch()

        let result = saves.runner.perform(in: context) { context in
            let program = Program(name: "Strength")
            context.insert(program)
            return program
        }

        #expect(try result.get().name == "Strength")
        #expect(!context.hasChanges)
        #expect(saves.saveAttempts == 1)
        #expect(try TestStore.savedModels(Program.self, in: container).map(\.name) == ["Strength"])
    }

    @Test func rollsBackAFailedInsert() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let saves = SaveSwitch(isFailing: true)

        let result = saves.runner.perform(in: context) { context in
            context.insert(Program(name: "Strength"))
        }

        #expect(result.isRolledBackSaveFailure)
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<Program>()).isEmpty)
        #expect(try TestStore.savedModels(Program.self, in: container).isEmpty)
    }

    @Test func rollsBackAFailedEdit() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let program = try Fixtures.savedProgram(in: context, name: "Strength")
        let saves = SaveSwitch(isFailing: true)

        let result = saves.runner.perform(in: context) { _ in
            program.name = "Hypertrophy"
        }

        #expect(result.isRolledBackSaveFailure)
        #expect(program.name == "Strength")
        #expect(!context.hasChanges)
    }

    @Test func rollsBackAFailedDeleteIncludingCascades() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let program = try Fixtures.savedProgram(in: context, workoutNames: ["Push", "Pull"])
        let saves = SaveSwitch(isFailing: true)

        let result = saves.runner.perform(in: context) { context in
            context.delete(program)
        }

        #expect(result.isRolledBackSaveFailure)
        #expect(!program.isDeleted)
        #expect(program.workoutsList.count == 2)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count == 2)
        #expect(try TestStore.savedModels(Program.self, in: container).count == 1)
    }

    @Test func rollsBackWhenTheCommandThrows() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        let saves = SaveSwitch()

        let result: Result<Void, PersistenceCommandError> = saves.runner.perform(in: context) { context in
            context.insert(Program(name: "Strength"))
            throw PersistenceCommandError.unavailable
        }

        #expect(result.failure == .unavailable)
        #expect(saves.saveAttempts == 0)
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<Program>()).isEmpty)
    }

    @Test func refusesADirtyContextWithoutDiscardingItsChanges() throws {
        let container = try TestStore.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(Program(name: "Unsaved"))
        let saves = SaveSwitch()
        var didRunCommand = false

        let result = saves.runner.perform(in: context) { _ in
            didRunCommand = true
        }

        #expect(result.failure == .pendingChanges)
        #expect(!didRunCommand)
        #expect(saves.saveAttempts == 0)
        #expect(context.hasChanges)
        #expect(context.insertedModelsArray.count == 1)

        try context.save()
        #expect(try TestStore.savedModels(Program.self, in: container).map(\.name) == ["Unsaved"])
    }

    @Test func skipsSavingWhenNothingChanged() throws {
        let container = try TestStore.makeInMemoryContainer()
        let saves = SaveSwitch(isFailing: true)

        let result = saves.runner.perform(in: container.mainContext) { _ in }

        #expect(result.failure == nil)
        #expect(saves.saveAttempts == 0)
    }

    @Test func savedChangesSurviveReopeningAnOnDiskStore() throws {
        let directory = try TestStore.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Liftly.store")

        do {
            let container = try TestStore.makeOnDiskContainer(at: storeURL)
            let context = container.mainContext
            let runner = PersistenceCommandRunner()

            _ = try ProgramsViewModel(commandRunner: runner)
                .createProgram(name: "Strength", description: "", context: context)
                .get()
            let exercise = try CreateExerciseViewModel(commandRunner: runner)
                .createExercise(name: "Squat", muscleGroup: .quads, equipment: .barbell, context: context)
                .get()
            _ = try ProgressViewModel(commandRunner: runner)
                .logSet(for: exercise, reps: 5, weight: 225, completedAt: .now, context: context)
                .get()
        }

        let reopened = try TestStore.makeOnDiskContainer(at: storeURL)
        let context = reopened.mainContext
        #expect(try context.fetch(FetchDescriptor<Program>()).map(\.name) == ["Strength"])
        let sets = try context.fetch(FetchDescriptor<LoggedSet>())
        #expect(sets.count == 1)
        #expect(sets.first?.weight == 225)
        #expect(sets.first?.isPersonalRecord == true)
        #expect(sets.first?.exercise?.name == "Squat")
    }
}
