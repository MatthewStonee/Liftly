import SwiftUI
import SwiftData

struct ProgramsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @State private var viewModel = ProgramsViewModel()
    @State private var showingCreateProgram = false
    @State private var showingSettings = false
    @State private var pendingDeleteProgram: Program?
    @State private var deleteTask: Task<Void, Never>?

    private var visiblePrograms: [Program] {
        programs.filter { $0.id != pendingDeleteProgram?.id }
    }
    private var activeProgram: Program? { visiblePrograms.first { $0.isActive } }
    private var otherPrograms: [Program] { visiblePrograms.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            Group {
                if visiblePrograms.isEmpty {
                    emptyState
                } else {
                    programList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backgroundGradient }
            .navigationTitle("Programs")
            .titleDisplayMode(.large)
            .navigationDestination(for: Program.self) { program in
                ProgramDetailView(program: program, onDeleteProgram: {
                    pendingDeleteProgram = program
                    deleteTask = Task {
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            context.delete(program)
                            try? context.save()
                            pendingDeleteProgram = nil
                        }
                    }
                })
            }
            .undoToast(
                isPresented: Binding(
                    get: { pendingDeleteProgram != nil },
                    set: { if !$0 { pendingDeleteProgram = nil } }
                ),
                message: "Program deleted",
                onUndo: {
                    deleteTask?.cancel()
                    deleteTask = nil
                    pendingDeleteProgram = nil
                }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateProgram = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Create Program")
                }
            }
        }
        .sheet(isPresented: $showingCreateProgram) {
            CreateProgramView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var programList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Select your path to performance")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if let active = activeProgram {
                    activeProgramHero(active)
                }

                if !otherPrograms.isEmpty || activeProgram == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if activeProgram != nil {
                            Text("Other Programs")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                        }

                        VStack(spacing: 10) {
                            ForEach(activeProgram == nil ? programs : otherPrograms) { program in
                                NavigationLink(value: program) {
                                    ProgramRow(program: program) {
                                        viewModel.setActive(program, allPrograms: programs, context: context)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(program.name)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func activeProgramHero(_ program: Program) -> some View {
        NavigationLink(value: program) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.08, green: 0.10, blue: 0.22))
                    .overlay(
                        LinearGradient(
                            colors: [.blue.opacity(0.18), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    )

                VStack(alignment: .leading, spacing: 14) {
                    Text("CURRENTLY ACTIVE")
                        .font(.caption2.bold())
                        .tracking(1.5)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.blue.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(.blue.opacity(0.35), lineWidth: 0.5))

                    Text(program.name)
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(.white)
                        .tracking(-0.5)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        StatBadge(
                            value: "\(program.workoutsList.count)",
                            label: "Workouts",
                            style: .hero
                        )
                        StatBadge(
                            value: "\(program.exerciseCount)",
                            label: "Exercises",
                            style: .hero
                        )
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(program.name)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            VStack(spacing: 10) {
                Text("Build Your First Program")
                    .font(.title2.bold())
                Text("Programs organize your workouts into a weekly structure.\nStart with one and add workout days as you go.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 20) {
                benefitHint(icon: "calendar", text: "Structure\nyour week")
                benefitHint(icon: "checkmark.circle", text: "Track\nevery set")
                benefitHint(icon: "chart.line.uptrend.xyaxis", text: "See your\nprogress")
            }

            PrimaryButton("Get Started", icon: "plus.circle") {
                showingCreateProgram = true
            }
            .padding(.horizontal, 20)
        }
        .padding(32)
    }

    private func benefitHint(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue.opacity(0.6))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProgramRow: View {
    let program: Program
    let onSetActive: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(program.name)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("\(program.workoutsList.count) \(program.workoutsList.count == 1 ? "Day" : "Days")  ·  \(program.exerciseCount) Exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassBackground()
        .contextMenu {
            Button {
                onSetActive()
            } label: {
                Label("Set as Active", systemImage: "checkmark.circle")
            }
        }
    }
}
