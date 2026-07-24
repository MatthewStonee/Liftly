import Foundation
import SwiftData

@Observable
final class ProgramDetailViewModel {
    func reorderWorkouts(
        in program: Program,
        orderedIDs: [UUID],
        context _: ModelContext
    ) {
        let orderLookup = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in
            (id, index)
        })

        for workout in program.workoutsList {
            guard let index = orderLookup[workout.id] else { continue }
            if workout.orderIndex != index {
                workout.orderIndex = index
            }
        }
    }
}
