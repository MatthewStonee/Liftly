import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (Exercise) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedMuscle: MuscleGroup? = nil
    @State private var showingCreate = false
    @State private var searchDebounceTask: Task<Void, Never>?

    init(onSelect: @escaping (Exercise) -> Void) {
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                muscleFilter
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ExercisePickerResultsView(
                    selectedMuscle: selectedMuscle,
                    searchText: debouncedSearchText,
                    hasActiveFilter: selectedMuscle != nil || !debouncedSearchText.isEmpty,
                    onSelect: onSelect
                )
                .id("\(selectedMuscle?.rawValue ?? "All")|\(debouncedSearchText)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Choose Exercise")
            .titleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises")
            .onChange(of: searchText) { _, newValue in
                debounceSearch(newValue)
            }
            .onDisappear {
                searchDebounceTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Create Exercise")
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateExerciseView()
            }
        }
    }

    private func debounceSearch(_ text: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedSearchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private var muscleFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedMuscle == nil) {
                    selectedMuscle = nil
                }
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    FilterChip(title: muscle.rawValue, isSelected: selectedMuscle == muscle) {
                        selectedMuscle = selectedMuscle == muscle ? nil : muscle
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

}

private struct ExercisePickerResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let hasActiveFilter: Bool
    let onSelect: (Exercise) -> Void

    init(
        selectedMuscle: MuscleGroup?,
        searchText: String,
        hasActiveFilter: Bool,
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.hasActiveFilter = hasActiveFilter
        self.onSelect = onSelect

        if let selectedMuscle, !searchText.isEmpty {
            _exercises = Query(
                filter: #Predicate<Exercise> { exercise in
                    exercise.muscleGroup == selectedMuscle &&
                    exercise.name.localizedStandardContains(searchText)
                },
                sort: \Exercise.name
            )
        } else if let selectedMuscle {
            _exercises = Query(
                filter: #Predicate<Exercise> { exercise in
                    exercise.muscleGroup == selectedMuscle
                },
                sort: \Exercise.name
            )
        } else if !searchText.isEmpty {
            _exercises = Query(
                filter: #Predicate<Exercise> { exercise in
                    exercise.name.localizedStandardContains(searchText)
                },
                sort: \Exercise.name
            )
        } else {
            _exercises = Query(sort: \Exercise.name)
        }
    }

    var body: some View {
        if exercises.isEmpty {
            emptyState
        } else {
            List {
                ForEach(exercises) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        ExerciseRow(exercise: exercise)
                    }
                    .accessibilityLabel(exercise.name)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(hasActiveFilter ? "No results" : "No exercises yet")
                .font(.headline)
            Text(hasActiveFilter ? "Try a different search or filter" : "Tap + to add your first exercise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(exercise.muscleGroup.color)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    Text(exercise.muscleGroup.rawValue)
                    Text("·")
                    Text(exercise.equipment.rawValue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    isSelected ? Color.blue : Color.white.opacity(0.08),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CreateExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var name = ""
    @State private var muscleGroup: MuscleGroup = .chest
    @State private var equipment: Equipment = .barbell

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        let normalized = ExerciseLibrary.normalizedName(trimmedName)
        guard !normalized.isEmpty else { return false }
        return exercises.contains { ExerciseLibrary.normalizedName($0.name) == normalized }
    }

    private var canCreateExercise: Bool {
        !trimmedName.isEmpty && !isDuplicateName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                Form {
                    Section("Exercise Name") {
                        TextField("e.g. Bench Press", text: $name)
                        if isDuplicateName {
                            Text("An exercise with this name already exists.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Muscle Group") {
                        Picker("Muscle Group", selection: $muscleGroup) {
                            ForEach(MuscleGroup.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section("Equipment") {
                        Picker("Equipment", selection: $equipment) {
                            ForEach(Equipment.allCases, id: \.self) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Exercise")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { createExercise() }
                        .fontWeight(.bold)
                        .disabled(!canCreateExercise)
                }
            }
        }
    }

    private func createExercise() {
        guard canCreateExercise else { return }
        let exercise = Exercise(name: trimmedName, muscleGroup: muscleGroup, equipment: equipment)
        context.insert(exercise)
        try? context.save()
        dismiss()
    }
}
