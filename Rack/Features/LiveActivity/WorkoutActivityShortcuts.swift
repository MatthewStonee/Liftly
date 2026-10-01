import AppIntents
import Foundation

struct WorkoutDayEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout Day")
    static var defaultQuery = WorkoutDayQuery()

    let id: UUID
    let name: String
    let programName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(programName)")
    }

    init(reference: WorkoutDayReference) {
        id = reference.id
        name = reference.name
        programName = reference.programName
    }
}

struct WorkoutDayQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [WorkoutDayEntity] {
        let days = try await WorkoutActivityCoordinator.shared.availableDays()
        return identifiers.compactMap { id in days.first { $0.id == id }.map(WorkoutDayEntity.init(reference:)) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WorkoutDayEntity] {
        try await WorkoutActivityCoordinator.shared.availableDays().map(WorkoutDayEntity.init(reference:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [WorkoutDayEntity] {
        try await WorkoutActivityCoordinator.shared.availableDays()
            .filter { $0.name.localizedCaseInsensitiveContains(string) || $0.programName.localizedCaseInsensitiveContains(string) }
            .map(WorkoutDayEntity.init(reference:))
    }
}

struct ShowWorkoutDayOnLockScreenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Show Workout Day on Lock Screen"
    static var description = IntentDescription("Show a workout day's exercises and targets in a Live Activity. Keeps a different day already showing.")
    static var openAppWhenRun: Bool = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Workout Day") var workoutDay: WorkoutDayEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$workoutDay) on the Lock Screen")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await WorkoutActivityCoordinator.shared.start(workoutID: workoutDay.id, automatic: true)
        if result == .preservedExisting {
            return .result(dialog: "Another workout day is already showing. It was left running.")
        }
        return .result(dialog: "Your workout day is showing on the Lock Screen.")
    }
}

struct StopWorkoutLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Workout Live Activity"
    static var description = IntentDescription("End and immediately dismiss Liftly's workout reference.")
    static var openAppWhenRun: Bool = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutActivityCoordinator.shared.stop()
        return .result()
    }
}

struct LiftlyAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowWorkoutDayOnLockScreenIntent(),
            phrases: ["Show my workout in \(.applicationName)"],
            shortTitle: "Show Workout Day",
            systemImageName: "dumbbell"
        )
        AppShortcut(
            intent: StopWorkoutLiveActivityIntent(),
            phrases: ["Stop my workout reference in \(.applicationName)"],
            shortTitle: "Stop Live Activity",
            systemImageName: "stop.circle"
        )
    }
}
