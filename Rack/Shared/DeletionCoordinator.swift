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
        case loggedSet(UUID)

        enum Key: Hashable {
            case program(UUID), workout(UUID), planned(UUID), loggedSet(UUID)
        }

        var key: Key {
            switch self {
            case .program(let id): return .program(id)
            case .workout(let id, _): return .workout(id)
            case .planned(let id, _, _): return .planned(id)
            case .loggedSet(let id): return .loggedSet(id)
            }
        }
    }

    private(set) var pending: [Identity] = []
    private(set) var generation: UUID?
    private(set) var isToastDismissed = false
    private(set) var isPaused = false

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let alertCenter: PersistenceAlertCenter
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var remaining: TimeInterval = 4

    init(
        context: ModelContext,
        alertCenter: PersistenceAlertCenter,
        commandRunner: PersistenceCommandRunner = PersistenceCommandRunner(),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.context = context
        self.alertCenter = alertCenter
        self.commandRunner = commandRunner
        self.now = now
        self.sleep = sleep
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
        enqueue(.loggedSet(set.id))
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
        pending.contains(.loggedSet(set.id))
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
        remaining = 4
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
            try Self.commit(batch, in: context)
        }
        undo()
        if case .failure(let error) = result {
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
        remaining = 4
        if isPaused {
            timer?.cancel()
            generation = UUID()
        } else {
            restartTimer(after: 4)
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

    private static func commit(_ batch: [Identity], in context: ModelContext) throws {
        let programIDs = Set(batch.compactMap { if case .program(let id) = $0 { return id }; return nil })
        let workoutIDs = Set(batch.compactMap { if case .workout(let id, _) = $0 { return id }; return nil })
        let plannedIDs = Set(batch.compactMap { if case .planned(let id, _, _) = $0 { return id }; return nil })
        let setIDs = Set(batch.compactMap { if case .loggedSet(let id) = $0 { return id }; return nil })

        let programs = try context.fetch(FetchDescriptor<Program>())
        let workouts = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let planned = try context.fetch(FetchDescriptor<PlannedExercise>())
        let loggedSets = try context.fetch(FetchDescriptor<LoggedSet>())

        let deletedWorkouts = workouts.filter { workoutIDs.contains($0.id) && !programIDs.contains($0.program?.id ?? UUID()) }
        let deletedPlanned = planned.filter {
            plannedIDs.contains($0.id)
                && !workoutIDs.contains($0.workoutTemplate?.id ?? UUID())
                && !programIDs.contains($0.workoutTemplate?.program?.id ?? UUID())
        }
        let affectedPrograms = Set(deletedWorkouts.compactMap { $0.program?.id })
        let affectedWorkouts = Set(deletedPlanned.compactMap { $0.workoutTemplate?.id })

        try ProgressViewModel.deleteSetsInCommand(loggedSets.filter { setIDs.contains($0.id) }, context: context)
        for item in deletedPlanned { item.workoutTemplate = nil; context.delete(item) }
        for item in deletedWorkouts { item.program = nil; context.delete(item) }
        for item in programs where programIDs.contains(item.id) { context.delete(item) }

        for programID in affectedPrograms {
            SiblingOrder.normalize(workouts.filter {
                $0.program?.id == programID && !workoutIDs.contains($0.id)
            })
        }
        for workoutID in affectedWorkouts {
            SiblingOrder.normalize(planned.filter {
                $0.workoutTemplate?.id == workoutID && !plannedIDs.contains($0.id)
            })
        }
    }
}
