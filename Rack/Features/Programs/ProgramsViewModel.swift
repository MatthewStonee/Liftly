import SwiftUI
import SwiftData

@Observable
final class ProgramsViewModel {
    var programToDelete: Program?
    var showingDeleteAlert = false

    func deleteProgram(_ program: Program, context: ModelContext) {
        context.delete(program)
        try? context.save()
    }

    func setActive(_ program: Program, allPrograms: [Program], context: ModelContext) {
        var didChange = false

        for candidate in allPrograms where candidate.id != program.id && candidate.isActive {
            candidate.isActive = false
            didChange = true
        }

        if !program.isActive {
            program.isActive = true
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
