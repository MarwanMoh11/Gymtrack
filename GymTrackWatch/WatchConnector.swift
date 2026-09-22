import Foundation
import WatchConnectivity
import os

/// The watch's end of the link.
///
/// The watch keeps no database. It draws the last mirror the phone sent and
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

    /// What a set was logged with while the phone hasn't answered yet.
    private struct PendingLog: Hashable {
        var weightKg: Double
        var reps: Int
        var seconds: Int
    }

    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack.watchkitapp", category: "Connector")

    private override init() { super.init() }

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
        guard !pendingCompletions.isEmpty || !pendingUndos.isEmpty else { return session }

        session.exercises = session.exercises.map(folding)
        // The current set moves on as soon as the last one is logged, rather
        // than when the phone says so.
        if let next = session.exercises.first(where: { !$0.isComplete })?.sets.first(where: { !$0.isCompleted }) {
            session.currentSetID = next.id
        } else {
            session.currentSetID = nil
        }
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
                if exercise.tracking == .duration { set.seconds = pending.seconds }
            }
            if pendingUndos.contains(set.id) { set.isCompleted = false }
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

    /// True while there's something the phone hasn't acknowledged.
    var hasUnsyncedWork: Bool { !pendingCompletions.isEmpty || !pendingUndos.isEmpty }

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
    func logSet(_ set: WatchSetSnapshot, weightKg: Double, reps: Int, seconds: Int) {
        pendingUndos.remove(set.id)
        pendingCompletions[set.id] = PendingLog(weightKg: weightKg, reps: reps, seconds: seconds)
        send(.logSet(id: set.id, weightKg: weightKg, reps: reps, seconds: seconds))
    }

    func undoSet(_ set: WatchSetSnapshot) {
        pendingCompletions.removeValue(forKey: set.id)
        pendingUndos.insert(set.id)
        send(.undoSet(id: set.id))
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
            pendingCompletions.removeAll()
            pendingUndos.removeAll()
            return
        }
        let sets = Dictionary(session.allSets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        pendingCompletions = pendingCompletions.filter { sets[$0.key]?.isCompleted == false }
        pendingUndos = pendingUndos.filter { sets[$0]?.isCompleted == true }
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
            if state == .activated { self.requestMirror() }
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
