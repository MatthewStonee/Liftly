import SwiftUI
import SwiftData

@Observable
final class ProgramsViewModel {
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner

    init(commandRunner: PersistenceCommandRunner = PersistenceCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Creates a program. When no program is active, the new one becomes active, so a
    /// new user's first program shows up in Progress right away.
    func createProgram(
        name: String,
        description: String,
        context: ModelContext
    ) -> Result<Program, PersistenceCommandError> {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return .failure(.invalidInput) }
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)

        return commandRunner.perform(in: context) { context in
            let activeCount = try context.fetchCount(
                FetchDescriptor<Program>(predicate: #Predicate<Program> { program in
                    program.isActive
                })
            )
            let program = Program(name: trimmedName, description: trimmedDescription)
            program.isActive = activeCount == 0
            context.insert(program)
            return program
        }
    }

    func updateProgram(
        _ program: Program,
        name: String,
        description: String,
        context: ModelContext
    ) -> Result<Void, PersistenceCommandError> {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return .failure(.invalidInput) }
        guard !program.isDeleted else { return .failure(.unavailable) }
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)

        return commandRunner.perform(in: context) { _ in
            if program.name != trimmedName {
                program.name = trimmedName
            }
            if program.programDescription != trimmedDescription {
                program.programDescription = trimmedDescription
            }
        }
    }

    func setActive(_ program: Program, context: ModelContext) -> Result<Void, PersistenceCommandError> {
        guard !program.isDeleted else { return .failure(.unavailable) }

        return commandRunner.perform(in: context) { context in
            try ProgramActivation.activate(program, in: context)
        }
    }

    /// Commits a program deletion once its undo window has passed.
    func deleteProgram(_ program: Program, context: ModelContext) -> Result<Void, PersistenceCommandError> {
        guard !program.isDeleted else { return .success(()) }

        return commandRunner.perform(in: context) { context in
            context.delete(program)
        }
    }
}

/// The day and exercise counts a program shows. Items waiting out their Undo window
/// are left out, so the numbers match the rows on screen.
struct ProgramCounts: Equatable {
    let days: Int
    let exercises: Int

    init(_ program: Program, hiding coordinator: DeletionCoordinator?) {
        let visibleDays = program.workoutsList.filter { coordinator?.isPending($0) != true }
        days = visibleDays.count
        exercises = visibleDays.reduce(0) { total, day in
            total + day.plannedExercisesList.filter { coordinator?.isPending($0) != true }.count
        }
    }

    var daysText: String { "\(days) \(days == 1 ? "Day" : "Days")" }
    var exercisesText: String { "\(exercises) \(exercises == 1 ? "Exercise" : "Exercises")" }

    /// For VoiceOver labels, such as "3 days, 1 exercise".
    var spokenSummary: String { "\(daysText.lowercased()), \(exercisesText.lowercased())" }
}

/// How the Programs list arranges its programs: the active program leads, and every
/// other program is listed below it. More than one program can be active after iCloud
/// merges activations made on two devices; the extra ones stay in the list.
struct ProgramListSections {
    let active: Program?
    let others: [Program]

    init(programs: [Program]) {
        let active = programs.first { $0.isActive }
        self.active = active
        others = programs.filter { $0.id != active?.id }
    }
}

enum ProgramActivation {
    /// Makes `program` the only active program.
    static func activate(_ program: Program, in context: ModelContext) throws {
        let activePrograms = try context.fetch(
            FetchDescriptor<Program>(predicate: #Predicate<Program> { program in
                program.isActive
            })
        )

        for candidate in activePrograms where candidate.id != program.id {
            candidate.isActive = false
        }

        if !program.isActive {
            program.isActive = true
        }
    }
}
