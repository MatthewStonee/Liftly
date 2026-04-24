import Foundation
import SwiftData

@Observable
final class WorkoutTemplateDetailViewModel {
    func reorderExercises(
        in workout: WorkoutTemplate,
        orderedIDs: [UUID],
        context: ModelContext
    ) {
        let orderLookup = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in
            (id, index)
        })

        for exercise in workout.plannedExercisesList {
            guard let index = orderLookup[exercise.id] else { continue }
            exercise.orderIndex = index
        }
    }
}
