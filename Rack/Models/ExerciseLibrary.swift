import SwiftData
import Foundation
import OSLog

enum ExerciseLibrary {
    private static let seededKey = "exerciseLibrarySeeded"
    private static let logger = Logger(subsystem: "com.matthewstone.liftly", category: "ExerciseLibrary")

    /// Performs the minimum work required to make the library available on first launch.
    /// Relationship repair runs later in `ExerciseLibraryMaintenanceActor`.
    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        do {
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            var identities = Set(exercises.map { ExerciseIdentity(exercise: $0) })
            var didInsert = false

            for entry in seed {
                let identity = ExerciseIdentity(entry: entry)
                guard identities.insert(identity).inserted else { continue }

                context.insert(
                    Exercise(
                        name: entry.name,
                        muscleGroup: entry.muscleGroup,
                        equipment: entry.equipment
                    )
                )
                didInsert = true
            }

            if didInsert {
                try context.save()
            }

            UserDefaults.standard.set(true, forKey: seededKey)
            logger.notice("Seeded the exercise library.")
        } catch {
            context.rollback()
            logger.error("Failed to seed the exercise library: \(String(describing: error), privacy: .public)")
        }
    }

    static func resetSeedState() {
        UserDefaults.standard.removeObject(forKey: seededKey)
    }

    fileprivate static func reconcile(context: ModelContext) throws -> Bool {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var exercisesByIdentity = Dictionary(grouping: exercises) {
            ExerciseIdentity(exercise: $0)
        }
        var didChange = false

        for entry in seed {
            let identity = ExerciseIdentity(entry: entry)
            guard exercisesByIdentity[identity] == nil else { continue }

            let exercise = Exercise(
                name: entry.name,
                muscleGroup: entry.muscleGroup,
                equipment: entry.equipment
            )
            context.insert(exercise)
            exercisesByIdentity[identity] = [exercise]
            didChange = true
        }

        for entry in seed {
            let identity = ExerciseIdentity(entry: entry)
            guard let matches = exercisesByIdentity[identity], !matches.isEmpty else { continue }

            var plannedExercises: [PlannedExercise] = []
            var loggedSets: [LoggedSet] = []
            var referenceCounts: [UUID: Int] = [:]

            // Avoid faulting relationship collections for the normal, duplicate-free path.
            if matches.count > 1 {
                for exercise in matches {
                    let exercisePlannedExercises = exercise.plannedExercisesList
                    let exerciseLoggedSets = exercise.loggedSetsList
                    plannedExercises.append(contentsOf: exercisePlannedExercises)
                    loggedSets.append(contentsOf: exerciseLoggedSets)
                    referenceCounts[exercise.id] =
                        exercisePlannedExercises.count + exerciseLoggedSets.count
                }
            }

            let canonical = matches.count == 1
                ? matches[0]
                : canonicalExercise(from: matches, referenceCounts: referenceCounts)

            if canonical.name != entry.name {
                canonical.name = entry.name
                didChange = true
            }
            if canonical.muscleGroup != entry.muscleGroup {
                canonical.muscleGroup = entry.muscleGroup
                didChange = true
            }
            if canonical.equipment != entry.equipment {
                canonical.equipment = entry.equipment
                didChange = true
            }

            let duplicateIDs = Set(matches.lazy.map(\.id)).subtracting([canonical.id])
            guard !duplicateIDs.isEmpty else { continue }

            for plannedExercise in plannedExercises {
                if let exerciseID = plannedExercise.exercise?.id,
                   duplicateIDs.contains(exerciseID) {
                    plannedExercise.exercise = canonical
                    didChange = true
                }
            }

            for loggedSet in loggedSets {
                if let exerciseID = loggedSet.exercise?.id,
                   duplicateIDs.contains(exerciseID) {
                    loggedSet.exercise = canonical
                    didChange = true
                }
            }

            if recalculatePersonalRecords(for: canonical, loggedSets: loggedSets) {
                didChange = true
            }

            for duplicate in matches where duplicate.id != canonical.id {
                context.delete(duplicate)
                didChange = true
            }
        }

        return didChange
    }

    fileprivate static func normalizeInvalidRepTargets(context: ModelContext) throws -> Bool {
        let exactType = PlannedRepTargetType.exact.rawValue
        let rangeType = PlannedRepTargetType.range.rawValue
        let failureType = PlannedRepTargetType.failure.rawValue
        let invalidRepTarget = #Predicate<PlannedExercise> { plannedExercise in
            plannedExercise.reps < 1 ||
                plannedExercise.repRangeLowerBound < 1 ||
                plannedExercise.repRangeUpperBound < plannedExercise.repRangeLowerBound ||
                (
                    plannedExercise.repTargetTypeRaw != exactType &&
                        plannedExercise.repTargetTypeRaw != rangeType &&
                        plannedExercise.repTargetTypeRaw != failureType
                )
        }
        let descriptor = FetchDescriptor<PlannedExercise>(predicate: invalidRepTarget)
        let plannedExercises = try context.fetch(descriptor)

        var didChange = false
        for plannedExercise in plannedExercises {
            let normalizedReps = max(1, plannedExercise.reps)
            if plannedExercise.reps != normalizedReps {
                plannedExercise.reps = normalizedReps
                didChange = true
            }

            let normalizedLowerBound = max(1, plannedExercise.repRangeLowerBound)
            if plannedExercise.repRangeLowerBound != normalizedLowerBound {
                plannedExercise.repRangeLowerBound = normalizedLowerBound
                didChange = true
            }

            let normalizedUpperBound = max(normalizedLowerBound, plannedExercise.repRangeUpperBound)
            if plannedExercise.repRangeUpperBound != normalizedUpperBound {
                plannedExercise.repRangeUpperBound = normalizedUpperBound
                didChange = true
            }

            if PlannedRepTargetType(rawValue: plannedExercise.repTargetTypeRaw) == nil {
                plannedExercise.repTargetTypeRaw = PlannedRepTargetType.exact.rawValue
                didChange = true
            }
        }

        return didChange
    }

    fileprivate static func markSeeded() {
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func canonicalExercise(
        from exercises: [Exercise],
        referenceCounts: [UUID: Int]
    ) -> Exercise {
        exercises.max { lhs, rhs in
            let lhsReferences = referenceCounts[lhs.id, default: 0]
            let rhsReferences = referenceCounts[rhs.id, default: 0]
            if lhsReferences != rhsReferences {
                return lhsReferences < rhsReferences
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }!
    }

    private static func recalculatePersonalRecords(for exercise: Exercise, loggedSets: [LoggedSet]) -> Bool {
        let exerciseSets = loggedSets.filter { $0.exercise?.id == exercise.id }
        var didChange = false

        let groupedByReps = Dictionary(grouping: exerciseSets) { $0.reps }
        for sets in groupedByReps.values {
            let best = sets.reduce(nil as LoggedSet?) { currentBest, candidate in
                guard candidate.weight > 0 else { return currentBest }
                guard let currentBest else { return candidate }
                return isPreferredPersonalRecordCandidate(candidate, over: currentBest)
                    ? candidate
                    : currentBest
            }

            for set in sets {
                let shouldBePersonalRecord = set.id == best?.id
                guard set.isPersonalRecord != shouldBePersonalRecord else { continue }
                set.isPersonalRecord = shouldBePersonalRecord
                didChange = true
            }
        }

        return didChange
    }

    private struct ExerciseIdentity: Hashable {
        let name: String
        let muscleGroup: MuscleGroup
        let equipment: Equipment

        init(name: String, muscleGroup: MuscleGroup, equipment: Equipment) {
            self.name = ExerciseLibrary.normalizedName(name)
            self.muscleGroup = muscleGroup
            self.equipment = equipment
        }

        init(entry: (name: String, muscleGroup: MuscleGroup, equipment: Equipment)) {
            self.init(name: entry.name, muscleGroup: entry.muscleGroup, equipment: entry.equipment)
        }

        init(exercise: Exercise) {
            self.init(name: exercise.name, muscleGroup: exercise.muscleGroup, equipment: exercise.equipment)
        }
    }

    static let seed: [(name: String, muscleGroup: MuscleGroup, equipment: Equipment)] = [
        // MARK: Chest
        ("Bench Press",             .chest,      .barbell),
        ("Incline Bench Press",     .chest,      .barbell),
        ("Decline Bench Press",     .chest,      .barbell),
        ("Dumbbell Fly",            .chest,      .dumbbell),
        ("Incline Dumbbell Press",  .chest,      .dumbbell),
        ("Push-Up",                 .chest,      .bodyweight),
        ("Cable Fly",               .chest,      .cable),
        ("Chest Press Machine",     .chest,      .machine),

        // MARK: Back
        ("Deadlift",                .back,       .barbell),
        ("Barbell Row",             .back,       .barbell),
        ("T-Bar Row",               .back,       .barbell),
        ("Pull-Up",                 .back,       .bodyweight),
        ("Lat Pulldown",            .back,       .cable),
        ("Seated Cable Row",        .back,       .cable),
        ("Face Pull",               .back,       .cable),
        ("Dumbbell Row",            .back,       .dumbbell),

        // MARK: Shoulders
        ("Overhead Press",          .shoulders,  .barbell),
        ("Upright Row",             .shoulders,  .barbell),
        ("Dumbbell Shoulder Press", .shoulders,  .dumbbell),
        ("Lateral Raise",           .shoulders,  .dumbbell),
        ("Front Raise",             .shoulders,  .dumbbell),
        ("Arnold Press",            .shoulders,  .dumbbell),
        ("Cable Lateral Raise",     .shoulders,  .cable),
        ("Machine Shoulder Press",  .shoulders,  .machine),

        // MARK: Biceps
        ("Barbell Curl",            .biceps,     .barbell),
        ("Dumbbell Curl",           .biceps,     .dumbbell),
        ("Hammer Curl",             .biceps,     .dumbbell),
        ("Incline Dumbbell Curl",   .biceps,     .dumbbell),
        ("Concentration Curl",      .biceps,     .dumbbell),
        ("Cable Curl",              .biceps,     .cable),
        ("Preacher Curl",           .biceps,     .machine),

        // MARK: Triceps
        ("Close-Grip Bench Press",          .triceps,    .barbell),
        ("Skull Crusher",                   .triceps,    .barbell),
        ("Tricep Dip",                      .triceps,    .bodyweight),
        ("Diamond Push-Up",                 .triceps,    .bodyweight),
        ("Tricep Pushdown",                 .triceps,    .cable),
        ("Cable Overhead Tricep Extension", .triceps,    .cable),
        ("Overhead Tricep Extension",       .triceps,    .dumbbell),

        // MARK: Quads
        ("Squat",                   .quads,      .barbell),
        ("Front Squat",             .quads,      .barbell),
        ("Lunge",                   .quads,      .dumbbell),
        ("Bulgarian Split Squat",   .quads,      .dumbbell),
        ("Goblet Squat",            .quads,      .kettlebell),
        ("Leg Press",               .quads,      .machine),
        ("Leg Extension",           .quads,      .machine),
        ("Hack Squat",              .quads,      .machine),

        // MARK: Hamstrings
        ("Romanian Deadlift",           .hamstrings, .barbell),
        ("Stiff-Leg Deadlift",          .hamstrings, .barbell),
        ("Good Morning",                .hamstrings, .barbell),
        ("Dumbbell Romanian Deadlift",  .hamstrings, .dumbbell),
        ("Nordic Hamstring Curl",       .hamstrings, .bodyweight),
        ("Leg Curl",                    .hamstrings, .machine),

        // MARK: Glutes
        ("Hip Thrust",              .glutes,     .barbell),
        ("Sumo Deadlift",           .glutes,     .barbell),
        ("Step-Up",                 .glutes,     .dumbbell),
        ("Sumo Squat",              .glutes,     .dumbbell),
        ("Cable Kickback",          .glutes,     .cable),
        ("Glute Bridge",            .glutes,     .bodyweight),

        // MARK: Calves
        ("Standing Calf Raise",     .calves,     .machine),
        ("Seated Calf Raise",       .calves,     .machine),
        ("Donkey Calf Raise",       .calves,     .bodyweight),
        ("Single-Leg Calf Raise",   .calves,     .bodyweight),

        // MARK: Core
        ("Plank",                   .core,       .bodyweight),
        ("Side Plank",              .core,       .bodyweight),
        ("Crunch",                  .core,       .bodyweight),
        ("Bicycle Crunch",          .core,       .bodyweight),
        ("Leg Raise",               .core,       .bodyweight),
        ("Hanging Knee Raise",      .core,       .bodyweight),
        ("Dead Bug",                .core,       .bodyweight),
        ("Russian Twist",           .core,       .dumbbell),
        ("Cable Crunch",            .core,       .cable),
        ("Ab Rollout",              .core,       .other),

        // MARK: Full Body
        ("Clean and Jerk",          .fullBody,   .barbell),
        ("Snatch",                  .fullBody,   .barbell),
        ("Thruster",                .fullBody,   .barbell),
        ("Burpee",                  .fullBody,   .bodyweight),
        ("Kettlebell Swing",        .fullBody,   .kettlebell),
        ("Turkish Get-Up",          .fullBody,   .kettlebell),
        ("Man Maker",               .fullBody,   .dumbbell),
    ]
}

@ModelActor
actor ExerciseLibraryMaintenanceActor {
    private static let logger = Logger(
        subsystem: "com.matthewstone.liftly",
        category: "StartupMaintenance"
    )

    func performMaintenance() -> Bool {
        do {
            let didReconcileExercises = try ExerciseLibrary.reconcile(context: modelContext)
            let didNormalizeRepTargets = try ExerciseLibrary.normalizeInvalidRepTargets(context: modelContext)

            if didReconcileExercises || didNormalizeRepTargets {
                try modelContext.save()
                Self.logger.notice("Completed deferred exercise-library and rep-target maintenance.")
            }

            ExerciseLibrary.markSeeded()
            return true
        } catch {
            modelContext.rollback()
            Self.logger.error("Deferred startup maintenance failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
