import Foundation
import SwiftData
import OSLog

/// Why a user-triggered write didn't happen.
enum PersistenceCommandError: Error, Equatable {
    /// The context already had unsaved changes, so the command was refused
    /// without rolling those changes back.
    case pendingChanges
    /// The item the command targets no longer exists.
    case unavailable
    /// The command's input was rejected before anything changed.
    case invalidInput
    /// Applying or saving the change failed, and the command's changes were rolled back.
    case failed(String)

    var message: String {
        switch self {
        case .pendingChanges:
            return "Another change is still being saved, so nothing was changed. Try again."
        case .unavailable:
            return "This item is no longer available."
        case .invalidInput:
            return "Check the details and try again."
        case .failed:
            return "Your changes weren't saved. Make sure your iPhone has free storage, then try again."
        }
    }
}

/// Runs a user-triggered write as a single explicit save.
///
/// A command starts from a clean context, applies its changes synchronously, and
/// saves. If anything fails, the command's changes are rolled back so nothing is left
/// half-applied. `ModelContext.rollback()` discards every pending change, so a context
/// that is already dirty is refused instead of rolled back.
nonisolated struct PersistenceCommandRunner {
    typealias SaveOperation = @MainActor (ModelContext) throws -> Void

    private static let logger = Logger(subsystem: "com.matthewstone.liftly", category: "Persistence")

    private let save: SaveOperation

    init(save: @escaping SaveOperation = { try PersistenceCommandRunner.saveContext($0) }) {
        self.save = save
    }

    @MainActor
    func perform<Value>(
        in context: ModelContext,
        _ command: (ModelContext) throws -> Value
    ) -> Result<Value, PersistenceCommandError> {
        guard !context.hasChanges else {
            Self.logger.error("Refused a write because the context already had unsaved changes.")
            return .failure(.pendingChanges)
        }

        do {
            let value = try command(context)
            if context.hasChanges {
                try save(context)
            }
            return .success(value)
        } catch {
            context.rollback()
            Self.logger.error("Rolled back a failed write: \(String(describing: error), privacy: .public)")
            if let commandError = error as? PersistenceCommandError {
                return .failure(commandError)
            }
            return .failure(.failed(String(describing: error)))
        }
    }

    @MainActor
    static func saveContext(_ context: ModelContext) throws {
        #if DEBUG
        try DebugPersistenceFaults.consumeSaveFailure()
        #endif
        try context.save()
    }
}
