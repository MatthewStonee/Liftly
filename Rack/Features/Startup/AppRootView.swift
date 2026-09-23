import SwiftUI
import SwiftData

struct AppRootView: View {
    let dataStore: AppDataStore

    var body: some View {
        ZStack {
            switch dataStore.phase {
            case .loading:
                StartupLoadingView()
            case .failed:
                DataStoreRecoveryView(isRetrying: dataStore.isOpening) {
                    Task { await dataStore.open() }
                }
            case .ready(let container):
                LoadedAppView(
                    container: container,
                    isCloudSyncUnavailable: dataStore.isCloudSyncUnavailable
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .task {
            await dataStore.open()
        }
    }
}

private struct LoadedAppView: View {
    let container: ModelContainer

    @Environment(\.scenePhase) private var scenePhase
    @State private var alertCenter: PersistenceAlertCenter
    @State private var deletionCoordinator: DeletionCoordinator
    @State private var showingSyncNotice: Bool

    init(container: ModelContainer, isCloudSyncUnavailable: Bool) {
        self.container = container
        let center = PersistenceAlertCenter()
        _alertCenter = State(initialValue: center)
        #if DEBUG
        let undoInterval = DebugUITestFixture.undoInterval
        #else
        let undoInterval: TimeInterval = 4
        #endif
        _deletionCoordinator = State(initialValue: DeletionCoordinator(
            context: container.mainContext,
            alertCenter: center,
            undoInterval: undoInterval
        ))
        _showingSyncNotice = State(initialValue: isCloudSyncUnavailable)
    }

    var body: some View {
        ContentView()
            .modelContainer(container)
            .environment(alertCenter)
            .environment(deletionCoordinator)
            .deletionUndoToast(deletionCoordinator)
            .overlay(alignment: .top) {
                if showingSyncNotice {
                    CloudSyncUnavailableNotice {
                        hideSyncNotice()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    deletionCoordinator.setActive(true)
                case .background:
                    // Undo can't be offered while the app isn't visible, and iOS may
                    // terminate it, so save pending deletions now.
                    deletionCoordinator.setActive(false)
                    deletionCoordinator.commitPendingNow()
                default:
                    // Brief interruptions, like Control Center, keep the Undo window.
                    deletionCoordinator.setActive(false)
                }
            }
            .task(priority: .utility) {
                #if DEBUG
                guard DebugUITestFixture.current == nil else { return }
                #endif
                await AppDataStore.performStartupMaintenance(container: container)
            }
            .task {
                guard showingSyncNotice else { return }
                try? await Task.sleep(for: .seconds(8))
                hideSyncNotice()
            }
    }

    private func hideSyncNotice() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showingSyncNotice = false
        }
    }
}

private struct StartupLoadingView: View {
    @State private var showsProgress = false

    var body: some View {
        ProgressView()
            .controlSize(.large)
            .opacity(showsProgress ? 1 : 0)
            .accessibilityLabel("Opening your data")
            .task {
                // Avoid flashing a spinner when the store opens quickly.
                try? await Task.sleep(for: .milliseconds(600))
                showsProgress = true
            }
    }
}

private struct DataStoreRecoveryView: View {
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Liftly couldn't open your data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Nothing was changed or deleted. Try opening your data again.")
        } actions: {
            Button {
                onRetry()
            } label: {
                ZStack {
                    Text("Retry")
                        .fontWeight(.semibold)
                        .opacity(isRetrying ? 0 : 1)
                    if isRetrying {
                        ProgressView()
                    }
                }
                .frame(minWidth: 120, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isRetrying)
            .accessibilityLabel(isRetrying ? "Retrying" : "Retry")
        }
    }
}

private struct CloudSyncUnavailableNotice: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud Sync Unavailable")
                    .font(.subheadline.bold())
                Text("Changes are saved on this iPhone for this launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.vertical, 4)
        .glassBackground(cornerRadius: 16)
        .padding(.horizontal, 16)
        // Sit below the navigation bar's buttons so they stay tappable.
        .padding(.top, 52)
    }
}
