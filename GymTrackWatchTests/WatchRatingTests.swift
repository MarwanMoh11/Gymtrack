import Foundation
import Testing
@testable import GymTrackWatch

/// An effort answer given on the wrist belongs to one completion of one set,
/// and it travels to the phone by a different route from the log it answers,
/// so either can arrive first. These hold the answer to the four words the
/// question offers, to the completion it was given for, and to the outbox that
/// keeps it until the phone echoes it, across a relaunch included.
///
/// How a mirror settles the outbox mid-session is in `WatchSessionStateTests`.
@MainActor @Suite(.serialized)
struct WatchRatingTests {

    private let t0 = WatchTestClock.reference

    /// Every answer the question offers, no answer at all, and numbers that
    /// are none of them: the old strip's 7 and 8.5, out of range, and not a
    /// number.
    static let validity: [(rpe: Double?, valid: Bool)] =
        [(nil, true)]
        + SetFeel.allCases.map { (rpe: Optional($0.rawValue), valid: true) }
        + [0, 7, 8.5, 11, .infinity, .nan].map { (rpe: Optional($0), valid: false) }

    @Test(arguments: WatchRatingTests.validity)
    func onlyTheFourAnswersOrClearingOneAreValid(rpe: Double?, valid: Bool) {
        let rating = WatchSetRating(sessionID: UUID(), setID: UUID(), completedAt: t0, rpe: rpe)
        #expect(rating.isValid == valid)

        // An answer that is not one is never queued, so it never reaches the phone.
        var outbox = WatchRatingOutbox()
        outbox.record(rating)
        #expect(outbox.entries.count == (valid ? 1 : 0))
    }

    @Test func anAnswerMatchesOnlyItsOwnCompletionAndSurvivesTheWire() throws {
        // Finer than the wire's milliseconds, as the wrist's own clock stamps it.
        let moment = t0.addingTimeInterval(0.123456)
        let rating = WatchSetRating(sessionID: UUID(), setID: UUID(), completedAt: moment, rpe: 9)
        #expect(rating.matches(moment))
        #expect(!rating.matches(nil), "an undone set turns a late answer away")
        #expect(!rating.matches(moment.addingTimeInterval(1)), "a re-log turns the old answer away")

        let payload = WatchCommand.rateSet(rating).watchPayload(key: WatchLink.commandKey)
        guard case .rateSet(let back)? = WatchCommand.fromWatchPayload(payload, key: WatchLink.commandKey) else {
            Issue.record("A rating did not survive the wire")
            return
        }
        #expect(back.matches(moment), "the wire's precision must not turn an answer away")
        #expect(back.rpe == 9)

        // Clearing an answer says so by having none: no key, not a null or a zero.
        var cleared = rating
        cleared.rpe = nil
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder.watchLink.encode(cleared)) as? [String: Any])
        #expect(object["rpe"] == nil)
        #expect(object["completedAt"] != nil)
    }

    @Test func theOutboxKeepsAnAnswerAcrossARelaunchUntilThePhoneEchoesIt() throws {
        let session = UUID(), setID = UUID()
        let rating = WatchSetRating(sessionID: session, setID: setID, completedAt: t0, rpe: 9)
        func mirrored(_ set: WatchSetSnapshot) -> WatchSessionSnapshot {
            watchSession(id: session, startedAt: t0.addingTimeInterval(-600), sets: [set])
        }
        func relaunched(_ outbox: WatchRatingOutbox) throws -> WatchRatingOutbox {
            try JSONDecoder().decode(WatchRatingOutbox.self, from: JSONEncoder().encode(outbox))
        }

        var outbox = WatchRatingOutbox()
        outbox.record(rating)
        let beforeTheLog = outbox.reconcile(with: mirrored(watchSet(setID)))
        #expect(beforeTheLog.isEmpty)
        #expect(outbox.entries.count == 1, "an answer that beat its log stays queued")

        // A force-quit while offline must not lose the answer.
        outbox = try relaunched(outbox)
        #expect(outbox.entries[setID]?.rating == rating)
        let released = outbox.reconcile(with: mirrored(watchSet(setID, completedAt: t0)))
        #expect(released == [rating], "the log the phone confirmed releases the answer again")
        let repeated = outbox.reconcile(with: mirrored(watchSet(setID, completedAt: t0)))
        #expect(repeated.isEmpty, "a repeated mirror is not a reason to send again")
        let echoed = outbox.reconcile(with: mirrored(watchSet(setID, completedAt: t0, rpe: 9)))
        #expect(echoed.isEmpty)
        #expect(outbox.entries.isEmpty, "the echoed answer retires it")

        // What the outbox has seen survives a relaunch too, so an undo on the
        // phone after the completion was seen still retires the answer.
        outbox.record(rating, confirmed: true)
        outbox = try relaunched(outbox)
        #expect(outbox.entries[setID]?.sawCompletion == true)
        _ = outbox.reconcile(with: mirrored(watchSet(setID)))
        #expect(outbox.entries.isEmpty)
    }

    @Test func aClearedAnswerIsSettledByNoAnswerAndAWristUndoErasesAQueuedOne() {
        let session = UUID(), setID = UUID()
        let rating = WatchSetRating(sessionID: session, setID: setID, completedAt: t0, rpe: 9)
        var cleared = rating
        cleared.rpe = nil

        var outbox = WatchRatingOutbox()
        outbox.record(cleared, confirmed: true)
        let resent = outbox.reconcile(with: watchSession(id: session, startedAt: t0.addingTimeInterval(-600),
                                                         sets: [watchSet(setID, completedAt: t0)]))
        #expect(resent.isEmpty)
        #expect(outbox.entries.isEmpty, "a set showing no answer is the clearing acknowledged")

        outbox.record(rating)
        outbox.remove(setID)
        #expect(outbox.entries.isEmpty)
    }
}
