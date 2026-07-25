import SwiftUI
import SwiftData
import OSLog

struct ExerciseProgressSummary: Sendable {
    var prWeight: Double = 0
    var setCount: Int = 0
}

struct ProgressOverview {
    var programExercises: [Exercise] = []
    var summariesByExerciseID: [UUID: ExerciseProgressSummary] = [:]
    var weeklyVolume: Double = 0
}

struct ExerciseProgressChartPoint: Identifiable, Equatable {
    let date: Date
    let weight: Double

    var id: Date { date }
}

struct ExerciseProgressMetrics {
    var chartPoints: [ExerciseProgressChartPoint] = []
    var personalRecord: LoggedSet?
    var totalVolume: Double = 0
    var recentSets: [LoggedSet] = []
    var hasFilteredSets = false
    var latestSet: LoggedSet?
}

@Observable
final class ProgressViewModel {
    private static let logger = Logger(subsystem: "com.matthewstone.liftly", category: "Progress")

    var selectedExercise: Exercise?
    var timeRange: TimeRange = .threeMonths
    var overview = ProgressOverview()
    var exerciseMetrics = ExerciseProgressMetrics()
    @ObservationIgnored private var allSetsAscending: [LoggedSet] = []
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

    func personalRecord(for sets: [LoggedSet]) -> LoggedSet? {
        var bestSet: LoggedSet?
        for set in sets where set.weight > 0 {
            if isPreferredPersonalRecordCandidate(set, over: bestSet) {
                bestSet = set
            }
        }
        return bestSet
    }

    @MainActor
    func refreshOverview(
        activeProgram: Program?,
        modelContainer: ModelContainer,
        now: Date = Date()
    ) async {
        guard let activeProgram else {
            overview = ProgressOverview()
            return
        }

        var exercisesByID: [UUID: Exercise] = [:]
        for workout in activeProgram.workoutsList {
            for plannedExercise in workout.plannedExercisesList {
                guard let exercise = plannedExercise.exercise else { continue }
                exercisesByID[exercise.id] = exercise
            }
        }

        let programExercises = exercisesByID.values.sorted {
            let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        guard !programExercises.isEmpty else {
            overview = ProgressOverview()
            return
        }

        let exerciseIDs = programExercises.map(\.id)
        let activeExerciseIDs = Set(exerciseIDs)

        do {
            let result: (summaries: [UUID: ExerciseProgressSummary], weeklyVolume: Double) =
                try await Task.detached(priority: .userInitiated) {
                    let context = ModelContext(modelContainer)
                    var summaries: [UUID: ExerciseProgressSummary] = [:]
                    summaries.reserveCapacity(exerciseIDs.count)

                    for exerciseID in exerciseIDs {
                        let exercisePredicate = #Predicate<LoggedSet> { set in
                            set.exercise?.id == exerciseID
                        }
                        let setCount = try context.fetchCount(
                            FetchDescriptor<LoggedSet>(predicate: exercisePredicate)
                        )

                        let personalRecordPredicate = #Predicate<LoggedSet> { set in
                            set.exercise?.id == exerciseID && set.weight > 0
                        }
                        var personalRecordDescriptor = FetchDescriptor<LoggedSet>(
                            predicate: personalRecordPredicate,
                            sortBy: [
                                SortDescriptor(\LoggedSet.weight, order: .reverse),
                                SortDescriptor(\LoggedSet.completedAt)
                            ]
                        )
                        personalRecordDescriptor.fetchLimit = 1
                        let prWeight = try context.fetch(personalRecordDescriptor).first?.weight ?? 0

                        summaries[exerciseID] = ExerciseProgressSummary(
                            prWeight: prWeight,
                            setCount: setCount
                        )
                    }

                    let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
                    let weeklyDescriptor = FetchDescriptor<LoggedSet>(
                        predicate: #Predicate<LoggedSet> { set in
                            set.completedAt >= oneWeekAgo
                        }
                    )
                    let weeklyVolume = try context.fetch(weeklyDescriptor).reduce(0) { total, set in
                        guard let exerciseID = set.exercise?.id,
                              activeExerciseIDs.contains(exerciseID) else {
                            return total
                        }
                        return total + set.volume
                    }

                    return (summaries, weeklyVolume)
                }.value

