import SwiftUI
import SwiftData
import Combine

struct ExerciseHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    let exercise: Exercise
    @State private var viewModel = ProgressViewModel()
    @State private var allSets: [LoggedSet] = []
    @State private var range: ProgressViewModel.TimeRange = .allTime
    @State private var displayedCount = 50
    @State private var loadingError: PersistenceCommandError?
    @State private var setToEdit: LoggedSet?

    private var matchingSets: [LoggedSet] {
        ProgressViewModel.history(allSets, in: range)
            .filter { deletionCoordinator?.isPending($0) != true }
    }

    var body: some View {
        let matching = matchingSets
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(exercise.name)
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                rangePicker

                if let loadingError {
                    ContentUnavailableView {
                        Label("Couldn't Load History", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadingError.message)
                    } actions: {
                        Button("Retry") { reload() }
                            .buttonStyle(.glassProminent)
                            .frame(minHeight: 44)
                    }
                } else if allSets.isEmpty {
                    ContentUnavailableView("No Sets Yet", systemImage: "dumbbell", description: Text("Logged sets for this exercise will appear here."))
                } else if matching.isEmpty {
                    ContentUnavailableView("No Sets in This Period", systemImage: "calendar", description: Text("Choose a longer time range to see earlier sets."))
                } else {
                    GlassCard(padding: 14) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matching.prefix(displayedCount))) { set in
                                historyRow(set)
                                if set.id != matching.prefix(displayedCount).last?.id {
                                    Divider().background(.white.opacity(0.07))
                                }
                            }
                        }
                    }

                    if matching.count > displayedCount {
                        Button {
                            displayedCount += 50
                        } label: {
                            Text("Load More")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle("History")
        .titleDisplayMode(.inline)
        .background {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
        }
        .sheet(item: $setToEdit, onDismiss: reload) { set in
            EditLoggedSetSheet(
                set: set,
                viewModel: viewModel,
                weightInput: WeightInput(unit: weightUnit, locale: locale)
            ).deletionUndoToast(deletionCoordinator)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reload()
        }
        .onChange(of: deletionCoordinator?.pendingCount) { _, count in
            if count == 0 { reload() }
        }
    }

    private var rangePicker: some View {
        GlassCard(padding: 8) {
            HStack(spacing: 0) {
                ForEach(ProgressViewModel.TimeRange.allCases, id: \.self) { choice in
                    Button {
                        range = choice
                    } label: {
                        Text(choice.rawValue)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(range == choice ? Color.white : Color.secondary)
                            .background {
                                if range == choice {
                                    RoundedRectangle(cornerRadius: 10).fill(.blue)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.rawValue) history")
                }
            }
        }
    }

    private func historyRow(_ set: LoggedSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(set.completedAt.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(set.weight == 0 ? "Bodyweight" : "\(set.weight.formattedWeight(unit: weightUnit)) \(weightUnit.symbol)")
                    .font(.subheadline.bold())
                Spacer(minLength: 8)
                Text("× \(set.reps)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 12) {
                Button {
                    setToEdit = set
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(minWidth: 72, minHeight: 44)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    deletionCoordinator?.request(set)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(minWidth: 80, minHeight: 44)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .font(.caption)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(set.completedAt.formatted(.dateTime.month(.abbreviated).day().year())), \(set.weight.formattedWeight(unit: weightUnit)) \(weightUnit.symbol), \(set.reps) reps")
    }

    private func reload() {
        switch viewModel.fetchHistory(for: exercise, context: context) {
        case .success(let sets):
            allSets = sets
            loadingError = nil
        case .failure(let error):
            allSets = []
            loadingError = error
        }
    }
}
