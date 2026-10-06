import Foundation
import Testing
@testable import GymTrackWatch

/// The decisions the wrist makes on its own, held to their boundaries: which
/// taps count, when a rest buzzes and what its countdown shows, what the
/// recorder does with a session that went quiet or ended somewhere else, and
/// how a command travels to the phone.
///
/// Complements the script-style `Tests/WatchLoggerRulesTests.swift` and
/// `Tests/WatchRecordingRulesTests.swift`, which run the same rules without a
/// test target. These sit on the exact edges (the 0.6 s double tap, the 2 s and
/// 60 s buzz tolerances, the 90 minute idle line) and on the dates around
/// midnight, where a countdown that leaned on the calendar would go wrong.
///
/// Haptics are not asserted: `WatchHaptics` plays through `WKInterfaceDevice`
/// and nothing here can see what it played. Every claim is about state.
@MainActor @Suite(.serialized)
struct WatchRulesTests {

    // MARK: - Set taps

    /// A chalked thumb double-taps, and a clock that stepped backwards must not
    /// leave the button dead. Dates are offsets from the reference epoch so the
    /// elapsed time is exactly the number written: 0.6 s of difference between
    /// two present-day dates is not exactly 0.6 in a double.
    @Test(arguments: zip(
        [nil, 0, 0.3, 0.5999, 0.6, 5, -3] as [Double?],
        [true, false, false, false, true, true, true]
    ))
    func setTapIsDebouncedForSixTenthsOfASecond(elapsed: Double?, accepted: Bool) {
        let loggedAt = Date(timeIntervalSinceReferenceDate: 0)
        let last = elapsed == nil ? nil : loggedAt
        let now = Date(timeIntervalSinceReferenceDate: elapsed ?? 0)
        #expect(WatchLoggerRules.acceptsSetTap(lastLoggedAt: last, now: now) == accepted)
    }

    @Test func aFinishedExerciseIsOnlyReviewedAndAnUnknownOneIsLetThrough() {
        let done = watchExercise("bench", order: 0, sets: [watchSet(completedAt: WatchTestClock.reference)])
        let open = watchExercise("squat", order: 1, sets: [watchSet(), watchSet(completedAt: WatchTestClock.reference)])
        // An exercise with no sets is not "complete": nothing was finished, so
        // tapping it must still move the session onto it.
        let empty = watchExercise("curl", order: 2, sets: [])
        let all = [done, open, empty]

        #expect(WatchLoggerRules.tap(on: done) == .review)
        #expect(WatchLoggerRules.tap(on: open) == .focus)
        #expect(WatchLoggerRules.tap(on: empty) == .focus)

        #expect(!WatchLoggerRules.allowsFocus(on: "bench", in: all))
        #expect(WatchLoggerRules.allowsFocus(on: "squat", in: all))
        #expect(WatchLoggerRules.allowsFocus(on: "curl", in: all))
        // The mirror does not hold it: refusing is the phone's call.
        #expect(WatchLoggerRules.allowsFocus(on: "deadlift", in: all))
        #expect(WatchLoggerRules.allowsFocus(on: "deadlift", in: []))
        // The same lift listed twice, once finished: one focusable copy is enough.
        #expect(WatchLoggerRules.allowsFocus(on: "bench", in: all + [watchExercise("bench", order: 3, sets: [watchSet()])]))
    }

    // MARK: - Rest tolerances

