import Foundation
import SwiftData

@Observable
final class WorkoutTemplateDetailViewModel {
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner

    init(commandRunner: PersistenceCommandRunner = PersistenceCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func reorderExercises(
        in workout: WorkoutTemplate,
        orderedIDs: [UUID],
        context: ModelContext
    ) -> Result<Void, PersistenceCommandError> {
        guard !workout.isDeleted else { return .failure(.unavailable) }
        guard SiblingOrder.isCompleteOrder(orderedIDs, of: workout.plannedExercisesList.map(\.id)) else {
            return .failure(.invalidInput)
        }
        let orderLookup = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in
            (id, index)
        })

        return commandRunner.perform(in: context) { _ in
            for exercise in workout.plannedExercisesList {
                guard let index = orderLookup[exercise.id] else { continue }
                if exercise.orderIndex != index {
                    exercise.orderIndex = index
                }
            }
        }
    }

    func addExercise(
        _ exercise: Exercise,
        to workout: WorkoutTemplate,
        repTargetType: PlannedRepTargetType,
        context: ModelContext
    ) -> Result<PlannedExercise, PersistenceCommandError> {
        guard !workout.isDeleted, !exercise.isDeleted else { return .failure(.unavailable) }

        return commandRunner.performInsert(in: context) { context in
            context.reloadRelationships(of: workout, [\.plannedExercises])
            context.reloadRelationships(of: exercise, [\.plannedExercises])
        } _: { insertionContext in
            guard let insertionWorkout = try insertionContext.existingModel(workout),
                  let insertionExercise = try insertionContext.existingModel(exercise) else {
                throw PersistenceCommandError.unavailable
            }
            SiblingOrder.normalize(insertionWorkout.plannedExercisesList)
            let planned = PlannedExercise(
                exercise: insertionExercise,
                sets: 3,
                reps: PlannedRepTargetDefaults.exactReps,
                repTargetType: repTargetType,
                repRangeLowerBound: PlannedRepTargetDefaults.rangeLowerBound,
                repRangeUpperBound: PlannedRepTargetDefaults.rangeUpperBound,
                orderIndex: insertionWorkout.plannedExercisesList.count
            )
            planned.workoutTemplate = insertionWorkout
            insertionContext.insert(planned)
            return planned
        }
    }

    func renameWorkout(
        _ workout: WorkoutTemplate,
        to name: String,
        context: ModelContext
    ) -> Result<Void, PersistenceCommandError> {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return .failure(.invalidInput) }
        guard !workout.isDeleted else { return .failure(.unavailable) }

        return commandRunner.perform(in: context) { _ in
            if workout.name != trimmedName {
                workout.name = trimmedName
            }
        }
    }

    func updatePlannedExercise(
        _ planned: PlannedExercise,
        sets: Int,
        repTargetType: PlannedRepTargetType,
        exactReps: Int,
        rangeLowerBound: Int,
        rangeUpperBound: Int,
        targetWeight: Double?,
        context: ModelContext
    ) -> Result<Void, PersistenceCommandError> {
        guard !planned.isDeleted else { return .failure(.unavailable) }

        return commandRunner.perform(in: context) { _ in
            if planned.sets != sets {
                planned.sets = sets
            }
            planned.configureRepTarget(
                repTargetType,
                exactReps: exactReps,
                rangeLowerBound: rangeLowerBound,
                rangeUpperBound: rangeUpperBound
            )
            if planned.targetWeight != targetWeight {
                planned.targetWeight = targetWeight
            }
        }
    }

    /// Commits a planned exercise deletion once its undo window has passed.
    func deletePlannedExercise(
        _ planned: PlannedExercise,
        context: ModelContext
    ) -> Result<Void, PersistenceCommandError> {
        guard !planned.isDeleted else { return .success(()) }

        return commandRunner.perform(in: context) { context in
            let siblings = planned.workoutTemplate?.plannedExercisesList.filter { $0.id != planned.id } ?? []
            planned.workoutTemplate = nil
            context.delete(planned)
            SiblingOrder.normalize(siblings)
        }
    }
}
