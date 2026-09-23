import Foundation
import Observation
import SwiftData

/// Keeps an Undo batch in memory until its single save deadline expires.
@MainActor @Observable
final class DeletionCoordinator {
    enum Identity: Hashable {
        case program(UUID)
        case workout(UUID, programID: UUID?)
        case planned(UUID, workoutID: UUID?, programID: UUID?)
        case loggedSet(UUID, exerciseID: UUID?)

        enum Key: Hashable {
            case program(UUID), workout(UUID), planned(UUID), loggedSet(UUID)
        }

        var key: Key {
            switch self {
            case .program(let id): return .program(id)
            case .workout(let id, _): return .workout(id)
            case .planned(let id, _, _): return .planned(id)
            case .loggedSet(let id, _): return .loggedSet(id)
            }
        }
    }

    private(set) var pending: [Identity] = []
    private(set) var generation: UUID?
    private(set) var isToastDismissed = false
    private(set) var isPaused = false

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored let alertCenter: PersistenceAlertCenter
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let onFetch: (FetchKind) -> Void
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private let undoInterval: TimeInterval
    @ObservationIgnored private var remaining: TimeInterval

    enum FetchKind: Equatable {
        case requestedPrograms, requestedWorkouts, requestedPlanned, requestedLoggedSets
        case workoutSiblings, plannedSiblings
    }

    init(
        context: ModelContext,
        alertCenter: PersistenceAlertCenter,
        undoInterval: TimeInterval = 4,
        commandRunner: PersistenceCommandRunner = PersistenceCommandRunner(),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onFetch: @escaping (FetchKind) -> Void = { _ in }
    ) {
        self.undoInterval = undoInterval
        self.remaining = undoInterval
        self.context = context
        self.alertCenter = alertCenter
        self.commandRunner = commandRunner
        self.now = now
        self.sleep = sleep
        self.onFetch = onFetch
    }

    var pendingCount: Int { pending.count }
    var showsToast: Bool { !pending.isEmpty && !isToastDismissed }
    var toastMessage: String {
        let count = pendingCount
        return "\(count) \(count == 1 ? "item" : "items") deleted"
    }

    func request(_ program: Program) {
        guard !program.isDeleted else { return }
        enqueue(.program(program.id))
    }

    func request(_ workout: WorkoutTemplate) {
        guard !workout.isDeleted else { return }
        enqueue(.workout(workout.id, programID: workout.program?.id))
    }

    func request(_ planned: PlannedExercise) {
        guard !planned.isDeleted else { return }
        let workout = planned.workoutTemplate
        enqueue(.planned(planned.id, workoutID: workout?.id, programID: workout?.program?.id))
    }

    func request(_ set: LoggedSet) {
        guard !set.isDeleted else { return }
        enqueue(.loggedSet(set.id, exerciseID: set.exercise?.id))
    }

    func isPending(_ program: Program) -> Bool {
        pending.contains(.program(program.id))
    }

    func isPending(_ workout: WorkoutTemplate) -> Bool {
        pending.contains { identity in
            switch identity {
            case .program(let id): return id == workout.program?.id
            case .workout(let id, _): return id == workout.id
            default: return false
            }
        }
    }

    func isPending(_ planned: PlannedExercise) -> Bool {
        pending.contains { identity in
            switch identity {
            case .program(let id): return id == planned.workoutTemplate?.program?.id
            case .workout(let id, _): return id == planned.workoutTemplate?.id
            case .planned(let id, _, _): return id == planned.id
            default: return false
            }
        }
    }

    func isPending(_ set: LoggedSet) -> Bool {
        pending.contains { $0.key == .loggedSet(set.id) }
    }

    func pendingLoggedSetIDs(for exerciseID: UUID) -> Set<UUID> {
        Set(pending.compactMap { identity in
            if case .loggedSet(let id, let ownerID) = identity, ownerID == exerciseID { return id }
            return nil
        })
    }

    func hasPendingWorkouts(in program: Program) -> Bool {
        pending.contains { identity in
            switch identity {
            case .program(let id): return id == program.id
            case .workout(_, let programID): return programID == program.id
            default: return false
            }
        }
    }

    func hasPendingExercises(in workout: WorkoutTemplate) -> Bool {
        pending.contains { identity in
            switch identity {
            case .program(let id): return id == workout.program?.id
            case .workout(let id, _): return id == workout.id
            case .planned(_, let workoutID, _): return workoutID == workout.id
            default: return false
            }
        }
    }

    func undo() {
        timer?.cancel()
        timer = nil
        pending = []
        generation = nil
        deadline = nil
        remaining = undoInterval
        isToastDismissed = false
    }

    func dismissToast() {
        isToastDismissed = true
    }

    func setActive(_ active: Bool) {
        if active && isPaused {
            isPaused = false
            if !pending.isEmpty {
                restartTimer(after: remaining)
            }
        } else if !active && !isPaused {
            isPaused = true
            guard !pending.isEmpty else { return }
            remaining = max(0, deadline?.timeIntervalSince(now()) ?? remaining)
            timer?.cancel()
            timer = nil
            generation = UUID() // Invalidate a callback already queued on the main actor.
            deadline = nil
        }
    }

    /// A stale callback cannot commit or clear a newer batch.
    func expire(generation expected: UUID) {
        guard !isPaused, generation == expected, !pending.isEmpty else { return }
        let batch = pending
        let result = commandRunner.perform(in: context) { context in
            try Self.commit(batch, in: context, onFetch: onFetch)
        }
        undo()
        switch result {
        case .success(let exerciseIDs):
            LoggedSetChange.publish(exerciseIDs: exerciseIDs)
        case .failure(let error):
            alertCenter.report(PersistenceAlert(title: "Couldn't Delete Items", error: error))
        }
    }

