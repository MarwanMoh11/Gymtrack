import Foundation
import WatchConnectivity
import os

/// The watch's end of the link.
///
/// The watch keeps no workout database. It draws the last mirror the phone sent and
/// sends back a command for anything the user does — which means a set logged
/// here goes through the phone's own logging path, with the same personal
/// record check and load carry-forward, and comes back in the next mirror.
///
/// The one exception is the optimistic overlay below. Waiting for a round trip
/// before the button responds would be unusable in a gym where the phone is in
/// a locker, so a logged set is drawn as done immediately and reconciled when
/// the phone confirms it. Out of range, the command sits in the guaranteed
/// `transferUserInfo` queue and lands when the watch is back.
@MainActor
@Observable
final class WatchConnector: NSObject {

    static let shared = WatchConnector()

    private(set) var mirror: WatchMirror = .placeholder
    private(set) var isReachable = false
    private(set) var hasEverReceivedMirror = false
    /// The phone's last description of a running session, kept after the
    /// phone ends it. A recording closed because the phone retired a session
    /// left open reads the last set from this: by then the mirror no longer
    /// names the session, and ending the workout on arrival instead recorded
    /// the hours it sat forgotten.
    private(set) var lastMirroredSession: WatchSessionSnapshot?
    /// A cached active session needs the reachable phone's current answer
    /// before the watch can treat it as a workout to record.
    private var waitingForFreshMirror = false

    private static let pendingActionsKey = "watch.pendingActions"
    private var pending = WatchPendingActions() {
        didSet {
            if let data = try? JSONEncoder().encode(pending) {
                UserDefaults.standard.set(data, forKey: Self.pendingActionsKey)
            }
        }
    }
    private static let ratingsKey = "watch.pendingSetRatings"
    private var ratings = WatchRatingOutbox() {
        didSet {
            if let data = try? JSONEncoder().encode(ratings) {
                UserDefaults.standard.set(data, forKey: Self.ratingsKey)
            }
        }
    }
    /// The session Finish or Discard closed on this wrist, until the phone
    /// agrees it is over. See `WatchSessionTombstone`.
    private var endedLocally = WatchSessionTombstone() {
        didSet {
            if endedLocally != oldValue { endedLocally.save(to: .standard) }
        }
    }
    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack.watchkitapp", category: "Connector")

    private override init() {
        super.init()
        endedLocally = WatchSessionTombstone(defaults: .standard)
        if let data = UserDefaults.standard.data(forKey: Self.ratingsKey),
           let saved = try? JSONDecoder().decode(WatchRatingOutbox.self, from: data) {
            ratings = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.pendingActionsKey),
           let saved = try? JSONDecoder().decode(WatchPendingActions.self, from: data) {
            pending = saved
        }
    }

    // MARK: - Lifecycle

