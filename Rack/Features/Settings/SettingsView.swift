import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 64))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)

                    VStack(spacing: 8) {
                        Text("Settings")
                            .font(.title2.bold())
                        Text("Units, preferences, and more\ncoming soon.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(32)
            }
            .navigationTitle("Settings")
            .titleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
