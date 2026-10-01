import ActivityKit
import Foundation
import Observation
import SwiftData

struct WorkoutActivityRecord: Equatable {
    let id: String
    let state: WorkoutActivityAttributes.ContentState
}

@MainActor
protocol WorkoutActivityClient {
    var isEnabled: Bool { get }
    var records: [WorkoutActivityRecord] { get }
    var dismissibleIDs: [String] { get }
    func start(state: WorkoutActivityAttributes.ContentState) throws
    func update(id: String, state: WorkoutActivityAttributes.ContentState) async
    func end(id: String) async
}

extension WorkoutActivityClient {
    var dismissibleIDs: [String] { records.map(\.id) }
}

final class ActivityKitWorkoutActivityClient: WorkoutActivityClient {
    private var submittedStates: [String: WorkoutActivityAttributes.ContentState] = [:]
    private var locallyEndedIDs: Set<String> = []
    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // Ended activities can remain on the Lock Screen after the system's time
    // limit. The explicit Stop action dismisses those residual cards too.
    var dismissibleIDs: [String] { Activity<WorkoutActivityAttributes>.activities.map(\.id) }

    var records: [WorkoutActivityRecord] {
        Activity<WorkoutActivityAttributes>.activities
            .filter { !locallyEndedIDs.contains($0.id) }
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map { WorkoutActivityRecord(id: $0.id, state: submittedStates[$0.id] ?? $0.content.state) }
            .sorted { $0.id < $1.id }
    }

    func start(state: WorkoutActivityAttributes.ContentState) throws {
        do {
            let activity = try Activity.request(
                attributes: WorkoutActivityAttributes(referenceID: UUID()),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            submittedStates[activity.id] = state
        } catch { throw WorkoutActivityError.startFailed }
    }

    func update(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
        // Activity.content can lag a successful update. Keep the latest submitted
        // page so a second intent or a UI reconciliation cannot restore old data.
        submittedStates[id] = state
    }

    func end(id: String) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        locallyEndedIDs.insert(id)
        submittedStates.removeValue(forKey: id)
    }
}

@Observable
final class WorkoutActivityCoordinator {
    static let shared: WorkoutActivityCoordinator = {
        let coordinator = WorkoutActivityCoordinator(store: .shared, client: ActivityKitWorkoutActivityClient())
        coordinator.beginObserving()
        return coordinator
    }()

    enum StartResult: Equatable { case showing, preservedExisting }
    private(set) var current: WorkoutActivityRecord?
    private(set) var areActivitiesEnabled: Bool
    private(set) var operationCount = 0
    var isWorking: Bool { operationCount > 0 }
    @ObservationIgnored weak var deletionCoordinator: DeletionCoordinator?
    @ObservationIgnored private let repository: WorkoutActivityRepository
    @ObservationIgnored private let client: any WorkoutActivityClient
    @ObservationIgnored private let loadSnapshot: (UUID, DeletionCoordinator?) async throws -> WorkoutActivitySnapshot
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var watchedActivityIDs: Set<String> = []
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []

    init(store: AppDataStore, client: any WorkoutActivityClient, loadSnapshot: ((UUID, DeletionCoordinator?) async throws -> WorkoutActivitySnapshot)? = nil) {
        let repository = WorkoutActivityRepository(store: store)
        self.repository = repository
        self.loadSnapshot = loadSnapshot ?? { id, deletions in
            try await repository.snapshot(id: id, hiding: deletions)
        }
        self.client = client
        areActivitiesEnabled = client.isEnabled
        current = client.records.first
    }

    func synchronize() {
        areActivitiesEnabled = client.isEnabled
        current = client.records.first
    }

