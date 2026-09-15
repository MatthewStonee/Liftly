import Foundation
import SwiftData

@Observable
final class CreateExerciseViewModel {
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner

    init(commandRunner: PersistenceCommandRunner = PersistenceCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func createExercise(
        name: String,
        muscleGroup: MuscleGroup,
        equipment: Equipment,
        context: ModelContext
    ) -> Result<Exercise, PersistenceCommandError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure(.invalidInput) }

        return commandRunner.perform(in: context) { context in
            let exercise = Exercise(name: trimmedName, muscleGroup: muscleGroup, equipment: equipment)
            context.insert(exercise)
            return exercise
        }
    }
}
