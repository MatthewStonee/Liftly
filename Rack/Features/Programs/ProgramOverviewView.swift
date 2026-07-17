import SwiftUI

enum ProgramDetailMode: String {
    case overview
    case days
}

struct ProgramOverviewView: View {
    let workouts: [WorkoutTemplate]

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                ProgramOverviewDaySection(
                    workout: workout,
                    dayNumber: index + 1
                )
            }
        }
    }
}

private struct ProgramOverviewDaySection: View {
    let workout: WorkoutTemplate
    let dayNumber: Int

    @AppStorage private var isExpanded: Bool
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .lbs

    init(workout: WorkoutTemplate, dayNumber: Int) {
        self.workout = workout
        self.dayNumber = dayNumber
        _isExpanded = AppStorage(
            wrappedValue: true,
            "programOverview.expanded.\(workout.id.uuidString)"
        )
    }

    var body: some View {
        let exercises = workout.sortedExercises

        GlassCard(cornerRadius: 18, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Day \(dayNumber), \(workout.name)")
                .accessibilityValue(
                    "\(exerciseCountText), \(isExpanded ? "expanded" : "collapsed")"
                )
                .accessibilityHint(isExpanded ? "Collapses this workout day" : "Expands this workout day")

                if isExpanded {
                    Divider()
                        .overlay(.white.opacity(0.08))

                    if exercises.isEmpty {
                        Text("No exercises yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, planned in
                                ProgramOverviewExerciseRow(
                                    planned: planned,
                                    weightUnit: weightUnit
                                )

                                if index < exercises.count - 1 {
                                    Divider()
                                        .overlay(.white.opacity(0.06))
                                        .padding(.leading, 24)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Day \(dayNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                Text(workout.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(exerciseCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .padding(14)
    }

    private var exerciseCountText: String {
        let count = workout.plannedExercisesList.count
        return "\(count) \(count == 1 ? "exercise" : "exercises")"
    }
}

private struct ProgramOverviewExerciseRow: View {
    let planned: PlannedExercise
    let weightUnit: WeightUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .font(.subheadline.bold())
                .foregroundStyle(.blue)

            Text("\(Text(exerciseName).fontWeight(.semibold).foregroundStyle(.primary)): \(Text(visiblePrescription).foregroundStyle(.secondary))")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exerciseName), \(spokenPrescription)")
    }

    private var exerciseName: String {
        planned.exercise?.name ?? "Exercise"
    }

    private var setCountText: String {
        "\(planned.sets) \(planned.sets == 1 ? "set" : "sets")"
    }

    private var visibleRepTarget: String {
        switch planned.repTargetType {
        case .exact:
            let reps = planned.exactRepTarget
            return "\(reps) \(reps == 1 ? "rep" : "reps")"
        case .range:
            let range = planned.repRange
            return "\(range.lowerBound)–\(range.upperBound) reps"
        case .failure:
            return "failure"
        }
    }

    private var visiblePrescription: String {
        let repPrescription: String
        if planned.repTargetType == .failure {
            repPrescription = "\(setCountText) to \(visibleRepTarget)"
        } else {
            repPrescription = "\(setCountText) × \(visibleRepTarget)"
        }

        guard let weight = planned.targetWeight else {
            return repPrescription
        }

        return "\(repPrescription) · \(weight.formattedWeight(unit: weightUnit)) \(weightUnit.symbol)"
    }

    private var spokenPrescription: String {
        let repPrescription: String
        switch planned.repTargetType {
        case .exact:
            let reps = planned.exactRepTarget
            repPrescription = "\(setCountText) by \(reps) \(reps == 1 ? "rep" : "reps")"
        case .range:
            let range = planned.repRange
            repPrescription = "\(setCountText) by \(range.lowerBound) to \(range.upperBound) reps"
        case .failure:
            repPrescription = "\(setCountText) to failure"
        }

        guard let weight = planned.targetWeight else {
            return repPrescription
        }

        let unitName = weightUnit == .lbs ? "pounds" : "kilograms"
        return "\(repPrescription), target weight \(weight.formattedWeight(unit: weightUnit)) \(unitName)"
    }
}
