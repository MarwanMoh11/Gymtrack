import Foundation

/// Run with scripts/test-watch-wrist-leftovers.sh; no simulator, Health or
/// WCSession needed.
///
/// Three leftovers from the review of the wrist: a stale undo the phone
/// refuses stayed pending (LINK-05), the connector let a finished exercise be
/// focused (LOG-01), and the logger scrolled the effort card off the screen the
/// moment it asked its question (WATCH-14).
@main
struct WatchWristLeftoversTests {

    static let t0 = Date(timeIntervalSince1970: 1_000_000)

    static func main() {
        refusedUndoIsSettledByTheMirror()
        undoStillInFlightIsKept()
        appliedOrGoneUndoIsSettled()
        unstampedUndoKeepsItsOldBehaviour()
        finishAfterRefusalDoesNotCarryTheUndo()
        pendingStateDecodesBothWays()
        finishedExerciseCannotBeFocused()
        effortCardIsNotScrolledAway()
        print("WatchWristLeftoversTests passed")
    }

    // MARK: - LINK-05

    /// The phone re-logged the set at a moment of its own while the wrist's undo
    /// of the earlier log was on its way. It refuses that undo, and the mirror
    /// it pushes shows the set logged as something else. Nothing on the wrist
    /// clears the undo today, so the set stays drawn as undone for good.
    static func refusedUndoIsSettledByTheMirror() {
        let a = UUID()
        let first = t0.addingTimeInterval(10), relog = t0.addingTimeInterval(90)
        let session = snapshot(sets: [set(a, completedAt: relog, startedAt: t0.addingTimeInterval(80))])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.recordUndo(of: a, completedAt: first)
        pending.cancels.insert(a)

        let outcome = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(outcome.pending.undos.isEmpty, "A refused undo must not stay pending")
        precondition(outcome.pending.undoStamps.isEmpty, "Its stamp goes with it")
        precondition(outcome.pending.cancels.isEmpty,
                     "The cancel the undo added would hide the start of the log the phone kept")
    }

