import Foundation
import Testing
@testable import GymTrackWatch

/// The phone's load offer as the wrist draws it between a tap and the phone's
/// reply. Logging one of its rows answers it on the phone, and undoing the set
/// that produced it withdraws it, so neither may leave it drawn over the next
/// set as a question still open.
@MainActor @Suite(.serialized)
struct WatchLoadOfferFoldingTests {

    private let t0 = WatchTestClock.reference

    /// A rated opener and two rows still to come, with the offer over those two.
    private func scene() -> (exercise: WatchExerciseSnapshot, ids: [UUID]) {
        let ids = (0..<3).map { _ in UUID() }
        let sets = ids.enumerated().map { position, id in
            watchSet(id, index: position, weightKg: 25, completedAt: position == 0 ? t0 : nil)
        }
        var exercise = watchExercise("curl", sets: sets)
        exercise.loadOffer = WatchLoadOffer(subjectID: ids[0], fromKg: 25, toKg: 30,
                                            rows: [ids[1], ids[2]], taken: false)
        return (exercise, ids)
    }

    private func fold(_ exercise: WatchExerciseSnapshot, _ pending: WatchPendingActions) -> WatchExerciseSnapshot {
        WatchConnector.folding(exercise, pending: pending, ratings: WatchRatingOutbox())
    }

    @Test func theOfferIsDrawnOverItsRowsAndNoOthers() {
        let (exercise, _) = scene()
        let offer = exercise.loadOffer
        #expect(exercise.sets.map { offer?.covers($0) == true } == [false, true, true])
        #expect(fold(exercise, WatchPendingActions()).loadOffer == offer, "Nothing pending leaves it as the phone sent it")
    }

    @Test(arguments: [false, true])
    func aLogOfOneOfItsRowsTakesItOffTheWrist(taken: Bool) {
        var (exercise, ids) = scene()
        exercise.loadOffer?.taken = taken
        var pending = WatchPendingActions()
        pending.logs[ids[1]] = watchLog(ids[1], at: t0.addingTimeInterval(120), weightKg: 25)

        #expect(fold(exercise, pending).loadOffer == nil)
    }

    @Test func undoingTheSetThatProducedItTakesItOffTheWrist() {
        let (exercise, ids) = scene()
        var pending = WatchPendingActions()
        pending.recordUndo(of: ids[0], completedAt: t0)

        #expect(fold(exercise, pending).loadOffer == nil)
    }
}
