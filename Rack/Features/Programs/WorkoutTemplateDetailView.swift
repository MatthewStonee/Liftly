import SwiftUI
import SwiftData

struct WorkoutTemplateDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var workout: WorkoutTemplate
    var onDeleteWorkout: (() -> Void)?
    @AppStorage("plannedRepTargetDefault") private var plannedRepTargetDefault: PlannedRepTargetType = .exact
    @State private var showingExercisePicker = false
    @State private var showingRenameSheet = false
    @State private var viewModel = WorkoutTemplateDetailViewModel()
    @State private var isReorderMode = false
    @State private var pendingDeleteExercise: PlannedExercise?
    @State private var exerciseDeleteTask: Task<Void, Never>?

    private var visibleExercises: [PlannedExercise] {
        workout.sortedExercises.filter { $0.id != pendingDeleteExercise?.id }
    }

    private var canToggleReorderMode: Bool {
        pendingDeleteExercise == nil && !showingExercisePicker && visibleExercises.count > 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if visibleExercises.isEmpty {
                    emptyExercisesState
                } else {
                    ReorderableForEach(
                        items: visibleExercises,
                        isEnabled: isReorderMode,
                        onCommitOrder: { orderedIDs in
                            viewModel.reorderExercises(in: workout, orderedIDs: orderedIDs, context: context)
                        }
                    ) { planned, dragHandle in
                        PlannedExerciseRow(
                            planned: planned,
                            isReorderMode: isReorderMode,
                            dragHandle: dragHandle
                        ) {
                                deletePlannedExercise(planned)
                            }
                    }
                }

                PrimaryButton("Add Exercise", icon: "plus.circle") {
                    showingExercisePicker = true
                }
                .disabled(isReorderMode)
                .opacity(isReorderMode ? 0.45 : 1.0)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(workout.name)
        .titleDisplayMode(.large)
        .background {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isReorderMode {
                    Button("Done") {
                        toggleReorderMode()
                    }
                    .accessibilityLabel("Done Reordering")
                }

                Menu {
                    if visibleExercises.count > 1 && !isReorderMode {
                        Button {
                            toggleReorderMode()
                        } label: {
                            Label("Reorder", systemImage: "arrow.up.arrow.down")
                        }
                        .disabled(!canToggleReorderMode)
                    }

                    if !isReorderMode {
                        Button {
                            showingRenameSheet = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteWorkout()
                        } label: {
                            Label("Delete Workout Day", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Workout Options")
            }
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenameWorkoutDaySheet(workout: workout)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                addExercise(exercise)
            }
        }
        .undoToast(
            isPresented: Binding(
                get: { pendingDeleteExercise != nil },
                set: { if !$0 { pendingDeleteExercise = nil } }
            ),
            message: "Exercise deleted",
            onUndo: {
                exerciseDeleteTask?.cancel()
                exerciseDeleteTask = nil
                pendingDeleteExercise = nil
            }
        )
    }

    private var emptyExercisesState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                Text("No exercises yet")
                    .font(.subheadline.bold())
                Text("Add exercises to define this workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func addExercise(_ exercise: Exercise) {
        let planned = PlannedExercise(
            exercise: exercise,
            sets: 3,
            reps: PlannedRepTargetDefaults.exactReps,
            repTargetType: plannedRepTargetDefault,
            repRangeLowerBound: PlannedRepTargetDefaults.rangeLowerBound,
            repRangeUpperBound: PlannedRepTargetDefaults.rangeUpperBound,
            orderIndex: workout.plannedExercisesList.count
        )
        planned.workoutTemplate = workout
        var plannedExercises = workout.plannedExercises ?? []
        plannedExercises.append(planned)
        workout.plannedExercises = plannedExercises
        context.insert(planned)
    }

    private func deletePlannedExercise(_ planned: PlannedExercise) {
        exitReorderMode()
        exerciseDeleteTask?.cancel()
        pendingDeleteExercise = planned
        exerciseDeleteTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                var plannedExercises = workout.plannedExercises ?? []
                plannedExercises.removeAll { $0.id == planned.id }
                workout.plannedExercises = plannedExercises
                context.delete(planned)
                pendingDeleteExercise = nil
            }
        }
    }

    private func deleteWorkout() {
        exitReorderMode()
        onDeleteWorkout?()
        dismiss()
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

struct PlannedExerciseRow: View {
    @Bindable var planned: PlannedExercise
    let isReorderMode: Bool
    let dragHandle: ReorderDragHandle
    let onDelete: () -> Void
    @State private var showingEdit = false
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let muscle = planned.exercise?.muscleGroup {
                        Text(muscle.rawValue.uppercased())
                            .font(.caption2.bold())
                            .tracking(1)
                            .foregroundStyle(muscle.color.opacity(0.8))
                    }
                    Text(planned.exercise?.name ?? "Exercise")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .tracking(-0.3)
                    if let equip = planned.exercise?.equipment {
                        Text(equip.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    if !isReorderMode {
                        Menu {
                            Button {
                                showingEdit = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Exercise Options")
                    }

                    if isReorderMode {
                        dragHandle
                    }
                }
            }

            HStack(spacing: 8) {
                SetRepsBadge(value: "\(planned.sets)", label: "sets")
                SetRepsBadge(value: planned.formattedRepTarget, label: "target")
                if let weight = planned.targetWeight {
                    SetRepsBadge(value: weight.formattedWeight(unit: weightUnit), label: weightUnit.symbol)
                }
            }
        }
        .padding(16)
        .glassBackground()
        .accessibilityLabel(planned.exercise?.name ?? "Exercise")
        .sheet(isPresented: $showingEdit) {
            EditPlannedExerciseView(planned: planned)
        }
    }
}

struct RenameWorkoutDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var workout: WorkoutTemplate
    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout Day Name")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $name)
                            .font(.title3)
                            .padding(14)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                            )
                            .autocorrectionDisabled()
                            .focused($isFocused)
                    }
                    Spacer()
                    PrimaryButton("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Rename Workout Day")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                name = workout.name
                isFocused = true
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        workout.name = trimmed
        dismiss()
    }
}

