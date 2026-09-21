import Foundation
import SwiftData
@testable import Rack

struct InjectedSaveFailure: Error {}

/// Controls whether command saves fail, and counts save attempts.
@MainActor
final class SaveSwitch {
    var isFailing: Bool
    private(set) var saveAttempts = 0

    init(isFailing: Bool = false) {
        self.isFailing = isFailing
    }

    var runner: PersistenceCommandRunner {
        PersistenceCommandRunner { [self] context in
            saveAttempts += 1
            if isFailing {
                throw InjectedSaveFailure()
            }
            try context.save()
        }
    }
}

/// Counts the metrics loads a `ProgressViewModel` makes.
@MainActor
final class MetricsLoadCounter {
    private(set) var count = 0

    var loader: ProgressViewModel.MetricsLoader {
        { [self] exerciseID, context in
            count += 1
            return try ProgressViewModel.fetchExerciseSets(exerciseID, in: context)
        }
    }
}

@MainActor
enum TestStore {
    /// An isolated in-memory store configured like the app's main context.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            UUID().uuidString,
            schema: AppDataStore.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: AppDataStore.schema, configurations: configuration)
        container.mainContext.autosaveEnabled = false
        return container
    }

    static func makeOnDiskContainer(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: AppDataStore.schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: AppDataStore.schema, configurations: configuration)
        container.mainContext.autosaveEnabled = false
        return container
    }

    static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LiftlyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Fetches through a fresh context, so results reflect only what was saved.
    static func savedModels<Model: PersistentModel>(
        _ type: Model.Type,
        in container: ModelContainer
    ) throws -> [Model] {
        try ModelContext(container).fetch(FetchDescriptor<Model>())
    }
}

@MainActor
enum Fixtures {
    static func savedExercise(
        in context: ModelContext,
        name: String = "Bench Press",
        equipment: Equipment = .barbell
    ) throws -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: .chest, equipment: equipment)
        context.insert(exercise)
        try context.save()
        return exercise
    }

    static func savedSet(
        for exercise: Exercise,
        reps: Int,
        weight: Double,
        daysAgo: Int,
        isPersonalRecord: Bool,
        in context: ModelContext
    ) throws -> LoggedSet {
        let set = LoggedSet(exercise: exercise, reps: reps, weight: weight)
        set.completedAt = Date.now.addingTimeInterval(-Double(daysAgo) * 86_400)
        set.isPersonalRecord = isPersonalRecord
        context.insert(set)
        try context.save()
        return set
    }

    static func savedProgram(
        in context: ModelContext,
        name: String = "Push Pull Legs",
        isActive: Bool = false,
        workoutNames: [String] = []
    ) throws -> Program {
        let program = Program(name: name)
        program.isActive = isActive
        context.insert(program)
        for (index, workoutName) in workoutNames.enumerated() {
            let workout = WorkoutTemplate(name: workoutName, orderIndex: index)
            workout.program = program
            context.insert(workout)
        }
        try context.save()
        return program
    }
}

extension AppDataStore.Phase {
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
