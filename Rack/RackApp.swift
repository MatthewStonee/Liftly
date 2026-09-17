import SwiftUI

@main
struct RackApp: App {
    @State private var dataStore = AppDataStore()

    var body: some Scene {
        WindowGroup {
            AppRootView(dataStore: dataStore)
                .preferredColorScheme(.dark)
        }
    }
}