    /// Production-only subscriptions. Notifications from background contexts are
    /// delivered to MainActor before touching observable state or SwiftData.
    private func beginObserving() {
        for name in [ModelContext.didSave,
                     Notification.Name("NSPersistentStoreRemoteChangeNotification")] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.current != nil else { return }
                    await self.refresh()
                }
            }
            notificationTokens.append(token)
        }
        for activity in Activity<WorkoutActivityAttributes>.activities { watch(activity) }
        observationTasks.append(Task { @MainActor [weak self] in
            for await activity in Activity<WorkoutActivityAttributes>.activityUpdates {
                guard let self else { return }
                self.watch(activity)
                self.synchronize()
            }
        })
        observationTasks.append(Task { @MainActor [weak self] in
            for await _ in ActivityAuthorizationInfo().activityEnablementUpdates {
                self?.synchronize()
            }
        })
    }

    private func watch(_ activity: Activity<WorkoutActivityAttributes>) {
        guard watchedActivityIDs.insert(activity.id).inserted else { return }
        observationTasks.append(Task { @MainActor [weak self] in
            for await state in activity.activityStateUpdates {
                self?.synchronize()
                if state == .dismissed || state == .ended { return }
            }
        })
    }

    @discardableResult
    func start(workoutID: UUID, automatic: Bool = false, allowSwitch: Bool = false) async throws -> StartResult {
        try await serialized { [self] in
            synchronize()
            guard client.isEnabled else { throw WorkoutActivityError.disabled }
            let snapshot = try await loadSnapshot(workoutID, deletionCoordinator)
            if let current, current.state.workoutID != workoutID {
                if automatic { return .preservedExisting }
                guard allowSwitch else { throw WorkoutActivityError.needsSwitch }
            }
            let sameDay = current?.state.workoutID == workoutID
            var state = try snapshot.content(
                startingIndex: sameDay ? current?.state.startingIndex ?? 0 : 0,
                anchorID: sameDay ? current?.state.pageAnchorID : nil
            )
            if let current {
                state.revision = current.state.revision + 1
                await client.update(id: current.id, state: state)
            } else {
                try client.start(state: state)
            }
            await removeDuplicates()
            synchronize()
            return .showing
        }
    }

    func stop() async {
        _ = try? await serialized { [self] in
            for id in client.dismissibleIDs { await client.end(id: id) }
            synchronize()
        }
    }

    func refresh() async {
        _ = try? await serialized { [self] in
            await removeDuplicates()
            synchronize()
            guard let record = current else { return }
            do {
                let snapshot = try await loadSnapshot(record.state.workoutID, nil)
                var state = try snapshot.content(startingIndex: record.state.startingIndex, anchorID: record.state.pageAnchorID)
                state.revision = record.state.revision
                if state != record.state {
                    state.revision += 1
                    await client.update(id: record.id, state: state)
                }
            } catch WorkoutActivityError.missingWorkout {
                await client.end(id: record.id)
            } catch WorkoutActivityError.emptyWorkout {
                await client.end(id: record.id)
            } catch {
                await markNeedsRefresh(record)
            }
            synchronize()
        }
    }

    func page(activityID: String, direction: Int, visibleCount: Int, displayedPage: WorkoutActivityPageReference? = nil) async throws {
        try await serialized { [self] in
            synchronize()
            guard let record = current, record.id == activityID else { return }
            do {
                // A freshly restored ActivityKit object can lag the rendered page.
                // Prefer the higher version; queued taps with an older render
                // continue from our latest submitted state instead.
                let reference = displayedPage.flatMap { $0.revision > record.state.revision ? $0 : nil }
                    ?? WorkoutActivityPageReference(workoutID: record.state.workoutID, startingIndex: record.state.startingIndex,
                                                    anchorID: record.state.pageAnchorID, revision: record.state.revision)
                let snapshot = try await loadSnapshot(reference.workoutID, nil)
                let base = try snapshot.content(startingIndex: reference.startingIndex, anchorID: reference.anchorID)
                let step = min(max(visibleCount, 1), 10)
                // WidgetKit's remote accessibility tree can report disabled
                // controls as enabled. Keep boundary intents harmless too.
                guard direction < 0 ? base.startingIndex > 0 : base.startingIndex + step < base.totalExercises else { return }
                let index = base.startingIndex + (direction < 0 ? -step : step)
                var state = try snapshot.content(startingIndex: index)
                state.revision = reference.revision + 1
                await client.update(id: record.id, state: state)
            } catch WorkoutActivityError.missingWorkout {
                await client.end(id: record.id)
            } catch WorkoutActivityError.emptyWorkout {
                await client.end(id: record.id)
            } catch {
                await markNeedsRefresh(record)
                synchronize()
                throw error
            }
            synchronize()
        }
    }

    func availableDays() async throws -> [WorkoutDayReference] {
        try await repository.days(hiding: deletionCoordinator)
    }

    private func markNeedsRefresh(_ record: WorkoutActivityRecord) async {
        guard !record.state.needsRefresh else { return }
        var state = record.state
        state.needsRefresh = true
        state.revision += 1
        await client.update(id: record.id, state: state)
    }

    private func removeDuplicates() async {
        for record in client.records.dropFirst() { await client.end(id: record.id) }
    }

    /// A task chain serializes the complete operation, including ActivityKit awaits.
    /// MainActor alone would permit a second tap to enter during those awaits.
    private func serialized<Value>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        operationCount += 1
        defer { operationCount -= 1 }
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return try await operation()
        }
        tail = Task { @MainActor in _ = try? await task.value }
        return try await task.value
    }
}
