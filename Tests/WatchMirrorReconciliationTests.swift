import Foundation

/// Run with scripts/test-watch-mirror-reconciliation.sh; no simulator, Health
/// or WCSession needed.
///
/// `WatchConnector` used to hold these rules inside a WCSession delegate.
/// Here they run against plain values, including the two scenarios the review
/// filed against the link: a phone that comes back with no session (LINK-02),
/// and a wrist that ended a session while the phone was out of range
/// (WATCH-01).
@main
struct WatchMirrorReconciliationTests {

    static let t0 = Date(timeIntervalSince1970: 1_000_000)

    static func main() {
        ordering()
        cacheNeverAcknowledges()
        overlayKeptUntilConfirmed()
        overlayDroppedWhenSettled()
        noSessionClearsOverlayAndResendsRatings()
        otherSessionOverlayIsCleared()
        phoneReturnsWithNoSession()
        wristEndedWhilePhoneAway()
        print("WatchMirrorReconciliationTests passed")
    }

    // MARK: - Ordering

    static func ordering() {
        let held = mirror(nil, at: t0)
        precondition(WatchMirrorReconciliation.accepts(mirror(nil, at: t0.addingTimeInterval(1)), over: held))
        precondition(WatchMirrorReconciliation.accepts(mirror(nil, at: t0), over: held),
                     "The context and the reply for one push carry the same instant")
        precondition(!WatchMirrorReconciliation.accepts(mirror(nil, at: t0.addingTimeInterval(-1)), over: held),
                     "An older mirror arriving second must not drag the screen backwards")
        // The phone's counter starts over on a relaunch; only the timestamp counts.
        var restarted = mirror(nil, at: t0.addingTimeInterval(5))
        restarted.revision = 0
        var running = held
        running.revision = 900
        precondition(WatchMirrorReconciliation.accepts(restarted, over: running))
        precondition(WatchMirrorReconciliation.accepts(mirror(nil, at: t0), over: WatchMirror.placeholder))
    }

    static func cacheNeverAcknowledges() {
        precondition(!WatchMirrorReconciliation.mayReconcile(fromCache: true))
        precondition(WatchMirrorReconciliation.mayReconcile(fromCache: false))
    }

    // MARK: - Reconcile with a session

    static func overlayKeptUntilConfirmed() {
        let a = UUID(), b = UUID()
        let session = snapshot(sets: [set(a), set(b)])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.logs[a] = log(a, at: t0.addingTimeInterval(10))
        pending.starts[b] = t0.addingTimeInterval(20)
        pending.focus = "squat"

        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(out.pending.logs[a] != nil, "A log the phone has not shown yet is the only copy the screen has")
        precondition(out.pending.starts[b] != nil)
        precondition(out.pending.focus == "squat", "The phone still shows another exercise")
        precondition(out.pending.sessionID == session.sessionID)
    }

    static func overlayDroppedWhenSettled() {
        let a = UUID(), b = UUID(), c = UUID(), gone = UUID()
        let done = t0.addingTimeInterval(10)
        var session = snapshot(sets: [set(a, completedAt: done), set(b, completedAt: done), set(c)])
        session.preferredExerciseID = "squat"
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.logs[a] = log(a, at: done)
        pending.logs[b] = log(b, at: done.addingTimeInterval(30))
        pending.logs[gone] = log(gone, at: done)
        pending.undos = [a, gone]
        pending.starts[c] = t0
        pending.starts[b] = t0
        pending.cancels = [c]
        pending.focus = "squat"

        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(out.pending.logs[a] == nil, "The phone shows this completion; the overlay is done with it")
        precondition(out.pending.logs[b] != nil,
                     "A fresh log of a row the phone shows completed at another moment is not acknowledged")
        precondition(out.pending.logs[gone] == nil, "A row the phone no longer has is dropped")
        precondition(out.pending.undos == [a], "An undo waits until the set shows completed, and only for sets that exist")
        precondition(out.pending.starts[c] != nil, "The phone has not shown this start yet")
        precondition(out.pending.starts[b] == nil, "A start on a set the phone shows done is never coming")
        precondition(out.pending.cancels.isEmpty, "Nothing to cancel once the phone shows no start")
        precondition(out.pending.focus == nil, "The phone names the same exercise")

        var deleted = session
        deleted.exercises[0].id = "bench"
        var focused = pending
        focused.focus = "squat"
        let gone2 = WatchMirrorReconciliation.reconcile(pending: focused, ratings: WatchRatingOutbox(), with: deleted)
        precondition(gone2.pending.focus == nil, "An exercise that left the session is the phone turning the pick down")
    }

    // MARK: - No session, another session

