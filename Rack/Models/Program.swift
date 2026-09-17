import SwiftData
import Foundation

enum PlannedRepTargetType: String, Codable, CaseIterable {
    case exact
    case range
    case failure

    var title: String {
        switch self {
        case .exact:
            return "Exact"
        case .range:
            return "Range"
        case .failure:
            return "Failure"
        }
    }

    var settingsPreview: String {
        switch self {
        case .exact:
            return "\(PlannedRepTargetDefaults.exactReps) reps"
        case .range:
            return "\(PlannedRepTargetDefaults.rangeLowerBound)-\(PlannedRepTargetDefaults.rangeUpperBound) reps"
        case .failure:
            return "To failure"
        }
    }
}

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
        SiblingOrder.workouts(workoutsList)
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
        SiblingOrder.exercises(plannedExercisesList)
    }
}

@Model
final class PlannedExercise {
    var id: UUID = UUID()
    var sets: Int = 3
    var reps: Int = 8
    var repTargetTypeRaw: String = PlannedRepTargetType.exact.rawValue
    var repRangeLowerBound: Int = PlannedRepTargetDefaults.rangeLowerBound
    var repRangeUpperBound: Int = PlannedRepTargetDefaults.rangeUpperBound
    var targetWeight: Double?
    var orderIndex: Int = 0

    var exercise: Exercise?
    var workoutTemplate: WorkoutTemplate?

    init(
        exercise: Exercise,
        sets: Int = 3,
        reps: Int = PlannedRepTargetDefaults.exactReps,
        repTargetType: PlannedRepTargetType = .exact,
        repRangeLowerBound: Int = PlannedRepTargetDefaults.rangeLowerBound,
        repRangeUpperBound: Int = PlannedRepTargetDefaults.rangeUpperBound,
        targetWeight: Double? = nil,
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.sets = sets
        self.reps = reps
        self.repTargetTypeRaw = repTargetType.rawValue
        self.repRangeLowerBound = repRangeLowerBound
        self.repRangeUpperBound = repRangeUpperBound
        self.targetWeight = targetWeight
        self.orderIndex = orderIndex
        self.exercise = exercise
        normalizeRepTarget()
    }

    var repTargetType: PlannedRepTargetType {
        get { PlannedRepTargetType(rawValue: repTargetTypeRaw) ?? .exact }
        set { repTargetTypeRaw = newValue.rawValue }
    }

    var exactRepTarget: Int {
        max(1, reps)
    }

    var repRange: ClosedRange<Int> {
        let lowerBound = max(1, repRangeLowerBound)
        let upperBound = max(lowerBound, repRangeUpperBound)
        return lowerBound...upperBound
    }

    func configureRepTarget(
        _ type: PlannedRepTargetType,
        exactReps: Int? = nil,
        rangeLowerBound: Int? = nil,
        rangeUpperBound: Int? = nil
    ) {
        repTargetType = type
        if let exactReps {
            reps = max(1, exactReps)
        }
        if let rangeLowerBound {
            repRangeLowerBound = max(1, rangeLowerBound)
        }
        if let rangeUpperBound {
            repRangeUpperBound = max(1, rangeUpperBound)
        }
        normalizeRepTarget()
    }

    func normalizeRepTarget() {
        reps = max(1, reps)
        repRangeLowerBound = max(1, repRangeLowerBound)
        repRangeUpperBound = max(repRangeLowerBound, repRangeUpperBound)
        if PlannedRepTargetType(rawValue: repTargetTypeRaw) == nil {
            repTargetTypeRaw = PlannedRepTargetType.exact.rawValue
        }
    }
}
