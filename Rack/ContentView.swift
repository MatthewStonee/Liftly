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
        .background(
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

#Preview {
    ContentView()
}
