import Foundation

/// The decisions `WatchWorkoutRecorder` makes about which GymTrack session its
/// `HKWorkoutSession` belongs to, kept free of HealthKit so the test harness
/// can hold them to account without a watch.
enum WatchRecordingRules {

    /// Whether a start that has just come back from a suspension should go on
    /// to record.
    ///
    /// Every `await` in a start can outlast the session it was for. The Health
    /// permission sheet waits for as long as the lifter leaves it, and the
    /// phone can finish, discard or replace the session in that time. A start
    /// that carried on regardless left a workout session running for a session
    /// that was over: it held the heart rate sensor and the app's runtime for
    /// the rest of the day, and its readings went to the finished record.
    ///
    /// Task cancellation is deliberately not an input. The view's task is
    /// cancelled on any change to its key, a Health toggle included, and a
    /// start dropped for that would never be asked again.
    static func stillWanted(_ id: UUID, liveSessionID: UUID?, admitted: Bool, cancelled: Bool) -> Bool {
        !cancelled && admitted && liveSessionID == id
    }

    /// Whether a start that has just finished, or given up, should go straight
    /// on to the session that is live now. While it was busy, the call for the
    /// session that replaced its own was turned away, and nothing asks again.
    static func handsOver(from attempted: UUID?, toLive live: UUID?, recording: UUID?) -> Bool {
        guard let live else { return false }
        return live != attempted && live != recording
    }

    /// How a start gets Health's permission for its workout session.
    enum Permission: Equatable {
        /// Ask, showing the sheet if the question is still open.
        case ask
        /// Already granted; start without asking.
        case granted
        /// Not granted, and not to be asked for; no session.
        case withheld
    }

    /// The session runs with Health saving off too, because it is what keeps
    /// the app on screen between sets, lets the rest-over tap fire with the
    /// wrist down, and collects heart rate. The permission sheet belongs to
    /// saving, though: a lifter who switched that off is never stopped mid-set
    /// to answer it, and gets the session only if Health was granted before.
    static func permission(healthEnabled: Bool, workoutSharingAuthorized: Bool) -> Permission {
        if healthEnabled { return .ask }
        return workoutSharingAuthorized ? .granted : .withheld
    }

    /// What closing a recording does with it.
    struct Close: Equatable {
        /// Throw the samples away rather than save a Health workout.
        var discards: Bool
        /// Send the final heart rate and energy to the phone.
        var reportsMetrics: Bool
    }

    /// Closing a recording because the phone ended its session.
    ///
    /// A missing session alone does not say whether the phone finished or
    /// discarded, so only a finish of this very session keeps anything, and
    /// only when the phone has not already written its own fallback workout.
    /// With Health saving off the phone still gets the numbers, never the
    /// workout.
    static func closeAfterPhoneEnd(_ end: WatchSessionEnd?, recording: UUID, healthEnabled: Bool) -> Close {
        let finished = end?.sessionID == recording
            && end?.reason == .finished
            && end?.phoneHealthWorkoutID == nil
        return Close(discards: !(finished && healthEnabled), reportsMetrics: finished)
    }

    /// Closing a recording because Finish was tapped on the wrist, or the idle
    /// rule tapped it for the lifter.
    ///
    /// A Finish with nothing logged is a Discard: the phone deletes the
    /// session, and a workout saved for it would sit in Health with no session
    /// to own it, moving the rings for a mis-tap.
    static func discardsOnWristFinish(healthEnabled: Bool, setsLogged: Int) -> Bool {
        !healthEnabled || setsLogged == 0
    }

    // MARK: - Idle sessions

    /// How long a recording may go without a set logged or started before the
    /// wrist finishes it on the lifter's behalf.
    ///
    /// The workout is recorded as ending at the last completed set whatever
    /// this is, so a longer wait costs only sensor time and battery, never
    /// accuracy. A shorter one risks ending a workout that is only paused: a
    /// long break between exercises, a queue for the rack, a conversation.
    /// Ended there, the lifter's next set starts a second session and the one
    /// workout is split in two. Ninety minutes is past any rest anybody takes
    /// inside a workout, and still far short of the night of recording that a
    /// forgotten Finish used to cost.
    static let idleFinishAfter: TimeInterval = 90 * 60