            guard !Task.isCancelled else { return }

            overview = ProgressOverview(
                programExercises: programExercises,
                summariesByExerciseID: result.summaries,
                weeklyVolume: result.weeklyVolume
            )
        } catch {
            Self.logger.error("Failed to refresh progress overview: \(String(describing: error), privacy: .public)")
        }
    }

    func refreshExerciseMetrics(with sets: [LoggedSet]) {
        allSetsAscending = sets
        rebuildPersonalRecordCache(from: sets)

        exerciseMetrics.personalRecord = personalRecord(for: sets)
        exerciseMetrics.latestSet = sets.last
        refreshRangeMetrics()
    }

    func refreshExerciseMetrics(for exercise: Exercise, context: ModelContext) {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate<LoggedSet> { set in
                set.exercise?.id == exerciseID
            },
            sortBy: [SortDescriptor(\LoggedSet.completedAt)]
        )

        do {
            refreshExerciseMetrics(with: try context.fetch(descriptor))
        } catch {
            Self.logger.error("Failed to refresh exercise metrics: \(String(describing: error), privacy: .public)")
        }
    }

    func updateTimeRange(_ range: TimeRange) {
        guard timeRange != range else { return }
        timeRange = range
        refreshRangeMetrics()
    }

    // MARK: - PR Detection

    func assignPersonalRecordStatus(to set: LoggedSet, for exercise: Exercise) {
        let key = PersonalRecordKey(exerciseID: exercise.id, reps: set.reps)
        guard set.weight > 0 else {
            if set.isPersonalRecord {
                set.isPersonalRecord = false
            }
            return
        }

        guard let currentPR = personalRecordsByRep[key] else {
            if !set.isPersonalRecord {
                set.isPersonalRecord = true
            }
            personalRecordsByRep[key] = set
            return
        }

        let isNewPersonalRecord = set.weight > currentPR.weight
        if set.isPersonalRecord != isNewPersonalRecord {
            set.isPersonalRecord = isNewPersonalRecord
        }

        if isNewPersonalRecord {
            if currentPR.isPersonalRecord {
                currentPR.isPersonalRecord = false
            }
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
        var bucketSets: [LoggedSet] = []

        for set in sets where set.exercise?.id == exercise.id && set.reps == reps && set.id != excludedID && set.weight > 0 {
            bucketSets.append(set)
            if isPreferredPersonalRecordCandidate(set, over: bestSet) {
                bestSet = set
            }
        }

        for set in sets where set.exercise?.id == exercise.id && set.reps == reps && set.id != excludedID && set.weight <= 0 {
            bucketSets.append(set)
        }

        for set in bucketSets {
            let shouldBePersonalRecord = set.id == bestSet?.id
            if set.isPersonalRecord != shouldBePersonalRecord {
                set.isPersonalRecord = shouldBePersonalRecord
            }
        }

        if excludedSet?.isPersonalRecord == true {
            excludedSet?.isPersonalRecord = false
        }

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
        originalWeight: Double,
        in sets: [LoggedSet]
    ) {
        guard originalReps != set.reps || originalWeight != set.weight else { return }

        if originalReps != set.reps {
            recalculatePersonalRecord(for: exercise, reps: originalReps, in: sets, excluding: set)
        }
        recalculatePersonalRecord(for: exercise, reps: set.reps, in: sets)
    }

    private func refreshRangeMetrics(now: Date = Date()) {
        let startIndex = filteredStartIndex(for: timeRange, now: now)
        let filteredSets = allSetsAscending[startIndex...]
        let calendar = Calendar.current

        var chartPoints: [ExerciseProgressChartPoint] = []
        var currentBucketDate: Date?
        var currentBucketMaximum: Double = 0
        var totalVolume: Double = 0

        for set in filteredSets {
            totalVolume += set.volume
            let bucketDate = chartBucketDate(for: set.completedAt, range: timeRange, calendar: calendar)

            if bucketDate != currentBucketDate {
                if let currentBucketDate {
                    chartPoints.append(
                        ExerciseProgressChartPoint(date: currentBucketDate, weight: currentBucketMaximum)
                    )
                }
                currentBucketDate = bucketDate
                currentBucketMaximum = set.weight
            } else {
                currentBucketMaximum = max(currentBucketMaximum, set.weight)
            }
        }

        if let currentBucketDate {
            chartPoints.append(
                ExerciseProgressChartPoint(date: currentBucketDate, weight: currentBucketMaximum)
            )
        }

        exerciseMetrics.chartPoints = chartPoints
        exerciseMetrics.totalVolume = totalVolume
        exerciseMetrics.recentSets = Array(filteredSets.suffix(20).reversed())
        exerciseMetrics.hasFilteredSets = !filteredSets.isEmpty
    }

    private func filteredStartIndex(for range: TimeRange, now: Date) -> Int {
        guard let days = range.days else { return allSetsAscending.startIndex }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        var lowerBound = allSetsAscending.startIndex
        var upperBound = allSetsAscending.endIndex

        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if allSetsAscending[midpoint].completedAt < cutoff {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return lowerBound
    }

    private func chartBucketDate(for date: Date, range: TimeRange, calendar: Calendar) -> Date {
        switch range {
        case .oneMonth, .threeMonths, .sixMonths:
            return calendar.startOfDay(for: date)
        case .oneYear:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .allTime:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private func rebuildPersonalRecordCache(from sets: [LoggedSet]) {
        personalRecordsByRep.removeAll(keepingCapacity: true)

        for set in sets where set.weight > 0 {
            guard let exerciseID = set.exercise?.id else { continue }
            let key = PersonalRecordKey(exerciseID: exerciseID, reps: set.reps)

            if isPreferredPersonalRecordCandidate(set, over: personalRecordsByRep[key]) {
                personalRecordsByRep[key] = set
            }
        }
    }

}

private struct PersonalRecordKey: Hashable {
    let exerciseID: UUID
    let reps: Int
}

func isPreferredPersonalRecordCandidate(_ candidate: LoggedSet, over current: LoggedSet?) -> Bool {
    guard candidate.weight > 0 else { return false }
    guard let current else { return true }

    if candidate.weight != current.weight {
        return candidate.weight > current.weight
    }
    if candidate.isPersonalRecord != current.isPersonalRecord {
        return candidate.isPersonalRecord
    }
    if candidate.completedAt != current.completedAt {
        return candidate.completedAt < current.completedAt
    }
    return candidate.id.uuidString < current.id.uuidString
}

@ModelActor
actor PersonalRecordBackfillActor {
    /// One-time backfill: marks the correct PR set per exercise per rep count.
    func backfillIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "prBackfillComplete") else { return }
        let descriptor = FetchDescriptor<LoggedSet>(
            sortBy: [SortDescriptor(\LoggedSet.completedAt)]
        )

        do {
            let sets = try modelContext.fetch(descriptor)
            var winnersByKey: [PersonalRecordKey: LoggedSet] = [:]

            for set in sets where set.weight > 0 {
                guard let exerciseID = set.exercise?.id else { continue }
                let key = PersonalRecordKey(exerciseID: exerciseID, reps: set.reps)
                if isPreferredPersonalRecordCandidate(set, over: winnersByKey[key]) {
                    winnersByKey[key] = set
                }
            }

            var didChange = false
            for set in sets {
                guard let exerciseID = set.exercise?.id else { continue }
                let key = PersonalRecordKey(exerciseID: exerciseID, reps: set.reps)
                let shouldBePersonalRecord = set.weight > 0 && winnersByKey[key]?.id == set.id
                if set.isPersonalRecord != shouldBePersonalRecord {
                    set.isPersonalRecord = shouldBePersonalRecord
                    didChange = true
                }
            }

            if didChange {
                try modelContext.save()
            }
            UserDefaults.standard.set(true, forKey: "prBackfillComplete")
        } catch {
            modelContext.rollback()
        }
    }
}
