import Foundation
import SwiftData
import OSLog

/// Which store configuration an opening attempt uses.
enum PersistentStoreKind: String {
    case cloudKit
    case localOnly
}

/// Opens the app's SwiftData store without ever deleting or replacing it.
///
/// Opening tries the CloudKit-backed configuration first, then a local-only
/// configuration at the same store location. If both fail, the store is left untouched
/// and the app shows a recovery screen that can retry.
@Observable
final class AppDataStore {
    enum Phase {
        case loading
        case ready(ModelContainer)
        case failed
    }

    typealias ContainerOpener = @MainActor (PersistentStoreKind) throws -> ModelContainer
    typealias ContainerPreparation = @MainActor (ModelContainer) -> Void

    private static let logger = Logger(subsystem: "com.matthewstone.liftly", category: "Persistence")

    private(set) var phase: Phase = .loading
    /// Whether this launch fell back to the local-only store.
    private(set) var isCloudSyncUnavailable = false
    private(set) var isOpening = false

    @ObservationIgnored private let openContainer: ContainerOpener
    @ObservationIgnored private let prepareContainer: ContainerPreparation

    init(
        openContainer: @escaping ContainerOpener = { try AppDataStore.openAppContainer($0) },
        prepareContainer: @escaping ContainerPreparation = { AppDataStore.prepareAppContainer($0) }
    ) {
        self.openContainer = openContainer
        self.prepareContainer = prepareContainer
    }

    var container: ModelContainer? {
        guard case .ready(let container) = phase else { return nil }
        return container
    }

    /// Opens the store. Calls made while opening, or after the store is ready, do nothing.
    func open() async {
        guard !isOpening, container == nil else { return }
        isOpening = true
        defer { isOpening = false }

        // Let the loading or retrying state render before the synchronous open.
        await Task.yield()

        if let container = attemptToOpen(.cloudKit) {
            finishOpening(container, isCloudSyncUnavailable: false)
        } else if let container = attemptToOpen(.localOnly) {
            Self.logger.warning("Fell back to local-only SwiftData store. iCloud sync is disabled for this launch.")
            finishOpening(container, isCloudSyncUnavailable: true)
        } else {
            Self.logger.error("Couldn't open the SwiftData store. The existing store was left untouched.")
            phase = .failed
        }
    }

    private func attemptToOpen(_ kind: PersistentStoreKind) -> ModelContainer? {
        do {
            let container = try openContainer(kind)
            Self.logger.notice("Loaded \(kind.rawValue, privacy: .public) SwiftData store.")
            return container
        } catch {
            Self.logger.error("Failed to load \(kind.rawValue, privacy: .public) SwiftData store: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func finishOpening(_ container: ModelContainer, isCloudSyncUnavailable: Bool) {
        prepareContainer(container)
        self.isCloudSyncUnavailable = isCloudSyncUnavailable
        phase = .ready(container)
    }
}

extension AppDataStore {
    static let schema = Schema([
        Program.self,
        WorkoutTemplate.self,
        PlannedExercise.self,
        Exercise.self,
        WorkoutSession.self,
        LoggedSet.self
    ])

    static func openAppContainer(_ kind: PersistentStoreKind) throws -> ModelContainer {
        #if DEBUG
        try DebugPersistenceFaults.consumeStoreOpenFailure()
        #endif
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: kind == .cloudKit ? .automatic : .none
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    static func prepareAppContainer(_ container: ModelContainer) {
        // User-triggered writes save explicitly through PersistenceCommandRunner.
        container.mainContext.autosaveEnabled = false
        ExerciseLibrary.seedIfNeeded(context: container.mainContext)
    }

    /// Deferred maintenance that runs in background contexts once the store is open.
    static func performStartupMaintenance(container: ModelContainer) async {
        let maintenanceActor = ExerciseLibraryMaintenanceActor(modelContainer: container)
        guard await maintenanceActor.performMaintenance() else {
            logger.error("Deferred startup maintenance failed; personal record backfill was not started.")
            return
        }

        let backfillActor = PersonalRecordBackfillActor(modelContainer: container)
        await backfillActor.backfillIfNeeded()
    }
}
