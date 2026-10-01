import SwiftUI

struct GymAutomationGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Gym Automations", systemImage: "location.circle")
                .font(.headline)
            Text("Show your workout when you arrive and dismiss it when you leave. Set up two personal automations in Apple's Shortcuts app.")
                .font(.subheadline)
            Text("Your Lock Screen shows exercise names together whenever they fit. Larger text or longer days use Previous and Next. Sets, reps, and weights stay in Liftly.")
                .font(.caption)
                .foregroundStyle(.secondary)
            guideStep("When you arrive", text: "In Shortcuts, open Automation and create an Arrive automation. Choose your gym and adjust the blue location boundary. Select Run Immediately (or turn off Ask Before Running). Add Liftly's Show Workout Day on Lock Screen action and select your workout day.")
            guideStep("When you leave", text: "Create a Leave automation for the same gym boundary. Enable automatic execution and add Liftly's Stop Workout Live Activity action.")
            Text("The arrival action uses the day you select. To show different days during the week, add weekday conditions in Shortcuts. A different workout already showing stays running.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Shortcuts handles location detection. Liftly doesn't track your location. Arrival and departure timing depends on iOS, and Live Activities must be enabled for Liftly.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.openShortcuts")
        }
    }

    private func guideStep(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
