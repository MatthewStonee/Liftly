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

    /// Runs a command that inserts a model into a to-many relationship.
    ///
    /// On iOS 27, rolling back a context after such an insert leaves the related model's
    /// relationship unreadable, and the next read crashes. These commands run in a
    /// disposable context instead, so a failed save is discarded without touching
    /// `context`. After a successful save, `refresh` reloads relationships that `context`
    /// already loaded, and the inserted model is returned from `context`.
    @MainActor
    func performInsert<Model: PersistentModel>(
        in context: ModelContext,
        refresh: (ModelContext) -> Void,
        _ command: (ModelContext) throws -> Model
    ) -> Result<Model, PersistenceCommandError> {
        guard !context.hasChanges else {
            Self.logger.error("Refused a write because the context already had unsaved changes.")
            return .failure(.pendingChanges)
        }

        let insertionContext = ModelContext(context.container)
        insertionContext.autosaveEnabled = false

        let insertedID: PersistentIdentifier
        do {
            let model = try command(insertionContext)
            try save(insertionContext)
            insertedID = model.persistentModelID
        } catch {
            Self.logger.error("Discarded a failed insert: \(String(describing: error), privacy: .public)")
            if let commandError = error as? PersistenceCommandError {
                return .failure(commandError)
            }
            return .failure(.failed(String(describing: error)))
        }

        refresh(context)
        guard let model = context.model(for: insertedID) as? Model else {
            return .failure(.unavailable)
        }
        return .success(model)
    }

    @MainActor
    static func saveContext(_ context: ModelContext) throws {
        #if DEBUG
        try DebugPersistenceFaults.consumeSaveFailure()
        #endif
        try context.save()
    }
}

extension ModelContext {
    /// This context's instance of a model loaded elsewhere, or `nil` if it no longer exists.
    func existingModel<Model: PersistentModel>(_ model: Model) throws -> Model? {
        let modelID = model.persistentModelID
        var descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.persistentModelID == modelID })
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    /// Reloads relationships of a model this context already loaded, so they include
    /// models saved through another context.
    func reloadRelationships<Model: PersistentModel>(of model: Model, _ keyPaths: [PartialKeyPath<Model>]) {
        let modelID = model.persistentModelID
        var descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.persistentModelID == modelID })
        descriptor.relationshipKeyPathsForPrefetching = keyPaths
        do {
            _ = try fetch(descriptor)
        } catch {
            Logger(subsystem: "com.matthewstone.liftly", category: "Persistence")
                .error("Failed to reload relationships: \(String(describing: error), privacy: .public)")
        }
    }
}
