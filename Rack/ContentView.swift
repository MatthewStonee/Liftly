import SwiftUI

enum AppTab: Hashable {
    case programs
    case progress
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .programs

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Programs", systemImage: "list.bullet.clipboard.fill", value: AppTab.programs) {
                ProgramsView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                ProgressTabView(onShowPrograms: { selectedTab = .programs })
            }
        }
        .tint(.blue)
        .appBackground()
    }
}

#Preview {
    ContentView()
}
