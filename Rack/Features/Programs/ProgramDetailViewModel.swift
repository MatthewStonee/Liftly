import Foundation
import SwiftData

@Observable
final class ProgramDetailViewModel {
    func reorderWorkouts(
        in program: Program,
        orderedIDs: [UUID],
        context: ModelContext
    ) {
        let orderLookup = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { index, id in
            (id, index)
        })

        for workout in program.workoutsList {
            guard let index = orderLookup[workout.id] else { continue }
            workout.orderIndex = index
        }
    }
}
