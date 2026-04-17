import SwiftData
import Foundation
import SwiftUI

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var muscleGroup: MuscleGroup = MuscleGroup.chest
    var equipment: Equipment = Equipment.barbell
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \PlannedExercise.exercise)
    var plannedExercises: [PlannedExercise]? = []

    @Relationship(deleteRule: .nullify, inverse: \LoggedSet.exercise)
    var loggedSets: [LoggedSet]? = []

    init(name: String, muscleGroup: MuscleGroup, equipment: Equipment) {
        self.id = UUID()
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.createdAt = Date()
    }

    var plannedExercisesList: [PlannedExercise] {
        plannedExercises ?? []
    }

    var loggedSetsList: [LoggedSet] {
        loggedSets ?? []
    }
}

enum MuscleGroup: String, Codable, CaseIterable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case core = "Core"
    case fullBody = "Full Body"

    var color: Color {
        switch self {
        case .chest:      return Color(red: 0.95, green: 0.35, blue: 0.35)
        case .back:       return Color(red: 0.30, green: 0.65, blue: 0.95)
        case .shoulders:  return Color(red: 0.55, green: 0.40, blue: 0.95)
        case .biceps:     return Color(red: 0.25, green: 0.80, blue: 0.65)
        case .triceps:    return Color(red: 0.20, green: 0.70, blue: 0.55)
        case .quads:      return Color(red: 0.95, green: 0.65, blue: 0.20)
        case .hamstrings: return Color(red: 0.90, green: 0.50, blue: 0.20)
        case .glutes:     return Color(red: 0.85, green: 0.35, blue: 0.60)
        case .calves:     return Color(red: 0.95, green: 0.80, blue: 0.20)
        case .core:       return Color(red: 0.35, green: 0.80, blue: 0.35)
        case .fullBody:   return Color(red: 0.60, green: 0.60, blue: 0.65)
        }
    }

    var sfSymbol: String {
        switch self {
        case .chest: return "figure.strengthtraining.functional"
        case .back: return "figure.strengthtraining.traditional"
        case .shoulders: return "figure.arms.open"
        case .biceps, .triceps: return "dumbbell.fill"
        case .quads: return "figure.run"
        case .hamstrings: return "figure.gymnastics"
        case .glutes: return "figure.squats"
        case .calves: return "figure.step.training"
        case .core: return "figure.core.training"
        case .fullBody: return "figure.mixed.cardio"
        }
    }
}

enum Equipment: String, Codable, CaseIterable {
    case barbell = "Barbell"
    case dumbbell = "Dumbbell"
    case machine = "Machine"
    case cable = "Cable"
    case bodyweight = "Bodyweight"
    case kettlebell = "Kettlebell"
    case resistanceBand = "Resistance Band"
    case other = "Other"

    var sfSymbol: String {
        switch self {
        case .barbell: return "scalemass.fill"
        case .dumbbell: return "dumbbell.fill"
        case .machine: return "gearshape.2.fill"
        case .cable: return "arrow.up.and.down.and.arrow.left.and.right"
        case .bodyweight: return "figure.stand"
        case .kettlebell: return "circle.fill"
        case .resistanceBand: return "minus.circle"
        case .other: return "questionmark.circle"
        }
    }
}
