import SwiftUI
import SwiftData

@Observable
final class ProgressViewModel {
    var selectedExercise: Exercise?
    var timeRange: TimeRange = .threeMonths

    enum TimeRange: String, CaseIterable {
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case allTime = "All"

        var days: Int? {
            switch self {
            case .oneMonth: return 30
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .oneYear: return 365
            case .allTime: return nil
            }
        }
    }

    func filteredSets(_ sets: [LoggedSet], for timeRange: TimeRange) -> [LoggedSet] {
        guard let days = timeRange.days else { return sets }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sets.filter { $0.completedAt >= cutoff }
    }

    func maxWeightPoints(for sets: [LoggedSet]) -> [(Date, Double)] {
        let grouped = Dictionary(grouping: sets) { set in
            Calendar.current.startOfDay(for: set.completedAt)
        }
        return grouped.map { (date, daySets) in
            (date, daySets.map(\.weight).max() ?? 0)
        }
        .sorted { $0.0 < $1.0 }
    }

    func personalRecord(for sets: [LoggedSet]) -> LoggedSet? {
        sets.max(by: { $0.weight < $1.weight })
    }

    func totalVolume(for sets: [LoggedSet]) -> Double {
        sets.reduce(0) { $0 + $1.volume }
    }

    // MARK: - PR Detection

    /// Checks if a weight beats the current PR for an exercise at a given rep count.
    func isNewPersonalRecord(exercise: Exercise, weight: Double, reps: Int, excluding: LoggedSet? = nil) -> Bool {
        let previousMax = exercise.loggedSetsList
            .filter { $0.reps == reps && $0.id != excluding?.id }
            .map(\.weight)
            .max() ?? 0
        return weight > 0 && weight > previousMax
    }

    /// Clears the PR flag on all sets for an exercise at a given rep count.
    func clearPR(exercise: Exercise, reps: Int, excluding: LoggedSet? = nil) {
        for set in exercise.loggedSetsList where set.reps == reps && set.isPersonalRecord && set.id != excluding?.id {
            set.isPersonalRecord = false
        }
    }

    /// Promotes the heaviest set at a given rep count to PR after a deletion.
    func promotePR(exercise: Exercise, reps: Int, excluding: LoggedSet? = nil) {
        if let newPR = exercise.loggedSetsList
            .filter({ $0.reps == reps && $0.id != excluding?.id })
            .max(by: { $0.weight < $1.weight }), newPR.weight > 0 {
            newPR.isPersonalRecord = true
        }
    }

    /// One-time backfill: marks the correct PR set per exercise per rep count.
    func backfillPersonalRecords(exercises: [Exercise]) {
        guard !UserDefaults.standard.bool(forKey: "prBackfillComplete") else { return }
        for exercise in exercises {
            // Clear all existing PR flags
            for set in exercise.loggedSetsList { set.isPersonalRecord = false }
            // Group by rep count, mark max weight in each group
            let grouped = Dictionary(grouping: exercise.loggedSetsList) { $0.reps }
            for (_, sets) in grouped {
                if let best = sets.max(by: { $0.weight < $1.weight }), best.weight > 0 {
                    best.isPersonalRecord = true
                }
            }
        }
        UserDefaults.standard.set(true, forKey: "prBackfillComplete")
    }
}
