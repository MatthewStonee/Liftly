import OSLog

/// Marks the moments the latency benchmarks in `Benchmarks/` compare, on Instruments'
/// Points of Interest track. Signposts cost nothing unless Instruments is recording.
nonisolated enum PerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: "com.matthewstone.liftly",
        category: .pointsOfInterest
    )

    /// Lets views mark a moment without importing OSLog.
    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
