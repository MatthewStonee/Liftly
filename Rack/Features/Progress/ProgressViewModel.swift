import SwiftUI
import SwiftData
import OSLog

enum LoggedSetChange {
    static let didCommit = Notification.Name("LiftlyLoggedSetsDidCommit")
    static let exerciseIDsKey = "exerciseIDs"
    static let removedSetsKey = "removedSets"

    /// - Parameter removedSets: Whether the change deleted sets. A screen that still
    ///   holds those sets must drop them right away, even while it's covered.
    static func publish(exerciseIDs: Set<UUID>, removedSets: Bool = false) {
        guard !exerciseIDs.isEmpty else { return }
        NotificationCenter.default.post(
            name: didCommit,
            object: nil,
            userInfo: [exerciseIDsKey: exerciseIDs, removedSetsKey: removedSets]
        )
    }

    static func affects(_ exerciseID: UUID, notification: Notification) -> Bool {
        (notification.userInfo?[exerciseIDsKey] as? Set<UUID>)?.contains(exerciseID) == true
    }

    static func removedSets(_ notification: Notification) -> Bool {
        notification.userInfo?[removedSetsKey] as? Bool == true
    }
}

/// Built off the main actor by `ProgressViewModel.loadOverviewStats`, so it stays `nonisolated`.
nonisolated struct ExerciseProgressSummary: Sendable, Equatable {
    var prWeight: Double = 0
    var setCount: Int = 0
}

/// What the overview's background load returns for the listed exercises.
nonisolated struct ProgressOverviewStats: Sendable {
    var summariesByExerciseID: [UUID: ExerciseProgressSummary] = [:]
    var weeklyVolume: Double = 0
}

struct ProgressOverview {
    var programExercises: [Exercise] = []
    /// An exercise without an entry is still loading its stats.
    var summariesByExerciseID: [UUID: ExerciseProgressSummary] = [:]
    /// `nil` while loading. It totals every listed exercise, so it resets when the list changes.
    var weeklyVolume: Double?
}

struct ExerciseProgressChartPoint: Identifiable, Equatable {
    let date: Date
    let weight: Double

    var id: Date { date }

    func displayWeight(unit: WeightUnit) -> Double { unit.display(weight) }
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
    /// Loads every set for an exercise, the input for its detail screen's metrics.
    typealias MetricsLoader = @MainActor (UUID, ModelContext) throws -> [LoggedSet]
    /// Loads the overview's stats for the listed exercises, off the main actor.
    typealias StatsLoader = @Sendable (_ exerciseIDs: [UUID], ModelContainer, _ now: Date) throws -> ProgressOverviewStats

    private static let logger = Logger(subsystem: "com.matthewstone.liftly", category: "Progress")

    var timeRange: TimeRange = .threeMonths
    var overview = ProgressOverview()
    /// Whether `showExercises` has listed the exercises, so Progress doesn't show an empty
    /// state before it first runs.
    private(set) var hasLoadedOverview = false
    var exerciseMetrics = ExerciseProgressMetrics()
    @ObservationIgnored private var allSetsAscending: [LoggedSet] = []
    @ObservationIgnored private var isShowingExerciseDetail = false
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner
    @ObservationIgnored private let metricsLoader: MetricsLoader
    @ObservationIgnored private let statsLoader: StatsLoader

