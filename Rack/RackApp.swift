import SwiftUI
import SwiftData

@main
struct RackApp: App {
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

        if let ck = try? ModelContainer(for: schema, configurations: cloudConfiguration) {
            container = ck
        } else if let local = try? ModelContainer(for: schema, configurations: localConfiguration) {
            container = local
        } else {
            // Store is corrupted (e.g. failed CloudKit migration). Wipe and start fresh.
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: storeURL)
            container = try! ModelContainer(for: schema, configurations: localConfiguration)
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
