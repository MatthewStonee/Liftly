import SwiftUI
import SwiftData
import Charts

// MARK: - Progress Tab

struct ProgressTabView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var plannedExercises: [PlannedExercise]
    @State private var viewModel = ProgressViewModel()
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    private var programExercises: [Exercise] {
        let usedIDs = Set(plannedExercises.compactMap { $0.exercise?.id })
        return exercises.filter { usedIDs.contains($0.id) }
    }

    private var weeklyVolume: Double {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var total: Double = 0
        for exercise in programExercises {
            for set in exercise.loggedSetsList where set.completedAt >= oneWeekAgo {
                total += set.weight * Double(set.reps)
            }
        }
        return total
    }

    var body: some View {
        NavigationStack {
            Group {
                if programExercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backgroundGradient }
            .navigationTitle("Progress")
            .titleDisplayMode(.large)
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseProgressView(exercise: exercise)
            }
            .onAppear { viewModel.backfillPersonalRecords(exercises: exercises) }
        }
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
                Text(weeklyVolume > 0 ? String(format: "%.0f", weightUnit.display(weeklyVolume)) : "\u{2014}")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                if weeklyVolume > 0 {
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
            VStack(spacing: 12) {
                weeklyVolumeCard

                ForEach(programExercises) { exercise in
                    NavigationLink(value: exercise) {
                        ExerciseProgressRow(exercise: exercise)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(exercise.name)
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
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    private var sortedSets: [LoggedSet] { exercise.loggedSetsList.sorted { $0.completedAt > $1.completedAt } }
    private var prWeight: Double { sortedSets.map(\.weight).max() ?? 0 }

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
                        if prWeight > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(prWeight.formattedWeight(unit: weightUnit))
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
                        Text("\(sortedSets.count)")
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
    let exercise: Exercise
    @State private var viewModel = ProgressViewModel()
    @State private var showingQuickLog = false
    @State private var setToEdit: LoggedSet?
    @Namespace private var pickerNamespace
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        let allSets = exercise.loggedSetsList.sorted { $0.completedAt < $1.completedAt }
        let filteredSets = viewModel.filteredSets(allSets, for: viewModel.timeRange)
        let chartPoints = viewModel.maxWeightPoints(for: filteredSets)
        let pr = viewModel.personalRecord(for: allSets)
        let totalVol = viewModel.totalVolume(for: filteredSets)
        let recentSets = Array(filteredSets.suffix(20).reversed())

        ScrollView {
            VStack(spacing: 16) {
                Text(exercise.name)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(-0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statsCard(pr: pr, totalVol: totalVol)
                timeRangePicker
                chartCard(chartPoints: chartPoints)
                setHistoryCard(recentSets: recentSets, isEmpty: filteredSets.isEmpty)
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
            QuickLogSheet(exercise: exercise, viewModel: viewModel)
        }
        .sheet(item: $setToEdit) { set in
            EditLoggedSetSheet(set: set, viewModel: viewModel)
        }
    }

    private func deleteSet(_ set: LoggedSet) {
        if set.isPersonalRecord, let exercise = set.exercise {
            viewModel.promotePR(exercise: exercise, reps: set.reps, excluding: set)
        }
        context.delete(set)
        try? context.save()
    }

    // MARK: Cards

    private func statsCard(pr: LoggedSet?, totalVol: Double) -> some View {
        GlassCard {
            HStack(spacing: 8) {
                StatBadge(
                    value: pr.map { "\($0.weight.formattedWeight(unit: weightUnit)) \(weightUnit.symbol)" } ?? "\u{2014}",
                    label: "PR Weight"
                )
                StatBadge(
                    value: pr.map { "\($0.reps) reps" } ?? "\u{2014}",
                    label: "At PR"
                )
                StatBadge(
                    value: totalVol > 0 ? String(format: "%.0f", weightUnit.display(totalVol)) : "\u{2014}",
                    label: "Total Vol. (\(weightUnit.symbol))"
                )
            }
        }
    }

    private var timeRangePicker: some View {
        GlassCard(padding: 8) {
            HStack(spacing: 0) {
                ForEach(ProgressViewModel.TimeRange.allCases, id: \.self) { range in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            viewModel.timeRange = range
                        }
                    } label: {
                        Text(range.rawValue)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(viewModel.timeRange == range ? Color.white : Color.secondary.opacity(0.7))
                            .animation(.easeOut(duration: 0.2), value: viewModel.timeRange)
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
        }
    }

    private func chartCard(chartPoints: [(Date, Double)]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Max Weight Over Time")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Group {
                    if chartPoints.count < 2 {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Not enough data yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Log at least 2 sets on different days to see your chart.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        Chart {
                            ForEach(chartPoints, id: \.0) { date, weight in
                                LineMark(
                                    x: .value("Date", date),
                                    y: .value("Weight", weight)
                                )
                                .foregroundStyle(Color.blue)
                                .interpolationMethod(.catmullRom)

                                AreaMark(
                                    x: .value("Date", date),
                                    y: .value("Weight", weight)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.3), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)

                                PointMark(
                                    x: .value("Date", date),
                                    y: .value("Weight", weight)
                                )
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
                        .frame(height: 200)
                    }
                }
                .id(viewModel.timeRange)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
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
                if isEmpty {
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
                        .padding(.vertical, 4)
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
                .id(viewModel.timeRange)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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

    @State private var weightText: String = ""
    @State private var reps: Int = 5
    @State private var date: Date = .now
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        NavigationStack {
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
                    Text("Weight (\(weightUnit.symbol))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                        )
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

                Spacer()

                PrimaryButton("Log Set", icon: "checkmark") {
                    logSet()
                }
                .disabled(weightText.isEmpty && exercise.equipment != .bodyweight)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onAppear { prefill() }
    }

    private func prefill() {
        let sorted = exercise.loggedSetsList.sorted { $0.completedAt > $1.completedAt }
        if let last = sorted.first {
            if last.weight > 0 {
                weightText = last.weight.formattedWeight(unit: weightUnit)
            }
            reps = last.reps
        }
    }

    private func logSet() {
        let weight = weightUnit.store(Double(weightText) ?? 0)
        let set = LoggedSet(exercise: exercise, reps: reps, weight: weight)
        set.completedAt = date
        let isPR = viewModel.isNewPersonalRecord(exercise: exercise, weight: weight, reps: reps)
        if isPR { viewModel.clearPR(exercise: exercise, reps: reps) }
        set.isPersonalRecord = isPR
        context.insert(set)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Edit Logged Set Sheet

struct EditLoggedSetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: LoggedSet
    let viewModel: ProgressViewModel

    @State private var weightText: String = ""
    @State private var reps: Int = 1
    @State private var date: Date = .now
    @State private var originalReps: Int = 0
    @State private var originalWeight: Double = 0
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        NavigationStack {
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
                    Text("Weight (\(weightUnit.symbol))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                        )
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

                Spacer()

                PrimaryButton("Save Changes", icon: "checkmark") {
                    saveChanges()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onAppear {
            weightText = set.weight > 0 ? set.weight.formattedWeight(unit: weightUnit) : ""
            reps = set.reps
            date = set.completedAt
            originalReps = set.reps
            originalWeight = set.weight
        }
    }

    private func saveChanges() {
        let newWeight = weightUnit.store(Double(weightText) ?? 0)
        guard let exercise = set.exercise else { return }

        // If reps changed and this was a PR, promote the next-best at the old rep count
        if originalReps != reps && set.isPersonalRecord {
            set.isPersonalRecord = false
            viewModel.promotePR(exercise: exercise, reps: originalReps, excluding: set)
        }

        set.weight = newWeight
        set.reps = reps
        set.completedAt = date

        // Recalculate PR at the (possibly new) rep count
        let isPR = viewModel.isNewPersonalRecord(exercise: exercise, weight: newWeight, reps: reps, excluding: set)
        if isPR { viewModel.clearPR(exercise: exercise, reps: reps, excluding: set) }
        set.isPersonalRecord = isPR

        try? context.save()
        dismiss()
    }
}
