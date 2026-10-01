import Foundation
import SwiftData

enum WorkoutActivityError: LocalizedError, Equatable {
    case storeUnavailable, missingWorkout, emptyWorkout, disabled, pendingDeletion, needsSwitch, payloadTooLarge, startFailed

    var errorDescription: String? {
        switch self {
        case .storeUnavailable: return "Liftly couldn't open your data. Open Liftly and try again."
        case .missingWorkout: return "This workout day no longer exists. Choose another day in Liftly or Shortcuts."
        case .emptyWorkout: return "Add exercises to this workout day before showing it on the Lock Screen."
        case .disabled: return "Live Activities are turned off. Enable them for Liftly in the Settings app."
        case .pendingDeletion: return "Undo the pending deletion or choose another workout day."
        case .needsSwitch: return "Another workout day is already showing on the Lock Screen."
        case .payloadTooLarge: return "This workout couldn't fit in a Live Activity. Open it in Liftly instead."
        case .startFailed: return "Couldn't start the Live Activity. Try again or close another Live Activity."
        }
    }
}

struct WorkoutActivitySnapshot {
    let workoutID: UUID
    let workoutName: String
    let exercises: [WorkoutActivityAttributes.Exercise]

    init(workout: WorkoutTemplate) {
        workoutID = workout.id
        workoutName = workout.name
        exercises = workout.sortedExercises.compactMap { planned in
            guard let exercise = planned.exercise else { return nil }
            return .init(id: planned.id, name: exercise.name)
        }
    }

    func content(startingIndex: Int = 0, anchorID: UUID? = nil) throws -> WorkoutActivityAttributes.ContentState {
        guard !exercises.isEmpty else { throw WorkoutActivityError.emptyWorkout }
        let anchor = anchorID.flatMap { id in exercises.firstIndex { $0.id == id } }
        let index = min(max(0, anchor ?? startingIndex), exercises.count - 1)
        let windowStart = exercises.count <= 10 ? 0 : index
        let rows = exercises.dropFirst(windowStart).prefix(10).map { exercise in
            var row = exercise
            row.name = Self.bounded(row.name, bytes: 160)
            return row
        }
        var state = WorkoutActivityAttributes.ContentState(
            workoutID: workoutID,
            workoutName: Self.bounded(workoutName, bytes: 160),
            totalExercises: exercises.count,
            startingIndex: index,
            windowStartingIndex: windowStart,
            exercises: rows
        )
        // Count both static attributes and dynamic content, with headroom for
        // ActivityKit's envelope. Bound values only in this display projection.
        let encoder = JSONEncoder()
        let attributes = WorkoutActivityAttributes(referenceID: UUID())
        // Control characters can expand to six bytes each in JSON. Re-bound
        // those pathological display strings rather than rejecting the day.
        for limit in [128, 64, 32] {
            if try encoder.encode(attributes).count + encoder.encode(state).count <= 3_800 { return state }
            state.workoutName = Self.bounded(state.workoutName, bytes: limit)
            state.exercises = state.exercises.map { exercise in
                var row = exercise
                row.name = Self.bounded(row.name, bytes: limit)
                return row
            }
        }
        guard try encoder.encode(attributes).count + encoder.encode(state).count <= 3_800 else { throw WorkoutActivityError.payloadTooLarge }
        return state
    }

    private static func bounded(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var result = String(text.prefix(bytes))
        while result.utf8.count > bytes - 3 { result.removeLast() }
        return result + "…"
    }
}

struct WorkoutDayReference: Equatable {
    let id: UUID
    let name: String
    let programName: String
}

/// Reads through a fresh context so unsaved drafts and pending Undo requests
/// cannot change what the Lock Screen shows.
struct WorkoutActivityRepository {
    let store: AppDataStore

    func snapshot(id: UUID, hiding deletions: DeletionCoordinator? = nil) async throws -> WorkoutActivitySnapshot {
        let container = try await store.readyContainer()
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let workout = try context.fetch(descriptor).first else { throw WorkoutActivityError.missingWorkout }
        if deletions?.isPending(workout) == true { throw WorkoutActivityError.pendingDeletion }
        return WorkoutActivitySnapshot(workout: workout)
    }

    func days(hiding deletions: DeletionCoordinator? = nil) async throws -> [WorkoutDayReference] {
        let container = try await store.readyContainer()
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<WorkoutTemplate>())
            .filter { deletions?.isPending($0) != true }
            .map { WorkoutDayReference(id: $0.id, name: $0.name, programName: $0.program?.name ?? "Program") }
            .sorted {
                if $0.programName != $1.programName { return $0.programName.localizedStandardCompare($1.programName) == .orderedAscending }
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
    }
}
