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
    @State private var persistenceAlert: PersistenceAlert?
    @State private var showingPersistenceAlert = false
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?

    var body: some View {
        let visibleExercises = SiblingOrder.exercises(workout.plannedExercisesList)
            .filter { deletionCoordinator?.isPending($0) != true }
        let canToggleReorderMode = deletionCoordinator?.hasPendingExercises(in: workout) != true
            && !showingExercisePicker
            && visibleExercises.count > 1

        ScrollView {
            VStack(spacing: 12) {
                if visibleExercises.isEmpty {
                    emptyExercisesState
                } else {
                    GlassEffectContainer(spacing: 12) {
                        ReorderableForEach(
                            items: visibleExercises,
                            isEnabled: isReorderMode && canToggleReorderMode,
                            onCommitOrder: { orderedIDs in
                                commitExerciseOrder(orderedIDs)
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
                        exitReorderMode()
                    }
                    .accessibilityLabel("Done Reordering")
                }

                Menu {
                    if visibleExercises.count > 1 && !isReorderMode {
                        Button {
                            enterReorderMode(if: canToggleReorderMode)
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
            RenameWorkoutDaySheet(workout: workout).deletionUndoToast(deletionCoordinator)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                addExercise(exercise)
            }.deletionUndoToast(deletionCoordinator)
        }
        .onChange(of: deletionCoordinator?.hasPendingExercises(in: workout)) { _, pending in
            if pending == true { exitReorderMode() }
        }
        .persistenceAlert(isPresented: $showingPersistenceAlert, alert: persistenceAlert)
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

    /// Adds the picked exercise. The picker shows failures and stays open for another try.
    private func addExercise(_ exercise: Exercise) -> Result<Void, PersistenceCommandError> {
        viewModel.addExercise(exercise, to: workout, repTargetType: plannedRepTargetDefault, context: context)
            .map { _ in }
    }

    private func commitExerciseOrder(_ orderedIDs: [UUID]) {
        guard deletionCoordinator?.hasPendingExercises(in: workout) != true else { return }
        if case .failure(let error) = viewModel.reorderExercises(in: workout, orderedIDs: orderedIDs, context: context) {
            persistenceAlert = PersistenceAlert(title: "Couldn't Save Order", error: error)
            showingPersistenceAlert = true
        }
    }

    private func deletePlannedExercise(_ planned: PlannedExercise) {
        exitReorderMode()
        deletionCoordinator?.request(planned)
    }

    private func deleteWorkout() {
        exitReorderMode()
        onDeleteWorkout?()
        dismiss()
    }

    private func enterReorderMode(if canToggle: Bool) {
        guard canToggle else { return }
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
    @Environment(\.locale) private var locale
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(planned.exercise?.name ?? "Exercise")
        .sheet(isPresented: $showingEdit) {
            EditPlannedExerciseView(
                planned: planned,
                weightInput: WeightInput(unit: weightUnit, locale: locale)
            ).deletionUndoToast(deletionCoordinator)
        }
    }
}

struct RenameWorkoutDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let workout: WorkoutTemplate
    @State private var viewModel = WorkoutTemplateDetailViewModel()
    @State private var name: String
    @State private var saveAlert: PersistenceAlert?
    @State private var showingSaveAlert = false
    @FocusState private var isFocused: Bool

    init(workout: WorkoutTemplate) {
        self.workout = workout
        _name = State(initialValue: workout.name)
    }

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
                isFocused = true
            }
        }
        .persistenceAlert(isPresented: $showingSaveAlert, alert: saveAlert)
    }

    private func save() {
        switch viewModel.renameWorkout(workout, to: name, context: context) {
        case .success:
            dismiss()
        case .failure(let error):
            saveAlert = PersistenceAlert(title: "Couldn't Rename Workout Day", error: error)
            showingSaveAlert = true
        }
    }
}

struct EditPlannedExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let planned: PlannedExercise

    @State private var viewModel = WorkoutTemplateDetailViewModel()
    @State private var sets: Int
    @State private var repTargetType: PlannedRepTargetType
    @State private var exactReps: Int
    @State private var rangeLowerBound: Int
    @State private var rangeUpperBound: Int
    @State private var weightDraft: WeightDraft
    @State private var saveAlert: PersistenceAlert?
    @State private var showingSaveAlert = false
    @FocusState private var isWeightFieldFocused: Bool

    /// Captures the display unit and locale when the sheet opens. An untouched target
    /// weight saves the original stored value.
    init(planned: PlannedExercise, weightInput: WeightInput) {
        self.planned = planned
        _sets = State(initialValue: planned.sets)
        _repTargetType = State(initialValue: planned.repTargetType)
        _exactReps = State(initialValue: planned.exactRepTarget)
        let repRange = planned.repRange
        _rangeLowerBound = State(initialValue: repRange.lowerBound)
        _rangeUpperBound = State(initialValue: repRange.upperBound)
        _weightDraft = State(initialValue: WeightDraft(input: weightInput, pounds: planned.targetWeight))
    }

    private var resolvedTargetWeight: Result<Double?, WeightInputError> {
        weightDraft.resolvedPounds(whenBlank: .noWeight)
    }

    private var weightMessage: String? {
        weightDraft.validationMessage(whenBlank: .noWeight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                        Text("Target Weight (\(weightDraft.input.unit.symbol))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        TextField("Optional", text: $weightDraft.text)
                            .accessibilityLabel("Target weight in \(weightDraft.input.unit.spokenName)")
                            .keyboardType(.decimalPad)
                            .focused($isWeightFieldFocused)
                            .padding(14)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                if weightMessage != nil {
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.red.opacity(0.7), lineWidth: 1)
                                }
                            }
                        if let weightMessage {
                            WeightValidationMessage(weightMessage)
                        }
                    }
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) {
                PinnedActionBar(isFieldFocused: $isWeightFieldFocused) {
                    PrimaryButton("Save") { save() }
                        .disabled(weightMessage != nil)
                }
            }
            .background {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Edit Exercise")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
            }
            .onChange(of: repTargetType) { _, newValue in
                normalizeDraftRepTarget(for: newValue)
            }
        }
        .persistenceAlert(isPresented: $showingSaveAlert, alert: saveAlert)
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
        guard case .success(let targetWeight) = resolvedTargetWeight else { return }

        let result = viewModel.updatePlannedExercise(
            planned,
            sets: sets,
            repTargetType: repTargetType,
            exactReps: exactReps,
            rangeLowerBound: rangeLowerBound,
            rangeUpperBound: rangeUpperBound,
            targetWeight: targetWeight,
            context: context
        )

        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            saveAlert = PersistenceAlert(title: "Couldn't Save Exercise", error: error)
            showingSaveAlert = true
        }
    }
}
