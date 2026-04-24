import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var program: Program
    @Query private var allPrograms: [Program]
    var onDeleteProgram: (() -> Void)?
    @State private var showingAddWorkout = false
    @State private var editingWorkoutName: WorkoutTemplate?
    @State private var newWorkoutName = ""
    @State private var showingEditProgram = false
    @State private var pendingDeleteWorkout: WorkoutTemplate?
    @State private var workoutDeleteTask: Task<Void, Never>?
    @FocusState private var workoutNameFocused: Bool
    @State private var viewModel = ProgramDetailViewModel()
    @State private var isReorderMode = false
    @State private var selectedWorkout: WorkoutTemplate?

    private var gradient: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var visibleWorkouts: [WorkoutTemplate] {
        program.sortedWorkouts.filter { $0.id != pendingDeleteWorkout?.id }
    }

    private var canToggleReorderMode: Bool {
        pendingDeleteWorkout == nil && !showingAddWorkout && visibleWorkouts.count > 1
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    programHero

                    if visibleWorkouts.isEmpty {
                        emptyWorkoutsState
                    } else {
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

                    PrimaryButton("Add Workout Day", icon: "plus") {
                        newWorkoutName = ""
                        showAddWorkoutOverlay()
                    }
                    .disabled(isReorderMode)
                    .opacity(isReorderMode ? 0.45 : 1.0)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .allowsHitTesting(!showingAddWorkout)

            if showingAddWorkout {
                addWorkoutOverlay
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
                        if let program = workout.program {
                            var workouts = program.workouts ?? []
                            workouts.removeAll { $0.id == workout.id }
                            program.workouts = workouts
                        }
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
                        toggleReorderMode()
                    }
                    .accessibilityLabel("Done Reordering")
                }

                Menu {
                    if visibleWorkouts.count > 1 && !isReorderMode {
                        Button {
                            toggleReorderMode()
                        } label: {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(!canToggleReorderMode)
                    }

                    if !isReorderMode {
                        if !program.isActive {
                            Button {
                                for p in allPrograms { p.isActive = false }
                                program.isActive = true
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

    private var addWorkoutOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    workoutNameFocused = false
                    newWorkoutName = ""
                    hideAddWorkoutOverlay()
                }

            VStack(spacing: 16) {
                Text("Add Workout Day")
                    .font(.headline)
                    .foregroundStyle(.white)

                TextField("e.g. Push Day, Day 1", text: $newWorkoutName)
                    .focused($workoutNameFocused)
                    .submitLabel(.done)
                    .onSubmit { submitWorkout() }
                    .padding(14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    GlassButton("Cancel", role: .cancel) {
                        workoutNameFocused = false
                        newWorkoutName = ""
                        hideAddWorkoutOverlay()
                    }

                    PrimaryButton("Add") {
                        submitWorkout()
                    }
                    .opacity(newWorkoutName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1.0)
                    .disabled(newWorkoutName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .glassBackground(cornerRadius: 20)
            .padding(.horizontal, 32)
            .onAppear { workoutNameFocused = true }
        }
    }

    private var programHero: some View {
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

            HStack(spacing: 12) {
                StatBadge(
                    value: "\(program.workoutsList.count)",
                    label: program.workoutsList.count == 1 ? "Day" : "Days",
                    style: .hero
                )
                StatBadge(
                    value: "\(program.exerciseCount)",
                    label: "Exercises",
                    style: .hero
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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

    private func submitWorkout() {
        workoutNameFocused = false
        addWorkout()
        hideAddWorkoutOverlay()
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

    private func addWorkout() {
        let trimmed = newWorkoutName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let workout = WorkoutTemplate(name: trimmed, orderIndex: program.workoutsList.count)
        workout.program = program
        var workouts = program.workouts ?? []
        workouts.append(workout)
        program.workouts = workouts
        context.insert(workout)
        newWorkoutName = ""
    }

    private func toggleReorderMode() {
        isReorderMode ? exitReorderMode() : enterReorderMode()
    }

    private func enterReorderMode() {
        guard canToggleReorderMode else { return }
        isReorderMode = true
    }

    private func exitReorderMode() {
        isReorderMode = false
    }
}

struct WorkoutTemplateRow: View {
    let workout: WorkoutTemplate
    let isReorderMode: Bool
    let dragHandle: ReorderDragHandle
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if isReorderMode {
                rowContent
            } else {
                Button(action: onTap) {
                    rowContent
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

    private var rowContent: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if workout.plannedExercisesList.isEmpty {
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

                if !workout.sortedExercises.isEmpty {
                    let preview = workout.sortedExercises.prefix(3).compactMap(\.exercise?.name)
                    let overflow = workout.sortedExercises.count - preview.count
                    let baseText = preview.joined(separator: " · ")
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
                    .fill(workout.plannedExercisesList.isEmpty ? Color.white.opacity(0.05) : Color.blue.opacity(isReorderMode ? 0.08 : 0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(
                        workout.plannedExercisesList.isEmpty
                        ? Color.secondary.opacity(isReorderMode ? 0.22 : 0.4)
                        : Color.blue.opacity(isReorderMode ? 0.55 : 1.0)
                    )
            }
        }
        .contentShape(Rectangle())
    }
}
