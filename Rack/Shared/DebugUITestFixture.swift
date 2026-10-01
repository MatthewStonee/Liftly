#if DEBUG
import Foundation
import SwiftData

/// A unique, local-only store for each UI test. Relaunches reuse the same fixture ID.
@MainActor
enum DebugUITestFixture {
    struct Configuration {
        let name: String
        let id: String
    }

    enum FixtureError: Error {
        case invalidConfiguration
        case missingExerciseSeed
    }

    /// Reads `-LiftlyUITestFixture <reorder|history|firstRun|liveActivity> <id>`.
    static var current: Configuration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-LiftlyUITestFixture"),
              arguments.indices.contains(index + 2) else { return nil }
        let name = arguments[index + 1]
        let id = arguments[index + 2]
        guard ["reorder", "history", "firstRun", "liveActivity"].contains(name),
              !id.isEmpty,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).contains($0) })
        else { return nil }
        return Configuration(name: name, id: id)
    }

    /// Allows slower UI automation to finish its draft before the delayed failure.
    /// Only isolated fixtures can override the production four-second interval.
    static var undoInterval: TimeInterval {
        guard current != nil else { return 4 }
        let seconds = UserDefaults.standard.double(forKey: "LiftlyUITestUndoSeconds")
        return seconds.isFinite && (4...30).contains(seconds) ? seconds : 4
    }

    static func open(_ fixture: Configuration) throws -> ModelContainer {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { throw FixtureError.invalidConfiguration }
        let directory = support.appending(path: "LiftlyUITestFixtures", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appending(path: "\(fixture.id).store")
        let configuration = ModelConfiguration(
            schema: AppDataStore.schema, url: storeURL, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: AppDataStore.schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false

        let seededKey = "LiftlyUITestFixtureSeeded-\(fixture.id)"
        if !UserDefaults.standard.bool(forKey: seededKey) {
            try seed(fixture.name, in: context)
            try context.save()
            UserDefaults.standard.set(true, forKey: seededKey)
        }
        return container
    }

    private static func seed(_ name: String, in context: ModelContext) throws {
        guard name != "firstRun" else {
            // A new user's store: the exercise library and no programs.
            for entry in ExerciseLibrary.seed {
                context.insert(Exercise(
                    name: entry.name, muscleGroup: entry.muscleGroup, equipment: entry.equipment
                ))
            }
            return
        }

        let program = Program(name: name == "liveActivity" ? "UI Live Activity" : name == "reorder" ? "UI Reorder" : "UI History")
        program.isActive = true
        context.insert(program)

        let dayNames = name == "reorder" ? ["Day A", "Day B", "Day C"] : name == "liveActivity" ? ["Push Day", "Other Day", "Empty Day"] : ["Day A"]
        var days: [WorkoutTemplate] = []
        for (index, dayName) in dayNames.enumerated() {
            let day = WorkoutTemplate(name: dayName, orderIndex: index)
            if name == "liveActivity" {
                day.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
            }
            day.program = program
            context.insert(day)
            days.append(day)
        }

        if name == "reorder" {
            // Day A gets exercises so their list can be reordered too.
            let exercises = try insertLibrary(in: context)
            guard exercises.count >= 3, let day = days.first else { throw FixtureError.missingExerciseSeed }
            for (index, exercise) in exercises.prefix(3).enumerated() {
                let planned = PlannedExercise(exercise: exercise, orderIndex: index)
                planned.workoutTemplate = day
                context.insert(planned)
            }
            return
        }

        if name == "liveActivity" {
            let exercises = try insertLibrary(in: context)
            guard exercises.count >= 5 else { throw FixtureError.missingExerciseSeed }
            for day in days.prefix(2) {
                for (index, exercise) in exercises.prefix(5).enumerated() {
                    let planned = PlannedExercise(
                        exercise: exercise, sets: 3, reps: 8,
                        repTargetType: index == 1 ? .range : index == 4 ? .failure : .exact,
                        targetWeight: index == 4 ? nil : 45.125,
                        orderIndex: index
                    )
                    planned.workoutTemplate = day
                    context.insert(planned)
                }
            }
            return
        }
        guard name == "history" else { return }
        guard let entry = ExerciseLibrary.seed.first,
              let day = days.first else { throw FixtureError.missingExerciseSeed }
        let exercise = Exercise(
            name: entry.name, muscleGroup: entry.muscleGroup, equipment: entry.equipment
        )
        context.insert(exercise)
        let planned = PlannedExercise(exercise: exercise)
        planned.workoutTemplate = day
        context.insert(planned)

        for index in 0..<120 {
            let set = LoggedSet(exercise: exercise, reps: 5, weight: Double(120 - index))
            set.completedAt = Date.now.addingTimeInterval(-Double(index) * 86_400)
            set.isPersonalRecord = index == 0
            context.insert(set)
        }
    }

    /// Inserts the exercise library and returns it sorted by name.
    private static func insertLibrary(in context: ModelContext) throws -> [Exercise] {
        for entry in ExerciseLibrary.seed {
            context.insert(Exercise(name: entry.name, muscleGroup: entry.muscleGroup, equipment: entry.equipment))
        }
        return try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))
    }
}
#endif
