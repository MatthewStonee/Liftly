import ActivityKit
import Foundation

/// Only display values cross into the extension; SwiftData models never do.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    struct Exercise: Codable, Hashable, Identifiable, Sendable {
        let id: UUID
        var name: String
    }

    struct ContentState: Codable, Hashable, Sendable {
        var workoutID: UUID
        var workoutName: String
        var totalExercises: Int
        var startingIndex: Int
        var windowStartingIndex: Int = 0
        var exercises: [Exercise]
        var needsRefresh: Bool = false
        var revision: Int = 0

        var pageAnchorID: UUID? {
            let offset = startingIndex - windowStartingIndex
            return exercises.indices.contains(offset) ? exercises[offset].id : nil
        }

        var workoutURL: URL {
            URL(string: "liftly://workout/\(workoutID.uuidString)")!
        }

        func rangeLabel(visibleCount: Int) -> String {
            let end = min(startingIndex + visibleCount, totalExercises)
            if end == startingIndex + 1 {
                return "\(end) of \(totalExercises) exercises"
            }
            return "\(startingIndex + 1)–\(end) of \(totalExercises) exercises"
        }
    }

    let referenceID: UUID
}

extension WorkoutActivityAttributes.ContentState {
    private enum CodingKeys: String, CodingKey {
        case workoutID, workoutName, totalExercises, startingIndex, windowStartingIndex, exercises, needsRefresh, revision
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workoutID = try values.decode(UUID.self, forKey: .workoutID)
        workoutName = try values.decode(String.self, forKey: .workoutName)
        totalExercises = try values.decode(Int.self, forKey: .totalExercises)
        startingIndex = try values.decode(Int.self, forKey: .startingIndex)
        windowStartingIndex = try values.decodeIfPresent(Int.self, forKey: .windowStartingIndex) ?? startingIndex
        exercises = try values.decode([WorkoutActivityAttributes.Exercise].self, forKey: .exercises)
        needsRefresh = try values.decodeIfPresent(Bool.self, forKey: .needsRefresh) ?? false
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }
}

nonisolated struct WorkoutActivityPageReference: Sendable {
    let workoutID: UUID
    let startingIndex: Int
    let anchorID: UUID?
    let revision: Int
}

nonisolated enum WorkoutActivityLink {
    static func workoutID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "liftly", url.host == "workout",
              url.query == nil, url.fragment == nil else { return nil }
        let components = url.path.split(separator: "/")
        guard components.count == 1 else { return nil }
        return UUID(uuidString: String(components[0]))
    }
}
