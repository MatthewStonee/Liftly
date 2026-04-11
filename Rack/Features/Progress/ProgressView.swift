import SwiftUI
import SwiftData
import Charts

// MARK: - Progress Tab

struct ProgressTabView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    private var weeklyVolume: Double {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return exercises.flatMap { $0.loggedSets }
            .filter { $0.completedAt >= oneWeekAgo }
            .reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backgroundGradient }
            .navigationTitle("Progress")
            .titleDisplayMode(.large)
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
                Text(weeklyVolume > 0 ? String(format: "%.0f", weeklyVolume) : "\u{2014}")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                if weeklyVolume > 0 {
                    Text("lbs")
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

                ForEach(exercises) { exercise in
                    NavigationLink(destination: ExerciseProgressView(exercise: exercise)) {
                        ExerciseProgressRow(exercise: exercise)
                    }
                    .buttonStyle(.plain)
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
                Text("No Exercises Yet")
                    .font(.title2.bold())
                Text("Add exercises to your programs to start tracking progress.")
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

    private var sortedSets: [LoggedSet] { exercise.loggedSets.sorted { $0.completedAt > $1.completedAt } }
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
                        .tracking(1.5)
                        .foregroundStyle(exercise.muscleGroup.color.opacity(0.8))
                    Text(exercise.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .tracking(-0.3)
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LAST PR")
                            .font(.caption2.bold())
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        if prWeight > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(Int(prWeight))")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                Text("lbs")
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
                        Text("SETS")
                            .font(.caption2.bold())
                            .tracking(1)
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

    private var allSets: [LoggedSet] { exercise.loggedSets.sorted { $0.completedAt < $1.completedAt } }
    private var filteredSets: [LoggedSet] { viewModel.filteredSets(allSets, for: viewModel.timeRange) }
    private var chartPoints: [(Date, Double)] { viewModel.maxWeightPoints(for: filteredSets) }
    private var pr: LoggedSet? { viewModel.personalRecord(for: allSets) }
    private var totalVol: Double { viewModel.totalVolume(for: filteredSets) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(exercise.name)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(-0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statsCard
                timeRangePicker
                chartCard
                setHistoryCard
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
                    .background(.ultraThinMaterial, in: Circle())
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
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showingQuickLog) {
            QuickLogSheet(exercise: exercise)
        }
        .sheet(item: $setToEdit) { set in
            EditLoggedSetSheet(set: set)
        }
    }

    private func deleteSet(_ set: LoggedSet) {
        context.delete(set)
        try? context.save()
    }

    // MARK: Cards

    private var statsCard: some View {
        GlassCard {
            HStack(spacing: 8) {
                StatBadge(
                    value: pr.map { "\(Int($0.weight)) lbs" } ?? "\u{2014}",
                    label: "PR Weight"
                )
                StatBadge(
                    value: pr.map { "\($0.reps) reps" } ?? "\u{2014}",
                    label: "At PR"
                )
                StatBadge(
                    value: totalVol > 0 ? String(format: "%.0f", totalVol) : "\u{2014}",
                    label: "Total Vol. (lbs)"
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

    private var chartCard: some View {
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

    private var setHistoryCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Sets")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Group {
                if filteredSets.isEmpty {
                    Text("No sets logged in this period.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                    ForEach(filteredSets.suffix(20).reversed()) { set in
                        HStack {
                            Text(set.completedAt.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            Text(set.weight == 0 ? "Bodyweight" : "\(Int(set.weight)) lbs")
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

                        if set.id != filteredSets.suffix(20).reversed().last?.id {
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

    @State private var weightText: String = ""
    @State private var reps: Int = 5
    @State private var date: Date = .now

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
                    Text("Weight (lbs)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

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
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
        let sorted = exercise.loggedSets.sorted { $0.completedAt > $1.completedAt }
        if let last = sorted.first {
            if last.weight > 0 {
                weightText = String(format: "%.0f", last.weight)
            }
            reps = last.reps
        }
    }

    private func logSet() {
        let weight = Double(weightText) ?? 0
        let set = LoggedSet(exercise: exercise, reps: reps, weight: weight)
        set.completedAt = date
        context.insert(set)
        try? context.save()
        dismiss()
    }
}

// MARK: - Edit Logged Set Sheet

struct EditLoggedSetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: LoggedSet

    @State private var weightText: String = ""
    @State private var reps: Int = 1
    @State private var date: Date = .now

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
                    Text("Weight (lbs)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

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
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
            weightText = set.weight > 0 ? String(format: "%.0f", set.weight) : ""
            reps = set.reps
            date = set.completedAt
        }
    }

    private func saveChanges() {
        set.weight = Double(weightText) ?? 0
        set.reps = reps
        set.completedAt = date
        try? context.save()
        dismiss()
    }
}
