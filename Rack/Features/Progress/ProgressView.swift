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
    private let onShowPrograms: () -> Void

    /// - Parameter onShowPrograms: Switches to the Programs tab, where a program can be
    ///   activated or given exercises.
    init(onShowPrograms: @escaping () -> Void = {}) {
        self.onShowPrograms = onShowPrograms
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !viewModel.overview.programExercises.isEmpty {
                    exerciseList
                } else if viewModel.hasLoadedOverview {
                    emptyState(for: overviewSelection.program)
                } else {
                    // Keeps `onAppear` attached while the first overview loads.
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
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
            // Background contexts (startup maintenance) post `didSave` on their own
            // thread, so hop to the main thread before touching view state.
            .onReceive(
                NotificationCenter.default.publisher(for: ModelContext.didSave)
                    .receive(on: DispatchQueue.main)
            ) { _ in
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

    private var weeklyVolumeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEEKLY VOLUME")
                .font(.caption.bold())
                .tracking(2)
                .foregroundStyle(.blue)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(weeklyVolumeText ?? "\u{2014}")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if weeklyVolumeText != nil {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly volume, last 7 days")
        .accessibilityValue(weeklyVolumeText.map { "\($0) \(weightUnit.spokenName)" } ?? "None")
    }

    /// Grouped for readability, such as "12,500"; `nil` when nothing was lifted.
    private var weeklyVolumeText: String? {
        let volume = viewModel.overview.weeklyVolume
        guard volume > 0 else { return nil }
        return weightUnit.display(volume).formatted(.number.precision(.fractionLength(0)))
    }

    private var exerciseList: some View {
        ScrollView {
            GlassEffectContainer(spacing: 0) {
                LazyVStack(spacing: 12) {
                    weeklyVolumeCard

                    ForEach(viewModel.overview.programExercises) { exercise in
                        let summary = viewModel.overview.summariesByExerciseID[exercise.id] ?? ExerciseProgressSummary()
                        NavigationLink(value: ProgressRoute.exercise(exercise)) {
                            ExerciseProgressRow(exercise: exercise, summary: summary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            ExerciseProgressRow.accessibilityLabel(for: exercise, summary: summary, unit: weightUnit)
                        )
                        .accessibilityIdentifier("progress.exercise.\(exercise.name)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    /// Progress lists the active program's exercises, so each empty state says which of
    /// those two steps is missing and leads back to Programs to finish it.
    private func emptyState(for activeProgram: Program?) -> some View {
        VStack(spacing: 20) {
            Image(systemName: activeProgram == nil ? "chart.line.uptrend.xyaxis" : "dumbbell")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(activeProgram == nil ? "No Active Program" : "No Exercises Yet")
                    .font(.title2.bold())
                Text(emptyStateMessage(for: activeProgram))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onShowPrograms()
            } label: {
                Text("Go to Programs")
                    .fontWeight(.semibold)
                    .frame(minWidth: 160, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier("progress.showPrograms")
        }
        .padding(32)
    }

    private func emptyStateMessage(for activeProgram: Program?) -> String {
        if let activeProgram {
            return "Add exercises to a workout day in \(activeProgram.name) to track them and log sets here."
        }
        return "Set a program as active to track its exercises and log sets here."
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
                        Text("PR Weight")
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
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        // Clip before adding glass. Inside the list's GlassEffectContainer, a clipShape
        // applied after the glass left the accent bar's corners unclipped.
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassBackground()
        .contentShape(Rectangle())
    }

    /// Everything the row shows, such as "Bench Press, Chest, PR weight 225 pounds, 42 sets".
    static func accessibilityLabel(
        for exercise: Exercise,
        summary: ExerciseProgressSummary,
        unit: WeightUnit
    ) -> String {
        let record = summary.prWeight > 0
            ? "PR weight \(summary.prWeight.formattedWeight(unit: unit)) \(unit.spokenName)"
            : "No PR yet"
        let sets = "\(summary.setCount) \(summary.setCount == 1 ? "set" : "sets")"
        return "\(exercise.name), \(exercise.muscleGroup.rawValue), \(record), \(sets)"
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
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs
    @Environment(\.locale) private var locale

    var body: some View {
        let metrics = viewModel.exerciseMetrics
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    Text(exercise.name)
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)
                        .tracking(-0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statsCard(pr: metrics.personalRecord, totalVol: metrics.totalVolume)
                    TimeRangePicker(selection: viewModel.timeRange, identifierPrefix: "progress.range") { range in
                        viewModel.updateTimeRange(range)
                    }
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
        .appBackground()
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            Button {
                showingQuickLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.blue)
                    .frame(width: 58, height: 58)
                    .contentShape(Circle())
            }
            .buttonStyle(FABButtonStyle())
            .accessibilityLabel("Log Set")
            .accessibilityIdentifier("progress.logSet")
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
                    value: totalVol > 0
                        ? weightUnit.display(totalVol).formatted(.number.precision(.fractionLength(0)))
                        : "\u{2014}",
                    label: "Total Vol. (\(weightUnit.symbol))",
                    surface: .embedded
                )
            }
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
                        Button {
                            setToEdit = set
                        } label: {
                            HStack {
                                Text(set.completedAt.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .leading)
                                Text(set.weight == 0 ? "Bodyweight" : "\(set.weight.formattedWeight(unit: weightUnit)) \(weightUnit.symbol)")
                                    .font(.subheadline)
                                if set.isPersonalRecord {
                                    PersonalRecordBadge()
                                }
                                Spacer()
                                Text("\u{d7} \(set.reps)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.blue)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(set.spokenSummary(unit: weightUnit, dateStyle: .dateTime.month(.abbreviated).day()))
                        .accessibilityHint("Edits this set")
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
        /// Where the area fill starts: the bottom of the fitted y-axis, not zero.
        let floor: Double
    }

    /// How the x-axis steps through the chart's dates, and how it labels each step.
    struct DateAxis {
        let component: Calendar.Component
        let count: Int
        let format: Date.FormatStyle
    }

    let chartPoints: [ExerciseProgressChartPoint]
    let weightUnit: WeightUnit

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chartPoints == rhs.chartPoints && lhs.weightUnit == rhs.weightUnit
    }

    /// Fits the y-axis to the weights, so a gain from 185 to 205 reads as a climb rather
    /// than a flat line near the top of a zero-based axis. The range never drops below
    /// zero and keeps some height when every weight is the same.
    static func yDomain(for weights: [Double]) -> ClosedRange<Double> {
        guard let low = weights.min(), let high = weights.max() else { return 0...1 }
        let span = max(high - low, high * 0.1, 1)
        return max(0, low - span * 0.25)...(high + span * 0.15)
    }

    /// Steps the x-axis so the dates shown get a handful of labels: days or weeks for
    /// about a month of sets, months within a year, and years for long histories.
    static func dateAxis(for dates: [Date]) -> DateAxis {
        guard let first = dates.min(), let last = dates.max() else {
            return DateAxis(component: .month, count: 1, format: .dateTime.month(.abbreviated))
        }
        let monthDay = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let month = Date.FormatStyle.dateTime.month(.abbreviated)
        switch last.timeIntervalSince(first) / 86_400 {
        case ..<8: return DateAxis(component: .day, count: 2, format: monthDay)
        case ..<22: return DateAxis(component: .weekOfYear, count: 1, format: monthDay)
        case ..<46: return DateAxis(component: .weekOfYear, count: 2, format: monthDay)
        case ..<121: return DateAxis(component: .month, count: 1, format: month)
        case ..<241: return DateAxis(component: .month, count: 2, format: month)
        case ..<401: return DateAxis(component: .month, count: 3, format: month)
        case ..<801: return DateAxis(component: .month, count: 6, format: month.year(.twoDigits))
        default: return DateAxis(component: .year, count: 1, format: .dateTime.year())
        }
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
                            .accessibilityHidden(true)
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
                    let weights = chartPoints.map { $0.displayWeight(unit: weightUnit) }
                    let yDomain = Self.yDomain(for: weights)
                    let dateAxis = Self.dateAxis(for: chartPoints.map(\.date))
                    let displayPoints = zip(chartPoints, weights).map { point, weight in
                        DisplayPoint(date: point.date, weight: weight, floor: yDomain.lowerBound)
                    }
                    Chart {
                        AreaPlot(displayPoints,
                                 x: .value("Date", \.date),
                                 yStart: .value("Axis Floor", \.floor),
                                 yEnd: .value("Weight (\(weightUnit.symbol))", \.weight))
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
                    .chartYScale(domain: yDomain)
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisGridLine().foregroundStyle(.white.opacity(0.08))
                            // No foregroundStyle here: on iOS 27 a styled y-axis label isn't
                            // drawn at all. The default is already secondary.
                            AxisValueLabel()
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: dateAxis.component, count: dateAxis.count)) {
                            AxisGridLine().foregroundStyle(.white.opacity(0.08))
                            AxisTick().foregroundStyle(.clear)
                            AxisValueLabel(format: dateAxis.format)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .accessibilityLabel("Maximum weight over time in \(weightUnit.spokenName)")
                    .frame(height: 200)
                }
            }
        }
    }
}
