import SwiftData
import Foundation

@Model
final class Program {
    var id: UUID = UUID()
    var name: String = ""
    var programDescription: String = ""
    var createdAt: Date = Date()
    var isActive: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \WorkoutTemplate.program)
    var workouts: [WorkoutTemplate]? = []

    init(name: String, description: String = "") {
        self.id = UUID()
        self.name = name
        self.programDescription = description
        self.createdAt = Date()
        self.isActive = false
    }

    var workoutsList: [WorkoutTemplate] {
        workouts ?? []
    }

    var sortedWorkouts: [WorkoutTemplate] {
        workoutsList.sorted { $0.orderIndex < $1.orderIndex }
    }

    var exerciseCount: Int {
        workoutsList.reduce(0) { $0 + $1.plannedExercisesList.count }
    }
}

@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var orderIndex: Int = 0
    var createdAt: Date = Date()

    var program: Program?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.workoutTemplate)
    var plannedExercises: [PlannedExercise]? = []

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.workoutTemplate)
    var sessions: [WorkoutSession]? = []

    init(name: String, orderIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.createdAt = Date()
    }

    var plannedExercisesList: [PlannedExercise] {
        plannedExercises ?? []
    }

    var sortedExercises: [PlannedExercise] {
        plannedExercisesList.sorted { $0.orderIndex < $1.orderIndex }
    }
}

@Model
final class PlannedExercise {
    var id: UUID = UUID()
    var sets: Int = 3
    var reps: Int = 8
    var targetWeight: Double?
    var orderIndex: Int = 0

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
