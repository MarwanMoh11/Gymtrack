import Foundation

/// What the wrist does with a mirror from the phone, apart from drawing it.
///
/// These lived in `WatchConnector`, a `WCSession` delegate, so nothing short of
/// two paired simulators could ask whether a stale mirror was refused or a
/// wrist log was kept. They are pure over their inputs now, and the connector
/// only carries the answers out.
enum WatchMirrorReconciliation {

    /// Whether a mirror replaces the one the watch holds.
    ///
    /// Ordered by the phone's own timestamp, never by the revision counter,
    /// which starts over each time the phone app is relaunched: a watch that
    /// stayed running across that restart would otherwise reject everything the
    /// phone said from then on. Equal is accepted, because the application
    /// context and the live reply for one push carry the same instant.
    ///
    /// The phone keeps a fresh process from sending a mirror with no session
    /// before it has read its store (LINK-02). The guard here is the other half:
    /// whatever does arrive late and older, a newer answer already held is not
    /// walked backwards by it.
    static func accepts(_ incoming: WatchMirror, over held: WatchMirror) -> Bool {
        incoming.sentAt >= held.sentAt
    }

    /// Whether a mirror may retire the wrist's unconfirmed work.
    ///
    /// A cached application context can predate a queued command, so it is
    /// good for drawing offline and for nothing else: acknowledging on it
    /// erased sets the phone had never heard.
    static func mayReconcile(fromCache: Bool) -> Bool { !fromCache }

    /// What reconciling leaves behind.
    struct Outcome {
        var pending: WatchPendingActions
        var ratings: WatchRatingOutbox
        /// Ratings to hand to WatchConnectivity again, because the phone may
        /// have taken the first copy before the set it belongs to.
        var resend: [WatchSetRating]
    }

    /// Drops the optimistic overlay for everything the phone has now agreed
    /// with, and keeps the rest.
    ///
    /// With no session the overlay goes altogether: every command it stands for
    /// was already handed to WatchConnectivity, which keeps its own queue, and
    /// an overlay kept for a session that is gone would draw its sets into the
    /// next one. The ratings are the exception that must be sent again first,
    /// since the phone accepts them for finished sessions too.
    static func reconcile(pending: WatchPendingActions, ratings: WatchRatingOutbox,
                          with session: WatchSessionSnapshot?) -> Outcome {
        var pending = pending
        var ratings = ratings
        guard let session else {
            let resend = ratings.entries.values.map(\.rating)
            return Outcome(pending: WatchPendingActions(), ratings: WatchRatingOutbox(), resend: resend)
        }
        if let pendingID = pending.sessionID, pendingID != session.sessionID {
            pending.clear()
        }
        let sets = Dictionary(session.allSets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let resend = ratings.reconcile(with: session)
        pending.logs = pending.logs.filter { id, logged in
            guard let set = sets[id] else { return false }
            guard set.isCompleted else { return true }
            guard let moment = set.completedAt else { return false }
            // A mirror of the completion before an undo must not acknowledge
            // a new log of that same row and replace its fresh timestamp.
            return abs(moment.timeIntervalSince(logged.completedAt)) >= 0.001
        }
        // An undo is settled once the phone shows the set unlogged, or shows it
        // logged as something other than the completion the undo took back:
        // that is the phone refusing a stale undo (LINK-05), and it will never
        // apply. Kept while the stamped log is still there, since that is an
        // undo that has not arrived. The refused undo's cancel goes with it,
        // so the start of the log it did not touch is not hidden.
        let refused = pending.undos.filter { id in
            guard let set = sets[id], set.isCompleted else { return false }
            return pending.undoWasRefused(id, mirroredCompletion: set.completedAt)
        }
        for id in pending.undos where sets[id]?.isCompleted != true || refused.contains(id) {
            pending.forgetUndo(of: id)
        }
        pending.cancels.subtract(refused)
        // A start is also settled once the phone shows its set as done, unless
        // an undo from here is still on its way. Either it landed first and
        // shows as the set's start, or the set was logged inside the count-in
        // and the phone's answer is that there is none. Waiting on a start
        // that is never coming would hold the overlay, and with it the
        // logger's own guess at the current set, for the rest of the session.
        pending.starts = pending.starts.filter { id, _ in
            guard let set = sets[id] else { return false }
            return set.startedAt == nil && (!set.isCompleted || pending.undos.contains(id))
        }
        pending.cancels = pending.cancels.filter { sets[$0]?.startedAt != nil }
        // The pick is the phone's own once it names the same exercise — or once
        // that exercise is no longer in the session, which is the one way the
        // phone turns a pick down. Without the second half the watch would go
        // on insisting on an exercise that had been deleted underneath it.
        if let focus = pending.focus,
           focus == session.preferredExerciseID || !session.exercises.contains(where: { $0.id == focus }) {
            pending.focus = nil
        }
        return Outcome(pending: pending, ratings: ratings, resend: resend)
    }
}
