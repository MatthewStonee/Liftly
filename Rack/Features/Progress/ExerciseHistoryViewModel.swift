import Foundation
import Observation
import SwiftData
import OSLog

struct HistoryPageRequest {
    let exerciseID: UUID
    let cutoff: Date
    let offset: Int
    let limit: Int
    let excludedPendingDeletionIDs: [UUID]
}

struct HistoryPage {
    let rows: [LoggedSet]
    let hasMore: Bool
    let hasAnyHistory: Bool
}

enum HistoryLoadingError: Error, Equatable {
    case failed(String)

    var message: String { "Your history couldn’t be loaded. Try again." }
}

@MainActor @Observable
final class ExerciseHistoryViewModel {
    typealias PageLoader = @MainActor (HistoryPageRequest, ModelContext) throws -> HistoryPage

    private static let logger = Logger(subsystem: "com.matthewstone.liftly", category: "History")
    private static let pageSize = 50

    enum RetryOperation {
        case loadMore, refresh
    }

    private(set) var range: ProgressViewModel.TimeRange = .allTime
    private(set) var rows: [LoggedSet] = []
    private(set) var hasMore = false
    private(set) var hasAnyHistory = false
    private(set) var initialError: HistoryLoadingError?
    private(set) var inlineError: HistoryLoadingError?
    /// The row the list is scrolled to. The view binds it to `scrollPosition(id:)`.
    var scrollAnchorID: UUID?
    @ObservationIgnored private var cutoff: Date = .distantPast
    @ObservationIgnored private var loadedWindowLimit = pageSize
    @ObservationIgnored private var retryOperation: RetryOperation?
    @ObservationIgnored private var displacedAnchor: DisplacedAnchor?
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private let pageLoader: PageLoader

    /// The row a pending deletion took from under the user, and the row holding their
    /// place until Undo brings it back. The replacement is `nil` when no rows survived.
    private struct DisplacedAnchor {
        let originalID: UUID
        let replacementID: UUID?
    }

    init(pageLoader: @escaping PageLoader = { try ExerciseHistoryViewModel.fetchPage($0, in: $1) }) {
        self.pageLoader = pageLoader
    }

    func selectRange(
        _ choice: ProgressViewModel.TimeRange,
        exerciseID: UUID,
        context: ModelContext,
        excluding excludedIDs: Set<UUID>,
        now: Date = .now
    ) {
        guard range != choice else { return }
        range = choice
        loadInitial(exerciseID: exerciseID, context: context, excluding: excludedIDs, now: now)
    }

    /// The first appearance loads the window; later ones refresh it, so returning to
    /// History keeps the loaded pages, the cutoff and the user's place.
    func appear(
        exerciseID: UUID,
        context: ModelContext,
        excluding excludedIDs: Set<UUID>
    ) {
        if hasLoaded {
            refresh(exerciseID: exerciseID, context: context, excluding: excludedIDs)
        } else {
            loadInitial(exerciseID: exerciseID, context: context, excluding: excludedIDs)
        }
    }

