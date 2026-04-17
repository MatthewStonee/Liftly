import SwiftUI
import SwiftData
import OSLog

@main
struct RackApp: App {
    private static let logger = Logger(subsystem: "com.matthewstone.rack", category: "Persistence")
    let container: ModelContainer

    init() {
        let schema = Schema([
            Program.self,
            WorkoutTemplate.self,
            PlannedExercise.self,
            Exercise.self,
            WorkoutSession.self,
            LoggedSet.self
        ])
        let cloudConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        let localConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            container = try ModelContainer(for: schema, configurations: cloudConfiguration)
            Self.logger.notice("Loaded CloudKit-backed SwiftData store.")
        } catch {
            Self.logger.error("Failed to load CloudKit-backed SwiftData store: \(String(describing: error), privacy: .public)")

            do {
                container = try ModelContainer(for: schema, configurations: localConfiguration)
                Self.logger.warning("Fell back to local-only SwiftData store. iCloud sync is disabled for this launch.")
            } catch {
                Self.logger.error("Failed to load local SwiftData store: \(String(describing: error), privacy: .public)")

                // Store is corrupted (e.g. failed CloudKit migration). Wipe and start fresh.
                let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
                try? FileManager.default.removeItem(at: storeURL)
                container = try! ModelContainer(for: schema, configurations: localConfiguration)
                Self.logger.warning("Recreated local-only SwiftData store after removing the existing store. iCloud sync is disabled for this launch.")
            }
        }
        ExerciseLibrary.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .preferredColorScheme(.dark)
        }
    }
}
