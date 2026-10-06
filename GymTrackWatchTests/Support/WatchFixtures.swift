import Foundation
@testable import GymTrackWatch

/// Builders and fixed clocks for the watch's value-type tests.
///
/// The `GymTrackTests/Support` helpers are not compiled into this target, so the
/// watch carries its own small copy. Every date a test asserts on comes from
/// here: the wrist's rules all take `now:` as a parameter, and a test that read
/// the wall clock instead would pass or fail with the day it ran.
enum WatchTestClock {

    /// A Wednesday at noon UTC, clear of month ends and daylight-saving changes.
    static let reference = at("2026-03-11T12:00:00")

    /// A reference for the rest timer, which arms a real `Timer` for the end of
    /// a rest it is handed. A rest ending in the real past would fire that timer
    /// the first time the run loop turns between tests; one ending long after
    /// any machine's present never does, so a test finishes with nothing left
    /// scheduled. The timer's own arithmetic is all in the `now:` parameter, so
    /// the date it is given changes nothing it decides.
    static let restReference = at("2099-12-31T23:59:30")

    /// A wall-clock time in the given zone, written `yyyy-MM-dd'T'HH:mm:ss`.
    static func at(_ stamp: String, in zone: String = "UTC") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)!
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = formatter.date(from: stamp) else {
            preconditionFailure("Unreadable test date \(stamp)")
        }
        return date
    }
}

/// A `UserDefaults` of its own, emptied first, for the types that persist
/// themselves through one. Never `.standard`: the watch host app is running
/// beside the tests and keeps its own state there.
func watchTestDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "GymTrackWatchTests.\(name)"
    UserDefaults().removePersistentDomain(forName: suite)
    return UserDefaults(suiteName: suite)!
}

/// One set on the wrist, unlogged unless `completedAt` says when it was.
func watchSet(_ id: UUID = UUID(), index: Int = 0, weightKg: Double = 60, reps: Int = 5,
              completedAt: Date? = nil, startedAt: Date? = nil, rpe: Double? = nil,
              continuation: Bool? = nil) -> WatchSetSnapshot {
    WatchSetSnapshot(id: id, index: index, weightKg: weightKg, reps: reps, seconds: 0,
                     targetRepsLow: reps, targetRepsHigh: reps,
                     isCompleted: completedAt != nil, continuation: continuation,
                     startedAt: startedAt, completedAt: completedAt, rpe: rpe)
}

/// An exercise holding the given sets, in plan position `order`.
func watchExercise(_ id: String = "squat", order: Int = 0,
                   sets: [WatchSetSnapshot]) -> WatchExerciseSnapshot {
    WatchExerciseSnapshot(id: id, name: id.capitalized, order: order, tracking: .weightReps,
                          restSeconds: 90, sets: sets)
}

/// A session of the given exercises. Pass `exercises: []` for the empty
/// session the phone mirrors in the moment between starting and picking a lift.
func watchSession(id: UUID = UUID(), title: String = "Push", startedAt: Date = WatchTestClock.reference,
                  exercises: [WatchExerciseSnapshot], preferred: String? = nil,
                  volumeKg: Double = 0) -> WatchSessionSnapshot {
    WatchSessionSnapshot(sessionID: id, title: title, planName: "", startedAt: startedAt,
                         exercises: exercises, preferredExerciseID: preferred,
                         restTotalSeconds: 0, restAutoStart: true, volumeKg: volumeKg, unit: .kg)
}

/// A single-exercise session, the shape most of the wrist's decisions need.
func watchSession(id: UUID = UUID(), startedAt: Date = WatchTestClock.reference,
                  sets: [WatchSetSnapshot]) -> WatchSessionSnapshot {
    watchSession(id: id, startedAt: startedAt, exercises: [watchExercise(sets: sets)])
}

/// A mirror sent at `sentAt`. Revision 0 unless a test is about the counter.
func watchMirror(_ session: WatchSessionSnapshot?, at sentAt: Date, revision: Int = 0,
                 healthEnabled: Bool = false, ended: WatchSessionEnd? = nil) -> WatchMirror {
    WatchMirror(revision: revision, sentAt: sentAt, idle: .empty, session: session,
                healthEnabled: healthEnabled, endedSession: ended)
}

/// A log the wrist made and has not yet heard the phone agree with.
func watchLog(_ id: UUID, at moment: Date, weightKg: Double = 62.5) -> WatchPendingLog {
    WatchPendingLog(setID: id, weightKg: weightKg, reps: 5, seconds: 0, completedAt: moment)
}
