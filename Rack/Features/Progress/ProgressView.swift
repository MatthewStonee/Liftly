import SwiftUI
import SwiftData
import Charts
import Combine

// MARK: - Progress Tab

/// Screens pushed onto the Progress tab's navigation stack.
///
/// Keep every push value-based and resolved by the stack root's `navigationDestination(for:)`.
/// On iOS 27, a view-destination `NavigationLink` inside a screen pushed with
/// `navigationDestination(item:)` got stuck in an update loop with the stack when its
/// destination contained a `ScrollView`: opening History froze the app at 100% CPU.
enum ProgressRoute: Hashable {
    case exercise(Exercise)
    case history(Exercise)
}

struct ProgressTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?
    @Query(
        filter: #Predicate<Program> { program in
            program.isActive
        },
        sort: \Program.createdAt,
        order: .reverse
    )
    private var activePrograms: [Program]
    @State private var viewModel = ProgressViewModel()
    @State private var path: [ProgressRoute] = []
    @State private var overviewRefreshTask: Task<Void, Never>?
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.overview.programExercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backgroundGradient }
            .navigationTitle("Progress")
            .titleDisplayMode(.large)
            .navigationDestination(for: ProgressRoute.self) { route in
                switch route {
                case .exercise(let exercise):
                    ExerciseProgressView(exercise: exercise)
                case .history(let exercise):
                    ExerciseHistoryView(exercise: exercise)
                }
            }
            .onAppear { refreshOverview() }
            .onChange(of: activePrograms.first?.id) { _, _ in
                refreshOverview()
            }
            .onChange(of: deletionCoordinator?.generation) { _, _ in
                scheduleOverviewRefresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    scheduleOverviewRefresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                scheduleOverviewRefresh()
            }
            .onDisappear {
                overviewRefreshTask?.cancel()
            }
        }
    }

    private func refreshOverview() {
        overviewRefreshTask?.cancel()
        let selection = overviewSelection
        let modelContainer = context.container
        let currentViewModel = viewModel

        overviewRefreshTask = Task { @MainActor in
            await currentViewModel.refreshOverview(
                activeProgram: selection.program,
                modelContainer: modelContainer,
                excludingWorkoutIDs: selection.excludedWorkoutIDs,
                excludingPlannedIDs: selection.excludedPlannedIDs
            )
        }
    }

    private func scheduleOverviewRefresh() {
        overviewRefreshTask?.cancel()
        let selection = overviewSelection
        let modelContainer = context.container
        let currentViewModel = viewModel

        overviewRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await currentViewModel.refreshOverview(
                activeProgram: selection.program,
                modelContainer: modelContainer,
                excludingWorkoutIDs: selection.excludedWorkoutIDs,
                excludingPlannedIDs: selection.excludedPlannedIDs
            )
        }
    }

    private var overviewSelection: (program: Program?, excludedWorkoutIDs: Set<UUID>, excludedPlannedIDs: Set<UUID>) {
        guard let program = activePrograms.first,
              deletionCoordinator?.isPending(program) != true else {
            return (nil, [], [])
        }
        let excludedWorkoutIDs = Set(program.workoutsList.filter {
            deletionCoordinator?.isPending($0) == true
        }.map(\.id))
        let excludedPlannedIDs = Set(program.workoutsList.flatMap { $0.plannedExercisesList }.filter {
            deletionCoordinator?.isPending($0) == true
        }.map(\.id))
        return (program, excludedWorkoutIDs, excludedPlannedIDs)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var weeklyVolumeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEEKLY VOLUME")
                .font(.caption.bold())
                .tracking(2)
                .foregroundStyle(.blue)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(viewModel.overview.weeklyVolume > 0 ? String(format: "%.0f", weightUnit.display(viewModel.overview.weeklyVolume)) : "\u{2014}")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                if viewModel.overview.weeklyVolume > 0 {
                    Text(weightUnit.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Last 7 days")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassBackground()
    }

    private var exerciseList: some View {
        ScrollView {
            GlassEffectContainer(spacing: 0) {
                LazyVStack(spacing: 12) {
                    weeklyVolumeCard

                    ForEach(viewModel.overview.programExercises) { exercise in
                        ExerciseProgressRow(
                            exercise: exercise,
                            summary: viewModel.overview.summariesByExerciseID[exercise.id] ?? ExerciseProgressSummary()
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            path.append(.exercise(exercise))
                        }
                        .accessibilityElement()
                        .accessibilityLabel(exercise.name)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("progress.exercise.\(exercise.name)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("No Progress Data Yet")
                    .font(.title2.bold())
                Text("Exercises from your active program will appear here once you start logging sets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}

// MARK: - Exercise Row

struct ExerciseProgressRow: View {
    let exercise: Exercise
    let summary: ExerciseProgressSummary
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(exercise.muscleGroup.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.muscleGroup.rawValue.uppercased())
                        .font(.caption2.bold())
                        .tracking(1)
                        .foregroundStyle(exercise.muscleGroup.color.opacity(0.8))
                    Text(exercise.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .tracking(-0.3)
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last PR")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if summary.prWeight > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(summary.prWeight.formattedWeight(unit: weightUnit))
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                Text(weightUnit.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No data")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 0.5, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sets")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(summary.setCount)")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .padding(.vertical, 16)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity)
        .glassBackground()
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Exercise Progress Detail

struct ExerciseProgressView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DeletionCoordinator.self) private var deletionCoordinator: DeletionCoordinator?
    let exercise: Exercise
    @State private var viewModel = ProgressViewModel()
    @State private var showingQuickLog = false
    @State private var setToEdit: LoggedSet?
    @Namespace private var pickerNamespace
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs
    @Environment(\.locale) private var locale

    var body: some View {
        let metrics = viewModel.exerciseMetrics
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    Text(exercise.name)
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.white)
                        .tracking(-0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statsCard(pr: metrics.personalRecord, totalVol: metrics.totalVolume)
                    timeRangePicker
                    ExerciseProgressChartCard(chartPoints: metrics.chartPoints, weightUnit: weightUnit)
                        .equatable()
                    setHistoryCard(
                        recentSets: metrics.recentSets.filter { deletionCoordinator?.isPending($0) != true },
                        isEmpty: !metrics.hasFilteredSets
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(exercise.name)
        .titleDisplayMode(.inline)
        .background {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            Button {
                showingQuickLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.blue)
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .blue.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                    )
                    .shadow(color: .blue.opacity(0.25), radius: 20, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
            }
            .accessibilityLabel("Log Set")
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showingQuickLog) {
            QuickLogSheet(
                exercise: exercise,
                viewModel: viewModel,
                latestSet: viewModel.exerciseMetrics.latestSet,
                weightInput: WeightInput(unit: weightUnit, locale: locale)
            ).deletionUndoToast(deletionCoordinator)
        }
        .sheet(item: $setToEdit) { set in
            EditLoggedSetSheet(
                set: set,
                viewModel: viewModel,
                weightInput: WeightInput(unit: weightUnit, locale: locale)
            ).deletionUndoToast(deletionCoordinator)
        }
        .onAppear {
            viewModel.exerciseDetailAppeared(exercise, context: context)
        }
        .onDisappear {
            viewModel.exerciseDetailDisappeared()
        }
        .onReceive(NotificationCenter.default.publisher(for: LoggedSetChange.didCommit)) { notification in
            viewModel.handleCommittedChange(notification, exercise: exercise, context: context)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.refreshVisibleExerciseMetrics(for: exercise, context: context)
            }
        }
    }

    private func deleteSet(_ set: LoggedSet) {
        deletionCoordinator?.request(set)
    }

    // MARK: Cards

    private func statsCard(pr: LoggedSet?, totalVol: Double) -> some View {
        GlassCard {
            HStack(spacing: 8) {
                StatBadge(
                    value: pr.map { "\($0.weight.formattedWeight(unit: weightUnit)) \(weightUnit.symbol)" } ?? "\u{2014}",
                    label: "PR Weight",
                    surface: .embedded
                )
                StatBadge(
                    value: pr.map { "\($0.reps) reps" } ?? "\u{2014}",
                    label: "At PR",
                    surface: .embedded
                )
                StatBadge(
                    value: totalVol > 0 ? String(format: "%.0f", weightUnit.display(totalVol)) : "\u{2014}",
                    label: "Total Vol. (\(weightUnit.symbol))",
                    surface: .embedded
                )
            }
        }
    }

    private var timeRangePicker: some View {
        GlassCard(padding: 8) {
            HStack(spacing: 0) {
                ForEach(ProgressViewModel.TimeRange.allCases, id: \.self) { range in
                    Button {
                        viewModel.updateTimeRange(range)
                    } label: {
                        Text(range.rawValue)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .foregroundStyle(viewModel.timeRange == range ? Color.white : Color.secondary.opacity(0.7))
                            .background {
                                if viewModel.timeRange == range {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.blue)
                                        .matchedGeometryEffect(id: "pickerPill", in: pickerNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.timeRange)
        }
    }

    private func setHistoryCard(recentSets: [LoggedSet], isEmpty: Bool) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Sets")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Group {
                if isEmpty || recentSets.isEmpty {
                    Text("No sets logged in this period.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                    ForEach(recentSets) { set in
                        HStack {
                            Text(set.completedAt.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            Text(set.weight == 0 ? "Bodyweight" : "\(set.weight.formattedWeight(unit: weightUnit)) \(weightUnit.symbol)")
                                .font(.subheadline)
                            Spacer()
                            Text("\u{d7} \(set.reps)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .onTapGesture { setToEdit = set }
                        .contextMenu {
                            Button {
                                setToEdit = set
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteSet(set)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                        if set.id != recentSets.last?.id {
                            Divider().background(.white.opacity(0.07))
                        }
                    }
                    }
                }
                }

                NavigationLink(value: ProgressRoute.history(exercise)) {
                    HStack {
                        Text("View All History")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.bold())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityIdentifier("progress.viewAllHistory")
            }
        }
    }
}

struct ExerciseProgressChartCard: View, Equatable {
    private struct DisplayPoint {
        let date: Date
        let weight: Double
    }

    let chartPoints: [ExerciseProgressChartPoint]
    let weightUnit: WeightUnit

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chartPoints == rhs.chartPoints && lhs.weightUnit == rhs.weightUnit
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Max Weight Over Time (\(weightUnit.symbol))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                if chartPoints.count < 2 {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Not enough data yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Log sets in at least 2 chart periods to see your trend.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    let displayPoints = chartPoints.map {
                        DisplayPoint(date: $0.date, weight: $0.displayWeight(unit: weightUnit))
                    }
                    Chart {
                        AreaPlot(displayPoints,
                                 x: .value("Date", \.date),
                                 y: .value("Weight (\(weightUnit.symbol))", \.weight))
                            .foregroundStyle(
                                LinearGradient(colors: [.blue.opacity(0.3), .clear],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .interpolationMethod(.catmullRom)
                        LinePlot(displayPoints,
                                 x: .value("Date", \.date),
                                 y: .value("Weight (\(weightUnit.symbol))", \.weight))
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.catmullRom)
                        if chartPoints.count <= 60 {
                            PointPlot(displayPoints,
                                      x: .value("Date", \.date),
                                      y: .value("Weight (\(weightUnit.symbol))", \.weight))
                                .foregroundStyle(Color.blue)
                                .symbolSize(30)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) {
                            AxisGridLine().foregroundStyle(.white.opacity(0.08))
                            AxisTick().foregroundStyle(.clear)
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks {
                            AxisGridLine().foregroundStyle(.white.opacity(0.08))
                            AxisTick().foregroundStyle(.clear)
                            AxisValueLabel().foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxisLabel("Weight (\(weightUnit.symbol))")
                    .accessibilityLabel("Maximum weight over time in \(weightUnit == .lbs ? "pounds" : "kilograms")")
                    .frame(height: 200)
                }
            }
        }
    }
}

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
    @FocusState private var isWeightFieldFocused: Bool

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

    private var weightMessage: String? {
        weightDraft.validationMessage(whenBlank: blankWeight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight (\(weightDraft.input.unit.symbol))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        TextField("0", text: $weightDraft.text)
                            .keyboardType(.decimalPad)
                            .focused($isWeightFieldFocused)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .accessibilityIdentifier("quickLog.weight")
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reps")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                if reps > 1 { reps -= 1 }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Decrease reps")

                            Text("\(reps)")
                                .font(.title.bold())
                                .frame(maxWidth: .infinity)

                            Button {
                                reps += 1
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Increase reps")
                        }
                    }

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
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) {
                PinnedActionBar(isFieldFocused: $isWeightFieldFocused) {
                    PrimaryButton("Log Set", icon: "checkmark") {
                        logSet()
                    }
                    .disabled(resolvedWeight == nil)
                }
            }
            .background {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Log Set")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .persistenceAlert(isPresented: $showingSaveAlert, alert: saveAlert)
    }

    private func logSet() {
        // Ignore extra taps while the sheet closes after a successful log.
        guard !didLogSet, let weight = resolvedWeight else { return }

        switch viewModel.logSet(for: exercise, reps: reps, weight: weight, completedAt: date, context: context) {
        case .success:
            didLogSet = true
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
    @FocusState private var isWeightFieldFocused: Bool

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

    private var weightMessage: String? {
        weightDraft.validationMessage(whenBlank: blankWeight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let exercise = set.exercise {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight (\(weightDraft.input.unit.symbol))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        TextField("0", text: $weightDraft.text)
                            .keyboardType(.decimalPad)
                            .focused($isWeightFieldFocused)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .accessibilityIdentifier("editSet.weight")
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reps")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                if reps > 1 { reps -= 1 }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Decrease reps")

                            Text("\(reps)")
                                .font(.title.bold())
                                .frame(maxWidth: .infinity)

                            Button {
                                reps += 1
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Increase reps")
                        }
                    }

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
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) {
                PinnedActionBar(isFieldFocused: $isWeightFieldFocused) {
                    PrimaryButton("Save Changes", icon: "checkmark") {
                        saveChanges()
                    }
                    .disabled(resolvedWeight == nil)
                }
            }
            .background {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .navigationTitle("Edit Set")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
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
