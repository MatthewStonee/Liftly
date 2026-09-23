import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs
    @AppStorage("plannedRepTargetDefault") private var plannedRepTargetDefault: PlannedRepTargetType = .exact

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
                        settingsSectionTitle("Units")

                        GlassCard(padding: 0) {
                            VStack(alignment: .leading, spacing: 12) {
                                settingsCardHeader(systemImage: "scalemass", title: "Weight Unit")

                                HStack(spacing: 8) {
                                    ForEach([WeightUnit.lbs, WeightUnit.kg], id: \.self) { unit in
                                        settingsChoiceButton(
                                            title: unit.symbol,
                                            subtitle: nil,
                                            isSelected: weightUnit == unit
                                        ) {
                                            weightUnit = unit
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                            }
                        }

                        settingsSectionTitle("Programming")

                        GlassCard(padding: 0) {
                            VStack(alignment: .leading, spacing: 12) {
                                settingsCardHeader(systemImage: "repeat", title: "Default Rep Target")

                                Text("Applies when you add a new exercise to a workout. You can still change each exercise individually.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)

                                VStack(spacing: 8) {
                                    ForEach(PlannedRepTargetType.allCases, id: \.self) { type in
                                        settingsChoiceButton(
                                            title: type.title,
                                            subtitle: type.settingsPreview,
                                            isSelected: plannedRepTargetDefault == type
                                        ) {
                                            plannedRepTargetDefault = type
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

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private func settingsCardHeader(systemImage: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
            Text(title)
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func settingsChoiceButton(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                isSelected ? Color.blue.opacity(0.22) : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.blue.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        // The checkmark and highlight are visual only; VoiceOver hears "Selected".
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
