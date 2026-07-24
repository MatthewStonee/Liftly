import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var program: Program
    @Query private var allPrograms: [Program]
    var onDeleteProgram: (() -> Void)?
    @State private var showingAddWorkout = false
    @State private var showingEditProgram = false
    @State private var pendingDeleteWorkout: WorkoutTemplate?
    @State private var workoutDeleteTask: Task<Void, Never>?
    @State private var viewModel = ProgramDetailViewModel()
    @State private var isReorderMode = false
    @State private var selectedWorkout: WorkoutTemplate?
    @AppStorage("programDetailViewMode") private var detailMode: ProgramDetailMode = .days

    private var gradient: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    var body: some View {
        let workouts = program.workoutsList
        let visibleWorkouts = workouts
            .sorted { $0.orderIndex < $1.orderIndex }
            .filter { $0.id != pendingDeleteWorkout?.id }
        let exerciseCount = workouts.reduce(0) { $0 + $1.plannedExercisesList.count }
        let canToggleReorderMode = detailMode == .days
            && pendingDeleteWorkout == nil
            && !showingAddWorkout
            && visibleWorkouts.count > 1

        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    programHero(
                        workoutCount: workouts.count,
                        exerciseCount: exerciseCount
                    )
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
                                isEnabled: isReorderMode,
                                onCommitOrder: { orderedIDs in
                                    viewModel.reorderWorkouts(in: program, orderedIDs: orderedIDs, context: context)
                                }
                            ) { workout, dragHandle in
                                WorkoutTemplateRow(
                                    workout: workout,
                                    isReorderMode: isReorderMode,
                                    dragHandle: dragHandle,
                                    onTap: {
                                        guard !isReorderMode else { return }
                                        selectedWorkout = workout
                                    }
                                )
                                .accessibilityElement()
                                .accessibilityLabel(workout.name)
                                .accessibilityAddTraits(.isButton)
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

            if showingAddWorkout {
                AddWorkoutOverlay(
                    onCancel: hideAddWorkoutOverlay,
                    onSubmit: { name in
                        addWorkout(named: name)
                        hideAddWorkoutOverlay()
                    }
                )
                    .transition(.opacity)
            }
        }
        .navigationTitle(program.name)
        .titleDisplayMode(.inline)
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutTemplateDetailView(workout: workout, onDeleteWorkout: {
                exitReorderMode()
                pendingDeleteWorkout = workout
                workoutDeleteTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        workout.program = nil
                        context.delete(workout)
                        pendingDeleteWorkout = nil
                    }
                }
            })
        }
        .background { gradient }
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
                        if !program.isActive {
                            Button {
                                setProgramActive()
                            } label: {
                                Label("Set as Active", systemImage: "checkmark.circle")
                            }
                        }
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
            CreateProgramView(existingProgram: program)
        }
        .onChange(of: detailMode) { _, newMode in
            if newMode == .overview {
                exitReorderMode()
            }
        }
        .undoToast(
            isPresented: Binding(
                get: { pendingDeleteWorkout != nil },
                set: { if !$0 { pendingDeleteWorkout = nil } }
            ),
            message: "Workout day deleted",
            onUndo: {
                workoutDeleteTask?.cancel()
                workoutDeleteTask = nil
                pendingDeleteWorkout = nil
            }
        )
    }

    private func programHero(workoutCount: Int, exerciseCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROGRAM")
                .font(.caption.bold())
                .tracking(2)
                .foregroundStyle(.blue)

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
                        value: "\(workoutCount)",
                        label: workoutCount == 1 ? "Day" : "Days",
                        style: .hero
                    )
                    StatBadge(
                        value: "\(exerciseCount)",
                        label: "Exercises",
                        style: .hero
                    )
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
        let workout = WorkoutTemplate(name: name, orderIndex: program.workoutsList.count)
        workout.program = program
        context.insert(workout)
    }

    private func setProgramActive() {
        for candidate in allPrograms where candidate.id != program.id && candidate.isActive {
            candidate.isActive = false
        }

        if !program.isActive {
            program.isActive = true
        }
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
    let onTap: () -> Void

    var body: some View {
        let exercises = workout.sortedExercises

        HStack(spacing: 16) {
            if isReorderMode {
                rowContent(exercises: exercises)
            } else {
                Button(action: onTap) {
                    rowContent(exercises: exercises)
                }
                .buttonStyle(.plain)
            }

            if isReorderMode {
                dragHandle
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
        }
        .contentShape(Rectangle())
    }
}
