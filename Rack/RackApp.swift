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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Surface the error clearly instead of a silent white screen
            fatalError("SwiftData ModelContainer failed: \(error.localizedDescription)")
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
