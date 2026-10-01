import SwiftUI

struct WorkoutActivityControl: View {
    let workout: WorkoutTemplate
    let isReordering: Bool
    @Environment(WorkoutActivityCoordinator.self) private var coordinator: WorkoutActivityCoordinator?
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?
    @State private var showingSwitch = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private var isShowing: Bool { coordinator?.current?.state.workoutID == workout.id }

    private var startUnavailable: Bool {
        coordinator?.areActivitiesEnabled != true
            || deletionCoordinator?.isPending(workout) == true
            || !workout.plannedExercisesList.contains { $0.exercise != nil && deletionCoordinator?.isPending($0) != true }
            || isReordering
    }

    var body: some View {
        if let coordinator {
            VStack(spacing: 6) {
                if isShowing {
                    GlassButton("Stop Live Activity", icon: "stop.circle") {
                        Task { await coordinator.stop() }
                    }
                    .accessibilityIdentifier("workout.liveActivity.stop")
                    .disabled(coordinator.isWorking)
                } else {
                    PrimaryButton("Show on Lock Screen", icon: "lock") {
                        if let current = coordinator.current, current.state.workoutID != workout.id {
                            showingSwitch = true
                        } else { start() }
                    }
                    .accessibilityIdentifier("workout.liveActivity.show")
                    .disabled(startUnavailable || coordinator.isWorking)
                }

                if isShowing {
                    Text(coordinator.current?.state.needsRefresh == true
                         ? "Open this day again to refresh your Lock Screen."
                         : "This day is showing on your Lock Screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !coordinator.areActivitiesEnabled {
                    Text("Enable Live Activities for Liftly in the Settings app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)
            .confirmationDialog("Switch the workout on your Lock Screen?", isPresented: $showingSwitch, titleVisibility: .visible) {
                Button("Show \(workout.name)") { start(allowSwitch: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(coordinator.current?.state.workoutName ?? "Another day") is already showing.")
            }
            .alert("Couldn't Show Workout", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
        }
    }

    private func start(allowSwitch: Bool = false) {
        guard let coordinator else { return }
        Task {
            do { try await coordinator.start(workoutID: workout.id, allowSwitch: allowSwitch) }
            catch WorkoutActivityError.needsSwitch { showingSwitch = true }
            catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
