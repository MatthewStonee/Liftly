import Foundation
import SwiftData
import Testing
@testable import Rack

struct StoreOpeningFailure: Error {}

/// Records store-opening attempts and fails the configured kinds.
@MainActor
final class StoreOpeningRecorder {
    var failingKinds: Set<PersistentStoreKind>
    let container: ModelContainer
    private(set) var attempts: [PersistentStoreKind] = []
    private(set) var preparedContainers: [ModelContainer] = []

    init(failingKinds: Set<PersistentStoreKind> = []) throws {
        self.failingKinds = failingKinds
        container = try TestStore.makeInMemoryContainer()
    }

    func makeDataStore() -> AppDataStore {
        AppDataStore(
            openContainer: { [self] kind in
                attempts.append(kind)
                if failingKinds.contains(kind) {
                    throw StoreOpeningFailure()
                }
                return container
            },
            prepareContainer: { [self] container in
                preparedContainers.append(container)
            }
        )
    }
}

@MainActor
struct AppDataStoreTests {
    @Test func opensTheCloudKitStoreFirst() async throws {
        let recorder = try StoreOpeningRecorder()
        let dataStore = recorder.makeDataStore()

        await dataStore.open()

        #expect(recorder.attempts == [.cloudKit])
        #expect(dataStore.container === recorder.container)
        #expect(!dataStore.isCloudSyncUnavailable)
        #expect(recorder.preparedContainers.count == 1)
    }

    @Test func fallsBackToTheLocalStoreWhenCloudKitFails() async throws {
        let recorder = try StoreOpeningRecorder(failingKinds: [.cloudKit])
        let dataStore = recorder.makeDataStore()

        await dataStore.open()

        #expect(recorder.attempts == [.cloudKit, .localOnly])
        #expect(dataStore.container === recorder.container)
        #expect(dataStore.isCloudSyncUnavailable)
        #expect(recorder.preparedContainers.count == 1)
    }

    @Test func failsWithoutPreparingAnythingWhenBothStoresFail() async throws {
        let recorder = try StoreOpeningRecorder(failingKinds: [.cloudKit, .localOnly])
        let dataStore = recorder.makeDataStore()

        await dataStore.open()

        #expect(recorder.attempts == [.cloudKit, .localOnly])
        #expect(dataStore.phase.isFailed)
        #expect(dataStore.container == nil)
        #expect(!dataStore.isOpening)
        #expect(recorder.preparedContainers.isEmpty)
    }

    @Test func retryOpensTheStoreAfterAFailure() async throws {
        let recorder = try StoreOpeningRecorder(failingKinds: [.cloudKit, .localOnly])
        let dataStore = recorder.makeDataStore()
        await dataStore.open()
        #expect(dataStore.phase.isFailed)

        recorder.failingKinds = []
        await dataStore.open()

        #expect(recorder.attempts == [.cloudKit, .localOnly, .cloudKit])
        #expect(dataStore.container === recorder.container)
        #expect(!dataStore.isCloudSyncUnavailable)
        #expect(recorder.preparedContainers.count == 1)
    }

    @Test func ignoresOpenRequestsWhileOpeningAndOnceReady() async throws {
        let recorder = try StoreOpeningRecorder()
        let dataStore = recorder.makeDataStore()

        async let first: Void = dataStore.open()
        async let second: Void = dataStore.open()
        _ = await (first, second)
        await dataStore.open()

        #expect(recorder.attempts == [.cloudKit])
        #expect(recorder.preparedContainers.count == 1)
    }

    @Test func failedOpeningLeavesStoreFilesAndMaintenanceFlagsIntact() async throws {
        let directory = try TestStore.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "default.store")
        let unreadableStore = Data("not a SQLite database".utf8)
        try unreadableStore.write(to: storeURL)

        let defaults = UserDefaults.standard
        let flagKeys = ["exerciseLibrarySeeded", "prBackfillComplete"]
        let originalFlags = flagKeys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(flagKeys, originalFlags) {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        for key in flagKeys {
            defaults.set(true, forKey: key)
        }

        // Both attempts hit the unreadable store, as a damaged real store would.
        let dataStore = AppDataStore(openContainer: { _ in
            try TestStore.makeOnDiskContainer(at: storeURL)
        })
        await dataStore.open()
        await dataStore.open()

        #expect(dataStore.phase.isFailed)
        #expect(try Data(contentsOf: storeURL) == unreadableStore)
        #expect(flagKeys.allSatisfy { defaults.bool(forKey: $0) })
    }
}

/// Startup maintenance changes the user's data on every launch: it merges and deletes
/// duplicate library exercises, restores missing ones, repairs rep targets, and backfills
/// PR flags. Each test records its flags in its own `UserDefaults` suite, so it can't
/// race `failedOpeningLeavesStoreFilesAndMaintenanceFlagsIntact` or the host app's
/// own launch maintenance.
@MainActor
final class StartupMaintenanceTests {
    private let container: ModelContainer
    private let defaultsSuiteName: String
    private let defaults: UserDefaults

    private var context: ModelContext {
        container.mainContext
    }

