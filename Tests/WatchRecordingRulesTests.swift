import Foundation

/// Run with scripts/test-watch-recording-rules.sh; no simulator or Health
/// access needed.
///
/// `Start` plays the part of `WatchWorkoutRecorder.startIfNeeded` against a
/// phone that changes its mind while the start is suspended: it asks the same
/// question after every `await` that the recorder asks, with the live session
/// and the wrist's tombstone standing in for `WatchConnector`.
@main
struct WatchRecordingRulesTests {

    struct Start {
        let id: UUID
        var live: UUID?
        var tombstone = WatchSessionTombstone()
        var cancelled = false

        var stillWanted: Bool {
            WatchRecordingRules.stillWanted(id, liveSessionID: live,
                                            admitted: tombstone.admits(id), cancelled: cancelled)
        }
    }

    static func main() {
        startsOnlyWhatIsStillWanted()
        handsOverToTheSessionThatReplacedIt()
        healthOffStillRecordsAndNeverSaves()
        closesOnlyWhenThePhoneHasSpoken()
        recoveryRefusesWhatItCannotOwn()
        recordSurvivesARelaunch()
        print("WatchRecordingRulesTests passed")
    }

    // MARK: - WATCH-06

    static func startsOnlyWhatIsStillWanted() {
        let s = UUID(), t = UUID()

        var start = Start(id: s, live: s)
        precondition(start.stillWanted, "A start for the live session must go on")

        // The Health sheet sat unanswered while the phone finished the session.
        start.live = nil
        precondition(!start.stillWanted,
                     "A start must not commit after the phone ended its session")

        // Discarded and replaced by another session during `beginCollection`.
        start.live = t
        precondition(!start.stillWanted,
                     "A start must not commit when a different session is live")

        // Finish on the wrist during the wait.
        start.live = s
        start.tombstone.mark(s)
        precondition(!start.stillWanted,
                     "A start must not commit for a session ended on the wrist")

        // `end` called while the start was suspended.
        var cancelled = Start(id: s, live: s)
        cancelled.cancelled = true
        precondition(!cancelled.stillWanted,
                     "A start must close itself once `end` has cancelled it")
    }

    static func handsOverToTheSessionThatReplacedIt() {
        let s = UUID(), t = UUID()
        precondition(WatchRecordingRules.handsOver(from: s, toLive: t, recording: nil),
                     "The session that replaced an abandoned start must be started next")
        precondition(!WatchRecordingRules.handsOver(from: s, toLive: s, recording: nil),
                     "A start that gave up must not retry the same session in a loop")
        precondition(!WatchRecordingRules.handsOver(from: s, toLive: s, recording: s),
                     "A committed start has nothing to hand over")
        precondition(!WatchRecordingRules.handsOver(from: s, toLive: nil, recording: nil),
                     "With nothing live, nothing starts")
        precondition(WatchRecordingRules.handsOver(from: nil, toLive: t, recording: nil),
                     "A start turned away during recovery must be run once recovery ends")
        precondition(!WatchRecordingRules.handsOver(from: nil, toLive: t, recording: t),
                     "A recovered session that is live needs no second start")
    }

    // MARK: - WATCH-07