struct EditPlannedExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var planned: PlannedExercise

    @State private var sets: Int = 3
    @State private var repTargetType: PlannedRepTargetType = .exact
    @State private var exactReps: Int = PlannedRepTargetDefaults.exactReps
    @State private var rangeLowerBound: Int = PlannedRepTargetDefaults.rangeLowerBound
    @State private var rangeUpperBound: Int = PlannedRepTargetDefaults.rangeUpperBound
    @State private var weight: String = ""
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    Text(planned.exercise?.name ?? "Exercise")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    GlassCard {
                        VStack(spacing: 16) {
                            Stepper("Sets: \(sets)", value: $sets, in: 1...20)
                            Divider().background(.white.opacity(0.1))
                            Picker("Rep Target", selection: $repTargetType) {
                                ForEach(PlannedRepTargetType.allCases, id: \.self) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            repTargetEditor
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Weight (\(weightUnit.symbol))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        TextField("Optional", text: $weight)
                            .keyboardType(.decimalPad)
                            .padding(14)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }

                    Spacer()

                    PrimaryButton("Save") { save() }
                }
                .padding(20)
            }
            .navigationTitle("Edit Exercise")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .onAppear {
                sets = planned.sets
                repTargetType = planned.repTargetType
                exactReps = planned.exactRepTarget
                let repRange = planned.repRange
                rangeLowerBound = repRange.lowerBound
                rangeUpperBound = repRange.upperBound
                if let w = planned.targetWeight {
                    weight = w.formattedWeight(unit: weightUnit)
                }
            }
            .onChange(of: repTargetType) { _, newValue in
                normalizeDraftRepTarget(for: newValue)
            }
        }
    }

    @ViewBuilder
    private var repTargetEditor: some View {
        switch repTargetType {
        case .exact:
            Stepper("Reps: \(exactReps)", value: $exactReps, in: 1...100)
        case .range:
            VStack(spacing: 16) {
                Stepper("Lower Reps: \(rangeLowerBound)", value: $rangeLowerBound, in: 1...rangeUpperBound)
                Divider().background(.white.opacity(0.1))
                Stepper("Upper Reps: \(rangeUpperBound)", value: $rangeUpperBound, in: rangeLowerBound...100)
            }
        case .failure:
            VStack(alignment: .leading, spacing: 8) {
                Text("Target")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text("This exercise will be programmed to failure.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func normalizeDraftRepTarget(for type: PlannedRepTargetType) {
        exactReps = max(1, exactReps)
        rangeLowerBound = max(1, rangeLowerBound)
        rangeUpperBound = max(rangeLowerBound, rangeUpperBound)

        switch type {
        case .exact:
            if exactReps < 1 {
                exactReps = PlannedRepTargetDefaults.exactReps
            }
        case .range:
            if rangeLowerBound < 1 {
                rangeLowerBound = PlannedRepTargetDefaults.rangeLowerBound
            }
            if rangeUpperBound < rangeLowerBound {
                rangeUpperBound = max(rangeLowerBound, PlannedRepTargetDefaults.rangeUpperBound)
            }
        case .failure:
            break
        }
    }

    private func save() {
        planned.sets = sets
        planned.configureRepTarget(
            repTargetType,
            exactReps: exactReps,
            rangeLowerBound: rangeLowerBound,
            rangeUpperBound: rangeUpperBound
        )
        planned.targetWeight = Double(weight).map { weightUnit.store($0) }
        dismiss()
    }
}
