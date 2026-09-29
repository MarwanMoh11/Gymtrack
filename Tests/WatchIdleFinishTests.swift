import Foundation

/// Run with scripts/test-watch-idle-finish.sh; no simulator or Health access
/// needed.
///
/// WATCH-10: a session nobody finishes is finished by the wrist once nothing
/// has been logged or started in it for ninety minutes, ending at its last
/// set, and discarded if nothing was ever logged. STATS-05: a wrist Finish
/// with nothing logged keeps no Health workout.
@main
struct WatchIdleFinishTests {

    static let start = Date(timeIntervalSinceReferenceDate: 780_000_000)

    static func main() {
        waitsOutTheThreshold()
        finishesAtTheLastSet()
        discardsWhatNeverStarted()
        countsAnnouncedStartsAsActivity()
        endsWhereHealthWillTakeIt()
        emptyWristFinishKeepsNoWorkout()
        print("WatchIdleFinishTests passed")
    }

    static func set(_ index: Int, completedAfter minutes: Double? = nil,
                    startedAfter started: Double? = nil) -> WatchSetSnapshot {
        WatchSetSnapshot(id: UUID(), index: index, weightKg: 60, reps: 8, seconds: 0,
                         targetRepsLow: 8, targetRepsHigh: 8, isCompleted: minutes != nil,
                         startedAt: started.map { start.addingTimeInterval($0 * 60) },
                         completedAt: minutes.map { start.addingTimeInterval($0 * 60) })
    }

    static func session(_ sets: [WatchSetSnapshot]) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: UUID(), title: "Push", planName: "", startedAt: start,
            exercises: [WatchExerciseSnapshot(id: "bench", name: "Bench", order: 0, tracking: .weightReps,
                                               restSeconds: 90, sets: sets)],
            restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg
        )
    }

    static func at(minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    static func waitsOutTheThreshold() {
        let lifted = session([set(0, completedAfter: 10), set(1, completedAfter: 20), set(2)])
        // Last set at 20 minutes: 89 minutes after it the lifter may still be
        // resting between exercises.
        precondition(WatchRecordingRules.idleVerdict(for: lifted, now: at(minutes: 20 + 89)) == .keepRecording,
                     "Eighty-nine minutes after the last set is still the workout")
        let empty = session([set(0), set(1)])
        precondition(WatchRecordingRules.idleVerdict(for: empty, now: at(minutes: 89)) == .keepRecording,
                     "A session opened eighty-nine minutes ago with nothing logged is left alone")
    }

    static func finishesAtTheLastSet() {
        let lifted = session([set(0, completedAfter: 10), set(1, completedAfter: 20), set(2)])
        precondition(WatchRecordingRules.idleVerdict(for: lifted, now: at(minutes: 20 + 91))
                     == .finish(at: at(minutes: 20)),
                     "Ninety-one minutes idle finishes the session at its last completed set")
        precondition(WatchRecordingRules.idleVerdict(for: lifted, now: at(minutes: 11 * 60))
                     == .finish(at: at(minutes: 20)),
                     "However late the rule runs, the end is the last set, not the moment it ran")
    }

    static func discardsWhatNeverStarted() {
        let empty = session([set(0), set(1)])
        precondition(WatchRecordingRules.idleVerdict(for: empty, now: at(minutes: 91)) == .discard,
                     "Ninety-one minutes with nothing logged is a Discard")
    }

    static func countsAnnouncedStartsAsActivity() {
        // The last log was long ago, but a set was announced since: the lifter
        // is under the bar, not gone home.
        let underTheBar = session([set(0, completedAfter: 10), set(1, startedAfter: 60)])
        precondition(WatchRecordingRules.lastActivity(in: underTheBar) == at(minutes: 60))
        precondition(WatchRecordingRules.idleVerdict(for: underTheBar, now: at(minutes: 60 + 89)) == .keepRecording,
                     "A set started is activity, as a set logged is")
        precondition(WatchRecordingRules.idleVerdict(for: underTheBar, now: at(minutes: 60 + 91))
                     == .finish(at: at(minutes: 10)),
                     "A set announced and never logged is not part of the workout's end")
    }

    static func endsWhereHealthWillTakeIt() {
        let now = at(minutes: 200)
        precondition(WatchRecordingRules.recordingEnd(requested: nil, recordingStartedAt: start, now: now) == now,
                     "A Finish tapped now ends now")
        precondition(WatchRecordingRules.recordingEnd(requested: at(minutes: 20), recordingStartedAt: start, now: now)
                     == at(minutes: 20), "An idle finish ends at the last set")
        precondition(WatchRecordingRules.recordingEnd(requested: at(minutes: 300), recordingStartedAt: start, now: now)
                     == now, "No workout ends in the future")
        precondition(WatchRecordingRules.recordingEnd(requested: at(minutes: -5), recordingStartedAt: start, now: now)
                     == now, "An end before the recording began is one Health would refuse")
    }

    static func emptyWristFinishKeepsNoWorkout() {
        precondition(WatchRecordingRules.discardsOnWristFinish(healthEnabled: true, setsLogged: 0),
                     "A Finish with nothing logged saves no Health workout")
        precondition(!WatchRecordingRules.discardsOnWristFinish(healthEnabled: true, setsLogged: 1),
                     "A Finish with a set logged is saved")
        precondition(WatchRecordingRules.discardsOnWristFinish(healthEnabled: false, setsLogged: 1),
                     "Health saving off still discards")
    }
}
