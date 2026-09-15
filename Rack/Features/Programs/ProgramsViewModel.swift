import SwiftUI
import SwiftData

@Observable
final class ProgramsViewModel {
    @ObservationIgnored private let commandRunner: PersistenceCommandRunner

    init(commandRunner: PersistenceCommandRunner = PersistenceCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func createProgram(
        name: String,
        description: String,
        context: ModelContext
    ) -> Result<Program, PersistenceCommandError> {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return .failure(.invalidInput) }
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)

        return commandRunner.perform(in: context) { context in
            let program = Program(name: trimmedName, description: trimmedDescription)
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
