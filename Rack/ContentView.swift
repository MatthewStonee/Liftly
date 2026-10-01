import SwiftUI

enum AppTab: Hashable {
    case programs
    case progress
}

struct ContentView: View {
    var workoutLink: UUID? = nil
    var onWorkoutLinkHandled: () -> Void = {}
    @State private var selectedTab: AppTab = .programs

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Programs", systemImage: "list.bullet.clipboard.fill", value: AppTab.programs) {
                ProgramsView(workoutLink: workoutLink, onWorkoutLinkHandled: onWorkoutLinkHandled)
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                ProgressTabView(onShowPrograms: { selectedTab = .programs })
            }
        }
        .tint(.blue)
        .appBackground()
        .onChange(of: workoutLink, initial: true) { _, link in
            if link != nil { selectedTab = .programs }
        }
    }
}

#Preview {
    ContentView()
}
