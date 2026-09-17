import Foundation

/// The persisted order of a sibling collection. UUIDs make legacy ties stable.
enum SiblingOrder {
    static func workouts(_ items: [WorkoutTemplate]) -> [WorkoutTemplate] {
        items.sorted {
            $0.orderIndex == $1.orderIndex
                ? $0.id.uuidString < $1.id.uuidString
                : $0.orderIndex < $1.orderIndex
        }
    }

    static func exercises(_ items: [PlannedExercise]) -> [PlannedExercise] {
        items.sorted {
            $0.orderIndex == $1.orderIndex
                ? $0.id.uuidString < $1.id.uuidString
                : $0.orderIndex < $1.orderIndex
        }
    }

    static func normalize(_ items: [WorkoutTemplate]) {
        for (index, item) in workouts(items).enumerated() where item.orderIndex != index {
            item.orderIndex = index
        }
    }

    static func normalize(_ items: [PlannedExercise]) {
        for (index, item) in exercises(items).enumerated() where item.orderIndex != index {
            item.orderIndex = index
        }
    }

    static func isCompleteOrder(_ orderedIDs: [UUID], of existingIDs: [UUID]) -> Bool {
        orderedIDs.count == existingIDs.count
            && Set(orderedIDs).count == existingIDs.count
            && Set(orderedIDs) == Set(existingIDs)
    }
}
