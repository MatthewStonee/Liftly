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
                .padding(.vertical, 10)
                .activityBackgroundTint(Color(red: 0.08, green: 0.10, blue: 0.17))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.state.workoutURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.needsRefresh ? "Refresh" : "Liftly", systemImage: context.state.needsRefresh ? "arrow.clockwise" : "dumbbell.fill")
                        .font(.caption)
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .foregroundStyle(.blue)
                        .accessibilityLabel(context.state.needsRefresh ? "Open Liftly to refresh" : "Liftly")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Text(context.state.workoutName).lineLimit(1).privacySensitive()
                        Text("· \(context.state.totalExercises)").fixedSize()
                    }
                    .font(.caption.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .foregroundStyle(.white)
                    .padding(.trailing, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(context.state.workoutName), \(context.state.totalExercises) exercises")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityContent(state: context.state, activityID: context.activityID, isExpandedIsland: true)
                        .padding(.horizontal, 14)
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
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: Double = 18

    private var layout: WorkoutActivityLayout {
        WorkoutActivityLayout(state: state, rowHeight: rowHeight,
                              columns: dynamicTypeSize >= .xxxLarge ? 1 : 2)
    }

    var body: some View {
        let page = layout
        VStack(alignment: .leading, spacing: 0) {
            if !isExpandedIsland {
                HStack(spacing: 8) {
                    Label(state.needsRefresh ? "Refresh needed" : "Liftly", systemImage: state.needsRefresh ? "arrow.clockwise" : "dumbbell.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel(state.needsRefresh ? "Open Liftly to refresh" : "Liftly")
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text(state.workoutName).lineLimit(1).privacySensitive()
                        Text("· \(state.totalExercises)").fixedSize()
                    }
                    .fontWeight(.semibold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(state.workoutName), \(state.totalExercises) exercises")
                }
                .font(.caption)
                .dynamicTypeSize(...DynamicTypeSize.large)
                .frame(height: WorkoutActivityLayout.headerHeight)
                .accessibilityElement(children: .combine)
                .padding(.bottom, WorkoutActivityLayout.headerSpacing)
            }

            VStack(alignment: .leading, spacing: WorkoutActivityLayout.rowSpacing) {
                ForEach(0..<page.rowCount, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(0..<page.columns, id: \.self) { column in
                            let offset = row * page.columns + column
                            if page.exercises.indices.contains(offset) {
                                let exercise = page.exercises[offset]
                                Text(exercise.name)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .privacySensitive()
                                    .accessibilityLabel("\(exercise.name), exercise \(page.startingIndex + offset + 1) of \(state.totalExercises)")
                                    .accessibilityIdentifier("workout.activity.exercise.\(page.startingIndex + offset)")
                            } else {
                                Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(height: rowHeight)
                }
            }

            if page.showsPaging {
                HStack(spacing: 4) {
                    pageButton(direction: -1, name: "Previous exercises", symbol: "chevron.left", page: page)
                        .disabled(page.startingIndex == 0)
                        .opacity(page.startingIndex == 0 ? 0.35 : 1)
                    Spacer(minLength: 0)
                    Text(page.renderedState(state).rangeLabel(visibleCount: page.exercises.count))
                        .font(.caption2)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    pageButton(direction: 1, name: "Next exercises", symbol: "chevron.right", page: page)
                        .disabled(page.startingIndex + page.exercises.count >= state.totalExercises)
                        .opacity(page.startingIndex + page.exercises.count >= state.totalExercises ? 0.35 : 1)
                }
                .padding(.top, WorkoutActivityLayout.controlsSpacing)
            }
        }
        .foregroundStyle(.white)
    }

    private func pageButton(direction: Int, name: String, symbol: String, page: WorkoutActivityLayout) -> some View {
        Button(intent: WorkoutActivityPagingIntent(activityID: activityID, direction: direction,
                                                   visibleCount: page.navigationStep, state: page.renderedState(state))) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.large)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .accessibilityLabel(name)
    }
}
