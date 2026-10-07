import Foundation
import Testing
@testable import GymTrackWatch

/// What the wrist believes about the session, and how it gives that belief up:
/// mirrors that arrive late or out of order, an undo taken on the wrist before
/// the phone has heard it, ratings still in flight, an empty session, and the
/// tombstone that keeps a session the wrist ended from coming back. Beside the
/// main scenarios they pin the edges those skim past: a re-log a millisecond
/// apart, a refused undo that must not hide a start, a stamp that was never
/// sent, and a session that is exactly twelve hours old.
///
/// The tombstone across a relaunch, through `UserDefaults` and the wire, is in
/// the iPhone suite's `WatchLinkWireTests`; the answers themselves are in
/// `WatchRatingTests`.
///
/// Everything here is a value type. `WatchConnector` is a singleton over
/// `UserDefaults.standard` and is deliberately not touched; `WristState` below
/// applies the same three calls its `receive` does, in the same order.
@MainActor @Suite(.serialized)
struct WatchSessionStateTests {

    private let t0 = WatchTestClock.reference

    /// The connector's intake, minus WatchConnectivity: order the mirror by the
    /// phone's clock, and let it retire the wrist's unconfirmed work only if it
    /// is not a cached context.
    private struct WristState {
        var held = WatchMirror.placeholder
        var pending = WatchPendingActions()
        var ratings = WatchRatingOutbox()
        var resent: [WatchSetRating] = []

        mutating func receive(_ mirror: WatchMirror, fromCache: Bool = false) {
            guard WatchMirrorReconciliation.accepts(mirror, over: held) else { return }
            held = mirror
            guard WatchMirrorReconciliation.mayReconcile(fromCache: fromCache) else { return }
            let outcome = WatchMirrorReconciliation.reconcile(pending: pending, ratings: ratings, with: mirror.session)
            pending = outcome.pending
            ratings = outcome.ratings
            resent += outcome.resend
        }
    }

    /// What `WatchConnector.undoSet` does to the overlay before it sends.
    private func wristUndo(_ set: WatchSetSnapshot, in session: WatchSessionSnapshot,
                           pending: inout WatchPendingActions, stamped: Bool = true) {
        let completion = pending.logs[set.id]?.completedAt ?? set.completedAt
        pending.adopt(session.sessionID)
        pending.logs.removeValue(forKey: set.id)
        pending.recordUndo(of: set.id, completedAt: stamped ? completion : nil)
        pending.starts.removeValue(forKey: set.id)
        pending.cancels.insert(set.id)
    }

    // MARK: - Ordering and stale mirrors

