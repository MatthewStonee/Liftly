import SwiftUI

/// A persistence failure ready to show to the user.
struct PersistenceAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, error: PersistenceCommandError) {
        self.title = title
        message = error.message
    }
}

/// Collects failures from work that can outlive the screen that started it, such as
/// delayed deletions, so the app root can still show them.
@Observable
final class PersistenceAlertCenter {
    private(set) var alerts: [PersistenceAlert] = []

    var currentAlert: PersistenceAlert? {
        alerts.first
    }

    func report(_ alert: PersistenceAlert) {
        alerts.append(alert)
    }

    func dismiss(_ alert: PersistenceAlert) {
        alerts.removeAll { $0.id == alert.id }
    }
}

extension View {
    /// Shows a persistence failure. Keep `isPresented` in the presenting view's `@State`.
    func persistenceAlert(isPresented: Binding<Bool>, alert: PersistenceAlert?) -> some View {
        self.alert(alert?.title ?? "", isPresented: isPresented, presenting: alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { presentedAlert in
            Text(presentedAlert.message)
        }
    }
}