    static func healthOffStillRecordsAndNeverSaves() {
        precondition(WatchRecordingRules.permission(healthEnabled: false, workoutSharingAuthorized: true) == .granted,
                     "With Health saving off the workout session must still run")
        precondition(WatchRecordingRules.permission(healthEnabled: false, workoutSharingAuthorized: false) == .withheld,
                     "With Health saving off the lifter must never be asked for Health mid-set")
        precondition(WatchRecordingRules.permission(healthEnabled: true, workoutSharingAuthorized: false) == .ask,
                     "With Health saving on the start asks for permission")

        let s = UUID(), other = UUID(), phoneWorkout = UUID()
        let ends: [WatchSessionEnd?] = [
            nil,
            WatchSessionEnd(sessionID: s, reason: .finished, phoneHealthWorkoutID: nil),
            WatchSessionEnd(sessionID: s, reason: .finished, phoneHealthWorkoutID: phoneWorkout),
            WatchSessionEnd(sessionID: s, reason: .discarded, phoneHealthWorkoutID: nil),
            WatchSessionEnd(sessionID: other, reason: .finished, phoneHealthWorkoutID: nil),
        ]
        for end in ends {
            precondition(WatchRecordingRules.closeAfterPhoneEnd(end, recording: s, healthEnabled: false).discards,
                         "With Health saving off every phone end must discard")
        }
        precondition(WatchRecordingRules.discardsOnWristFinish(healthEnabled: false, setsLogged: 3),
                     "With Health saving off a wrist Finish must discard")

        let finished = WatchRecordingRules.closeAfterPhoneEnd(ends[1], recording: s, healthEnabled: false)
        precondition(finished.reportsMetrics,
                     "A finished session keeps its heart rate with Health saving off")

        // The saving side is unchanged with Health on.
        precondition(WatchRecordingRules.closeAfterPhoneEnd(ends[1], recording: s, healthEnabled: true)
                     == .init(discards: false, reportsMetrics: true),
                     "A matching finish with Health on is saved")
        for end in [ends[0], ends[2], ends[3], ends[4]] {
            let close = WatchRecordingRules.closeAfterPhoneEnd(end, recording: s, healthEnabled: true)
            precondition(close == .init(discards: true, reportsMetrics: false),
                         "Only a matching finish with no phone fallback may keep a recording")
        }
        precondition(!WatchRecordingRules.discardsOnWristFinish(healthEnabled: true, setsLogged: 3),
                     "A wrist Finish with Health on is saved")
    }

    // MARK: - WATCH-09

    static func closesOnlyWhenThePhoneHasSpoken() {
        let s = UUID(), t = UUID()
        precondition(!WatchRecordingRules.sessionIsOver(recording: s, liveSessionID: nil, mirroredSessionID: nil,
                                                        heardFromPhone: false, admitted: true),
                     "A recovered recording must survive a relaunch that has heard nothing yet")
        precondition(!WatchRecordingRules.sessionIsOver(recording: s, liveSessionID: nil, mirroredSessionID: s,
                                                        heardFromPhone: true, admitted: true),
                     "A cached context that still names the session must wait for the phone")
        precondition(!WatchRecordingRules.sessionIsOver(recording: s, liveSessionID: s, mirroredSessionID: s,
                                                        heardFromPhone: true, admitted: true),
                     "A live session is not over")
        precondition(WatchRecordingRules.sessionIsOver(recording: s, liveSessionID: nil, mirroredSessionID: nil,
                                                       heardFromPhone: true, admitted: true),
                     "The phone saying no session ends the recording")
        precondition(WatchRecordingRules.sessionIsOver(recording: s, liveSessionID: t, mirroredSessionID: t,
                                                       heardFromPhone: true, admitted: true),
                     "Another session on the phone ends the recording")
        precondition(WatchRecordingRules.sessionIsOver(recording: s, liveSessionID: nil, mirroredSessionID: s,
                                                       heardFromPhone: false, admitted: false),
                     "A session ended on the wrist is over whatever the phone says")
    }

    static func recoveryRefusesWhatItCannotOwn() {
        let s = UUID()
        let record = WatchRecordingRecord(sessionID: s, startedAt: Date().addingTimeInterval(-2400))
        var tombstone = WatchSessionTombstone()

        precondition(WatchRecordingRules.recovery(of: record, admits: { tombstone.admits($0) }) == .adopt(record),
                     "A recovered workout is kept for the session it was recording")
        precondition(WatchRecordingRules.recovery(of: nil, admits: { tombstone.admits($0) }) == .discard,
                     "A recovered workout with no record of its session must not be saved")

        tombstone.mark(s)
        precondition(WatchRecordingRules.recovery(of: record, admits: { tombstone.admits($0) }) == .discard,
                     "A recovered workout for a session ended on the wrist must be discarded")
    }

    static func recordSurvivesARelaunch() {
        let suite = "WatchRecordingRulesTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(WatchRecordingRecord(defaults: defaults) == nil, "A fresh wrist has no record")
        let record = WatchRecordingRecord(sessionID: UUID(), startedAt: Date(timeIntervalSinceReferenceDate: 780_000_000))
        record.save(to: defaults)
        precondition(WatchRecordingRecord(defaults: defaults) == record, "The record must read back unchanged")
        WatchRecordingRecord.clear(from: defaults)
        precondition(WatchRecordingRecord(defaults: defaults) == nil, "A closed recording leaves no record")
    }
}
