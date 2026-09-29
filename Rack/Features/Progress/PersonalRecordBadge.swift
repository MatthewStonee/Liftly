import SwiftUI

/// Marks a set that holds the personal record for its rep count. A row's VoiceOver label
/// already says so, so the badge is hidden from VoiceOver.
struct PersonalRecordBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
            Text("PR")
        }
        .font(.caption2.bold())
        .foregroundStyle(.yellow)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.yellow.opacity(0.15), in: Capsule())
        .accessibilityHidden(true)
    }
}