    init(
        commandRunner: PersistenceCommandRunner = PersistenceCommandRunner(),
        metricsLoader: @escaping MetricsLoader = { try ProgressViewModel.fetchExerciseSets($0, in: $1) },
        statsLoader: @escaping StatsLoader = { try ProgressViewModel.loadOverviewStats(for: $0, in: $1, now: $2) }
    ) {
        self.commandRunner = commandRunner
        self.metricsLoader = metricsLoader
        self.statsLoader = statsLoader
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

    /// Lists the active program's exercises right away, so Progress never waits on a fetch
    /// to show them. Exercises still listed keep the stats they had until `refreshStats`
    /// replaces them.
    /// - Returns: The listed exercises' IDs, for `refreshStats`.
    @MainActor @discardableResult
    func showExercises(
        of activeProgram: Program?,
        excludingWorkoutIDs: Set<UUID> = [],
        excludingPlannedIDs: Set<UUID> = []
    ) -> [UUID] {
        var exercisesByID: [UUID: Exercise] = [:]
        for workout in activeProgram?.workoutsList ?? [] where !excludingWorkoutIDs.contains(workout.id) {
            for plannedExercise in workout.plannedExercisesList where !excludingPlannedIDs.contains(plannedExercise.id) {
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
        let exerciseIDs = programExercises.map(\.id)
        let listedIDs = Set(exerciseIDs)

        var next = overview
        if Set(overview.programExercises.map(\.id)) != listedIDs {
            next.weeklyVolume = nil
        }
        next.programExercises = programExercises
        next.summariesByExerciseID = overview.summariesByExerciseID.filter { listedIDs.contains($0.key) }
        overview = next
        hasLoadedOverview = true
        return exerciseIDs
    }

    /// Loads PR weights, set counts, and the week's volume off the main actor, then fills
    /// them in for the exercises still listed. A failed load keeps earlier stats and shows
    /// the rest as empty, so no row is left loading.
    @MainActor
    func refreshStats(for exerciseIDs: [UUID], modelContainer: ModelContainer, now: Date = Date()) async {
        guard !exerciseIDs.isEmpty else { return }
        let signpostState = PerformanceSignposts.signposter.beginInterval("Progress stats")
        defer { PerformanceSignposts.signposter.endInterval("Progress stats", signpostState) }

        let loader = statsLoader
        do {
            let stats = try await Task.detached(priority: .userInitiated) {
                try loader(exerciseIDs, modelContainer, now)
            }.value
            guard !Task.isCancelled else { return }

            let listedIDs = Set(overview.programExercises.map(\.id))
            var next = overview
            next.summariesByExerciseID.merge(
                stats.summariesByExerciseID.filter { listedIDs.contains($0.key) }
            ) { _, loaded in loaded }
            // The volume covers exactly the exercises it loaded for.
            if Set(exerciseIDs) == listedIDs {
                next.weeklyVolume = stats.weeklyVolume
            }
            overview = next
        } catch {
            Self.logger.error("Failed to refresh progress stats: \(String(describing: error), privacy: .public)")
            guard !Task.isCancelled else { return }

            var next = overview
            for exercise in overview.programExercises where next.summariesByExerciseID[exercise.id] == nil {
                next.summariesByExerciseID[exercise.id] = ExerciseProgressSummary()
            }
            if next.weeklyVolume == nil {
                next.weeklyVolume = 0
            }
            overview = next
        }
    }

    /// Counts each exercise's sets and finds its heaviest, then totals the last 7 days'
    /// volume for those exercises, in a context of its own. Runs off the main actor, so it
    /// and everything it calls are `nonisolated`.
    nonisolated static func loadOverviewStats(
        for exerciseIDs: [UUID],
        in modelContainer: ModelContainer,
        now: Date
    ) throws -> ProgressOverviewStats {
        let context = ModelContext(modelContainer)
        var stats = ProgressOverviewStats()
        stats.summariesByExerciseID.reserveCapacity(exerciseIDs.count)

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

            stats.summariesByExerciseID[exerciseID] = ExerciseProgressSummary(
                prWeight: prWeight,
                setCount: setCount
            )
        }

        let activeExerciseIDs = Set(exerciseIDs)
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let weeklyDescriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate<LoggedSet> { set in
                set.completedAt >= oneWeekAgo
            }
        )
        stats.weeklyVolume = try context.fetch(weeklyDescriptor).reduce(0) { total, set in
            guard let exerciseID = set.exercise?.id,
                  activeExerciseIDs.contains(exerciseID) else {
                return total
            }
            return total + set.volume
        }
        return stats
    }

    func refreshExerciseMetrics(with sets: [LoggedSet]) {
        let ordered = Self.historyNewestFirst(sets).reversed()
        allSetsAscending = Array(ordered)
        exerciseMetrics.personalRecord = personalRecord(for: allSetsAscending)
        exerciseMetrics.latestSet = allSetsAscending.last
        refreshRangeMetrics()
    }

    static func historyNewestFirst(_ sets: [LoggedSet]) -> [LoggedSet] {
        sets.sorted {
            $0.completedAt == $1.completedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.completedAt > $1.completedAt
        }
    }

    func refreshExerciseMetrics(for exercise: Exercise, context: ModelContext) {
        do {
            refreshExerciseMetrics(with: try metricsLoader(exercise.id, context))
        } catch {
            Self.logger.error("Failed to refresh exercise metrics: \(String(describing: error), privacy: .public)")
        }
    }

    static func fetchExerciseSets(_ exerciseID: UUID, in context: ModelContext) throws -> [LoggedSet] {
        let descriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate<LoggedSet> { set in
                set.exercise?.id == exerciseID
            },
            sortBy: [SortDescriptor(\LoggedSet.completedAt)]
        )
        return try context.fetch(descriptor)
    }

    func updateTimeRange(_ range: TimeRange) {
        guard timeRange != range else { return }
        timeRange = range
        refreshRangeMetrics()
    }

    // MARK: - Exercise Detail

    /// Loads the detail screen's metrics each time it appears, including when History
    /// pops back to it.
    func exerciseDetailAppeared(_ exercise: Exercise, context: ModelContext) {
        isShowingExerciseDetail = true
        refreshExerciseMetrics(for: exercise, context: context)
    }

