#if DEBUG
import Foundation

/// Debug-only launch arguments for exercising persistence failure paths in the simulator.
///
/// - `-LiftlyDebugStoreOpenFailures <n>` fails the first `n` store-opening attempts.
///   Each launch or Retry tries the CloudKit store, then the local store, so `1` shows
///   the iCloud fallback notice and `2` shows the recovery screen until Retry.
/// - `-LiftlyDebugSaveFailures <n>` fails the first `n` user-triggered saves.
/// - `-LiftlyDebugHistoryLoadFailures <n>` fails the first `n` history page reads.
enum DebugPersistenceFaults {
    struct InjectedFailure: Error {}

    private static var remainingStoreOpenFailures =
        UserDefaults.standard.integer(forKey: "LiftlyDebugStoreOpenFailures")
    private static var remainingSaveFailures =
        UserDefaults.standard.integer(forKey: "LiftlyDebugSaveFailures")
    private static var remainingHistoryLoadFailures =
        UserDefaults.standard.integer(forKey: "LiftlyDebugHistoryLoadFailures")

    static func consumeStoreOpenFailure() throws {
        guard remainingStoreOpenFailures > 0 else { return }
        remainingStoreOpenFailures -= 1
        throw InjectedFailure()
    }

    static func consumeSaveFailure() throws {
        guard remainingSaveFailures > 0 else { return }
        remainingSaveFailures -= 1
        throw InjectedFailure()
    }

    static func consumeHistoryLoadFailure() throws {
        guard remainingHistoryLoadFailures > 0 else { return }
        remainingHistoryLoadFailures -= 1
        throw InjectedFailure()
    }
}
#endif