    /// A newer mirror that still shows the stamped log is an undo that has not
    /// arrived, and clearing it would draw the set as logged again in between.
    static func undoStillInFlightIsKept() {
        let a = UUID()
        let done = t0.addingTimeInterval(10)
        let session = snapshot(sets: [set(a, completedAt: done)])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.recordUndo(of: a, completedAt: done)
        // The phone's clock reaches the wrist through milliseconds.
        let onTheWire = done.addingTimeInterval(0.0004)
        var echoed = snapshot(sets: [set(a, completedAt: onTheWire)])
        echoed.sessionID = session.sessionID
        for shown in [session, echoed] {
            let outcome = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: shown)
            precondition(outcome.pending.undos == [a])
            precondition(outcome.pending.undoStamps[a] == done)
        }
    }

    static func appliedOrGoneUndoIsSettled() {
        let a = UUID(), b = UUID()
        let done = t0.addingTimeInterval(10)
        var pending = WatchPendingActions()
        let session = snapshot(sets: [set(a), set(b, completedAt: done)])
        pending.adopt(session.sessionID)
        pending.recordUndo(of: a, completedAt: done)
        pending.recordUndo(of: UUID(), completedAt: done)
        var outcome = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(outcome.pending.undos.isEmpty, "Unlogged, or no longer in the session: settled")
        precondition(outcome.pending.undoStamps.isEmpty)
        outcome = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: nil)
        precondition(outcome.pending.undos.isEmpty && outcome.pending.undoStamps.isEmpty)
    }

    /// An undo with no stamp takes back whatever the phone holds, so there is
    /// no refusal to recognise and it waits for the set to show unlogged, as it
    /// always did.
    static func unstampedUndoKeepsItsOldBehaviour() {
        let a = UUID()
        let session = snapshot(sets: [set(a, completedAt: t0.addingTimeInterval(50))])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.recordUndo(of: a, completedAt: nil)
        let outcome = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(outcome.pending.undos == [a])

        var relogged = pending
        relogged.forgetUndo(of: a)
        precondition(relogged.undos.isEmpty && relogged.undoStamps.isEmpty)
    }

    /// The harm the stale undo did: Finish carried it, and the phone applied it
    /// over the re-log it had just protected.
    static func finishAfterRefusalDoesNotCarryTheUndo() {
        let a = UUID()
        let session = snapshot(sets: [set(a, completedAt: t0.addingTimeInterval(90))])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.recordUndo(of: a, completedAt: t0.addingTimeInterval(10))
        precondition(pending.finishBatch(for: session.sessionID, ratings: []).undos == [a])
        let settled = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        precondition(settled.pending.finishBatch(for: session.sessionID, ratings: []).undos.isEmpty)
    }

    /// Old watch with new state and the reverse. State saved before the stamps
    /// existed must still decode, and state saved now must still decode for a
    /// build that has never heard of them.
    static func pendingStateDecodesBothWays() {
        let a = UUID(), session = UUID()
        let stamp = t0.addingTimeInterval(10)

        // A watch that updated mid-workout: the state it saved has no stamps.
        let old = Legacy(sessionID: session, logs: [:], undos: [a], starts: [:], cancels: [a], focus: "squat")
        let saved = try! JSONEncoder().encode(old)
        let revived = try! JSONDecoder().decode(WatchPendingActions.self, from: saved)
        precondition(revived.sessionID == session && revived.undos == [a] && revived.cancels == [a])
        precondition(revived.focus == "squat" && revived.undoStamps.isEmpty)
        precondition(try! JSONDecoder().decode(WatchPendingActions.self, from: Data("{}".utf8)).undos.isEmpty,
                     "Nothing saved is nothing pending, not a failed decode")

        // And the other way: new state read by a build with the old shape.
        var current = WatchPendingActions()
        current.adopt(session)
        current.recordUndo(of: a, completedAt: stamp)
        let written = try! JSONEncoder().encode(current)
        let again = try! JSONDecoder().decode(WatchPendingActions.self, from: written)
        precondition(again.undos == [a] && again.undoStamps[a] == stamp)
        let downgraded = try! JSONDecoder().decode(Legacy.self, from: written)
        precondition(downgraded.undos == [a] && downgraded.sessionID == session)
    }

    /// `WatchPendingActions` as it was before the stamps: what an older build
    /// writes and reads.
    struct Legacy: Codable {
        var sessionID: UUID?
        var logs: [UUID: WatchPendingLog]
        var undos: Set<UUID>
        var starts: [UUID: Date]
        var cancels: Set<UUID>
        var focus: String?
    }

    // MARK: - LOG-01

    static func finishedExerciseCannotBeFocused() {
        let done = exercise("squat", sets: [set(UUID(), completedAt: t0), set(UUID(), completedAt: t0)])
        let open = exercise("bench", sets: [set(UUID(), completedAt: t0), set(UUID())])
        let twin = exercise("row", sets: [set(UUID(), completedAt: t0)])
        let twinOpen = exercise("row", sets: [set(UUID())])
        let all = [done, open, twin, twinOpen]
        precondition(!WatchLoggerRules.allowsFocus(on: "squat", in: all),
                     "A finished exercise is reviewed, never focused")
        precondition(WatchLoggerRules.allowsFocus(on: "bench", in: all))
        precondition(WatchLoggerRules.allowsFocus(on: "row", in: all),
                     "The same exercise twice, one of them still open")
        precondition(WatchLoggerRules.allowsFocus(on: "deadlift", in: all),
                     "Unknown to the mirror: the phone's call")
    }

    // MARK: - WATCH-14

    static func effortCardIsNotScrolledAway() {
        precondition(WatchLoggerRules.scrollsToTop(whenRestBecomes: true, effortCardWaiting: false),
                     "The usual behaviour: a rest begins, the countdown comes into view")
        precondition(!WatchLoggerRules.scrollsToTop(whenRestBecomes: true, effortCardWaiting: true),
                     "The card is waiting below Log set; nothing moves under the thumb")
        precondition(!WatchLoggerRules.scrollsToTop(whenRestBecomes: false, effortCardWaiting: false),
                     "Only on the way in")
        precondition(!WatchLoggerRules.scrollsToTop(whenRestBecomes: false, effortCardWaiting: true))
    }

    // MARK: - Fixtures

    static func set(_ id: UUID, completedAt: Date? = nil, startedAt: Date? = nil) -> WatchSetSnapshot {
        var set = WatchSetSnapshot(id: id, index: 0, weightKg: 60, reps: 5, seconds: 0, targetRepsLow: 5,
                                   targetRepsHigh: 5, isCompleted: completedAt != nil, completedAt: completedAt)
        set.startedAt = startedAt
        return set
    }

    static func exercise(_ id: String, sets: [WatchSetSnapshot]) -> WatchExerciseSnapshot {
        WatchExerciseSnapshot(id: id, name: id, order: 0, tracking: .weightReps, restSeconds: 90, sets: sets)
    }

    static func snapshot(sets: [WatchSetSnapshot]) -> WatchSessionSnapshot {
        WatchSessionSnapshot(sessionID: UUID(), title: "Push", planName: "", startedAt: t0,
                             exercises: [exercise("squat", sets: sets)],
                             restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg)
    }
}
