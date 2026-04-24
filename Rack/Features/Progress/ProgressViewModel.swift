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
    @ObservationIgnored private var personalRecordsByRep: [PersonalRecordKey: LoggedSet] = [:]

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
        rebuildPersonalRecordCache(from: sets)

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

    func refreshPersonalRecordCache(with sets: [LoggedSet]) {
        rebuildPersonalRecordCache(from: sets)
    }

    func assignPersonalRecordStatus(to set: LoggedSet, for exercise: Exercise) {
        let key = PersonalRecordKey(exerciseID: exercise.id, reps: set.reps)
        guard set.weight > 0 else {
            set.isPersonalRecord = false
            return
        }

        guard let currentPR = personalRecordsByRep[key] else {
            set.isPersonalRecord = true
            personalRecordsByRep[key] = set
            return
        }

        let isNewPersonalRecord = set.weight > currentPR.weight
        set.isPersonalRecord = isNewPersonalRecord

        if isNewPersonalRecord {
            currentPR.isPersonalRecord = false
            personalRecordsByRep[key] = set
        }
    }

    func recalculatePersonalRecord(
        for exercise: Exercise,
        reps: Int,
        in sets: [LoggedSet],
        excluding excludedSet: LoggedSet? = nil
    ) {
        let excludedID = excludedSet?.id
        let key = PersonalRecordKey(exerciseID: exercise.id, reps: reps)
        var bestSet: LoggedSet?

        for set in sets where set.exercise?.id == exercise.id && set.reps == reps && set.id != excludedID && set.weight > 0 {
            if bestSet == nil || set.weight > (bestSet?.weight ?? 0) {
                bestSet = set
            }
        }

        for set in sets where set.exercise?.id == exercise.id && set.reps == reps && set.id != excludedID {
            set.isPersonalRecord = set.id == bestSet?.id
        }

        excludedSet?.isPersonalRecord = false

        if let bestSet {
            personalRecordsByRep[key] = bestSet
        } else {
            personalRecordsByRep.removeValue(forKey: key)
        }
    }

    func recalculatePersonalRecordsAfterEdit(
        _ set: LoggedSet,
        for exercise: Exercise,
        originalReps: Int,
        in sets: [LoggedSet]
    ) {
        if originalReps != set.reps {
            recalculatePersonalRecord(for: exercise, reps: originalReps, in: sets, excluding: set)
        }
        recalculatePersonalRecord(for: exercise, reps: set.reps, in: sets)
    }

    private func rebuildPersonalRecordCache(from sets: [LoggedSet]) {
        personalRecordsByRep.removeAll(keepingCapacity: true)

        for set in sets where set.weight > 0 {
            guard let exerciseID = set.exercise?.id else { continue }
            let key = PersonalRecordKey(exerciseID: exerciseID, reps: set.reps)

            if personalRecordsByRep[key] == nil || set.weight > (personalRecordsByRep[key]?.weight ?? 0) {
                personalRecordsByRep[key] = set
            }
        }
    }

}

private struct PersonalRecordKey: Hashable {
    let exerciseID: UUID
    let reps: Int
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
