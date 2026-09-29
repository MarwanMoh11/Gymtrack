import Foundation

/// Stands in for `GymTrackWatch/WatchHaptics.swift`, which plays through
/// WatchKit and cannot be built for the Mac. Counts what the real one would
/// have played, so a test can say a rest tapped the wrist once or not at all.
enum WatchHaptics {
    nonisolated(unsafe) static var restOvers = 0
    nonisolated(unsafe) static var ticks = 0

    static func tick() { ticks += 1 }
    static func restOver() { restOvers += 1 }
}