    /// How often a running recording asks whether it has gone idle. A minute
    /// late on a ninety-minute rule costs nothing, and the recorded end does
    /// not depend on when the question was asked.
    static let idleCheckInterval: TimeInterval = 60

    /// What the idle rule does with a recording.
    enum IdleVerdict: Equatable {
        /// Something happened recently enough; keep recording.
        case keepRecording
        /// Finish as the wrist's Finish would, ending at this moment: the last
        /// completed set.
        case finish(at: Date)
        /// Nothing was ever logged; end it as a Discard would.
        case discard
    }

    /// The latest moment anybody touched the session: its start, a set
    /// announced, a set logged. A start announced inside the count-in can lie
    /// a few seconds ahead of now, which only delays the rule by as much.
    static func lastActivity(in session: WatchSessionSnapshot) -> Date {
        let sets = session.allSets
        let moments = sets.compactMap(\.startedAt) + sets.filter(\.isCompleted).compactMap(\.completedAt)
        return moments.reduce(session.startedAt, max)
    }

    /// Whether the idle rule ends this session now, and how.
    ///
    /// The end is the last completed set, not the last activity: a set
    /// announced and never logged is dropped when the session closes, so the
    /// workout did not include it.
    static func idleVerdict(for session: WatchSessionSnapshot, now: Date) -> IdleVerdict {
        let lastTouched = lastActivity(in: session)
        guard now.timeIntervalSince(lastTouched) >= idleFinishAfter else { return .keepRecording }
        let completed = session.allSets.filter(\.isCompleted)
        guard !completed.isEmpty else { return .discard }
        return .finish(at: completed.compactMap(\.completedAt).max() ?? lastTouched)
    }

    /// When a closing recording's workout ends in Health.
    ///
    /// Now, unless the session went idle, in which case the lifter stopped at
    /// the requested moment. Never later than now, and never at or before the
    /// recording's own start, which Health refuses: a clock that disagrees
    /// with itself gets the plain end rather than no workout at all.
    static func recordingEnd(requested: Date?, recordingStartedAt start: Date?, now: Date) -> Date {
        guard let requested else { return now }
        let end = min(requested, now)
        if let start, end <= start { return now }
        return end
    }

    /// Whether the phone has said the recorded session is over.
    ///
    /// No live session is not enough on its own. A relaunched app has heard
    /// nothing from the phone yet, and a cached context that still names the
    /// session is held back until the phone's current answer arrives. Ending
    /// the recording on either threw away a workout watchOS had just
    /// recovered.
    static func sessionIsOver(recording: UUID, liveSessionID: UUID?, mirroredSessionID: UUID?,
                              heardFromPhone: Bool, admitted: Bool) -> Bool {
        if liveSessionID == recording { return false }
        if !admitted { return true }
        guard heardFromPhone else { return false }
        return mirroredSessionID != recording
    }

    /// What becomes of a workout session watchOS recovered after a crash.
    enum Recovery: Equatable {
        /// Keep recording it for this GymTrack session.
        case adopt(WatchRecordingRecord)
        /// End it and leave nothing in Health.
        case discard
    }

    /// A recovered session is kept only for the GymTrack session it was
    /// started for. Without the record there is no saying which that was, and
    /// saving it anyway would put a workout in Health that no session owns. A
    /// session ended on this wrist has its workout already, or was thrown away.
    static func recovery(of record: WatchRecordingRecord?, admits: (UUID) -> Bool) -> Recovery {
        guard let record, admits(record.sessionID) else { return .discard }
        return .adopt(record)
    }
}

/// The GymTrack session the running workout session records, kept on disk.
///
/// watchOS keeps a workout session running through a crash and relaunches the
/// app to take it back, but the recorder's memory of which session it was for
/// does not survive. Written before the session starts and removed when it
/// closes, so a record on disk always describes the one that may be running.
struct WatchRecordingRecord: Codable, Equatable, Sendable {

    static let defaultsKey = "watch.recordingSession"

    var sessionID: UUID
    var startedAt: Date

    init(sessionID: UUID, startedAt: Date) {
        self.sessionID = sessionID
        self.startedAt = startedAt
    }

    init?(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = saved
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
