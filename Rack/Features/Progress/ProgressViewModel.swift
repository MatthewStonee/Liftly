import SwiftUI
import SwiftData

struct ExerciseProgressSummary {
    var prWeight: Double = 0
    var setCount: Int = 0
}

struct ProgressOverview {
    var programExercises: [Exercise] = []
    var summariesByExerciseID: [UUID: ExerciseProgressSummary] = [:]
    var weeklyVolume: Double = 0
}

struct ExerciseProgressMetrics {
    var sortedSetsAscending: [LoggedSet] = []
    var sortedSetsDescending: [LoggedSet] = []
    var chartPoints: [(Date, Double)] = []
    var personalRecord: LoggedSet?
    var totalVolume: Double = 0
    var recentSets: [LoggedSet] = []
    var hasFilteredSets = false
}

@Observable
final class ProgressViewModel {
    var selectedExercise: Exercise?
    var timeRange: TimeRange = .threeMonths
    var overview = ProgressOverview()
    var exerciseMetrics = ExerciseProgressMetrics()

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

    func refreshOverview(
        plannedExercises: [PlannedExercise],
        loggedSets: [LoggedSet],
        now: Date = Date()
    ) {
        let programExercises = plannedExercises
            .compactMap(\.exercise)
            .reduce(into: [UUID: Exercise]()) { exercisesByID, exercise in
                exercisesByID[exercise.id] = exercise
            }
            .values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var setsByExerciseID: [UUID: [LoggedSet]] = [:]
        for set in loggedSets {
            guard let exerciseID = set.exercise?.id else { continue }
            setsByExerciseID[exerciseID, default: []].append(set)
        }
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        var summaries: [UUID: ExerciseProgressSummary] = [:]
        var weeklyVolume: Double = 0

        for exercise in programExercises {
            let exerciseSets = setsByExerciseID[exercise.id] ?? []
            summaries[exercise.id] = ExerciseProgressSummary(
                prWeight: exerciseSets.map(\.weight).max() ?? 0,
                setCount: exerciseSets.count
            )

            for set in exerciseSets where set.completedAt >= oneWeekAgo {
                weeklyVolume += set.volume
            }
        }

        overview = ProgressOverview(
            programExercises: programExercises,
            summariesByExerciseID: summaries,
            weeklyVolume: weeklyVolume
        )
    }

    func refreshExerciseMetrics(with sets: [LoggedSet]) {
        let sortedSetsAscending = sets.sorted { $0.completedAt < $1.completedAt }
        let sortedSetsDescending = sortedSetsAscending.reversed()
        let filteredSetsAscending = filteredSets(sortedSetsAscending, for: timeRange)
        let filteredSetsDescending = filteredSetsAscending.reversed()

        exerciseMetrics = ExerciseProgressMetrics(
            sortedSetsAscending: sortedSetsAscending,
            sortedSetsDescending: Array(sortedSetsDescending),
            chartPoints: maxWeightPoints(for: filteredSetsAscending),
            personalRecord: personalRecord(for: sortedSetsAscending),
            totalVolume: totalVolume(for: filteredSetsAscending),
            recentSets: Array(filteredSetsDescending.prefix(20)),
            hasFilteredSets: !filteredSetsAscending.isEmpty
        )
    }

    func updateTimeRange(_ range: TimeRange, sets: [LoggedSet]) {
        timeRange = range
        refreshExerciseMetrics(with: sets)
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

}

@ModelActor
actor PersonalRecordBackfillActor {
    /// One-time backfill: marks the correct PR set per exercise per rep count.
    func backfillIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "prBackfillComplete") else { return }
        let descriptor = FetchDescriptor<Exercise>()

        guard let exercises = try? modelContext.fetch(descriptor) else { return }

        for exercise in exercises {
            for set in exercise.loggedSetsList { set.isPersonalRecord = false }

            let grouped = Dictionary(grouping: exercise.loggedSetsList) { $0.reps }
            for (_, sets) in grouped {
                if let best = sets.max(by: { $0.weight < $1.weight }), best.weight > 0 {
                    best.isPersonalRecord = true
                }
            }
        }

        guard (try? modelContext.save()) != nil else { return }
        UserDefaults.standard.set(true, forKey: "prBackfillComplete")
    }
}