    /// Whole-second offsets from the reference epoch, so each boundary is hit
    /// exactly rather than approximately.
    @Test(arguments: zip(
        [-30.0, 0, 2, 2.5, 600] as [Double],
        [true, true, true, false, false]
    ))
    func aRestIsBuzzedAndFollowedUpToTwoSecondsAfterItEnded(lateBy: Double, buzzes: Bool) {
        let endsAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = Date(timeIntervalSinceReferenceDate: 1_000 + lateBy)
        #expect(WatchRestRules.buzzesOnEnd(endsAt: endsAt, now: now) == buzzes)
        #expect(WatchRestRules.isFollowable(endsAt: endsAt, now: now) == buzzes,
                "Following a rest and buzzing for one are the same question")
    }

    @Test func aRestTheWatchRanItselfStillBuzzesAMinuteLateButNotMinutesLate() {
        let endsAt = Date(timeIntervalSinceReferenceDate: 1_000)
        func buzzes(lateBy seconds: Double) -> Bool {
            WatchRestRules.buzzesOnExpiry(endsAt: endsAt, now: Date(timeIntervalSinceReferenceDate: 1_000 + seconds))
        }
        #expect(buzzes(lateBy: 0))
        #expect(buzzes(lateBy: 8), "a wrist-down wake a few seconds late is still the tap they are waiting for")
        #expect(buzzes(lateBy: 60))
        #expect(!buzzes(lateBy: 60.5))
        #expect(!buzzes(lateBy: 600))
    }

    /// The `TimelineView` ticks from this anchor, so it must sit a whole number
    /// of seconds before the end and cover the whole rest, whatever the clock
    /// and the stated total disagree about.
    @Test func tickAnchorSitsWholeSecondsBeforeTheEndAndCoversTheRest() {
        let now = Date(timeIntervalSinceReferenceDate: 5_000)
        // (seconds until the end, stated total, expected span back from the end)
        let cases: [(until: Double, total: Int, span: Double)] = [
            (90, 90, 91),      // an ordinary rest
            (37.4, 90, 91),    // joined mid-rest: the stated total is longer
            (200, 120, 201),   // extended past the stated total
            (37.4, 0, 39),     // no total at all: the remaining time rounds up
            (-30, 60, 61),     // already over: still anchored a total back
            (-30, 0, 1)        // already over and no total: never zero or negative
        ]
        for c in cases {
            let endsAt = now.addingTimeInterval(c.until)
            let anchor = WatchRestRules.tickAnchor(endsAt: endsAt, totalSeconds: c.total, now: now)
            let span = endsAt.timeIntervalSince(anchor)
            #expect(span == c.span, "until \(c.until), total \(c.total)")
            #expect(span == span.rounded(), "anchor must land on a second boundary of the rest")
            #expect(anchor <= now || c.until <= 0, "the anchor must not start after the rest has")
        }
    }

    // MARK: - Rest timer

    /// A rest that runs through midnight: the countdown is an interval, not a
    /// calendar sum, so the day rolling over must not show in it. Cairo's
    /// midnight is two hours off UTC's, which a timer reading the calendar
    /// would get wrong.
    @Test func aRestFollowedFromThePhoneCountsStraightThroughMidnight() {
        let start = WatchTestClock.at("2099-12-31T23:59:30", in: "Africa/Cairo")
        let endsAt = WatchTestClock.at("2100-01-01T00:01:00", in: "Africa/Cairo")
        let timer = WatchRestTimer()
        defer { timer.stop(silently: true) }

        timer.sync(endsAt: endsAt, total: 90, now: start)
        #expect(timer.isRunning && !timer.isLocal)
        #expect(timer.totalSeconds == 90)
        #expect(timer.endsAt == endsAt)
        #expect(timer.remaining(at: start) == 90)
        #expect(timer.label(at: start) == "1:30")
        #expect(timer.progress(at: start) == 0)

        let atMidnight = WatchTestClock.at("2100-01-01T00:00:00", in: "Africa/Cairo")
        #expect(timer.remaining(at: atMidnight) == 60)
        #expect(timer.label(at: atMidnight) == "1:00")
        #expect(abs(timer.progress(at: atMidnight) - 1.0 / 3.0) < 0.0001)

        // Nothing ticks between start and end, so a rest read long after its end
        // is still "running" here: it must show zero, never a negative time or a
        // fraction past one.
        for later in ["2100-01-01T00:01:00", "2100-01-01T00:05:00", "2100-01-02T09:00:00"] {
            let at = WatchTestClock.at(later, in: "Africa/Cairo")
            #expect(timer.remaining(at: at) == 0)
            #expect(timer.label(at: at) == "0:00")
            #expect(timer.progress(at: at) == 1)
        }
    }

    @Test func aStoppedOrNeverStartedRestShowsNothing() {
        let timer = WatchRestTimer()
        let now = WatchTestClock.restReference
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: now) == 0)
        #expect(timer.progress(at: now) == 0)
        #expect(timer.label(at: now) == "—")

        timer.sync(endsAt: now.addingTimeInterval(60), total: 60, now: now)
        #expect(timer.isRunning)
        timer.stop(silently: true)
        #expect(!timer.isRunning && timer.endsAt == nil && timer.totalSeconds == 0 && !timer.isLocal)
        #expect(timer.label(at: now) == "—")
    }

    /// The four ways a mirror can say something about the rest that is not "here
    /// is the end": long over, absent, unknown, and arriving while the wrist's
    /// own rest is younger than the phone's round trip.
    @Test func staleAbsentUnknownAndEarlyMirrorsLeaveTheRightRestStanding() {
        let now = WatchTestClock.restReference
        let timer = WatchRestTimer()
        defer { timer.stop(silently: true) }

        // A relaunch from a cached context carries a rest that ended ten minutes ago.
        timer.sync(endsAt: now.addingTimeInterval(-600), total: 90, now: now)
        #expect(!timer.isRunning, "a rest that is long over is the phone saying there is none")

        // A mirror built without knowing the rest says nothing: it must neither
        // start one nor wipe the one the lifter is standing in.
        timer.sync(endsAt: now.addingTimeInterval(45), total: 90, unknown: true, now: now)
        #expect(!timer.isRunning)
        timer.sync(endsAt: now.addingTimeInterval(45), total: 90, now: now)
        #expect(timer.isRunning)
        timer.sync(endsAt: nil, total: 0, unknown: true, now: now)
        #expect(timer.isRunning && timer.endsAt == now.addingTimeInterval(45))

        // A known absence does stop the phone's rest, and a stated total of zero
        // never divides anything.
        timer.sync(endsAt: nil, total: 0, now: now)
        #expect(!timer.isRunning)
        timer.sync(endsAt: now.addingTimeInterval(10), total: 0, now: now)
        #expect(timer.totalSeconds == 1)
        #expect(timer.progress(at: now) == 0)
        #expect(timer.progress(at: now.addingTimeInterval(10)) == 1)
        timer.stop(silently: true)

        // The wrist's own rest survives a mirror that crossed it in flight, and
        // gives way once the phone has had time to hear and still says nothing.
        timer.startLocal(seconds: 60, now: now)
        #expect(timer.isRunning && timer.isLocal && timer.endsAt == now.addingTimeInterval(60))
        timer.sync(endsAt: nil, total: 0, now: now.addingTimeInterval(1))
        #expect(timer.isRunning && timer.isLocal)
        timer.sync(endsAt: nil, total: 0, now: now.addingTimeInterval(3))
        #expect(timer.isRunning, "exactly the grace period is not past it")
        timer.sync(endsAt: nil, total: 0, now: now.addingTimeInterval(4))
        #expect(!timer.isRunning && !timer.isLocal)

        // The phone's own end date takes over a local rest.
        timer.startLocal(seconds: 60, now: now)
        timer.sync(endsAt: now.addingTimeInterval(90), total: 90, now: now.addingTimeInterval(1))
        #expect(!timer.isLocal && timer.endsAt == now.addingTimeInterval(90) && timer.totalSeconds == 90)

        // A rest of no length is no rest.
        timer.stop(silently: true)
        timer.startLocal(seconds: 0, now: now)
        timer.startLocal(seconds: -30, now: now)
        #expect(!timer.isRunning)
    }

    // MARK: - Recording

    @Test func healthPermissionAndThePhoneEndingAWorkoutAreDecidedFromTheirFacts() {
        typealias Rules = WatchRecordingRules
        #expect(Rules.permission(healthEnabled: true, workoutSharingAuthorized: true) == .ask)
        #expect(Rules.permission(healthEnabled: true, workoutSharingAuthorized: false) == .ask)
        #expect(Rules.permission(healthEnabled: false, workoutSharingAuthorized: true) == .granted)
        #expect(Rules.permission(healthEnabled: false, workoutSharingAuthorized: false) == .withheld)

        let session = UUID()
        func end(_ reason: WatchSessionEnd.Reason, of id: UUID? = nil, phoneWorkout: UUID? = nil) -> WatchSessionEnd {
            WatchSessionEnd(sessionID: id ?? session, reason: reason, phoneHealthWorkoutID: phoneWorkout)
        }
        func close(_ end: WatchSessionEnd?, health: Bool = true) -> WatchRecordingRules.Close {
            Rules.closeAfterPhoneEnd(end, recording: session, healthEnabled: health)
        }
        // Saved and reported only for a finish of this session that the phone did not already write.
        #expect(close(end(.finished)) == .init(discards: false, reportsMetrics: true))
        #expect(close(end(.finished), health: false) == .init(discards: true, reportsMetrics: true))
        #expect(close(end(.finished, phoneWorkout: UUID())) == .init(discards: true, reportsMetrics: false),
                "the phone wrote its own workout: a second one here would count it twice")
        #expect(close(end(.discarded)) == .init(discards: true, reportsMetrics: false))
        #expect(close(end(.finished, of: UUID())) == .init(discards: true, reportsMetrics: false),
                "another session's end says nothing about this recording")
        #expect(close(nil) == .init(discards: true, reportsMetrics: false))

        #expect(Rules.discardsOnWristFinish(healthEnabled: true, setsLogged: 0))
        #expect(Rules.discardsOnWristFinish(healthEnabled: false, setsLogged: 5))
        #expect(!Rules.discardsOnWristFinish(healthEnabled: true, setsLogged: 1))
    }

    /// A recording left running after the lifter went home. The line is 90
    /// minutes of silence, counted from the latest of the start and every set's
    /// start or completion.
    @Test func aQuietRecordingIsFinishedAtItsLastSetOrDiscardedIfItNeverHadOne() {
        let t0 = WatchTestClock.reference
        let line = WatchRecordingRules.idleFinishAfter
        #expect(line == 90 * 60)

        // The empty session: nothing was ever logged, so there is nothing to save.
        let empty = watchSession(startedAt: t0, exercises: [])
        #expect(WatchRecordingRules.lastActivity(in: empty) == t0)
        #expect(WatchRecordingRules.idleVerdict(for: empty, now: t0) == .keepRecording)
        #expect(WatchRecordingRules.idleVerdict(for: empty, now: t0.addingTimeInterval(line - 1)) == .keepRecording)
        #expect(WatchRecordingRules.idleVerdict(for: empty, now: t0.addingTimeInterval(line)) == .discard)

        // A set that was started but never logged keeps the recording alive, and
        // is not worth saving on its own.
        let begun = watchSession(startedAt: t0, sets: [watchSet(startedAt: t0.addingTimeInterval(3_600))])
        #expect(WatchRecordingRules.idleVerdict(for: begun, now: t0.addingTimeInterval(3_600 + line - 1)) == .keepRecording)
        #expect(WatchRecordingRules.idleVerdict(for: begun, now: t0.addingTimeInterval(3_600 + line)) == .discard)

        // Finished at the last completion, not at the moment the wrist noticed,
        // and not at a later start that was never logged.
        let done = t0.addingTimeInterval(1_800)
        let worked = watchSession(startedAt: t0, sets: [
            watchSet(completedAt: done),
            watchSet(startedAt: t0.addingTimeInterval(2_400))
        ])
        #expect(WatchRecordingRules.idleVerdict(for: worked, now: t0.addingTimeInterval(2_400 + line)) == .finish(at: done))

        // A set marked done with no moment recorded: fall back to the last time
        // anything is known to have happened rather than invent a completion.
        var unstamped = watchSet()
        unstamped.isCompleted = true
        let vague = watchSession(startedAt: t0, sets: [unstamped])
        #expect(WatchRecordingRules.idleVerdict(for: vague, now: t0.addingTimeInterval(line)) == .finish(at: t0))

        // Activity stamped after `now` (a skewed clock) is not idleness.
        let skewed = watchSession(startedAt: t0, sets: [watchSet(completedAt: t0.addingTimeInterval(7_200))])
        #expect(WatchRecordingRules.idleVerdict(for: skewed, now: t0.addingTimeInterval(3_600)) == .keepRecording)
    }

    @Test func aWorkoutThatQuietlyPassesMidnightIsFinishedAtItsLastSetNotAtMidnight() {
        let zone = "Africa/Cairo"
        let started = WatchTestClock.at("2026-03-10T23:00:00", in: zone)
        let lastSet = WatchTestClock.at("2026-03-10T23:30:00", in: zone)
        let session = watchSession(startedAt: started, sets: [watchSet(completedAt: lastSet)])

        let justShort = WatchTestClock.at("2026-03-11T00:59:59", in: zone)
        let onTheLine = WatchTestClock.at("2026-03-11T01:00:00", in: zone)
        #expect(WatchRecordingRules.idleVerdict(for: session, now: justShort) == .keepRecording)
        #expect(WatchRecordingRules.idleVerdict(for: session, now: onTheLine) == .finish(at: lastSet))
    }

    @Test func aRequestedEndIsNeverInTheFutureNorBeforeTheStart() {
        let start = WatchTestClock.reference
        let now = start.addingTimeInterval(3_600)
        func end(_ requested: Date?, started: Date? = start) -> Date {
            WatchRecordingRules.recordingEnd(requested: requested, recordingStartedAt: started, now: now)
        }
        #expect(end(nil) == now)
        #expect(end(start.addingTimeInterval(1_800)) == start.addingTimeInterval(1_800))
        #expect(end(now) == now)
        #expect(end(now.addingTimeInterval(600)) == now, "a phone clock ahead of the wrist's cannot end a workout in the future")
        #expect(end(start) == now, "a workout of no length is not one the phone's stamp can describe")
        #expect(end(start.addingTimeInterval(-60)) == now)
        #expect(end(start.addingTimeInterval(-60), started: nil) == start.addingTimeInterval(-60))
    }

    @Test func recordingGatesAgreeOnWhichSessionIsLiveAndWhichIsOver() {
        typealias Rules = WatchRecordingRules
        let a = UUID(), b = UUID()

        #expect(Rules.stillWanted(a, liveSessionID: a, admitted: true, cancelled: false))
        #expect(!Rules.stillWanted(a, liveSessionID: a, admitted: true, cancelled: true))
        #expect(!Rules.stillWanted(a, liveSessionID: a, admitted: false, cancelled: false))
        #expect(!Rules.stillWanted(a, liveSessionID: b, admitted: true, cancelled: false))
        #expect(!Rules.stillWanted(a, liveSessionID: nil, admitted: true, cancelled: false))

        #expect(!Rules.handsOver(from: a, toLive: nil, recording: a))
        #expect(!Rules.handsOver(from: a, toLive: a, recording: nil))
        #expect(!Rules.handsOver(from: nil, toLive: a, recording: a))
        #expect(Rules.handsOver(from: a, toLive: b, recording: a))
        #expect(Rules.handsOver(from: nil, toLive: b, recording: nil))

        func over(live: UUID?, mirrored: UUID?, heard: Bool, admitted: Bool = true) -> Bool {
            Rules.sessionIsOver(recording: a, liveSessionID: live, mirroredSessionID: mirrored,
                                heardFromPhone: heard, admitted: admitted)
        }
        #expect(!over(live: a, mirrored: nil, heard: true, admitted: false), "a live session is never over")
        #expect(over(live: nil, mirrored: a, heard: false, admitted: false), "ended on the wrist")
        #expect(!over(live: nil, mirrored: nil, heard: false), "the phone has not spoken: no verdict yet")
        #expect(over(live: nil, mirrored: nil, heard: true), "the phone spoke and has no such session")
        #expect(over(live: nil, mirrored: b, heard: true), "the phone moved on to another session")
        #expect(!over(live: nil, mirrored: a, heard: true))
    }

    @Test func aRecordingRecordSurvivesARelaunchOnlyIfItIsWellFormedAndStillAdmitted() {
        let defaults = watchTestDefaults()
        #expect(WatchRecordingRecord(defaults: defaults) == nil)

        let record = WatchRecordingRecord(sessionID: UUID(), startedAt: WatchTestClock.reference)
        record.save(to: defaults)
        #expect(WatchRecordingRecord(defaults: defaults) == record)

        WatchRecordingRecord.clear(from: defaults)
        #expect(WatchRecordingRecord(defaults: defaults) == nil)

        // Corrupt or foreign bytes under the key read as no record, not a crash.
        defaults.set(Data("not json".utf8), forKey: WatchRecordingRecord.defaultsKey)
        #expect(WatchRecordingRecord(defaults: defaults) == nil)
        defaults.set("a string where data belongs", forKey: WatchRecordingRecord.defaultsKey)
        #expect(WatchRecordingRecord(defaults: defaults) == nil)
        defaults.set(Data(#"{"sessionID":"nope","startedAt":1}"#.utf8), forKey: WatchRecordingRecord.defaultsKey)
        #expect(WatchRecordingRecord(defaults: defaults) == nil)

        // A saved record is adopted only while its session is still admitted.
        #expect(WatchRecordingRules.recovery(of: nil, admits: { _ in true }) == .discard)
        #expect(WatchRecordingRules.recovery(of: record, admits: { _ in true }) == .adopt(record))
        #expect(WatchRecordingRules.recovery(of: record, admits: { $0 != record.sessionID }) == .discard,
                "a session finished on the wrist must not be resumed by a relaunch")
    }

    @Test func aWorkoutSavedFromTheWristSaysOnlyWhatItHeardAboutItsOwnSession() {
        let id = UUID()
        let heard = watchSession(id: id, title: "  Push day \n", startedAt: WatchTestClock.reference,
                                 exercises: [watchExercise(sets: [watchSet(completedAt: WatchTestClock.reference)])],
                                 volumeKg: 300)
        let full = WatchWorkoutMetadata(recording: id, snapshot: heard)
        #expect(full.sessionID == id)
        #expect(full.title == "Push day")
        #expect(full.sets == 1)
        #expect(full.volumeKg == 300)

        // Another session's snapshot is ignored whole: its title and totals are somebody else's.
        let other = WatchWorkoutMetadata(recording: UUID(), snapshot: heard)
        #expect(other.title == nil && other.sets == nil && other.volumeKg == nil)
        let unknown = WatchWorkoutMetadata(recording: nil, snapshot: heard)
        #expect(unknown.sessionID == nil && unknown.title == nil)
        let silent = WatchWorkoutMetadata(recording: id, snapshot: nil)
        #expect(silent.sessionID == id && silent.title == nil && silent.sets == nil && silent.volumeKg == nil)

        // Zero is what an unheard-from session looks like, so it is left out, not written.
        let blank = watchSession(id: id, title: " \n ", exercises: [watchExercise(sets: [watchSet()])])
        let none = WatchWorkoutMetadata(recording: id, snapshot: blank)
        #expect(none.title == nil && none.sets == nil && none.volumeKg == nil)
    }

    // MARK: - Sending to the phone

    nonisolated static let lastSession = UUID()
    nonisolated static let queuedLog = WatchCommand.logSet(id: UUID(), weightKg: 60, reps: 5, seconds: 0,
                                                           at: WatchTestClock.reference)
    nonisolated static let queuedFinish = WatchCommand.finishSession(
        WatchFinishBatch(sessionID: lastSession, logs: [], undos: [], starts: [:], cancels: [], ratings: []),
        metrics: nil)
    /// The Health workout handed over after a session the phone ended.
    nonisolated static let queuedHandover = WatchCommand.metrics(
        WatchWorkoutMetrics(sessionID: lastSession, healthWorkoutID: UUID()))

    /// A Start tapped while anything at all waited in the delivery queue went
    /// in behind it, and the system delivers that queue when it chooses. The
    /// wrist sat on "Starting" and gave up, and the phone began the workout
    /// whenever the queue arrived. The end of the last workout is the one
    /// thing a Start must wait for: ahead of it, the phone answers with the
    /// session the wrist has just closed, which the wrist will not draw.
    @Test(arguments: [
        ([], .live),
        ([.requestMirror], .live),
        ([WatchRulesTests.queuedLog, WatchRulesTests.queuedHandover, .startToday], .live),
        ([WatchRulesTests.queuedLog, WatchRulesTests.queuedFinish], .queued),
        ([.discardSession(id: WatchRulesTests.lastSession)], .queued),
        ([.finish(metrics: nil)], .queued),
        ([.discard], .queued),
    ] as [([WatchCommand], WatchCommandRouting.Route)])
    func aStartWaitsInTheQueueOnlyBehindTheEndOfTheLastWorkout(waiting: [WatchCommand],
                                                               expected: WatchCommandRouting.Route) {
        for start: WatchCommand in [.startToday, .startFreestyle] {
            #expect(WatchCommandRouting.route(start, reachable: true, waiting: waiting) == expected)
            #expect(WatchCommandRouting.route(start, reachable: false, waiting: waiting) == .queued,
                    "out of reach, the queue is the only way to the phone")
            #expect(WatchCommandRouting.requeuesAfterFailure(start))
        }
    }

    /// A request for the mirror wants the phone's answer now. Queued, it
    /// landed long after anyone was waiting, and held every later command
    /// behind it until then, the Start and the request the idle screen sends
    /// three seconds later to recover a lost reply among them.
    @Test(arguments: [false, true])
    func aRequestForTheMirrorGoesLiveOrNotAtAllAndWaitsForNothing(backlogged: Bool) {
        let waiting: [WatchCommand] = backlogged ? [Self.queuedLog, Self.queuedFinish] : []
        #expect(WatchCommandRouting.route(.requestMirror, reachable: true, waiting: waiting) == .live)
        #expect(WatchCommandRouting.route(.requestMirror, reachable: false, waiting: waiting) == .dropped)
        #expect(!WatchCommandRouting.requeuesAfterFailure(.requestMirror))
    }

    @Test func aCommandThatChangesTheSessionKeepsTheOrderItWasTappedIn() {
        let undo = WatchCommand.undoSet(id: UUID(), completedAt: WatchTestClock.reference)
        for command: WatchCommand in [undo, Self.queuedFinish, Self.queuedHandover, .addSet(catalogID: "squat")] {
            #expect(WatchCommandRouting.route(command, reachable: true, waiting: []) == .live)
            #expect(WatchCommandRouting.route(command, reachable: true, waiting: [Self.queuedLog]) == .queued,
                    "sent live, it would reach the phone ahead of the log still queued")
            #expect(WatchCommandRouting.route(command, reachable: true, waiting: [.requestMirror]) == .live,
                    "a queued request changes nothing on the phone, so nothing has to land after it")
            #expect(WatchCommandRouting.route(command, reachable: false, waiting: []) == .queued)
            #expect(WatchCommandRouting.requeuesAfterFailure(command))
        }

        // A live heart-rate reading is out of date by the next one.
        let reading = WatchCommand.metrics(WatchWorkoutMetrics(sessionID: Self.lastSession, currentHeartRate: 128))
        #expect(WatchCommandRouting.route(reading, reachable: true, waiting: [Self.queuedLog]) == .live)
        #expect(WatchCommandRouting.route(reading, reachable: false, waiting: []) == .dropped)
        #expect(!WatchCommandRouting.requeuesAfterFailure(reading))
    }
}
