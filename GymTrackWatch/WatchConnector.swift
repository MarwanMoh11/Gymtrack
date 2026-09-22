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

    /// Sets logged here that the phone hasn't confirmed yet, and the numbers
    /// each was logged with. The numbers are kept, not just the fact of the
    /// log, because the phone mirrors the load just used onto the rest of the
    /// exercise — a watch that predicted only the tick would draw the next set
    /// at the weight the lifter had just moved away from.
    private var pendingCompletions: [UUID: PendingLog] = [:]
    private var pendingUndos: Set<UUID> = []
    private static let ratingsKey = "watch.pendingSetRatings"
    private var ratings = WatchRatingOutbox() {
        didSet {
            if let data = try? JSONEncoder().encode(ratings) {
                UserDefaults.standard.set(data, forKey: Self.ratingsKey)
            }
        }
    }
    /// Starts announced here that the phone hasn't confirmed yet, and the
    /// moment each was announced. The moment is kept rather than recomputed
    /// because it is the measurement: out of range the command waits in the
    /// queue, and the clock on the wrist has to count from when the lifter
    /// actually went, not from when the phone finally heard about it.
    private var pendingStarts: [UUID: Date] = [:]
    private var pendingCancels: Set<UUID> = []
    /// An exercise picked here that the phone hasn't confirmed yet, held for
    /// the same reason a logged set is drawn as done straight away: the pick
    /// has to take under the thumb that made it. Out of range the command sits
    /// in the queue for as long as the phone stays in the locker, and until it
    /// lands this is the only record that the lifter moved.
    private var pendingFocus: String?

    /// What a set was logged with while the phone hasn't answered yet.
    private struct PendingLog: Hashable {
        var weightKg: Double
        var reps: Int
        var seconds: Int
        var completedAt: Date
    }

    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack.watchkitapp", category: "Connector")

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.ratingsKey),
           let saved = try? JSONDecoder().decode(WatchRatingOutbox.self, from: data) {
            ratings = saved
        }
    }

    // MARK: - Lifecycle

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - What the UI draws

    /// The mirror's session with this watch's unconfirmed changes folded in.
    var session: WatchSessionSnapshot? {
        guard var session = mirror.session else { return nil }
        // The pick goes on first: everything below asks which exercise the
        // logger is on, and while this is set the answer is this one.
        if let pendingFocus { session.preferredExerciseID = pendingFocus }
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
            if let pending = pendingCompletions[set.id] {
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
            if pendingUndos.contains(set.id) {
                set.isCompleted = false
                set.completedAt = nil
                set.rpe = nil
            }
            if let started = pendingStarts[set.id] { set.startedAt = started }
            if pendingCancels.contains(set.id) { set.startedAt = nil }
            return set
        }
        // A continuation carries nothing forward: its weight was chosen to be
        // lower, for that row, and pushing it down the card would leave the
        // working sets still to come sitting at the drop weight.
        for logged in exercise.sets where pendingCompletions[logged.id] != nil && !logged.isContinuation {
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
        !pendingCompletions.isEmpty || !pendingUndos.isEmpty || !ratings.entries.isEmpty
    }

    /// Whether anything at all here still has to be drawn over the mirror.
    private var hasPendingChanges: Bool {
        hasUnsyncedWork || pendingFocus != nil || !pendingStarts.isEmpty || !pendingCancels.isEmpty
    }

    // MARK: - Sending

    func send(_ command: WatchCommand) {
        let payload = command.watchPayload(key: WatchLink.commandKey)
        guard !payload.isEmpty, WCSession.isSupported() else { return }
        let session = WCSession.default

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                // Reachability can lapse between the check and the send, so a
                // failed message is re-queued rather than dropped.
                self?.log.debug("Message failed, queueing: \(error.localizedDescription, privacy: .public)")
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
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
        pendingUndos.remove(set.id)
        ratings.remove(set.id)
        pendingCompletions[set.id] = PendingLog(weightKg: weightKg, reps: reps, seconds: seconds,
                                               completedAt: moment)
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
        ratings.remove(set.id)
        pendingCompletions.removeValue(forKey: set.id)
        pendingUndos.insert(set.id)
        // Whatever the phone knows about this set's start goes with it — that
        // is what `SetLog.unlog` does over there, and the wrist drawing a clock
        // still running on a set it has just taken back would be the two
        // screens disagreeing about whether the lifter is under a bar.
        pendingStarts.removeValue(forKey: set.id)
        pendingCancels.insert(set.id)
        send(.undoSet(id: set.id))
    }

    /// Says the set is beginning, now. Drawn here immediately and stamped here
    /// too — see `pendingStarts`.
    func announceStart(_ set: WatchSetSnapshot) {
        let moment = Date()
        pendingCancels.remove(set.id)
        pendingStarts[set.id] = moment
        send(.announceStart(id: set.id, at: moment))
    }

    /// Un-says it. A mis-tap on a 41mm screen has to cost nothing at all.
    func cancelStart(_ set: WatchSetSnapshot) {
        pendingStarts.removeValue(forKey: set.id)
        pendingCancels.insert(set.id)
        send(.cancelStart(id: set.id))
    }

    /// Moves the logger onto another exercise — a superset, or a machine that
    /// was taken when its turn came round. Taken here immediately, confirmed by
    /// the phone.
    func focus(on catalogID: String) {
        pendingFocus = catalogID
        send(.focusExercise(catalogID: catalogID))
    }

    func requestMirror() { send(.requestMirror) }

    // MARK: - Receiving

    private func receive(_ payload: [String: Any]) {
        guard let incoming = WatchMirror.fromWatchPayload(payload, key: WatchLink.mirrorKey) else { return }
        // Application context and live messages race; an older mirror arriving
        // second would drag the screen backwards. Ordered by the phone's own
        // timestamp rather than the revision counter, because that counter
        // starts over every time the phone app is relaunched — and a watch app
        // that has been running across that restart would otherwise reject
        // everything the phone says from then on.
        guard incoming.sentAt >= mirror.sentAt else { return }
        mirror = incoming
        hasEverReceivedMirror = true
        reconcile(with: incoming.session)
    }

    /// Drops the optimistic overlay for anything the phone has now agreed with.
    private func reconcile(with session: WatchSessionSnapshot?) {
        guard let session else {
            // The session can end before its final answer is echoed. The phone
            // accepts ratings for finished sessions too, so hand delivery to
            // WatchConnectivity before retiring the local overlay.
            for entry in ratings.entries.values { send(.rateSet(entry.rating)) }
            ratings = WatchRatingOutbox()
            pendingCompletions.removeAll()
            pendingUndos.removeAll()
            pendingStarts.removeAll()
            pendingCancels.removeAll()
            pendingFocus = nil
            return
        }
        let sets = Dictionary(session.allSets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for rating in ratings.reconcile(with: session) { send(.rateSet(rating)) }
        pendingCompletions = pendingCompletions.filter { id, pending in
            guard let set = sets[id] else { return false }
            guard set.isCompleted else { return true }
            guard let moment = set.completedAt else { return false }
            // A mirror of the completion before an undo must not acknowledge
            // a new log of that same row and replace its fresh timestamp.
            return abs(moment.timeIntervalSince(pending.completedAt)) >= 0.001
        }
        pendingUndos = pendingUndos.filter { sets[$0]?.isCompleted == true }
        pendingStarts = pendingStarts.filter { sets[$0.key]?.startedAt == nil }
        pendingCancels = pendingCancels.filter { sets[$0]?.startedAt != nil }
        // The pick is the phone's own once it names the same exercise — or once
        // that exercise is no longer in the session, which is the one way the
        // phone turns a pick down. Without the second half the watch would go
        // on insisting on an exercise that had been deleted underneath it.
        if let pending = pendingFocus,
           pending == session.preferredExerciseID || !session.exercises.contains(where: { $0.id == pending }) {
            pendingFocus = nil
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnector: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            // Whatever arrived while the app was closed is waiting in the
            // application context.
            if !session.receivedApplicationContext.isEmpty {
                self.receive(session.receivedApplicationContext)
            }
            if state == .activated {
                for entry in self.ratings.entries.values { self.send(.rateSet(entry.rating)) }
                self.requestMirror()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable { self.requestMirror() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.receive(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.receive(userInfo) }
    }
}
