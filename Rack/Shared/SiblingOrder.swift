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

    /// The order after moving `sources`, in the order given, to just before `destination`,
    /// or to the end when it's nil. Returns nil when the move no longer fits `ids`, such as
    /// when a sync removed every source or the destination during the drag.
    static func moving<ID: Hashable>(_ sources: [ID], before destination: ID?, in ids: [ID]) -> [ID]? {
        let existing = Set(ids)
        var moved = Set<ID>()
        let moving = sources.filter { existing.contains($0) && moved.insert($0).inserted }
        guard !moving.isEmpty else { return nil }

        var result = ids.filter { !moved.contains($0) }
        var insertion = result.endIndex
        if let destination {
            guard let anchor = ids.firstIndex(of: destination) else { return nil }
            // A destination that is itself moving means before the next item that stays.
            if let next = ids[anchor...].first(where: { !moved.contains($0) }),
               let index = result.firstIndex(of: next) {
                insertion = index
            }
        }
        result.insert(contentsOf: moving, at: insertion)
        return result
    }

    static func isCompleteOrder(_ orderedIDs: [UUID], of existingIDs: [UUID]) -> Bool {
        orderedIDs.count == existingIDs.count
            && Set(orderedIDs).count == existingIDs.count
            && Set(orderedIDs) == Set(existingIDs)
    }
}