    static func noSessionClearsOverlayAndResendsRatings() {
        let a = UUID(), sessionID = UUID()
        var pending = WatchPendingActions()
        pending.adopt(sessionID)
        pending.logs[a] = log(a, at: t0)
        pending.focus = "squat"
        var ratings = WatchRatingOutbox()
        let rating = WatchSetRating(sessionID: sessionID, setID: a, completedAt: t0, rpe: nil)
        ratings.record(rating)

        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: ratings, with: nil)
        precondition(out.pending.logs.isEmpty && out.pending.focus == nil && out.pending.sessionID == nil)
        precondition(out.ratings.entries.isEmpty)
        precondition(out.resend == [rating], "Delivery of the rating passes to WatchConnectivity before the outbox goes")
    }

    static func otherSessionOverlayIsCleared() {
        let a = UUID(), old = UUID()
        let session = snapshot(sets: [set(a)])
        var pending = WatchPendingActions()
        pending.adopt(old)
        pending.logs[a] = log(a, at: t0)
        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(out.pending.logs.isEmpty, "The last workout's overlay must not draw sets into this one")
    }

    // MARK: - LINK-02

    /// The phone side no longer says "no session" before it has read its store
    /// (`WatchMirrorState`). Whatever does reach the wrist is ordered by time,
    /// so a stale empty answer cannot undo a newer one.
    static func phoneReturnsWithNoSession() {
        let s = snapshot(sets: [set(UUID())])
        let running = mirror(s, at: t0.addingTimeInterval(60))
        let staleEmpty = mirror(nil, at: t0.addingTimeInterval(30))
        precondition(!WatchMirrorReconciliation.accepts(staleEmpty, over: running),
                     "An empty mirror older than the running one is refused")
        // A genuine ending is newer, is accepted, and only then clears the overlay.
        let ended = mirror(nil, at: t0.addingTimeInterval(90))
        precondition(WatchMirrorReconciliation.accepts(ended, over: running))
    }

    // MARK: - WATCH-01

    /// Finish tapped on the wrist with the phone out of range. A relaunch
    /// brings the cached context back, and a reply to `requestMirror` can
    /// overtake the queued Finish; both still name the session.
    static func wristEndedWhilePhoneAway() {
        let a = UUID()
        let session = snapshot(sets: [set(a)])
        var tombstone = WatchSessionTombstone()
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.logs[a] = log(a, at: t0)

        // The discard decision at the tap: nothing logged is a Discard of the
        // recording, and Health off is one whatever was logged.
        precondition(WatchRecordingRules.discardsOnWristFinish(healthEnabled: true, setsLogged: 0))
        precondition(WatchRecordingRules.discardsOnWristFinish(healthEnabled: false, setsLogged: 5))
        precondition(!WatchRecordingRules.discardsOnWristFinish(healthEnabled: true, setsLogged: 1))

        tombstone.mark(session.sessionID)
        let reply = mirror(session, at: t0.addingTimeInterval(5))
        precondition(WatchMirrorReconciliation.accepts(reply, over: WatchMirror.placeholder))
        tombstone.settle(with: reply, fromCache: false)
        precondition(tombstone.liveSession(in: reply, awaitingFreshMirror: false) == nil,
                     "The reply that overtook Finish must not bring the session back")
        precondition(!tombstone.admits(session.sessionID), "and must not start a second recording")

        // The wrist's own logs are still the phone's to hear, so the mirror
        // that names the session leaves them where they are.
        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(out.pending.logs[a] != nil)
    }

    // MARK: - Builders

    static func set(_ id: UUID, completedAt: Date? = nil) -> WatchSetSnapshot {
        WatchSetSnapshot(id: id, index: 0, weightKg: 60, reps: 5, seconds: 0, targetRepsLow: 5, targetRepsHigh: 5,
                         isCompleted: completedAt != nil, completedAt: completedAt)
    }

    static func log(_ id: UUID, at moment: Date) -> WatchPendingLog {
        WatchPendingLog(setID: id, weightKg: 62.5, reps: 5, seconds: 0, completedAt: moment)
    }

    static func snapshot(sets: [WatchSetSnapshot]) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: UUID(), title: "Push", planName: "", startedAt: t0,
            exercises: [WatchExerciseSnapshot(id: "squat", name: "Squat", order: 0, tracking: .weightReps,
                                              restSeconds: 90, sets: sets)],
            restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg
        )
    }

    static func mirror(_ session: WatchSessionSnapshot?, at sentAt: Date) -> WatchMirror {
        var mirror = WatchMirror.placeholder
        mirror.sentAt = sentAt
        mirror.session = session
        return mirror
    }
}
