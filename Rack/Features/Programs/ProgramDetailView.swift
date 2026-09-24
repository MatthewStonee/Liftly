import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let program: Program
    var onDeleteProgram: (() -> Void)?
    @State private var showingAddWorkout = false
    @State private var showingEditProgram = false
    @State private var viewModel = ProgramDetailViewModel()
    @State private var isReorderMode = false
    @State private var persistenceAlert: PersistenceAlert?
    @State private var showingPersistenceAlert = false
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?
    @AppStorage("programDetailViewMode") private var detailMode: ProgramDetailMode = .days

    var body: some View {
        let visibleWorkouts = SiblingOrder.workouts(program.workoutsList)
            .filter { deletionCoordinator?.isPending($0) != true }
        let canToggleReorderMode = detailMode == .days
            && deletionCoordinator?.hasPendingWorkouts(in: program) != true
            && !showingAddWorkout
            && visibleWorkouts.count > 1

        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    programHero(counts: ProgramCounts(program, hiding: deletionCoordinator))
                    viewModePicker

                    if visibleWorkouts.isEmpty {
                        emptyWorkoutsState
                        addWorkoutButton
                    } else if detailMode == .overview {
                        GlassEffectContainer(spacing: 12) {
                            ProgramOverviewView(workouts: visibleWorkouts)
                        }
                    } else {
                        GlassEffectContainer(spacing: 12) {
                            ReorderableForEach(
                                items: visibleWorkouts,
                                isEnabled: isReorderMode && canToggleReorderMode,
                                onCommitOrder: { orderedIDs in
                                    commitWorkoutOrder(orderedIDs)
                                }
                            ) { workout, dragHandle in
                                WorkoutTemplateRow(
                                    workout: workout,
                                    isReorderMode: isReorderMode,
                                    dragHandle: dragHandle
                                )
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel(workout.name)
                                .accessibilityIdentifier("workout.row.\(workout.name)")
                            }
                        }

                        addWorkoutButton
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .allowsHitTesting(!showingAddWorkout)
            // `isModal` only hides siblings, so hide the content behind the overlay too.
            .accessibilityHidden(showingAddWorkout)

            if showingAddWorkout {
                AddWorkoutOverlay(
                    onCancel: hideAddWorkoutOverlay,
                    onSubmit: { name in
                        addWorkout(named: name)
                    }
                )
                    .transition(.opacity)
            }
        }
        .navigationTitle(program.name)
        .titleDisplayMode(.inline)
        .appBackground()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isReorderMode {
                    Button("Done") {
                        exitReorderMode()
                    }
                    .accessibilityLabel("Done Reordering")
                }

                Menu {
                    if detailMode == .days && visibleWorkouts.count > 1 && !isReorderMode {
                        Button {
                            enterReorderMode(if: canToggleReorderMode)
                        } label: {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(!canToggleReorderMode)
                    }

                    if !isReorderMode {
                        Button {
                            showingEditProgram = true
                        } label: {
                            Label("Edit Program", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteProgram()
                        } label: {
                            Label("Delete Program", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Program Options")
            }
        }
        .sheet(isPresented: $showingEditProgram) {
            CreateProgramView(existingProgram: program).deletionUndoToast(deletionCoordinator)
        }
        .onChange(of: detailMode) { _, newMode in
            if newMode == .overview {
                exitReorderMode()
            }
        }
        .onChange(of: deletionCoordinator?.hasPendingWorkouts(in: program)) { _, pending in
            if pending == true { exitReorderMode() }
        }
        .persistenceAlert(isPresented: $showingPersistenceAlert, alert: persistenceAlert)
    }

    private func programHero(counts: ProgramCounts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            programHeading

            Text(program.name)
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.white)
                .tracking(-0.5)

            if !program.programDescription.isEmpty {
                Text(program.programDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    StatBadge(
                        value: "\(counts.days)",
                        label: counts.days == 1 ? "Day" : "Days",
                        style: .hero
                    )
                    StatBadge(
                        value: "\(counts.exercises)",
                        label: counts.exercises == 1 ? "Exercise" : "Exercises",
                        style: .hero
                    )
                }
            }
            .padding(.top, 4)

            if !program.isActive {
                setActiveButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var programHeading: some View {
        if program.isActive {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    programLabel
                    Spacer(minLength: 8)
                    activeIndicator
                }

                VStack(alignment: .leading, spacing: 4) {
                    programLabel
                    activeIndicator
                }
            }
        } else {
            programLabel
        }
    }

    private var programLabel: some View {
        Text("PROGRAM")
            .font(.caption.bold())
            .tracking(2)
            .foregroundStyle(.blue)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var activeIndicator: some View {
        Label("Active", systemImage: "checkmark.circle.fill")
            .font(.caption.bold())
            .foregroundStyle(.blue)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Active Program")
    }

    /// Progress tracks only the active program, so activating one is a visible action.
    private var setActiveButton: some View {
        Button {
            setProgramActive()
        } label: {
            Label("Set as Active", systemImage: "checkmark.circle")
                .font(.subheadline.bold())
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(isReorderMode || showingAddWorkout)
        .accessibilityHint("Tracks this program's exercises on the Progress tab")
        .accessibilityIdentifier("program.setActive")
    }

    private var viewModePicker: some View {
        Picker("Program View", selection: $detailMode) {
            Text("Overview").tag(ProgramDetailMode.overview)
            Text("Days").tag(ProgramDetailMode.days)
        }
        .pickerStyle(.segmented)
        .disabled(isReorderMode || showingAddWorkout)
        .accessibilityLabel("Program View")
        .accessibilityHint("Switches between the all-days overview and workout day management")
    }

    private var addWorkoutButton: some View {
        PrimaryButton("Add Workout Day", icon: "plus") {
            if detailMode == .overview {
                detailMode = .days
            }
            showAddWorkoutOverlay()
        }
        .disabled(isReorderMode)
        .opacity(isReorderMode ? 0.45 : 1.0)
    }

    private var emptyWorkoutsState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                Text("No workout days yet")
                    .font(.subheadline.bold())
                Text("Add workout days to build your program structure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func deleteProgram() {
        onDeleteProgram?()
        dismiss()
    }

    private func showAddWorkoutOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingAddWorkout = true
        }
    }

    private func hideAddWorkoutOverlay() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingAddWorkout = false
        }
    }

    private func addWorkout(named name: String) {
        // The overlay stays tappable while it fades out, so only add from an open overlay.
        guard showingAddWorkout else { return }

        switch viewModel.addWorkout(named: name, to: program, context: context) {
        case .success:
            hideAddWorkoutOverlay()
        case .failure(let error):
            // Keep the overlay open so the typed name can be submitted again.
            presentPersistenceAlert(title: "Couldn't Add Workout Day", error: error)
        }
    }

    private func setProgramActive() {
        if case .failure(let error) = viewModel.setActive(program, context: context) {
            presentPersistenceAlert(title: "Couldn't Set Active Program", error: error)
        }
    }

    private func commitWorkoutOrder(_ orderedIDs: [UUID]) {
        guard deletionCoordinator?.hasPendingWorkouts(in: program) != true else { return }
        if case .failure(let error) = viewModel.reorderWorkouts(in: program, orderedIDs: orderedIDs, context: context) {
            presentPersistenceAlert(title: "Couldn't Save Order", error: error)
        }
    }

    private func presentPersistenceAlert(title: String, error: PersistenceCommandError) {
        persistenceAlert = PersistenceAlert(title: title, error: error)
        showingPersistenceAlert = true
    }

    private func enterReorderMode(if canToggle: Bool) {
        guard canToggle else { return }
        isReorderMode = true
    }

    private func exitReorderMode() {
        isReorderMode = false
    }
}