    init() throws {
        let suiteName = "LiftlyTests-\(UUID().uuidString)"
        defaultsSuiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName)!
        container = try TestStore.makeInMemoryContainer()
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
    }

    // MARK: Exercise library

    @Test func duplicatesMergeIntoTheMostReferencedExercise() async throws {
        // Two copies of the library's Bench Press, as a second iCloud device can create.
        let lessUsed = insertedExercise("Bench Press", .chest, .barbell)
        let mostUsed = insertedExercise("bench press ", .chest, .barbell)
        insertedSet(lessUsed, reps: 5, weight: 100, isRecord: true)
        insertedSet(mostUsed, reps: 5, weight: 90, isRecord: true)
        let heaviest = insertedSet(mostUsed, reps: 5, weight: 110, isRecord: false)
        context.insert(PlannedExercise(exercise: mostUsed))
        try context.save()

        let succeeded = await ExerciseLibraryMaintenanceActor(modelContainer: container)
            .performMaintenance(defaults: defaults)

        #expect(succeeded)
        let benchPresses = try TestStore.savedModels(Exercise.self, in: container)
            .filter { ExerciseLibrary.normalizedName($0.name) == "bench press" }
        #expect(benchPresses.map(\.id) == [mostUsed.id])
        #expect(benchPresses.first?.name == "Bench Press")
        let sets = try TestStore.savedModels(LoggedSet.self, in: container)
        #expect(sets.count == 3)
        #expect(sets.allSatisfy { $0.exercise?.id == mostUsed.id })
        #expect(Set(sets.filter(\.isPersonalRecord).map(\.id)) == [heaviest.id])
        let planned = try TestStore.savedModels(PlannedExercise.self, in: container)
        #expect(planned.map(\.exercise?.id) == [mostUsed.id])
    }

    @Test func missingLibraryExercisesAreRestoredAndCustomOnesKept() async throws {
        let custom = insertedExercise("Landmine Press", .shoulders, .other)
        try context.save()

        let succeeded = await ExerciseLibraryMaintenanceActor(modelContainer: container)
            .performMaintenance(defaults: defaults)

        #expect(succeeded)
        let exercises = try TestStore.savedModels(Exercise.self, in: container)
        #expect(exercises.count == ExerciseLibrary.seed.count + 1)
        #expect(exercises.contains { $0.id == custom.id && $0.name == "Landmine Press" })
        #expect(exercises.contains { $0.name == "Squat" })
        #expect(defaults.bool(forKey: "exerciseLibrarySeeded"))
    }

    @Test func invalidRepTargetsAreRepaired() async throws {
        let exercise = insertedExercise("Landmine Press", .shoulders, .other)
        let planned = PlannedExercise(exercise: exercise)
        context.insert(planned)
        planned.reps = 0
        planned.repRangeLowerBound = 0
        planned.repRangeUpperBound = -3
        planned.repTargetTypeRaw = "someday"
        try context.save()

        let succeeded = await ExerciseLibraryMaintenanceActor(modelContainer: container)
            .performMaintenance(defaults: defaults)

        #expect(succeeded)
        let repaired = try #require(try TestStore.savedModels(PlannedExercise.self, in: container).first)
        #expect(repaired.reps == 1)
        #expect(repaired.repRangeLowerBound == 1)
        #expect(repaired.repRangeUpperBound == 1)
        #expect(repaired.repTargetTypeRaw == PlannedRepTargetType.exact.rawValue)
    }

    // MARK: Personal record backfill

    @Test func backfillFlagsTheBestSetPerRepCountAndSkipsBodyweight() async throws {
        let exercise = insertedExercise("Landmine Press", .shoulders, .other)
        insertedSet(exercise, reps: 5, weight: 100, isRecord: true)
        let fiveRepBest = insertedSet(exercise, reps: 5, weight: 110, isRecord: false)
        let threeRepBest = insertedSet(exercise, reps: 3, weight: 90, isRecord: false)
        insertedSet(exercise, reps: 8, weight: 0, isRecord: true)
        try context.save()

        await PersonalRecordBackfillActor(modelContainer: container).backfillIfNeeded(defaults: defaults)

        let records = try TestStore.savedModels(LoggedSet.self, in: container).filter(\.isPersonalRecord)
        #expect(Set(records.map(\.id)) == [fiveRepBest.id, threeRepBest.id])
        #expect(defaults.bool(forKey: "prBackfillComplete"))
    }

    @Test func backfillRunsOnlyOnce() async throws {
        defaults.set(true, forKey: "prBackfillComplete")
        let exercise = insertedExercise("Landmine Press", .shoulders, .other)
        insertedSet(exercise, reps: 5, weight: 100, isRecord: false)
        try context.save()

        await PersonalRecordBackfillActor(modelContainer: container).backfillIfNeeded(defaults: defaults)

        #expect(try TestStore.savedModels(LoggedSet.self, in: container).filter(\.isPersonalRecord).isEmpty)
    }

    // MARK: Helpers

    private func insertedExercise(_ name: String, _ muscleGroup: MuscleGroup, _ equipment: Equipment) -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: muscleGroup, equipment: equipment)
        context.insert(exercise)
        return exercise
    }

    @discardableResult
    private func insertedSet(_ exercise: Exercise, reps: Int, weight: Double, isRecord: Bool) -> LoggedSet {
        let set = LoggedSet(exercise: exercise, reps: reps, weight: weight)
        set.isPersonalRecord = isRecord
        context.insert(set)
        return set
    }
}
