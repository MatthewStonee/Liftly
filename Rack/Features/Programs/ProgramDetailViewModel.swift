import Foundation
import SwiftData

@Observable
final class ProgramDetailViewModel {
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner

    init(commandRunner: PersistenceCommandRunner = PersistenceCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func reorderWorkouts(
        in program: Program,
        orderedIDs: [UUID],
        context: ModelContext
    ) -> Result<Void, PersistenceCommandError> {
        guard !program.isDeleted else { return .failure(.unavailable) }
        guard SiblingOrder.isCompleteOrder(orderedIDs, of: program.workoutsList.map(\.id)) else {
            return .failure(.invalidInput)
        }
        let orderLookup = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in
            (id, index)
        })

        return commandRunner.perform(in: context) { _ in
            for workout in program.workoutsList {
                guard let index = orderLookup[workout.id] else { continue }
                if workout.orderIndex != index {
                    workout.orderIndex = index
                }
            }
        }
    }

    func addWorkout(
        named name: String,
        to program: Program,
        context: ModelContext
    ) -> Result<WorkoutTemplate, PersistenceCommandError> {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return .failure(.invalidInput) }
        guard !program.isDeleted else { return .failure(.unavailable) }

        return commandRunner.performInsert(in: context) { context in
            context.reloadRelationships(of: program, [\.workouts])
        } _: { insertionContext in
            guard let insertionProgram = try insertionContext.existingModel(program) else {
                throw PersistenceCommandError.unavailable
            }
            SiblingOrder.normalize(insertionProgram.workoutsList)
            let workout = WorkoutTemplate(name: trimmedName, orderIndex: insertionProgram.workoutsList.count)
            workout.program = insertionProgram
            insertionContext.insert(workout)
            return workout
        }
    }

    func setActive(_ program: Program, context: ModelContext) -> Result<Void, PersistenceCommandError> {
        guard !program.isDeleted else { return .failure(.unavailable) }

        return commandRunner.perform(in: context) { context in
            try ProgramActivation.activate(program, in: context)
        }
    }
}