private struct AddWorkoutOverlay: View {
    let onCancel: () -> Void
    let onSubmit: (String) -> Void

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    cancel()
                }
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Text("Add Workout Day")
                    .font(.headline)
                    .foregroundStyle(.white)

                TextField("e.g. Push Day, Day 1", text: $name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { submit() }
                    .padding(14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    GlassButton("Cancel", role: .cancel) {
                        cancel()
                    }

                    PrimaryButton("Add") {
                        submit()
                    }
                    .opacity(trimmedName.isEmpty ? 0.4 : 1.0)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .padding(24)
            .glassBackground(cornerRadius: 20)
            .padding(.horizontal, 32)
            .onAppear { isNameFocused = true }
        }
        // Keeps VoiceOver inside the overlay, like a system alert, and lets the
        // two-finger scrub gesture cancel it.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { cancel() }
    }

    private func cancel() {
        isNameFocused = false
        onCancel()
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        isNameFocused = false
        onSubmit(trimmedName)
    }
}

struct WorkoutTemplateRow: View {
    let workout: WorkoutTemplate
    let isReorderMode: Bool
    let dragHandle: ReorderDragHandle

    var body: some View {
        let exercises = workout.sortedExercises

        HStack(spacing: 16) {
            if isReorderMode {
                rowContent(exercises: exercises)
            } else {
                // Resolved by `ProgramsView`'s `navigationDestination(for:)`.
                NavigationLink(value: ProgramsRoute.workout(workout)) {
                    rowContent(exercises: exercises)
                }
                .buttonStyle(.plain)
            }

            if isReorderMode {
                dragHandle
                    .accessibilityIdentifier("workout.drag.\(workout.name)")
            }
        }
        .padding(20)
        .glassBackground()
    }

    private func rowContent(exercises: [PlannedExercise]) -> some View {
        let isEmpty = exercises.isEmpty
        let preview = exercises.prefix(3).compactMap(\.exercise?.name)
        let overflow = exercises.count - preview.count
        let baseText = preview.joined(separator: " · ")

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if isEmpty {
                        Circle()
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                            .frame(width: 6, height: 6)
                    } else {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                    Text(workout.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .tracking(-0.3)
                }

                if !isEmpty {
                    if overflow > 0 {
                        Text("\(baseText)  +\(overflow) more")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(baseText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(isEmpty ? Color.white.opacity(0.05) : Color.blue.opacity(isReorderMode ? 0.08 : 0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(
                        isEmpty
                        ? Color.secondary.opacity(isReorderMode ? 0.22 : 0.4)
                        : Color.blue.opacity(isReorderMode ? 0.55 : 1.0)
                    )
            }
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
