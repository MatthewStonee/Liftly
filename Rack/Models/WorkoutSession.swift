import SwiftData
import Foundation

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var completedAt: Date?
    var notes: String = ""

    var workoutTemplate: WorkoutTemplate?

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.session)
    var loggedSets: [LoggedSet]? = []

    init(workoutTemplate: WorkoutTemplate? = nil) {
        self.id = UUID()
        self.startedAt = Date()
        self.completedAt = nil
        self.notes = ""
        self.workoutTemplate = workoutTemplate
    }

    var loggedSetsList: [LoggedSet] {
        loggedSets ?? []
    }

    var duration: TimeInterval? {
        guard let completed = completedAt else { return nil }
        return completed.timeIntervalSince(startedAt)
    }

    var formattedDuration: String {
        guard let duration else { return "In Progress" }
        let minutes = Int(duration) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)m"
    }

    var totalVolume: Double {
        loggedSetsList.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    var setsByExercise: [Exercise: [LoggedSet]] {
        Dictionary(grouping: loggedSetsList.compactMap { $0.exercise != nil ? $0 : nil }) {
            $0.exercise!
        }
    }
}

@Model
final class LoggedSet {
    var id: UUID = UUID()
    var reps: Int = 0
    var weight: Double = 0
    var completedAt: Date = Date()
    var isPersonalRecord: Bool = false

    var exercise: Exercise?
    var session: WorkoutSession?

    init(exercise: Exercise, reps: Int, weight: Double) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.completedAt = Date()
        self.isPersonalRecord = false
        self.exercise = exercise
    }

    var volume: Double {
        weight * Double(reps)
    }
}