    /// While History covers the detail screen, changes wait for it to appear again.
    func exerciseDetailDisappeared() {
        isShowingExerciseDetail = false
    }

    /// Refreshes as soon as a change to this exercise saves, so reopening Quick Log
    /// prefills the latest set. A deletion refreshes even while History covers the
    /// screen, so the metrics never keep a set that no longer exists.
    func handleCommittedChange(_ notification: Notification, exercise: Exercise, context: ModelContext) {
        guard LoggedSetChange.affects(exercise.id, notification: notification) else { return }
        if LoggedSetChange.removedSets(notification) {
            refreshExerciseMetrics(for: exercise, context: context)
        } else {
            refreshVisibleExerciseMetrics(for: exercise, context: context)
        }
    }

    /// Skipped while History covers the detail screen, which refreshes when it appears again.
    func refreshVisibleExerciseMetrics(for exercise: Exercise, context: ModelContext) {
        guard isShowingExerciseDetail else { return }
        refreshExerciseMetrics(for: exercise, context: context)
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
        guard Self.isValidSetInput(reps: reps, weight: weight) else { return .failure(.invalidInput) }
        guard !exercise.isDeleted else { return .failure(.unavailable) }

        let result = commandRunner.performInsert(in: context) { context in
            context.reloadRelationships(of: exercise, [\.loggedSets])
        } _: { insertionContext in
            guard let insertionExercise = try insertionContext.existingModel(exercise) else {
                throw PersistenceCommandError.unavailable
            }
            let existingSets = try Self.loggedSets(for: insertionExercise, in: insertionContext)
            let set = LoggedSet(exercise: insertionExercise, reps: reps, weight: weight)
            set.completedAt = completedAt
            insertionContext.insert(set)
            Self.recalculatePersonalRecords(in: existingSets + [set], repCounts: [reps])
            return set
        }
        if case .success = result { LoggedSetChange.publish(exerciseIDs: [exercise.id]) }
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
        guard Self.isValidSetInput(reps: reps, weight: weight) else { return .failure(.invalidInput) }
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
            return context.hasChanges
        }
        if case .success(true) = result { LoggedSetChange.publish(exerciseIDs: [exercise.id]) }
        return result.map { _ in }
    }

    /// Deletes sets and promotes the next personal record for each affected rep count.
    /// `DeletionCoordinator` calls this inside its batch command, so every requested set
    /// and its PR flags save together.
    @discardableResult
    static func deleteSetsInCommand(_ sets: [LoggedSet], context: ModelContext) throws -> Set<UUID> {
        let liveSets = sets.filter { !$0.isDeleted }
        let removedIDs = Set(liveSets.map(\.id))
        let grouped = Dictionary(grouping: liveSets.compactMap { set -> (UUID, Int)? in
            set.exercise.map { ($0.id, set.reps) }
        }, by: { $0.0 })

        for set in liveSets {
            context.delete(set)
        }
        for (exerciseID, entries) in grouped {
            for reps in Set(entries.map { $0.1 }) {
                let descriptor = FetchDescriptor<LoggedSet>(
                    predicate: #Predicate<LoggedSet> { set in
                        set.exercise?.id == exerciseID && set.reps == reps
                    }
                )
                let remaining = try context.fetch(descriptor).filter { !removedIDs.contains($0.id) }
                recalculatePersonalRecords(in: remaining, repCounts: [reps])
            }
        }
        return Set(grouped.keys)
    }

    private static func isValidSetInput(reps: Int, weight: Double) -> Bool {
        reps > 0 && weight.isFinite && weight >= 0
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

/// Keyed off the main actor by `PersonalRecordBackfillActor`, so the type and its
/// `Hashable` conformance stay `nonisolated`.
private nonisolated struct PersonalRecordKey: Hashable {
    let exerciseID: UUID
    let reps: Int
}

/// Pure comparison over two sets; callable from `ProgressViewModel` and from the backfill actor.
nonisolated func isPreferredPersonalRecordCandidate(_ candidate: LoggedSet, over current: LoggedSet?) -> Bool {
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
    private static let logger = Logger(
        subsystem: "com.matthewstone.liftly",
        category: "StartupMaintenance"
    )

    /// One-time backfill: marks the correct PR set per exercise per rep count.
    /// - Parameter defaults: Where completion is recorded. Tests pass their own.
    func backfillIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "prBackfillComplete") else { return }
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
            defaults.set(true, forKey: "prBackfillComplete")
        } catch {
            modelContext.rollback()
            Self.logger.error("Personal record backfill failed: \(String(describing: error), privacy: .public)")
        }
    }
}
