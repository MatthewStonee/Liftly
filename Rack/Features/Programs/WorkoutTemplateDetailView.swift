import SwiftUI
import SwiftData

struct WorkoutTemplateDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var workout: WorkoutTemplate
    @State private var showingExercisePicker = false
    @State private var editingTitle = false
    @State private var draftName = ""
    @State private var confirmingDelete = false
    @State private var viewModel = WorkoutTemplateDetailViewModel()
    @State private var localExercises: [PlannedExercise] = []
    @State private var isReordering = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if localExercises.isEmpty {
                    emptyExercisesState
                } else {
                    ReorderableForEach(
                        items: $localExercises,
                        isDragging: $isReordering,
                        onMove: { from, to in
                            viewModel.reorderExercises(in: workout, from: from, to: to, context: context)
                        }
                    ) { planned, isDragging in
                        PlannedExerciseRow(planned: planned, isDragging: isDragging) {
                            deletePlannedExercise(planned)
                        }
                    }
                }

                PrimaryButton("Add Exercise", icon: "plus.circle") {
                    showingExercisePicker = true
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDisabled(isReordering)
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        draftName = workout.name
                        editingTitle = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Workout Day", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Workout Options")
            }
        }
        .alert("Rename Workout Day", isPresented: $editingTitle) {
            TextField("Workout name", text: $draftName)
            Button("Save") {
                let trimmed = draftName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    workout.name = trimmed
                    try? context.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Workout Day", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { deleteWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(workout.name)\" and all its exercises will be permanently removed.")
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                addExercise(exercise)
            }
        }
        .onAppear { localExercises = workout.sortedExercises }
        .onChange(of: workout.plannedExercises.count) { localExercises = workout.sortedExercises }
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
            reps: 8,
            orderIndex: workout.plannedExercises.count
        )
        planned.workoutTemplate = workout
        workout.plannedExercises.append(planned)
        context.insert(planned)
        try? context.save()
        localExercises = workout.sortedExercises
    }

    private func deletePlannedExercise(_ planned: PlannedExercise) {
        workout.plannedExercises.removeAll { $0.id == planned.id }
        context.delete(planned)
        try? context.save()
    }

    private func deleteWorkout() {
        if let program = workout.program {
            program.workouts.removeAll { $0.id == workout.id }
        }
        context.delete(workout)
        try? context.save()
        dismiss()
    }
}

struct PlannedExerciseRow: View {
    @Bindable var planned: PlannedExercise
    let isDragging: Bool
    let onDelete: () -> Void
    @State private var showingEdit = false

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
                if !isDragging {
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
                } else {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }

            HStack(spacing: 8) {
                SetRepsBadge(value: "\(planned.sets)", label: "sets")
                SetRepsBadge(value: "\(planned.reps)", label: "reps")
                if let weight = planned.targetWeight {
                    SetRepsBadge(value: String(format: "%.0f", weight), label: "lbs")
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

struct EditPlannedExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var planned: PlannedExercise

    @State private var sets: Int = 3
    @State private var reps: Int = 8
    @State private var weight: String = ""

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
                            Stepper("Reps: \(reps)", value: $reps, in: 1...100)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Weight (lbs)")
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
                reps = planned.reps
                if let w = planned.targetWeight {
                    weight = String(format: "%.0f", w)
                }
            }
        }
    }

    private func save() {
        planned.sets = sets
        planned.reps = reps
        planned.targetWeight = Double(weight)
        try? context.save()
        dismiss()
    }
}
