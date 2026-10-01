import Foundation

/// Height budgeting is shared with the app's tests; the widget supplies the
/// scaled footnote row height and its Dynamic Type column count.
nonisolated struct WorkoutActivityLayout {
    static let heightLimit: Double = 160
    static let rowSpacing: Double = 4
    static let headerHeight: Double = 16
    static let headerSpacing: Double = 6
    static let verticalPadding: Double = 20
    static let controlsHeight: Double = 44
    static let controlsSpacing: Double = 4

    let columns: Int
    let capacity: Int
    let startingIndex: Int
    let exercises: [WorkoutActivityAttributes.Exercise]
    let showsPaging: Bool
    let navigationStep: Int

    init(state: WorkoutActivityAttributes.ContentState, rowHeight: Double, columns: Int) {
        self.columns = columns == 1 ? 1 : 2
        let height = rowHeight.isFinite ? max(18, rowHeight) : 18
        let available = Self.heightLimit - Self.verticalPadding - Self.headerHeight - Self.headerSpacing
        let overviewRows = max(1, Int((available + Self.rowSpacing) / (height + Self.rowSpacing)))
        let overviewCapacity = min(10, overviewRows * self.columns)
        let containsWholeDay = state.windowStartingIndex == 0 && state.exercises.count == state.totalExercises
        showsPaging = !containsWholeDay || state.totalExercises > overviewCapacity
        let pageRows = max(1, Int((available - Self.controlsHeight - Self.controlsSpacing + Self.rowSpacing) / (height + Self.rowSpacing)))
        capacity = showsPaging ? min(10, pageRows * self.columns) : overviewCapacity
        startingIndex = showsPaging ? max(state.windowStartingIndex, state.startingIndex) : 0
        let offset = max(0, startingIndex - state.windowStartingIndex)
        exercises = Array(state.exercises.dropFirst(offset).prefix(capacity))
        // On a final partial page, Previous still moves by a complete page.
        // Legacy two-row windows navigate by their supplied window until refreshed.
        let coversTail = state.windowStartingIndex + state.exercises.count >= state.totalExercises
        navigationStep = coversTail ? capacity : max(1, min(capacity, state.exercises.count))
    }

    func renderedState(_ state: WorkoutActivityAttributes.ContentState) -> WorkoutActivityAttributes.ContentState {
        var result = state
        result.startingIndex = startingIndex
        return result
    }

    var rowCount: Int { (exercises.count + columns - 1) / columns }
}
