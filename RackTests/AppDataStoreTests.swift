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
