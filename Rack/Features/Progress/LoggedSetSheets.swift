import SwiftUI
import SwiftData

// MARK: - Quick Log Sheet

struct QuickLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise
    let viewModel: ProgressViewModel

    @State private var weightDraft: WeightDraft
    @State private var reps: Int
    @State private var date: Date = .now
    @State private var saveAlert: PersistenceAlert?
    @State private var showingSaveAlert = false
    @State private var didLogSet = false

    /// Captures the display unit and locale when the sheet opens, and prefills from the
    /// latest set so an untouched weight logs the same stored value.
    init(exercise: Exercise, viewModel: ProgressViewModel, latestSet: LoggedSet?, weightInput: WeightInput) {
        self.exercise = exercise
        self.viewModel = viewModel
        let prefilledWeight = latestSet.flatMap { $0.weight > 0 ? $0.weight : nil }
        _weightDraft = State(initialValue: WeightDraft(input: weightInput, pounds: prefilledWeight))
        _reps = State(initialValue: latestSet?.reps ?? 5)
    }

    private var blankWeight: WeightDraft.BlankValue {
        exercise.equipment == .bodyweight ? .zero : .required
    }

    private var resolvedWeight: Double? {
        guard case .success(let pounds?) = weightDraft.resolvedPounds(whenBlank: blankWeight) else { return nil }
        return pounds
    }

    var body: some View {
        LoggedSetForm(
            title: "Log Set",
            exercise: exercise,
            weightDraft: $weightDraft,
            reps: $reps,
            date: $date,
            blankWeight: blankWeight,
            weightFieldIdentifier: "quickLog.weight",
            onCancel: { dismiss() }
        ) {
            PrimaryButton("Log Set", icon: "checkmark") {
                logSet()
            }
            .disabled(resolvedWeight == nil)
        }
        .persistenceAlert(isPresented: $showingSaveAlert, alert: saveAlert)
    }

    private func logSet() {
        // Ignore extra taps while the sheet closes after a successful log.
        guard !didLogSet, let weight = resolvedWeight else { return }

        switch viewModel.logSet(for: exercise, reps: reps, weight: weight, completedAt: date, context: context) {
        case .success:
            didLogSet = true
            // The sheet dismisses in the same action, so a `.sensoryFeedback` trigger on
            // it might never fire.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        case .failure(let error):
            saveAlert = PersistenceAlert(title: "Couldn't Log Set", error: error)
            showingSaveAlert = true
        }
    }
}

// MARK: - Edit Logged Set Sheet

struct EditLoggedSetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let set: LoggedSet
    let viewModel: ProgressViewModel

    @State private var weightDraft: WeightDraft
    @State private var reps: Int
    @State private var date: Date
    @State private var saveAlert: PersistenceAlert?
    @State private var showingSaveAlert = false

    /// Captures the display unit and locale when the sheet opens. An untouched weight
    /// saves the set's original stored value.
    init(set: LoggedSet, viewModel: ProgressViewModel, weightInput: WeightInput) {
        self.set = set
        self.viewModel = viewModel
        _weightDraft = State(initialValue: WeightDraft(
            input: weightInput,
            pounds: set.weight,
            blankWhenZero: set.exercise?.equipment == .bodyweight
        ))
        _reps = State(initialValue: set.reps)
        _date = State(initialValue: set.completedAt)
    }

    private var blankWeight: WeightDraft.BlankValue {
        self.set.exercise?.equipment == .bodyweight ? .zero : .required
    }

    private var resolvedWeight: Double? {
        guard case .success(let pounds?) = weightDraft.resolvedPounds(whenBlank: blankWeight) else { return nil }
        return pounds
    }

    var body: some View {
        LoggedSetForm(
            title: "Edit Set",
            exercise: set.exercise,
            weightDraft: $weightDraft,
            reps: $reps,
            date: $date,
            blankWeight: blankWeight,
            weightFieldIdentifier: "editSet.weight",
            onCancel: { dismiss() }
        ) {
            PrimaryButton("Save Changes", icon: "checkmark") {
                saveChanges()
            }
            .disabled(resolvedWeight == nil)
        }
        .persistenceAlert(isPresented: $showingSaveAlert, alert: saveAlert)
    }

    private func saveChanges() {
        guard let weight = resolvedWeight else { return }

        switch viewModel.updateSet(set, reps: reps, weight: weight, completedAt: date, context: context) {
        case .success:
            dismiss()
        case .failure(let error):
            saveAlert = PersistenceAlert(title: "Couldn't Save Set", error: error)
            showingSaveAlert = true
        }
    }
}

// MARK: - Shared Form

/// The fields and chrome shared by the Log Set and Edit Set sheets. Each sheet keeps its
/// own drafts and supplies its primary action.
private struct LoggedSetForm<PrimaryAction: View>: View {
    let title: String
    let exercise: Exercise?
    @Binding var weightDraft: WeightDraft
    @Binding var reps: Int
    @Binding var date: Date
    let blankWeight: WeightDraft.BlankValue
    let weightFieldIdentifier: String
    let onCancel: () -> Void
    @ViewBuilder let primaryAction: () -> PrimaryAction

    @FocusState private var isWeightFieldFocused: Bool

    private var weightMessage: String? {
        weightDraft.validationMessage(whenBlank: blankWeight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let exercise {
                        exerciseHeader(exercise)
                    }
                    weightField
                    repsStepper
                    datePicker
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) {
                PinnedActionBar(isFieldFocused: $isWeightFieldFocused, action: primaryAction)
            }
            .appBackground()
            .navigationTitle(title)
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exerciseHeader(_ exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(exercise.muscleGroup.color)
                .frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.headline)
                Text(exercise.muscleGroup.rawValue + " \u{b7} " + exercise.equipment.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassBackground()
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight (\(weightDraft.input.unit.symbol))")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            TextField("0", text: $weightDraft.text)
                .accessibilityLabel("Weight in \(weightDraft.input.unit.spokenName)")
                .keyboardType(.decimalPad)
                .focused($isWeightFieldFocused)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(16)
                .accessibilityIdentifier(weightFieldIdentifier)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            weightMessage == nil ? Color.white.opacity(0.1) : Color.red.opacity(0.7),
                            lineWidth: weightMessage == nil ? 0.5 : 1
                        )
                )
            if let weightMessage {
                WeightValidationMessage(weightMessage)
            }
        }
    }

    private var repsStepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reps")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            HStack {
                repsButton(systemImage: "minus", label: "Decrease reps") {
                    if reps > 1 { reps -= 1 }
                }

                Text("\(reps)")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity)

                repsButton(systemImage: "plus", label: "Increase reps") {
                    reps += 1
                }
            }
        }
    }

    /// Holding the button repeats its step, so reaching 12 or 20 reps doesn't take a tap each.
    private func repsButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}
