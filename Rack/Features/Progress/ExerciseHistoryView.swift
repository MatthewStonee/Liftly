import SwiftUI
import SwiftData
import Combine

struct ExerciseHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    let exercise: Exercise
    @State private var viewModel = ExerciseHistoryViewModel()
    @State private var editViewModel = ProgressViewModel()
    @State private var setToEdit: LoggedSet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(exercise.name)
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                TimeRangePicker(selection: viewModel.range, identifierPrefix: "history.range") { choice in
                    viewModel.selectRange(choice, exerciseID: exercise.id, context: context, excluding: pendingIDs)
                }

                if let loadingError = viewModel.initialError {
                    ContentUnavailableView {
                        Label("Couldn't Load History", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadingError.message)
                    } actions: {
                        Button("Retry") { retry() }
                            .buttonStyle(.glassProminent)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("history.initialRetry")
                    }
                } else if viewModel.rows.isEmpty && !viewModel.hasAnyHistory {
                    ContentUnavailableView("No Sets Yet", systemImage: "dumbbell", description: Text("Logged sets for this exercise will appear here."))
                } else if viewModel.rows.isEmpty {
                    ContentUnavailableView("No Sets in This Period", systemImage: "calendar", description: Text("Choose a longer time range to see earlier sets."))
                } else {
                    GlassCard(padding: 14) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.rows) { set in
                                historyRow(set)
                                    .id(set.id)
                                    .accessibilityIdentifier("history.row.\(set.id.uuidString)")
                                if set.id != viewModel.rows.last?.id {
                                    Divider().background(.white.opacity(0.07))
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("history.list")
                    .accessibilityValue("\(viewModel.rows.count) sets loaded")

                    if viewModel.inlineError == nil && viewModel.hasMore {
                        Button {
                            loadMore()
                        } label: {
                            Text("Load More")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("history.loadMore")
                    }
                }

                if let inlineError = viewModel.inlineError {
                    HStack(spacing: 12) {
                        Text(inlineError.message)
                            .font(.subheadline)
                        Spacer(minLength: 0)
                        Button("Retry") { retry() }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("history.inlineRetry")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollPosition(id: $viewModel.scrollAnchorID)
        .navigationTitle("History")
        .titleDisplayMode(.inline)
        .appBackground()
        .sheet(item: $setToEdit) { set in
            EditLoggedSetSheet(
                set: set,
                viewModel: editViewModel,
                weightInput: WeightInput(unit: weightUnit, locale: locale)
            ).deletionUndoToast(deletionCoordinator)
        }
        .onAppear {
            viewModel.appear(exerciseID: exercise.id, context: context, excluding: pendingIDs)
        }
        .onReceive(NotificationCenter.default.publisher(for: LoggedSetChange.didCommit)) { notification in
            viewModel.handleCommittedChange(
                notification, exerciseID: exercise.id, context: context, excluding: pendingIDs
            )
        }
        .onChange(of: pendingIDs) { _, _ in
            refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private var pendingIDs: Set<UUID> {
        deletionCoordinator?.pendingLoggedSetIDs(for: exercise.id) ?? []
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
                .accessibilityIdentifier("history.edit.\(set.id.uuidString)")

                Button(role: .destructive) {
                    deletionCoordinator?.request(set)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(minWidth: 80, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("history.delete.\(set.id.uuidString)")
                Spacer()
            }
            .font(.caption)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(set.spokenSummary(unit: weightUnit, dateStyle: .dateTime.month(.abbreviated).day().year()))
    }

    private func refresh() {
        viewModel.refresh(exerciseID: exercise.id, context: context, excluding: pendingIDs)
    }

    private func loadMore() {
        viewModel.loadMore(exerciseID: exercise.id, context: context, excluding: pendingIDs)
    }

    private func retry() {
        viewModel.retry(exerciseID: exercise.id, context: context, excluding: pendingIDs)
    }
}
