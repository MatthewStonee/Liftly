import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Units")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)

                        GlassCard(padding: 0) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "scalemass")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.blue)
                                    Text("Weight Unit")
                                        .font(.body)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 14)

                                HStack(spacing: 8) {
                                    ForEach([WeightUnit.lbs, WeightUnit.kg], id: \.self) { unit in
                                        Button {
                                            weightUnit = unit
                                        } label: {
                                            Text(unit.symbol)
                                                .font(.headline)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 14)
                                                .background(
                                                    weightUnit == unit
                                                        ? Color.blue.opacity(0.25)
                                                        : Color.white.opacity(0.06),
                                                    in: RoundedRectangle(cornerRadius: 12)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(
                                                            weightUnit == unit ? Color.blue.opacity(0.6) : Color.clear,
                                                            lineWidth: 1
                                                        )
                                                )
                                                .foregroundStyle(weightUnit == unit ? .blue : .secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                            }
                        }
                    }
                    .padding(20)
                }
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