    @Test func aMirrorIsOrderedByThePhonesClockAndNeverByItsRevisionCounter() {
        let held = watchMirror(nil, at: t0, revision: 900)
        #expect(WatchMirrorReconciliation.accepts(watchMirror(nil, at: t0.addingTimeInterval(1), revision: 0), over: held),
                "the counter starts over when the phone relaunches")
        #expect(WatchMirrorReconciliation.accepts(watchMirror(nil, at: t0, revision: 0), over: held),
                "the context and the reply for one push carry the same instant")
        #expect(!WatchMirrorReconciliation.accepts(watchMirror(nil, at: t0.addingTimeInterval(-0.001), revision: 901), over: held),
                "a higher revision cannot make an older mirror newer")
        #expect(WatchMirrorReconciliation.accepts(watchMirror(nil, at: .distantPast), over: .placeholder))
        #expect(WatchMirrorReconciliation.accepts(watchMirror(nil, at: t0), over: .placeholder))

        #expect(WatchMirrorReconciliation.mayReconcile(fromCache: false))
        #expect(!WatchMirrorReconciliation.mayReconcile(fromCache: true))
    }

    /// A log made on the wrist stays drawn until a mirror at least as new as
    /// the phone's agreement shows it. A late, older mirror must not undo that
    /// agreement, and a cached one must not claim it.
    @Test func outOfOrderAndCachedMirrorsNeitherRetireNorRestoreTheWristsWork() {
        let a = UUID(), b = UUID()
        let logged = t0.addingTimeInterval(60)
        let id = UUID()
        let before = watchMirror(watchSession(id: id, sets: [watchSet(a), watchSet(b)]), at: t0.addingTimeInterval(10))
        let after = watchMirror(watchSession(id: id, sets: [watchSet(a, completedAt: logged), watchSet(b)]),
                                at: t0.addingTimeInterval(90))

        var wrist = WristState()
        wrist.pending.adopt(id)
        wrist.pending.logs[a] = watchLog(a, at: logged)

        // The cached context arrives first with the phone's newest mirror: it
        // draws, but predates nothing it can vouch for, so the overlay stays.
        wrist.receive(after, fromCache: true)
        #expect(wrist.held.sentAt == after.sentAt)
        #expect(wrist.pending.logs[a] != nil, "a cache is not an acknowledgement")

        // The older live mirror lands after it and is refused whole.
        wrist.receive(before)
        #expect(wrist.held.sentAt == after.sentAt, "the screen must not walk backwards")
        #expect(wrist.pending.logs[a] != nil)

        // The same newest mirror live, once: now the phone has agreed.
        wrist.receive(after)
        #expect(wrist.pending.logs[a] == nil)

        // And an older one after that changes nothing: it cannot bring the set back.
        wrist.receive(before)
        #expect(wrist.held.session?.allSets.first { $0.id == a }?.isCompleted == true)
        #expect(wrist.pending.logs.isEmpty)
    }

    @Test func everythingThePhoneHasNotShownYetIsKeptForTheSessionItBelongsTo() {
        let a = UUID(), b = UUID()
        let session = watchSession(sets: [watchSet(a), watchSet(b)])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.logs[a] = watchLog(a, at: t0.addingTimeInterval(10))
        pending.starts[b] = t0.addingTimeInterval(20)
        pending.focus = "squat"

        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session).pending
        #expect(out.logs[a] != nil, "a log the phone has not shown yet is the only copy the screen has")
        #expect(out.starts[b] != nil)
        #expect(out.focus == "squat", "the phone names no exercise, so the pick is not its answer yet")
        #expect(out.sessionID == session.sessionID)
    }

    /// One mirror that settles some of the wrist's work and not the rest:
    /// each piece goes exactly when the phone shows it, and not before.
    @Test func aMirrorThatShowsSomeOfTheWristsWorkRetiresExactlyThatWork() {
        let a = UUID(), b = UUID(), c = UUID(), gone = UUID()
        let done = t0.addingTimeInterval(10)
        let session = watchSession(exercises: [watchExercise(sets: [
            watchSet(a, completedAt: done), watchSet(b, completedAt: done), watchSet(c)
        ])], preferred: "squat")
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.logs[a] = watchLog(a, at: done)
        pending.logs[b] = watchLog(b, at: done.addingTimeInterval(30))
        pending.logs[gone] = watchLog(gone, at: done)
        // Undos with no stamp, as a build from before stamps saved them.
        pending.undos = [a, gone]
        pending.starts[c] = t0
        pending.starts[b] = t0
        pending.cancels = [c]
        pending.focus = "squat"

        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session).pending
        #expect(out.logs[a] == nil, "the phone shows this completion")
        #expect(out.logs[b] != nil, "a row shown completed at another moment has not shown this log")
        #expect(out.logs[gone] == nil, "a row the phone no longer has is dropped")
        #expect(out.undos == [a], "an undo waits until its set shows completed, and only for a set that exists")
        #expect(out.starts[c] != nil, "the phone has not shown this start yet")
        #expect(out.starts[b] == nil, "a start on a set shown done is never coming")
        #expect(out.cancels.isEmpty, "nothing to cancel once the phone shows no start")
        #expect(out.focus == nil, "the phone names the same exercise")

        var deleted = session
        deleted.exercises[0].id = "bench"
        let refused = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: deleted)
        #expect(refused.pending.focus == nil, "an exercise gone from the session is the phone turning the pick down")
    }

    @Test func aLogIsAcknowledgedOnlyByTheCompletionItMadeNotByAnEarlierOneOfTheSameRow() {
        let acknowledged = UUID(), relogged = UUID(), milliseconds = UUID(), open = UUID()
        let gone = UUID(), unstamped = UUID()
        let moment = t0.addingTimeInterval(120)

        var vague = watchSet(unstamped)
        vague.isCompleted = true
        let session = watchSession(sets: [
            watchSet(acknowledged, completedAt: moment),
            // The phone still shows the completion from before an undo and re-log.
            watchSet(relogged, completedAt: moment.addingTimeInterval(-30)),
            // Wire dates are whole milliseconds: a sub-millisecond difference is the same instant.
            watchSet(milliseconds, completedAt: moment.addingTimeInterval(0.0004)),
            watchSet(open),
            vague
        ])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        for id in [acknowledged, relogged, milliseconds, open, gone, unstamped] {
            pending.logs[id] = watchLog(id, at: moment)
        }

        let kept = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session).pending.logs
        #expect(Set(kept.keys) == [relogged, open],
                "kept: a different completion of the same row, and a set the phone has not logged yet")
        #expect(kept[acknowledged] == nil)
        #expect(kept[milliseconds] == nil)
        #expect(kept[gone] == nil, "a set the phone does not have is not something to keep drawing")
        #expect(kept[unstamped] == nil, "a completion with no moment cannot be matched, so cannot be waited on")
    }

    // MARK: - Undo on the wrist

    @Test func anUndoIsKeptUntilThePhoneShowsTheSetUnloggedOrRefusesIt() {
        let a = UUID()
        let completion = t0.addingTimeInterval(300)
        let started = completion.addingTimeInterval(-40)
        let id = UUID()
        func mirrored(_ set: WatchSetSnapshot) -> WatchSessionSnapshot { watchSession(id: id, sets: [set]) }
        func undone(stamped: Bool = true) -> WatchPendingActions {
            var pending = WatchPendingActions()
            wristUndo(watchSet(a, completedAt: completion, startedAt: started), in: mirrored(watchSet(a)),
                      pending: &pending, stamped: stamped)
            return pending
        }
        func settle(_ pending: WatchPendingActions, against set: WatchSetSnapshot) -> WatchPendingActions {
            WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: mirrored(set)).pending
        }

        // The overlay for a wrist undo: no pending log, an undo with the stamp it answers.
        let fresh = undone()
        #expect(fresh.logs.isEmpty && fresh.undos == [a] && fresh.cancels == [a])
        #expect(fresh.undoStamps[a] == completion)

        // Still showing the very log the undo takes back: it has not arrived yet.
        let waiting = settle(fresh, against: watchSet(a, completedAt: completion, startedAt: started))
        #expect(waiting.undos == [a] && waiting.undoStamps[a] == completion && waiting.cancels == [a])
        let sameMillisecond = settle(fresh, against: watchSet(a, completedAt: completion.addingTimeInterval(0.0004), startedAt: started))
        #expect(sameMillisecond.undos == [a], "a sub-millisecond difference is the same completion")

        // The phone shows the set unlogged: the undo landed, and the cancel has nothing to hide.
        let landed = settle(fresh, against: watchSet(a))
        #expect(landed.undos.isEmpty && landed.undoStamps.isEmpty && landed.cancels.isEmpty)

        // The phone shows a different completion (LINK-05): it refused the undo and will never apply
        // it. The cancel goes too, or the start of the log it did not touch would stay hidden.
        let refused = settle(fresh, against: watchSet(a, completedAt: completion.addingTimeInterval(90), startedAt: started))
        #expect(refused.undos.isEmpty && refused.undoStamps.isEmpty)
        #expect(refused.cancels.isEmpty)

        // An undo sent with no stamp cannot be told apart from one still on its way.
        let blind = undone(stamped: false)
        #expect(blind.undos == [a] && blind.undoStamps.isEmpty)
        #expect(!blind.undoWasRefused(a, mirroredCompletion: completion.addingTimeInterval(90)))
        #expect(settle(blind, against: watchSet(a, completedAt: completion.addingTimeInterval(90))).undos == [a])
    }

    @Test func aFinishCarriesTheUndoSoItCannotBringTheSetBackAndNothingElseFromAnotherSession() {
        let kept = UUID(), undone = UUID()
        let session = watchSession(sets: [watchSet(kept), watchSet(undone, completedAt: t0)])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.logs[kept] = watchLog(kept, at: t0.addingTimeInterval(30))
        pending.logs[undone] = watchLog(undone, at: t0)
        wristUndo(session.allSets[1], in: session, pending: &pending)

        let mine = WatchSetRating(sessionID: session.sessionID, setID: kept, completedAt: t0.addingTimeInterval(30), rpe: 8)
        let foreign = WatchSetRating(sessionID: UUID(), setID: UUID(), completedAt: t0, rpe: 9)

        let batch = pending.finishBatch(for: session.sessionID, ratings: [mine, foreign])
        #expect(batch.logs.map(\.setID) == [kept], "the undone log must not be resurrected by Finish")
        #expect(batch.undos == [undone])
        #expect(batch.ratings == [mine])

        // Asked about a session the overlay was never adopted for: nothing local applies.
        let other = UUID()
        let empty = pending.finishBatch(for: other, ratings: [mine, WatchSetRating(sessionID: other, setID: UUID(), completedAt: t0, rpe: nil)])
        #expect(empty.logs.isEmpty && empty.undos.isEmpty && empty.starts.isEmpty && empty.cancels.isEmpty)
        #expect(empty.ratings.count == 1 && empty.ratings.first?.sessionID == other)
    }

    /// The harm a refused undo did while it stayed pending: Finish carried it,
    /// and the phone applied it over the re-log it had just protected.
    @Test func aFinishAfterThePhoneRefusedAnUndoNoLongerCarriesIt() {
        let a = UUID()
        let session = watchSession(sets: [watchSet(a, completedAt: t0.addingTimeInterval(90))])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.recordUndo(of: a, completedAt: t0.addingTimeInterval(10))
        #expect(pending.finishBatch(for: session.sessionID, ratings: []).undos == [a])

        let settled = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session).pending
        #expect(settled.finishBatch(for: session.sessionID, ratings: []).undos.isEmpty)
    }

    @Test func anUndoOfASetNoLongerThereIsSettledAndSoIsEveryUndoOnceThereIsNoSession() {
        let a = UUID(), b = UUID()
        let done = t0.addingTimeInterval(10)
        let session = watchSession(sets: [watchSet(a), watchSet(b, completedAt: done)])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.recordUndo(of: a, completedAt: done)
        pending.recordUndo(of: UUID(), completedAt: done)

        let shown = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session).pending
        #expect(shown.undos.isEmpty, "unlogged, or no longer in the session: settled either way")
        #expect(shown.undoStamps.isEmpty)
        let none = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: nil).pending
        #expect(none.undos.isEmpty && none.undoStamps.isEmpty)
    }

    @Test func forgettingAnUndoTakesItsStampWithIt() {
        let stamped = UUID(), blind = UUID()
        var pending = WatchPendingActions()
        pending.adopt(UUID())
        pending.recordUndo(of: stamped, completedAt: t0)
        pending.recordUndo(of: blind, completedAt: nil)
        #expect(Set(pending.undoStamps.keys) == [stamped], "an undo with no stamp stores no stamp, not a placeholder")

        pending.forgetUndo(of: stamped)
        pending.forgetUndo(of: blind)
        #expect(pending.undos.isEmpty && pending.undoStamps.isEmpty)
    }

    // MARK: - Starts, picks, other sessions, and nothing at all

    @Test func aStartAndAPickAreSettledByThePhoneAndOtherwiseKept() {
        let started = UUID(), waiting = UUID(), doneFirst = UUID(), undoing = UUID(), missing = UUID()
        let session = watchSession(exercises: [
            watchExercise("squat", order: 0, sets: [
                watchSet(started, startedAt: t0), watchSet(waiting), watchSet(doneFirst, completedAt: t0.addingTimeInterval(5))
            ]),
            watchExercise("bench", order: 1, sets: [watchSet(undoing, completedAt: t0.addingTimeInterval(9))])
        ], preferred: "squat")

        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        for id in [started, waiting, doneFirst, undoing, missing] { pending.starts[id] = t0 }
        pending.recordUndo(of: undoing, completedAt: t0.addingTimeInterval(9))

        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session).pending
        #expect(Set(out.starts.keys) == [waiting, undoing],
                "kept: not shown yet, and a set whose undo is still on its way")
        #expect(out.starts[started] == nil, "the phone shows its start")
        #expect(out.starts[doneFirst] == nil, "logged inside the count-in: that start is never coming")
        #expect(out.starts[missing] == nil)

        func focus(_ picked: String) -> String? {
            var p = WatchPendingActions()
            p.adopt(session.sessionID)
            p.focus = picked
            return WatchMirrorReconciliation.reconcile(pending: p, ratings: WatchRatingOutbox(), with: session).pending.focus
        }
        #expect(focus("squat") == nil, "the phone now names the same exercise")
        #expect(focus("bench") == "bench", "the phone still shows another exercise")
        #expect(focus("deadlift") == nil, "the phone turns a pick down by deleting the exercise")
    }

    @Test func noSessionAnotherSessionAndAnEmptySessionAllLeaveNoOverlayBehind() {
        let a = UUID()
        let rating = WatchSetRating(sessionID: UUID(), setID: a, completedAt: t0, rpe: 8)
        let second = WatchSetRating(sessionID: rating.sessionID, setID: UUID(), completedAt: t0, rpe: nil)
        var ratings = WatchRatingOutbox()
        ratings.record(rating)
        ratings.record(second)

        var pending = WatchPendingActions()
        pending.adopt(rating.sessionID)
        pending.logs[a] = watchLog(a, at: t0)
        pending.recordUndo(of: a, completedAt: t0)
        pending.focus = "squat"

        // The phone says there is no session: the overlay goes, the ratings are sent again first.
        let none = WatchMirrorReconciliation.reconcile(pending: pending, ratings: ratings, with: nil)
        #expect(none.pending.logs.isEmpty && none.pending.undos.isEmpty && none.pending.focus == nil)
        #expect(none.pending.sessionID == nil)
        #expect(none.ratings.entries.isEmpty)
        #expect(Set(none.resend) == [rating, second])

        // A different session: the old overlay must not draw its sets into the new one.
        let other = watchSession(sets: [watchSet(a)])
        let switched = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: other).pending
        #expect(switched.logs.isEmpty && switched.undos.isEmpty && switched.focus == nil)

        // A session with no exercises at all: nothing can match, so nothing is held, and
        // every derived answer is the quiet default rather than a crash.
        let empty = watchSession(id: rating.sessionID, exercises: [])
        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: ratings, with: empty)
        #expect(out.pending.logs.isEmpty && out.pending.focus == nil)
        #expect(out.ratings.entries.isEmpty, "the set each rating belongs to is not in the session")
        #expect(empty.allSets.isEmpty && empty.totalSets == 0 && empty.completedSets == 0)
        #expect(empty.progress == 0)
        #expect(empty.focusedExercise == nil && empty.currentExercise == nil && empty.currentSet == nil)
        #expect(empty.currentSetNumber == 1)
        #expect(empty.upNextName == nil)
        #expect(!empty.isResting)

        // And it still round-trips, so a mirror holding one is not lost on the way over.
        let mirror = watchMirror(empty, at: t0)
        let data = try? JSONEncoder().encode(mirror)
        #expect(data.flatMap { try? JSONDecoder().decode(WatchMirror.self, from: $0) } == mirror)
    }

    // MARK: - Ratings in flight

    @Test func aRatingIsResentOnceWhenItsLogIsFirstSeenAndRetiredWhenEchoed() {
        let a = UUID(), id = UUID()
        let completion = t0.addingTimeInterval(200)
        let rating = WatchSetRating(sessionID: id, setID: a, completedAt: completion, rpe: 8)
        func session(_ set: WatchSetSnapshot) -> WatchSessionSnapshot { watchSession(id: id, startedAt: t0, sets: [set]) }

        var outbox = WatchRatingOutbox()
        outbox.record(WatchSetRating(sessionID: id, setID: UUID(), completedAt: completion, rpe: 7))
        #expect(outbox.entries.isEmpty, "a number that is not one of the four answers is not recorded")
        outbox.record(WatchSetRating(sessionID: id, setID: UUID(), completedAt: completion, rpe: nil))
        #expect(outbox.entries.count == 1, "clearing an answer is a valid message")
        outbox = WatchRatingOutbox()
        outbox.record(rating)

        // The set is logged on the phone but without the answer: it may have beaten the log, so send again.
        var resent = outbox.reconcile(with: session(watchSet(a, completedAt: completion)))
        #expect(resent == [rating])
        #expect(outbox.entries[a]?.sawCompletion == true)
        // Mirrors repeat. They must not turn into a send-and-echo loop.
        resent = outbox.reconcile(with: session(watchSet(a, completedAt: completion)))
        #expect(resent.isEmpty && outbox.entries[a] != nil)

        // The phone echoes the answer: done.
        resent = outbox.reconcile(with: session(watchSet(a, completedAt: completion, rpe: 8)))
        #expect(resent.isEmpty)
        #expect(outbox.entries.isEmpty)
    }

    @Test func aRatingIsDroppedWhenItsCompletionIsGoneAndKeptWhileItsLogIsStillInFlight() {
        let a = UUID(), id = UUID()
        let completion = t0.addingTimeInterval(200)
        let rating = WatchSetRating(sessionID: id, setID: a, completedAt: completion, rpe: 9)
        func session(_ sets: [WatchSetSnapshot], startedAt: Date? = nil) -> WatchSessionSnapshot {
            watchSession(id: id, startedAt: startedAt ?? t0, sets: sets)
        }
        func outbox(confirmed: Bool) -> WatchRatingOutbox {
            var box = WatchRatingOutbox()
            box.record(rating, confirmed: confirmed)
            return box
        }

        // Not seen yet: the log is still on its way, so the answer waits with it.
        var box = outbox(confirmed: false)
        var resent = box.reconcile(with: session([watchSet(a)]))
        #expect(resent.isEmpty && box.entries[a] != nil)
        // Seen, then taken back or replaced by another completion: the answer no longer belongs to anything.
        box = outbox(confirmed: true)
        resent = box.reconcile(with: session([watchSet(a)]))
        #expect(resent.isEmpty && box.entries.isEmpty)
        box = outbox(confirmed: true)
        resent = box.reconcile(with: session([watchSet(a, completedAt: completion.addingTimeInterval(60))]))
        #expect(resent.isEmpty && box.entries.isEmpty)
        // The set is gone from its own session.
        box = outbox(confirmed: false)
        resent = box.reconcile(with: session([watchSet()]))
        #expect(resent.isEmpty && box.entries.isEmpty)

        // An answer for a session that has since been replaced: sent again if the new session began
        // after it was given (the phone accepts ratings for finished sessions), kept if it did not.
        box = outbox(confirmed: false)
        let later = watchSession(startedAt: completion.addingTimeInterval(1), sets: [watchSet()])
        resent = box.reconcile(with: later)
        #expect(resent == [rating] && box.entries.isEmpty)
        box = outbox(confirmed: false)
        let earlier = watchSession(startedAt: completion.addingTimeInterval(-1), sets: [watchSet()])
        resent = box.reconcile(with: earlier)
        #expect(resent.isEmpty && box.entries[a] != nil)
    }

    // MARK: - Persistence

    @Test func theOverlayAndTheTombstoneSurviveARelaunchAndTolerateWhatOlderBuildsSaved() throws {
        let a = UUID(), b = UUID()
        var pending = WatchPendingActions()
        pending.adopt(UUID())
        pending.logs[a] = watchLog(a, at: t0)
        pending.starts[b] = t0.addingTimeInterval(7)
        pending.recordUndo(of: b, completedAt: t0.addingTimeInterval(3))
        pending.cancels.insert(b)
        pending.focus = "bench"

        let data = try JSONEncoder().encode(pending)
        let decoded = try JSONDecoder().decode(WatchPendingActions.self, from: data)
        #expect(decoded.sessionID == pending.sessionID)
        #expect(decoded.logs == pending.logs && decoded.starts == pending.starts)
        #expect(decoded.undos == pending.undos && decoded.undoStamps == pending.undoStamps)
        #expect(decoded.cancels == pending.cancels && decoded.focus == pending.focus)

        // State saved before `undoStamps` existed: the overlay for the sets just logged must survive.
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "undoStamps")
        let old = try JSONDecoder().decode(WatchPendingActions.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.logs == pending.logs && old.undos == pending.undos && old.undoStamps.isEmpty)
        #expect(!old.undoWasRefused(b, mirroredCompletion: t0), "no stamp, no verdict")

        // Nothing saved at all decodes as nothing pending rather than failing the launch.
        let blank = try JSONDecoder().decode(WatchPendingActions.self, from: Data("{}".utf8))
        #expect(blank.sessionID == nil && blank.logs.isEmpty && blank.undos.isEmpty && blank.focus == nil)

        // The tombstone, through a suite of its own.
        let defaults = watchTestDefaults()
        #expect(WatchSessionTombstone(defaults: defaults).sessionID == nil)
        var tombstone = WatchSessionTombstone()
        tombstone.mark(a)
        tombstone.save(to: defaults)
        #expect(WatchSessionTombstone(defaults: defaults).sessionID == a)
        WatchSessionTombstone().save(to: defaults)
        #expect(WatchSessionTombstone(defaults: defaults).sessionID == nil, "an empty tombstone removes the key")
        defaults.set("not a uuid", forKey: WatchSessionTombstone.defaultsKey)
        #expect(WatchSessionTombstone(defaults: defaults).sessionID == nil)
    }

    /// `WatchPendingActions` as a build from before undo stamps writes and reads it.
    private struct LegacyPending: Codable {
        var sessionID: UUID?
        var logs: [UUID: WatchPendingLog]
        var undos: Set<UUID>
        var starts: [UUID: Date]
        var cancels: Set<UUID>
        var focus: String?
    }

    /// A watch that updated mid-workout reads what the old build saved, and a
    /// build that has never heard of stamps still reads what this one saves.
    @Test func theOverlayIsReadAcrossTheBuildThatAddedUndoStampsInBothDirections() throws {
        let a = UUID(), session = UUID()
        let stamp = t0.addingTimeInterval(10)

        let old = LegacyPending(sessionID: session, logs: [:], undos: [a], starts: [:], cancels: [a], focus: "squat")
        let revived = try JSONDecoder().decode(WatchPendingActions.self, from: JSONEncoder().encode(old))
        #expect(revived.sessionID == session && revived.undos == [a] && revived.cancels == [a])
        #expect(revived.focus == "squat" && revived.undoStamps.isEmpty)

        var current = WatchPendingActions()
        current.adopt(session)
        current.recordUndo(of: a, completedAt: stamp)
        let written = try JSONEncoder().encode(current)
        let again = try JSONDecoder().decode(WatchPendingActions.self, from: written)
        #expect(again.undos == [a] && again.undoStamps[a] == stamp)
        let downgraded = try JSONDecoder().decode(LegacyPending.self, from: written)
        #expect(downgraded.undos == [a] && downgraded.sessionID == session)
    }

    // MARK: - The tombstone

    @Test func aSessionTheWristEndedIsNotResurrectedByAStaleOrCachedMirror() {
        let ended = UUID()
        var tombstone = WatchSessionTombstone()
        #expect(tombstone.admits(ended), "nothing ended yet: everything is admitted")
        tombstone.mark(ended)
        #expect(!tombstone.admits(ended) && tombstone.admits(UUID()))

        let old = watchSession(id: ended, startedAt: t0, sets: [watchSet()])
        let now = t0.addingTimeInterval(600)
        #expect(tombstone.liveSession(in: watchMirror(old, at: now), awaitingFreshMirror: false, now: now) == nil)

        // The reply that overtook Finish still names the session, so it settles nothing.
        tombstone.settle(with: watchMirror(old, at: now), fromCache: false)
        #expect(!tombstone.admits(ended))
        // A cached context that no longer names it must not lift the tombstone: it predates the Finish.
        tombstone.settle(with: watchMirror(nil, at: now), fromCache: true)
        tombstone.settle(with: watchMirror(watchSession(sets: [watchSet()]), at: now), fromCache: true)
        #expect(!tombstone.admits(ended))
        // A fresh mirror that has moved on does.
        tombstone.settle(with: watchMirror(nil, at: now), fromCache: false)
        #expect(tombstone.admits(ended) && tombstone.sessionID == nil)

        // Waiting for a fresh mirror, no session, and an empty session.
        let live = watchSession(startedAt: t0, sets: [watchSet()])
        #expect(tombstone.liveSession(in: watchMirror(live, at: now), awaitingFreshMirror: true, now: now) == nil)
        #expect(tombstone.liveSession(in: watchMirror(nil, at: now), awaitingFreshMirror: false, now: now) == nil)
        let empty = watchSession(startedAt: t0, exercises: [])
        #expect(tombstone.liveSession(in: watchMirror(empty, at: now), awaitingFreshMirror: false, now: now) == empty)
    }

    /// Finish tapped on the wrist with the phone out of range, and the reply to
    /// `requestMirror` overtaking the queued Finish. Asked at the reply's own
    /// moment, so the twelve-hour rule cannot be what refuses the session: an
    /// unmarked tombstone shows the same reply as live.
    @Test func aReplyThatOvertookAWristFinishNeitherRevivesTheSessionNorDropsItsLogs() {
        let a = UUID()
        let session = watchSession(startedAt: t0, sets: [watchSet(a)])
        var pending = WatchPendingActions()
        pending.adopt(session.sessionID)
        pending.logs[a] = watchLog(a, at: t0)
        var tombstone = WatchSessionTombstone()
        tombstone.mark(session.sessionID)

        let replyAt = t0.addingTimeInterval(5)
        let reply = watchMirror(session, at: replyAt)
        #expect(WatchMirrorReconciliation.accepts(reply, over: .placeholder))
        tombstone.settle(with: reply, fromCache: false)
        #expect(tombstone.liveSession(in: reply, awaitingFreshMirror: false, now: replyAt) == nil)
        #expect(WatchSessionTombstone().liveSession(in: reply, awaitingFreshMirror: false, now: replyAt) == session)
        #expect(!tombstone.admits(session.sessionID), "and it must not start a second recording")

        // The wrist's own logs are still the phone's to hear, so a mirror that
        // names the session leaves them where they are.
        let out = WatchMirrorReconciliation.reconcile(pending: pending, ratings: WatchRatingOutbox(), with: session)
        #expect(out.pending.logs[a] != nil)
    }

    /// The phone closes a session left open past twelve hours on its next
    /// launch, and its old context can reach the watch first. Judged across a
    /// midnight in Cairo, where "yesterday's session" is the common case.
    @Test func aSessionExactlyTwelveHoursOldIsStaleAndOneSecondYoungerIsLive() {
        let zone = "Africa/Cairo"
        let now = WatchTestClock.at("2026-03-11T00:30:00", in: zone)
        let exactly = WatchTestClock.at("2026-03-10T12:30:00", in: zone)
        let younger = WatchTestClock.at("2026-03-10T12:30:01", in: zone)
        let tombstone = WatchSessionTombstone()
        func live(startedAt: Date) -> WatchSessionSnapshot? {
            let session = watchSession(startedAt: startedAt, sets: [watchSet()])
            return tombstone.liveSession(in: watchMirror(session, at: now), awaitingFreshMirror: false, now: now)
        }
        #expect(GymTrackSnapshot.Running.staleAfter == 12 * 3600)
        #expect(live(startedAt: exactly) == nil)
        #expect(live(startedAt: younger) != nil)
        // A session stamped after the wrist's own clock is not stale either.
        #expect(live(startedAt: now.addingTimeInterval(30)) != nil)
    }
}
