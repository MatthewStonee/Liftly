import Foundation
import SwiftData

@Observable
final class WorkoutTemplateDetailViewModel {
    func reorderExercises(
        in workout: WorkoutTemplate,
        orderedIDs: [UUID],
        context _: ModelContext
    ) {
        let orderLookup = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in
            (id, index)
        })

        for exercise in workout.plannedExercisesList {
            guard let index = orderLookup[exercise.id] else { continue }
            if exercise.orderIndex != index {
                exercise.orderIndex = index
            }
        }
    }
}
