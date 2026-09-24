import SwiftUI

/// The 1M–All range selector shared by an exercise's progress and history screens.
///
/// Each option is a button that VoiceOver reads by name ("Three months") and marks as
/// selected, since the highlight alone is visual only.
struct TimeRangePicker: View {
    let selection: ProgressViewModel.TimeRange
    /// Prefix for each option's accessibility identifier, such as `"history.range"`.
    let identifierPrefix: String
    let onSelect: (ProgressViewModel.TimeRange) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        GlassCard(padding: 8) {
            HStack(spacing: 0) {
                ForEach(ProgressViewModel.TimeRange.allCases, id: \.self) { range in
                    let isSelected = selection == range
                    Button {
                        onSelect(range)
                    } label: {
                        Text(range.rawValue)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.blue)
                                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(range.accessibilityLabel)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("\(identifierPrefix).\(range.rawValue)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: selection)
        }
    }
}

extension ProgressViewModel.TimeRange {
    /// Spoken names, since VoiceOver would read "1M" as "1 meter".
    var accessibilityLabel: String {
        switch self {
        case .oneMonth: return "One month"
        case .threeMonths: return "Three months"
        case .sixMonths: return "Six months"
        case .oneYear: return "One year"
        case .allTime: return "All time"
        }
    }
}
