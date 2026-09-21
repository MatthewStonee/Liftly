import SwiftUI
import SwiftData

@main
struct RackApp: App {
    @State private var dataStore: AppDataStore

    init() {
        #if DEBUG
        if let fixture = DebugUITestFixture.current {
            _dataStore = State(initialValue: AppDataStore(
                openContainer: { _ in try DebugUITestFixture.open(fixture) },
                prepareContainer: { $0.mainContext.autosaveEnabled = false }
            ))
        } else {
            _dataStore = State(initialValue: AppDataStore())
        }
        #else
        _dataStore = State(initialValue: AppDataStore())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(dataStore: dataStore)
                .preferredColorScheme(.dark)
        }
    }
}
