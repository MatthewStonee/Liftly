import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var program: Program
    @Query private var allPrograms: [Program]
    @State private var showingAddWorkout = false
    @State private var editingWorkoutName: WorkoutTemplate?
    @State private var newWorkoutName = ""
    @State private var editingTitle = false
    @State private var draftName = ""
    @State private var confirmingDelete = false

    private var gradient: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                programHero

                if program.sortedWorkouts.isEmpty {
                    emptyWorkoutsState
                } else {
                    ForEach(program.sortedWorkouts) { workout in
                        NavigationLink(destination: WorkoutTemplateDetailView(workout: workout)) {
                            WorkoutTemplateRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }

                PrimaryButton("Add Workout Day", icon: "plus") {
                    showingAddWorkout = true
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(program.name)
        .titleDisplayMode(.inline)
        .background { gradient }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !program.isActive {
                        Button {
                            for p in allPrograms { p.isActive = false }
                            program.isActive = true
                            try? context.save()
                        } label: {
                            Label("Set as Active", systemImage: "checkmark.circle")
                        }
                    }
                    Button {
                        draftName = program.name
                        editingTitle = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Program", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .fontWeight(.semibold)
                }
            }
        }
        .alert("Rename Program", isPresented: $editingTitle) {
            TextField("Program name", text: $draftName)
            Button("Save") {
                let trimmed = draftName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    program.name = trimmed
                    try? context.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Program", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { deleteProgram() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(program.name)\" and all its workout days will be permanently removed.")
        }
        .alert("Add Workout Day", isPresented: $showingAddWorkout) {
            TextField("e.g. Push Day, Day 1", text: $newWorkoutName)
            Button("Add") { addWorkout() }
            Button("Cancel", role: .cancel) { newWorkoutName = "" }
        } message: {
            Text("Name this workout day")
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

            HStack(spacing: 12) {
                heroStatCard(
                    value: "\(program.workouts.count)",
                    label: program.workouts.count == 1 ? "Day" : "Days"
                )
                heroStatCard(
                    value: "\(program.workouts.reduce(0) { $0 + $1.plannedExercises.count })",
                    label: "Exercises"
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func heroStatCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
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
        context.delete(program)
        try? context.save()
        dismiss()
    }

    private func addWorkout() {
        let trimmed = newWorkoutName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let workout = WorkoutTemplate(name: trimmed, orderIndex: program.workouts.count)
        workout.program = program
        program.workouts.append(workout)
        context.insert(workout)
        try? context.save()
        newWorkoutName = ""
    }
}

struct WorkoutTemplateRow: View {
    let workout: WorkoutTemplate

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .tracking(-0.3)

                HStack(spacing: 6) {
                    Circle()
                        .fill(workout.plannedExercises.isEmpty ? Color.secondary.opacity(0.4) : Color.blue)
                        .frame(width: 6, height: 6)
                    Text("\(workout.plannedExercises.count) \(workout.plannedExercises.count == 1 ? "exercise" : "exercises")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(workout.plannedExercises.isEmpty ? Color.white.opacity(0.05) : Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(workout.plannedExercises.isEmpty ? Color.secondary.opacity(0.4) : Color.blue)
            }
        }
        .padding(20)
        .glassBackground()
    }
}
