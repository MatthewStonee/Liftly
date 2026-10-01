import SwiftUI
import SwiftData

@main
struct RackApp: App {
    @State private var dataStore: AppDataStore

    init() {
        _dataStore = State(initialValue: AppDataStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(dataStore: dataStore)
                .preferredColorScheme(.dark)
        }
    }
}