    func loadInitial(
        exerciseID: UUID,
        context: ModelContext,
        excluding excludedIDs: Set<UUID>,
        now: Date = .now
    ) {
        cutoff = range.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }
            ?? .distantPast
        loadedWindowLimit = Self.pageSize
        rows = []
        hasMore = false
        hasAnyHistory = false
        initialError = nil
        inlineError = nil
        retryOperation = nil
        displacedAnchor = nil
        setAnchor(nil)
        hasLoaded = true
        fetchWindow(exerciseID: exerciseID, context: context, excluding: excludedIDs, initial: true)
    }

    func loadMore(exerciseID: UUID, context: ModelContext, excluding excludedIDs: Set<UUID>) {
        guard hasMore else { return }
        let request = request(
            exerciseID: exerciseID,
            offset: rows.count,
            limit: Self.pageSize,
            excluding: excludedIDs
        )
        do {
            let page = try pageLoader(request, context)
            rows += page.rows
            hasMore = page.hasMore
            inlineError = nil
            retryOperation = nil
            loadedWindowLimit += Self.pageSize
        } catch {
            record(error, operation: .loadMore)
        }
    }

    /// Requeries only the visible window. Its cutoff stays fixed until the range is reset.
    func refresh(exerciseID: UUID, context: ModelContext, excluding excludedIDs: Set<UUID>) {
        fetchWindow(exerciseID: exerciseID, context: context, excluding: excludedIDs, initial: rows.isEmpty && initialError != nil)
    }

    func handleCommittedChange(
        _ notification: Notification,
        exerciseID: UUID,
        context: ModelContext,
        excluding excludedIDs: Set<UUID>
    ) {
        guard LoggedSetChange.affects(exerciseID, notification: notification) else { return }
        refresh(exerciseID: exerciseID, context: context, excluding: excludedIDs)
    }

    func retry(exerciseID: UUID, context: ModelContext, excluding excludedIDs: Set<UUID>) {
        if initialError != nil {
            fetchWindow(exerciseID: exerciseID, context: context, excluding: excludedIDs, initial: true)
        } else if retryOperation == .loadMore {
            loadMore(exerciseID: exerciseID, context: context, excluding: excludedIDs)
        } else {
            refresh(exerciseID: exerciseID, context: context, excluding: excludedIDs)
        }
    }

    private func fetchWindow(
        exerciseID: UUID,
        context: ModelContext,
        excluding excludedIDs: Set<UUID>,
        initial: Bool
    ) {
        let request = request(
            exerciseID: exerciseID,
            offset: 0,
            limit: loadedWindowLimit,
            excluding: excludedIDs
        )
        do {
            let page = try pageLoader(request, context)
            let previousIDs = rows.map(\.id)
            rows = page.rows
            hasMore = page.hasMore
            hasAnyHistory = page.hasAnyHistory
            initialError = nil
            inlineError = nil
            retryOperation = nil
            updateAnchor(previousIDs: previousIDs, currentIDs: rows.map(\.id), pendingIDs: excludedIDs)
        } catch {
            if initial { initialError = .failed(String(describing: error)) }
            else { record(error, operation: .refresh) }
        }
    }

    /// Keeps the user's place when the anchored row disappears, and returns them to it
    /// when Undo, or a failed deletion, brings the row back, however many replacement
    /// rows were deleted in between.
    private func updateAnchor(previousIDs: [UUID], currentIDs: [UUID], pendingIDs: Set<UUID>) {
        if let displaced = displacedAnchor {
            if displaced.replacementID != scrollAnchorID {
                // The user moved off the replacement row, so their new place is their own.
                displacedAnchor = nil
            } else if currentIDs.contains(displaced.originalID) {
                displacedAnchor = nil
                setAnchor(displaced.originalID)
                return
            } else if !pendingIDs.contains(displaced.originalID) {
                // The deletion committed, so the row won't come back.
                displacedAnchor = nil
            }
        }

        guard let anchor = scrollAnchorID else { return }
        let surviving = Self.survivingAnchor(for: anchor, previousIDs: previousIDs, currentIDs: currentIDs)
        guard surviving != anchor else { return }
        // When a replacement disappears too, it passes the place on, but Undo still
        // returns to the original row. Only a row awaiting Undo can come back.
        let originalID = displacedAnchor?.originalID ?? anchor
        displacedAnchor = pendingIDs.contains(originalID)
            ? DisplacedAnchor(originalID: originalID, replacementID: surviving)
            : nil
        setAnchor(surviving)
    }

    /// Keeps the anchored row, else the nearest surviving row after it, else the
    /// nearest one before it.
    static func survivingAnchor(for anchor: UUID, previousIDs: [UUID], currentIDs: [UUID]) -> UUID? {
        let surviving = Set(currentIDs)
        if surviving.contains(anchor) { return anchor }
        guard let index = previousIDs.firstIndex(of: anchor) else { return nil }
        if let next = previousIDs[previousIDs.index(after: index)...].first(where: { surviving.contains($0) }) {
            return next
        }
        return previousIDs[..<index].last(where: { surviving.contains($0) })
    }

    /// An `@Observable` write re-scrolls the list even when the value is unchanged.
    private func setAnchor(_ id: UUID?) {
        guard scrollAnchorID != id else { return }
        scrollAnchorID = id
    }

    private func request(
        exerciseID: UUID,
        offset: Int,
        limit: Int,
        excluding excludedIDs: Set<UUID>
    ) -> HistoryPageRequest {
        HistoryPageRequest(
            exerciseID: exerciseID,
            cutoff: cutoff,
            offset: offset,
            limit: limit,
            excludedPendingDeletionIDs: Array(excludedIDs)
        )
    }

    private func record(_ error: Error, operation: RetryOperation) {
        Self.logger.error("Failed to load history: \(String(describing: error), privacy: .public)")
        inlineError = .failed(String(describing: error))
        retryOperation = operation
    }

    static func fetchPage(_ request: HistoryPageRequest, in context: ModelContext) throws -> HistoryPage {
        #if DEBUG
        try DebugPersistenceFaults.consumeHistoryLoadFailure()
        #endif
        let exerciseID = request.exerciseID
        let cutoff = request.cutoff
        let excludedIDs = request.excludedPendingDeletionIDs
        var descriptor = FetchDescriptor<LoggedSet>(
            predicate: #Predicate<LoggedSet> { set in
                set.exercise?.id == exerciseID
                    && set.completedAt >= cutoff
                    && !excludedIDs.contains(set.id)
            },
            sortBy: [
                SortDescriptor(\LoggedSet.completedAt, order: .reverse),
                SortDescriptor(\LoggedSet.id)
            ]
        )
        descriptor.fetchOffset = request.offset
        descriptor.fetchLimit = request.limit + 1
        let fetched = try context.fetch(descriptor)
        let rows = Array(fetched.prefix(request.limit))
        let hasAnyHistory: Bool
        if request.offset == 0 && rows.isEmpty {
            hasAnyHistory = try context.fetchCount(FetchDescriptor<LoggedSet>(
                predicate: #Predicate<LoggedSet> { $0.exercise?.id == exerciseID }
            )) > 0
        } else {
            hasAnyHistory = true
        }
        return HistoryPage(rows: rows, hasMore: fetched.count > request.limit, hasAnyHistory: hasAnyHistory)
    }
}
