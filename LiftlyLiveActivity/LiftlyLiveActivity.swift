import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LiftlyLiveActivityBundle: WidgetBundle {
    var body: some Widget { LiftlyWorkoutActivity() }
}

struct LiftlyWorkoutActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityContent(state: context.state, activityID: context.activityID)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .activityBackgroundTint(Color(red: 0.08, green: 0.10, blue: 0.17))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.state.workoutURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.needsRefresh ? "Refresh" : "Liftly", systemImage: context.state.needsRefresh ? "arrow.clockwise" : "dumbbell.fill")
                        .font(.caption)
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundStyle(.blue)
                        .accessibilityLabel(context.state.needsRefresh ? "Open Liftly to refresh" : "Liftly")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.workoutName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundStyle(.white)
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityContent(state: context.state, activityID: context.activityID, isExpandedIsland: true)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Liftly workout reference")
            } compactTrailing: {
                Text("\(context.state.totalExercises) ex.")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.blue)
                    .accessibilityLabel("\(context.state.totalExercises) exercises")
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Liftly workout reference")
            }
            .widgetURL(context.state.workoutURL)
            .keylineTint(.blue)
        }
    }
}

struct WorkoutActivityContent: View {
    let state: WorkoutActivityAttributes.ContentState
    let activityID: String
    var isExpandedIsland = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var rowCount: Int { dynamicTypeSize >= .xxxLarge ? 1 : 2 }
    private var rows: [WorkoutActivityAttributes.Exercise] { Array(state.exercises.prefix(rowCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpandedIsland ? 2 : 4) {
            if !isExpandedIsland {
                HStack(spacing: 8) {
                    Label(state.needsRefresh ? "Refresh needed" : "Liftly", systemImage: state.needsRefresh ? "arrow.clockwise" : "dumbbell.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel(state.needsRefresh ? "Open Liftly to refresh" : "Liftly")
                    Spacer(minLength: 4)
                    Text(state.workoutName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .privacySensitive()
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name)
                        .font(isExpandedIsland ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(row.target)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .privacySensitive()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name), \(row.spokenTarget)")
            }

            HStack(spacing: 4) {
                pageButton(direction: -1, name: "Previous exercises", symbol: "chevron.left")
                    .disabled(state.startingIndex == 0)
                    .opacity(state.startingIndex == 0 ? 0.35 : 1)
                Spacer(minLength: 0)
                Text(state.rangeLabel(visibleCount: rows.count))
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                pageButton(direction: 1, name: "Next exercises", symbol: "chevron.right")
                    .disabled(state.startingIndex + rows.count >= state.totalExercises)
                    .opacity(state.startingIndex + rows.count >= state.totalExercises ? 0.35 : 1)
            }
        }
        .foregroundStyle(.white)
        // Fit the platform's bounded presentation without shrinking content.
        // The one-row layout activates before this upper accessibility limit.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func pageButton(direction: Int, name: String, symbol: String) -> some View {
        Button(intent: WorkoutActivityPagingIntent(activityID: activityID, direction: direction, visibleCount: rowCount, state: state)) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .accessibilityLabel(name)
    }
}
