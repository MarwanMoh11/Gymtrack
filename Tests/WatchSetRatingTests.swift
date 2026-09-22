import Foundation

/// Run with scripts/test-watch-ratings.sh; no simulator or Health access needed.
@main
struct WatchSetRatingTests {
    static func main() throws {
        let moment = Date(timeIntervalSince1970: 1_790_079_000.123456)
        let rating = WatchSetRating(sessionID: UUID(), setID: UUID(), completedAt: moment, rpe: 9)
        precondition(rating.isValid)
        precondition(rating.matches(moment))
        precondition(!rating.matches(nil), "An undone set must reject a late answer")
        precondition(!rating.matches(moment.addingTimeInterval(1)), "A re-log must reject the old answer")

        var invalid = rating
        for value in [0.0, 7, 8.5, 11, .infinity, .nan] {
            invalid.rpe = value
            precondition(!invalid.isValid, "Only the four explicit answers may be recorded")
        }
        for feel in SetFeel.allCases {
            invalid.rpe = feel.rawValue
            precondition(invalid.isValid)
        }
        invalid.rpe = nil
        precondition(invalid.isValid, "Clearing an answer is valid")

        let command = WatchCommand.rateSet(rating)
        let decoded = WatchCommand.fromWatchPayload(command.watchPayload(key: WatchLink.commandKey),
                                                    key: WatchLink.commandKey)
        guard case .rateSet(let roundTrip) = decoded else { fatalError("Rating did not round-trip") }
        precondition(roundTrip.matches(moment), "Wire date precision must not reject an answer")
        precondition(roundTrip.rpe == 9)

        let legacySet = """
        {"id":"\(rating.setID)","index":0,"weightKg":50,"reps":8,"seconds":0,
         "targetRepsLow":6,"targetRepsHigh":10,"isCompleted":true}
        """
        let oldSet = try JSONDecoder().decode(WatchSetSnapshot.self, from: Data(legacySet.utf8))
        precondition(oldSet.rpe == nil && oldSet.completedAt == nil)
        let encodedSet = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldSet)) as! [String: Any]
        precondition(encodedSet["rpe"] == nil, "An unanswered set must omit difficulty")

        let legacyLog = """
        {"logSet":{"id":"\(rating.setID)","weightKg":50,"reps":8,"seconds":0}}
        """
        let oldCommand = try JSONDecoder().decode(WatchCommand.self, from: Data(legacyLog.utf8))
        guard case .logSet(_, _, _, _, let stamp) = oldCommand else { fatalError("Legacy log did not decode") }
        precondition(stamp == nil)

        var session = WatchSessionSnapshot(
            sessionID: rating.sessionID, title: "Test", planName: "", startedAt: moment,
            exercises: [WatchExerciseSnapshot(id: "test", name: "Test", order: 0, tracking: .weightReps,
                                               restSeconds: 60, sets: [oldSet])],
            restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg
        )
        var outbox = WatchRatingOutbox()
        outbox.record(rating)
        session.exercises[0].sets[0].isCompleted = false
        precondition(outbox.reconcile(with: session).isEmpty)
        precondition(outbox.entries.count == 1, "An answer arriving before its log must stay queued")

        // A force-quit while offline must not erase the explicit answer.
        outbox = try JSONDecoder().decode(WatchRatingOutbox.self, from: JSONEncoder().encode(outbox))
        session.exercises[0].sets[0].isCompleted = true
        session.exercises[0].sets[0].completedAt = moment
        precondition(outbox.reconcile(with: session).count == 1, "Confirmed logs release waiting answers")
        precondition(outbox.reconcile(with: session).isEmpty, "Mirrors must not create a resend loop")
        session.exercises[0].sets[0].rpe = 9
        precondition(outbox.reconcile(with: session).isEmpty)
        precondition(outbox.entries.isEmpty, "The echoed answer retires its pending overlay")

        outbox.record(rating)
        session.exercises[0].sets[0].rpe = nil
        _ = outbox.reconcile(with: session)
        session.exercises[0].sets[0].isCompleted = false
        session.exercises[0].sets[0].completedAt = nil
        precondition(outbox.reconcile(with: session).isEmpty)
        precondition(outbox.entries.isEmpty, "A phone undo must retire the pending answer")

        outbox.record(rating, confirmed: true)
        session.exercises[0].sets[0].isCompleted = true
        session.exercises[0].sets[0].completedAt = moment.addingTimeInterval(1)
        precondition(outbox.reconcile(with: session).isEmpty)
        precondition(outbox.entries.isEmpty, "Re-logging must not inherit the previous answer")

        var cleared = rating
        cleared.rpe = nil
        outbox.record(cleared, confirmed: true)
        session.exercises[0].sets[0].completedAt = moment
        session.exercises[0].sets[0].rpe = nil
        _ = outbox.reconcile(with: session)
        precondition(outbox.entries.isEmpty, "Clearing is acknowledged by an absent rating")

        outbox.record(rating)
        outbox.remove(rating.setID)
        precondition(outbox.entries.isEmpty, "A wrist undo must erase its queued answer")
        print("Watch rating validation, identity, wire compatibility and offline outbox checks passed")
    }
}
