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
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner

    init(commandRunner: PersistenceCommandRunner = PersistenceCommandRunner()) {
        self.commandRunner = commandRunner
    }

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

    // MARK: - Logged Set Commands

    /// Logs a set and updates personal record flags for its rep count in the same save.
    func logSet(
        for exercise: Exercise,
        reps: Int,
        weight: Double,
        completedAt: Date,
        context: ModelContext
    ) -> Result<LoggedSet, PersistenceCommandError> {
        guard !exercise.isDeleted else { return .failure(.unavailable) }

        let result = commandRunner.perform(in: context) { context in
            let existingSets = try Self.loggedSets(for: exercise, in: context)
            let set = LoggedSet(exercise: exercise, reps: reps, weight: weight)
            set.completedAt = completedAt
            context.insert(set)
            Self.recalculatePersonalRecords(in: existingSets + [set], repCounts: [reps])
            return set
        }
        refreshExerciseMetrics(for: exercise, context: context)
        return result
    }

    /// Edits a set and updates personal record flags for its old and new rep counts
    /// in the same save.
    func updateSet(
        _ set: LoggedSet,
        reps: Int,
        weight: Double,
        completedAt: Date,
        context: ModelContext
    ) -> Result<Void, PersistenceCommandError> {
        guard !set.isDeleted, let exercise = set.exercise else { return .failure(.unavailable) }

        let result = commandRunner.perform(in: context) { context in
            var exerciseSets = try Self.loggedSets(for: exercise, in: context)
            if !exerciseSets.contains(where: { $0.id == set.id }) {
                exerciseSets.append(set)
            }
            let originalReps = set.reps

            if set.weight != weight {
                set.weight = weight
            }
            if set.reps != reps {
                set.reps = reps
            }
            if set.completedAt != completedAt {
                set.completedAt = completedAt
            }

            // A set that moves to another rep count doesn't keep its record status.
            if originalReps != reps, set.isPersonalRecord {
                set.isPersonalRecord = false
            }
            Self.recalculatePersonalRecords(in: exerciseSets, repCounts: [originalReps, reps])
        }
        refreshExerciseMetrics(for: exercise, context: context)
        return result
    }

    /// Deletes a set and promotes the next personal record for its rep count in the same save.
    func deleteSet(_ set: LoggedSet, context: ModelContext) -> Result<Void, PersistenceCommandError> {
        guard !set.isDeleted else { return .success(()) }
        let exercise = set.exercise

        let result = commandRunner.perform(in: context) { context in
            let reps = set.reps
            let remainingSets = try exercise.map { exercise in
                try Self.loggedSets(for: exercise, in: context).filter { $0.id != set.id }
            } ?? []
            context.delete(set)
            Self.recalculatePersonalRecords(in: remainingSets, repCounts: [reps])
        }
        if let exercise {
            refreshExerciseMetrics(for: exercise, context: context)
        }
        return result
    }

    private static func loggedSets(for exercise: Exercise, in context: ModelContext) throws -> [LoggedSet] {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate<LoggedSet> { set in
                set.exercise?.id == exerciseID
            }
        )
        return try context.fetch(descriptor)
    }

    /// Marks the preferred set in each rep-count bucket as its personal record.
    static func recalculatePersonalRecords(in sets: [LoggedSet], repCounts: [Int]) {
        for reps in Set(repCounts) {
            let bucketSets = sets.filter { $0.reps == reps }
            var bestSet: LoggedSet?
            for set in bucketSets where isPreferredPersonalRecordCandidate(set, over: bestSet) {
                bestSet = set
            }

            for set in bucketSets {
                let shouldBePersonalRecord = set.id == bestSet?.id
                if set.isPersonalRecord != shouldBePersonalRecord {
                    set.isPersonalRecord = shouldBePersonalRecord
                }
            }
        }
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
