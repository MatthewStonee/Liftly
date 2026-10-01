import AppIntents
import Foundation

struct WorkoutActivityPagingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Browse Workout Exercises"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Activity") var activityID: String
    @Parameter(title: "Direction") var direction: Int
    @Parameter(title: "Visible exercises") var visibleCount: Int
    @Parameter(title: "Workout day") var workoutID: String
    @Parameter(title: "Displayed position") var startingIndex: Int
    @Parameter(title: "First displayed exercise") var anchorID: String
    @Parameter(title: "Page version") var revision: Int

    init() {}

    init(activityID: String, direction: Int, visibleCount: Int, state: WorkoutActivityAttributes.ContentState) {
        self.activityID = activityID
        self.direction = direction
        self.visibleCount = visibleCount
        workoutID = state.workoutID.uuidString
        startingIndex = state.startingIndex
        anchorID = state.exercises.first?.id.uuidString ?? ""
        revision = state.revision
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // LiveActivityIntent executes in the app process. The extension includes
        // this declaration so WidgetKit can identify the same intent there.
        #if LIFTLY_EXTENSION
        try requireAppProcess()
        #else
        guard let id = UUID(uuidString: workoutID) else { return .result() }
        try await WorkoutActivityCoordinator.shared.page(
            activityID: activityID, direction: direction, visibleCount: visibleCount,
            displayedPage: .init(workoutID: id, startingIndex: startingIndex, anchorID: UUID(uuidString: anchorID), revision: revision)
        )
        #endif
        return .result()
    }

    private func requireAppProcess() throws {
        throw PagingExecutionError.appRequired
    }
}

private enum PagingExecutionError: Error {
    case appRequired
}
