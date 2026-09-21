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
/// delayed deletions, and tracks which visible host should present them.
@Observable
final class PersistenceAlertCenter {
    private(set) var alerts: [PersistenceAlert] = []
    /// Hosts in the order they appeared. A sheet's host sits above the host that
    /// presented it, so the last one is frontmost.
    private(set) var hostIDs: [UUID] = []

    var currentAlert: PersistenceAlert? {
        alerts.first
    }

    var activeHostID: UUID? {
        hostIDs.last
    }

    func report(_ alert: PersistenceAlert) {
        alerts.append(alert)
    }

    func dismiss(_ alert: PersistenceAlert) {
        alerts.removeAll { $0.id == alert.id }
    }

    /// Makes `id` the frontmost host, moving it to the top if it's already registered.
    func registerHost(_ id: UUID) {
        hostIDs.removeAll { $0 == id }
        hostIDs.append(id)
    }

    func unregisterHost(_ id: UUID) {
        hostIDs.removeAll { $0 == id }
    }
}

extension View {
    /// Shows a persistence failure. Keep `isPresented` in the presenting view's `@State`.
    func persistenceAlert(
        isPresented: Binding<Bool>,
        alert: PersistenceAlert?,
        onAcknowledge: @escaping (PersistenceAlert) -> Void = { _ in }
    ) -> some View {
        self.alert(alert?.title ?? "", isPresented: isPresented, presenting: alert) { presentedAlert in
            Button("OK", role: .cancel) {
                onAcknowledge(presentedAlert)
            }
        } message: { presentedAlert in
            Text(presentedAlert.message)
        }
    }

    /// Presents `center`'s queued alerts while this view is the frontmost host.
    func persistenceAlertHost(_ center: PersistenceAlertCenter) -> some View {
        modifier(PersistenceAlertHost(center: center))
    }
}

/// Only the frontmost host presents. An alert presented by a lower host would make
/// SwiftUI dismiss the open sheet, and the sheet's draft, before showing it.
private struct PersistenceAlertHost: ViewModifier {
    let center: PersistenceAlertCenter
    @State private var hostID = UUID()
    @State private var presentedAlert: PersistenceAlert?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .persistenceAlert(isPresented: $isPresented, alert: presentedAlert) { alert in
                // Only OK acknowledges, so an alert torn down with its sheet stays
                // queued and the next host presents it.
                center.dismiss(alert)
            }
            .onAppear {
                center.registerHost(hostID)
                updatePresentation()
            }
            .onDisappear {
                center.unregisterHost(hostID)
            }
            .onChange(of: center.currentAlert?.id) { updatePresentation() }
            .onChange(of: center.activeHostID) { updatePresentation() }
            .onChange(of: isPresented) { updatePresentation() }
    }

    private func updatePresentation() {
        let isFrontmost = center.activeHostID == hostID
        if isPresented {
            // Hand the alert to the new frontmost host; it stays queued until OK.
            if !isFrontmost { isPresented = false }
            return
        }
        presentedAlert = isFrontmost ? center.currentAlert : nil
        isPresented = presentedAlert != nil
    }
}