    func activate() {
        // A unit-test host stays unlinked, so no test's state reaches a phone.
        guard !LaunchMode.isUnitTestHost, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - What the UI draws

    /// The mirror's session with this watch's unconfirmed changes folded in.
    var session: WatchSessionSnapshot? {
        guard var session = endedLocally.liveSession(in: mirror, awaitingFreshMirror: waitingForFreshMirror)
        else { return nil }
        // The pick goes on first: everything below asks which exercise the
        // logger is on, and while this is set the answer is this one.
        if let pendingID = pending.sessionID, pendingID != session.sessionID { return session }
        if let focus = pending.focus { session.preferredExerciseID = focus }
        guard hasPendingChanges else { return session }

        session.exercises = session.exercises.map(folding)
        // The current set moves on as soon as the last one is logged, rather
        // than when the phone says so — and it has to move to the set the phone
        // is about to name, which is the one on the exercise the lifter chose.
        // Reading the first unfinished exercise off the top instead threw that
        // choice away: log a set on the third exercise and the logger snapped
        // back to the first, and stayed there for as long as the phone took to
        // answer.
        session.currentSetID = session.focusedExercise?.sets.first { !$0.isCompleted }?.id
        return session
    }

    /// One exercise with this watch's unconfirmed work folded in: the numbers
    /// on the rows logged here, and the load those logs carry onto the rows
    /// still to come.
    ///
    /// The carry-forward is `ActiveWorkout.carryLoadForward` said again on the
    /// wrist, and it has to stay the same answer. The gap it closes is the one
    /// between the tap and the phone's reply — the set the logger moves to is
    /// drawn from this, so without it the dial lands on the weight the lifter
    /// just changed, and logging that row writes the old weight back over the
    /// phone's. Dropping a plate on the wrist undid itself for the rest of the
    /// exercise.
    private func folding(_ exercise: WatchExerciseSnapshot) -> WatchExerciseSnapshot {
        var exercise = exercise
        exercise.sets = exercise.sets.map { set in
            var set = set
            if let pending = pending.logs[set.id] {
                set.isCompleted = true
                set.weightKg = pending.weightKg
                set.reps = pending.reps
                set.completedAt = pending.completedAt
                set.rpe = nil
                if exercise.tracking == .duration { set.seconds = pending.seconds }
            }
            if let entry = ratings.entries[set.id], entry.rating.matches(set.completedAt), set.isCompleted {
                set.rpe = entry.rating.rpe
            }
            if pending.undos.contains(set.id) {
                set.isCompleted = false
                set.completedAt = nil
                set.rpe = nil
            }
            if let started = pending.starts[set.id] { set.startedAt = started }
            if pending.cancels.contains(set.id) { set.startedAt = nil }
            return set
        }
        // A continuation carries nothing forward: its weight was chosen to be
        // lower, for that row, and pushing it down the card would leave the
        // working sets still to come sitting at the drop weight.
        for logged in exercise.sets where pending.logs[logged.id] != nil && !logged.isContinuation {
            exercise.sets = exercise.sets.map { other in
                var other = other
                guard !other.isCompleted, !other.isContinuation, other.index > logged.index else { return other }
                other.weightKg = logged.weightKg
                if exercise.tracking == .duration { other.seconds = logged.seconds }
                return other
            }
        }
        return exercise
    }

    var idle: WatchIdleSnapshot { mirror.idle }
    var unit: WeightUnit { mirror.session?.unit ?? mirror.idle.unit }

    /// True while there's something the phone hasn't acknowledged. A pick and
    /// an announced start are both left out on purpose: the footer this drives
    /// warns that *sets* are waiting, and neither of those is one. A lifter who
    /// has only moved between exercises has nothing to lose by walking away,
    /// and the only way an unsent start is lost is walking away without logging
    /// the set it belongs to — which makes it a set nobody did.
    var hasUnsyncedWork: Bool {
        !pending.logs.isEmpty || !pending.undos.isEmpty || !ratings.entries.isEmpty
    }

    /// Whether anything at all here still has to be drawn over the mirror.
    private var hasPendingChanges: Bool {
        hasUnsyncedWork || pending.focus != nil || !pending.starts.isEmpty || !pending.cancels.isEmpty
    }

    // MARK: - Sending

    func send(_ command: WatchCommand) {
        var payload = command.watchPayload(key: WatchLink.commandKey)
        guard !payload.isEmpty, WCSession.isSupported() else { return }
        // Beside the command, not in it, so a phone that predates these keys
        // reads the command as it always did. See `WatchCommandDelivery`.
        payload.merge(WatchCommandDelivery.stamp(command, showing: self.session?.sessionID).payload) { $1 }
        let session = WCSession.default

        let waiting = session.outstandingUserInfoTransfers.compactMap {
            WatchCommand.fromWatchPayload($0.userInfo, key: WatchLink.commandKey)
        }
        switch WatchCommandRouting.route(command, reachable: session.isReachable, waiting: waiting) {
        case .dropped:
            return
        case .queued:
            session.transferUserInfo(payload)
            return
        case .live:
            break
        }
        let requeues = WatchCommandRouting.requeuesAfterFailure(command)
        let replyHandler: (([String: Any]) -> Void)?
        switch command {
        case .startToday, .startFreestyle, .requestMirror:
            replyHandler = { [weak self] reply in
                onMain { self?.receive(reply) }
            }
        default:
            replyHandler = nil
        }
        session.sendMessage(payload, replyHandler: replyHandler) { [weak self] error in
            // See `WatchCommandRouting.requeuesAfterFailure`.
            guard requeues else {
                self?.log.debug("Message failed, dropped: \(error.localizedDescription, privacy: .public)")
                return
            }
            self?.log.debug("Message failed, queueing: \(error.localizedDescription, privacy: .public)")
            WCSession.default.transferUserInfo(payload)
        }
    }

    /// Logs a set: drawn as done here immediately, confirmed by the phone.
    ///
    /// Stamped here too, exactly like an announced start. The phone may be in a
    /// locker or left at home, in which case this command waits in the delivery
    /// queue and the phone's own clock on arrival describes the walk back
    /// rather than the set.
    @discardableResult
    func logSet(_ set: WatchSetSnapshot, weightKg: Double, reps: Int, seconds: Int) -> Date {
        let moment = Date()
        guard let session else { return moment }
        pending.adopt(session.sessionID)
        // Logged inside the count-in, so the start is dropped here exactly as
        // the phone will drop it when the log lands — see
        // `ActiveWorkout.complete`. Left in the overlay it would never be
        // confirmed, since the phone's answer is no start at all, and the wrist
        // would go on holding a moment that never came.
        if let start = pending.starts[set.id] ?? set.startedAt, start > moment {
            pending.starts.removeValue(forKey: set.id)
            pending.cancels.insert(set.id)
        }
        pending.forgetUndo(of: set.id)
        ratings.remove(set.id)
        pending.logs[set.id] = WatchPendingLog(setID: set.id, weightKg: weightKg, reps: reps,
                                               seconds: seconds, completedAt: moment)
        send(.logSet(id: set.id, weightKg: weightKg, reps: reps, seconds: seconds, at: moment))
        return moment
    }

    func rateSet(_ set: WatchSetSnapshot, rpe: Double?) {
        guard let session, set.isCompleted, let moment = set.completedAt else { return }
        let rating = WatchSetRating(sessionID: session.sessionID, setID: set.id, completedAt: moment, rpe: rpe)
        guard rating.isValid else { return }
        let confirmed = mirror.session?.allSets.contains {
            $0.id == set.id && $0.isCompleted && rating.matches($0.completedAt)
        } == true
        ratings.record(rating, confirmed: confirmed)
        send(.rateSet(rating))
    }

    func undoSet(_ set: WatchSetSnapshot) {
        guard let session else { return }
        // Read before the overlay forgets it: the log being taken back is the
        // unconfirmed one if there is one, and otherwise the one the phone
        // confirmed. See `WatchCommand.undoSet`.
        let completion = pending.logs[set.id]?.completedAt ?? set.completedAt
        pending.adopt(session.sessionID)
        ratings.remove(set.id)
        pending.logs.removeValue(forKey: set.id)
        pending.recordUndo(of: set.id, completedAt: completion)
        // Whatever the phone knows about this set's start goes with it — that
        // is what `SetLog.unlog` does over there, and the wrist drawing a clock
        // still running on a set it has just taken back would be the two
        // screens disagreeing about whether the lifter is under a bar.
        pending.starts.removeValue(forKey: set.id)
        pending.cancels.insert(set.id)
        send(.undoSet(id: set.id, completedAt: completion))
    }

    /// Says the set is about to begin. Drawn here immediately and stamped here
    /// too, count-in included — see `pendingStarts`. This is the only place a
    /// wrist start gets one: the phone writes the moment it is sent as it
    /// came, so adding the count anywhere downstream would add it twice.
    func announceStart(_ set: WatchSetSnapshot) {
        guard let session else { return }
        pending.adopt(session.sessionID)
        let moment = SetLeadIn.start(forTapAt: Date())
        pending.cancels.remove(set.id)
        pending.starts[set.id] = moment
        send(.announceStart(id: set.id, at: moment))
    }

    /// Un-says it. A mis-tap on a 41mm screen has to cost nothing at all.
    func cancelStart(_ set: WatchSetSnapshot) {
        guard let session else { return }
        pending.adopt(session.sessionID)
        pending.starts.removeValue(forKey: set.id)
        pending.cancels.insert(set.id)
        send(.cancelStart(id: set.id))
    }

    /// Moves the logger onto another exercise — a superset, or a machine that
    /// was taken when its turn came round. Taken here immediately, confirmed by
    /// the phone.
    func focus(on catalogID: String) {
        guard let session, WatchLoggerRules.allowsFocus(on: catalogID, in: session.exercises) else { return }
        pending.adopt(session.sessionID)
        pending.focus = catalogID
        send(.focusExercise(catalogID: catalogID))
    }

    /// The latest local actions accompany Finish because queued set commands
    /// can arrive after its live message. Built at the tap, so the moment it
    /// carries is when the lifter stopped rather than when the recorder had
    /// finished saving, or the phone finally heard.
    func finishBatch(for sessionID: UUID) -> WatchFinishBatch {
        var batch = pending.finishBatch(for: sessionID, ratings: ratings.entries.values.map(\.rating))
        batch.endedAt = Date()
        return batch
    }

    func requestMirror() { send(.requestMirror) }

    /// Called by Finish and Discard on the wrist before the recorder closes,
    /// so no later mirror, and no relaunch, can hand the session back to it.
    /// The unconfirmed sets are left where they are: they still belong to the
    /// phone's copy of the session, whenever it hears them.
    ///
    /// - Parameter finished: what the idle screen may say about a Finish until
    ///   the phone answers; `nil` for a Discard. See `WatchIdleRules`.
    func markEndedLocally(_ sessionID: UUID, finished: WatchWristFinish? = nil) {
        endedLocally.mark(sessionID, finished: finished)
    }

    /// A session finished on this wrist that the phone has not answered for.
    var finishedHere: WatchWristFinish? { endedLocally.finished }

    /// Whether the recorder may run, or report, a Health workout for this
    /// session.
    func admitsRecording(of sessionID: UUID) -> Bool {
        endedLocally.admits(sessionID)
    }

    // MARK: - Receiving

    private func receive(_ payload: [String: Any], fromCache: Bool = false) {
        guard let incoming = WatchMirror.fromWatchPayload(payload, key: WatchLink.mirrorKey) else { return }
        // Application context and live messages race; see `accepts` for why the
        // phone's timestamp orders them.
        guard WatchMirrorReconciliation.accepts(incoming, over: mirror) else { return }
        mirror = incoming
        if let session = incoming.session { lastMirroredSession = session }
        endedLocally.settle(with: incoming, fromCache: fromCache)
        if !fromCache { waitingForFreshMirror = false }
        hasEverReceivedMirror = true
        // A cached context may predate a queued command. It is useful for
        // drawing offline, but cannot acknowledge or erase persisted work.
        if WatchMirrorReconciliation.mayReconcile(fromCache: fromCache) { reconcile(with: incoming.session) }
    }

    /// Drops the optimistic overlay for anything the phone has now agreed with.
    /// The rules are `WatchMirrorReconciliation`'s; this carries out its answer.
    private func reconcile(with session: WatchSessionSnapshot?) {
        let outcome = WatchMirrorReconciliation.reconcile(pending: pending, ratings: ratings, with: session)
        ratings = outcome.ratings
        pending = outcome.pending
        for rating in outcome.resend { send(.rateSet(rating)) }
    }
}

/// Hands a WatchConnectivity delegate callback to the main actor in the order
/// it arrived.
///
/// The callbacks come in on the session's own queue, and a `Task` per callback
/// promises no order between two of them: a live message and the queued one
/// behind it could apply the wrong way round, so the mirror ordering guard saw
/// the newer one first and dropped the older, or a wrist log landed after the
/// Finish that closed its session. The main queue runs its blocks in the order
/// they were submitted.
private func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
}

// MARK: - WCSessionDelegate

extension WatchConnector: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        // Read on the session's queue, where the callback is, so the hop
        // carries what the callback announced.
        let reachable = session.isReachable
        let context = WatchDelivered(session.receivedApplicationContext)
        onMain {
            self.isReachable = reachable
            // Whatever arrived while the app was closed is waiting in the
            // application context. If the phone is reachable, wait for its
            // current reply before letting that cached context start Health.
            if let cached = WatchMirror.fromWatchPayload(context.value, key: WatchLink.mirrorKey),
               cached.sentAt >= self.mirror.sentAt {
                self.waitingForFreshMirror = reachable
                self.receive(context.value, fromCache: true)
            }
            if state == .activated {
                for entry in self.ratings.entries.values { self.send(.rateSet(entry.rating)) }
                self.requestMirror()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        onMain {
            self.isReachable = reachable
            if !reachable { self.waitingForFreshMirror = false }
            if reachable { self.requestMirror() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let delivered = WatchDelivered(context)
        onMain { self.receive(delivered.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let delivered = WatchDelivered(message)
        onMain { self.receive(delivered.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let delivered = WatchDelivered(userInfo)
        onMain { self.receive(delivered.value) }
    }
}
