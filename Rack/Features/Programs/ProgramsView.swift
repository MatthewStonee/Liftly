import SwiftUI
import SwiftData

struct ProgramsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @State private var viewModel = ProgramsViewModel()
    @State private var showingCreateProgram = false
    @State private var showingSettings = false

    private var activeProgram: Program? { programs.first { $0.isActive } }
    private var otherPrograms: [Program] { programs.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            Group {
                if programs.isEmpty {
                    emptyState
                } else {
                    programList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backgroundGradient }
            .navigationTitle("Programs")
            .titleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateProgram = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
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
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .textCase(.uppercase)
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
                                NavigationLink(destination: ProgramDetailView(program: program)) {
                                    ProgramRow(program: program) {
                                        viewModel.setActive(program, allPrograms: programs, context: context)
                                    }
                                }
                                .buttonStyle(.plain)
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
        NavigationLink(destination: ProgramDetailView(program: program)) {
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

                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.white.opacity(0.06))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, -10)
                    .allowsHitTesting(false)

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

                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WORKOUTS")
                                .font(.caption2.bold())
                                .tracking(1)
                                .foregroundStyle(.secondary)
                            Text("\(program.workouts.count) / week")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EXERCISES")
                                .font(.caption2.bold())
                                .tracking(1)
                                .foregroundStyle(.secondary)
                            Text("\(program.workouts.reduce(0) { $0 + $1.plannedExercises.count }) total")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("No Programs Yet")
                    .font(.title2.bold())
                Text("Create a training program to organize\nyour workouts and track progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingCreateProgram = true
            } label: {
                Label("Create Program", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.blue, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(32)
    }
}

struct ProgramRow: View {
    let program: Program
    let onSetActive: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))
                    .frame(width: 52, height: 52)
                Image(systemName: "dumbbell")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(program.name)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("\(program.workouts.count) \(program.workouts.count == 1 ? "Day" : "Days")  ·  \(program.workouts.reduce(0) { $0 + $1.plannedExercises.count }) Exercises")
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