    private func enqueue(_ identity: Identity) {
        guard !pending.contains(where: { $0.key == identity.key }), !isCovered(identity) else { return }
        switch identity {
        case .program(let programID):
            pending.removeAll {
                switch $0 {
                case .workout(_, let parentID): return parentID == programID
                case .planned(_, _, let parentID): return parentID == programID
                default: return false
                }
            }
        case .workout(let workoutID, _):
            pending.removeAll {
                if case .planned(_, let parentID, _) = $0 { return parentID == workoutID }
                return false
            }
        default: break
        }
        pending.append(identity)
        isToastDismissed = false
        remaining = undoInterval
        if isPaused {
            timer?.cancel()
            generation = UUID()
        } else {
            restartTimer(after: undoInterval)
        }
    }

    private func isCovered(_ identity: Identity) -> Bool {
        switch identity {
        case .workout(_, let programID):
            return programID.map { pending.contains(.program($0)) } ?? false
        case .planned(_, let workoutID, let programID):
            return (programID.map { pending.contains(.program($0)) } ?? false)
                || pending.contains {
                    if case .workout(let id, _) = $0 { return id == workoutID }
                    return false
                }
        default: return false
        }
    }

    private func restartTimer(after seconds: TimeInterval) {
        timer?.cancel()
        let next = UUID()
        generation = next
        deadline = now().addingTimeInterval(seconds)
        timer = Task { [sleep] in
            do { try await sleep(.seconds(seconds)) } catch { return }
            guard !Task.isCancelled else { return }
            expire(generation: next)
        }
    }

    private static func commit(
        _ batch: [Identity],
        in context: ModelContext,
        onFetch: (FetchKind) -> Void
    ) throws -> Set<UUID> {
        let programIDs = Set(batch.compactMap { if case .program(let id) = $0 { return id }; return nil })
        let workoutIDs = Set(batch.compactMap { if case .workout(let id, _) = $0 { return id }; return nil })
        let plannedIDs = Set(batch.compactMap { if case .planned(let id, _, _) = $0 { return id }; return nil })
        let setIDs = Set(batch.compactMap { if case .loggedSet(let id, _) = $0 { return id }; return nil })

        var programs: [Program] = []
        if !programIDs.isEmpty {
            let ids = Array(programIDs)
            onFetch(.requestedPrograms)
            programs = try context.fetch(FetchDescriptor<Program>(
                predicate: #Predicate<Program> { ids.contains($0.id) }
            ))
        }
        var workouts: [WorkoutTemplate] = []
        if !workoutIDs.isEmpty {
            let ids = Array(workoutIDs)
            onFetch(.requestedWorkouts)
            workouts = try context.fetch(FetchDescriptor<WorkoutTemplate>(
                predicate: #Predicate<WorkoutTemplate> { ids.contains($0.id) }
            ))
        }
        var planned: [PlannedExercise] = []
        if !plannedIDs.isEmpty {
            let ids = Array(plannedIDs)
            onFetch(.requestedPlanned)
            planned = try context.fetch(FetchDescriptor<PlannedExercise>(
                predicate: #Predicate<PlannedExercise> { ids.contains($0.id) }
            ))
        }
        var loggedSets: [LoggedSet] = []
        if !setIDs.isEmpty {
            let ids = Array(setIDs)
            onFetch(.requestedLoggedSets)
            loggedSets = try context.fetch(FetchDescriptor<LoggedSet>(
                predicate: #Predicate<LoggedSet> { ids.contains($0.id) }
            ))
        }

        let deletedProgramIDs = Set(programs.map(\.id))
        let deletedWorkouts = workouts.filter { workout in
            !(workout.program.map { deletedProgramIDs.contains($0.id) } ?? false)
        }
        let deletedWorkoutIDs = Set(deletedWorkouts.map(\.id))
        let deletedPlanned = planned.filter { item in
            guard let workout = item.workoutTemplate else { return true }
            return !deletedWorkoutIDs.contains(workout.id)
                && !(workout.program.map { deletedProgramIDs.contains($0.id) } ?? false)
        }
        let affectedPrograms = Set(deletedWorkouts.compactMap { $0.program?.id })
        let affectedWorkouts = Set(deletedPlanned.compactMap { $0.workoutTemplate?.id })

        var workoutSiblings: [WorkoutTemplate] = []
        for programID in affectedPrograms where !deletedProgramIDs.contains(programID) {
            onFetch(.workoutSiblings)
            workoutSiblings += try context.fetch(FetchDescriptor<WorkoutTemplate>(
                predicate: #Predicate<WorkoutTemplate> { $0.program?.id == programID }
            ))
        }
        var plannedSiblings: [PlannedExercise] = []
        for workoutID in affectedWorkouts where !deletedWorkoutIDs.contains(workoutID) {
            onFetch(.plannedSiblings)
            plannedSiblings += try context.fetch(FetchDescriptor<PlannedExercise>(
                predicate: #Predicate<PlannedExercise> { $0.workoutTemplate?.id == workoutID }
            ))
        }

        let changedExerciseIDs = try ProgressViewModel.deleteSetsInCommand(loggedSets, context: context)
        for item in deletedPlanned { item.workoutTemplate = nil; context.delete(item) }
        for item in deletedWorkouts { item.program = nil; context.delete(item) }
        for item in programs { context.delete(item) }

        for programID in affectedPrograms {
            SiblingOrder.normalize(workoutSiblings.filter {
                $0.program?.id == programID && !deletedWorkoutIDs.contains($0.id)
            })
        }
        for workoutID in affectedWorkouts {
            SiblingOrder.normalize(plannedSiblings.filter {
                $0.workoutTemplate?.id == workoutID && !plannedIDs.contains($0.id)
            })
        }
        return changedExerciseIDs
    }
}
