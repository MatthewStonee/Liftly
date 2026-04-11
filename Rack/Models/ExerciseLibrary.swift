import SwiftData
import Foundation

enum ExerciseLibrary {
    private static let seededKey = "exerciseLibrarySeeded"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        for entry in seed {
            let exercise = Exercise(name: entry.name, muscleGroup: entry.muscleGroup, equipment: entry.equipment)
            context.insert(exercise)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
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
