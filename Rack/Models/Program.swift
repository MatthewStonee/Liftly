import SwiftData
import Foundation

@Model
final class Program {
    var id: UUID
    var name: String
    var programDescription: String
    var createdAt: Date
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplate.program)
    var workouts: [WorkoutTemplate] = []

    init(name: String, description: String = "") {
        self.id = UUID()
        self.name = name
        self.programDescription = description
        self.createdAt = Date()
        self.isActive = false
    }

    var sortedWorkouts: [WorkoutTemplate] {
        workouts.sorted { $0.orderIndex < $1.orderIndex }
    }
}

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var orderIndex: Int
    var createdAt: Date

    var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.workoutTemplate)
    var plannedExercises: [PlannedExercise] = []

    @Relationship(deleteRule: .nullify)
    var sessions: [WorkoutSession] = []

    init(name: String, orderIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.createdAt = Date()
    }

    var sortedExercises: [PlannedExercise] {
        plannedExercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}

@Model
final class PlannedExercise {
    var id: UUID
    var sets: Int
    var reps: Int
    var targetWeight: Double?
    var orderIndex: Int

    var exercise: Exercise?
    var workoutTemplate: WorkoutTemplate?

    init(exercise: Exercise, sets: Int = 3, reps: Int = 8, targetWeight: Double? = nil, orderIndex: Int = 0) {
        self.id = UUID()
        self.sets = sets
        self.reps = reps
        self.targetWeight = targetWeight
        self.orderIndex = orderIndex
        self.exercise = exercise
    }
}
