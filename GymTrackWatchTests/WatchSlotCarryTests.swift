import Foundation
import Testing
@testable import GymTrackWatch

/// The wrist's guess at the phone's answer to a set it logged, for a day that
/// holds one exercise twice: heavy sets, then lighter back-off sets. The phone
/// stops carrying a load where the plan slot ends; the wrist has to as well,
/// or the back-off prefills it shows are the heavy weight and the next log
/// sends that weight to the phone.
@MainActor @Suite(.serialized)
struct WatchSlotCarryTests {

    private let t0 = WatchTestClock.reference

    /// Two heavy rows (80 kg) then two back-off rows (60 kg), as the plan
    /// prefilled them. The rep ranges are the caller's: distinct, or equal.
    private func twoSlots(heavy: ClosedRange<Int>, backOff: ClosedRange<Int>,
                          named: Bool = true) -> (WatchExerciseSnapshot, [UUID]) {
        let ids = (0..<4).map { _ in UUID() }
        let sets = ids.enumerated().map { position, id -> WatchSetSnapshot in
            var set = watchSet(id, index: position, weightKg: position < 2 ? 80 : 60,
                               slot: named ? (position < 2 ? 0 : 1) : nil)
            let range = position < 2 ? heavy : backOff
            set.targetRepsLow = range.lowerBound
            set.targetRepsHigh = range.upperBound
            return set
        }
        return (watchExercise("bench", sets: sets), ids)
    }

    private func fold(_ exercise: WatchExerciseSnapshot, logging id: UUID,
                      at weightKg: Double) -> WatchExerciseSnapshot {
        var pending = WatchPendingActions()
        pending.logs[id] = watchLog(id, at: t0, weightKg: weightKg)
        return WatchConnector.folding(exercise, pending: pending, ratings: WatchRatingOutbox())
    }

    @Test(arguments: [(3...5, 8...10), (5...5, 5...5)])
    func aHeavyLogStopsAtTheEndOfItsSlot(heavy: ClosedRange<Int>, backOff: ClosedRange<Int>) {
        let (exercise, ids) = twoSlots(heavy: heavy, backOff: backOff)
        let folded = fold(exercise, logging: ids[0], at: 85)
        #expect(folded.sets.map(\.weightKg) == [85, 85, 60, 60],
                "the second heavy set takes the new load; the back-off sets keep what the plan prefilled")
    }

    @Test(arguments: [(3...5, 8...10), (5...5, 5...5)])
    func aBackOffLogCarriesWithinItsOwnSlot(heavy: ClosedRange<Int>, backOff: ClosedRange<Int>) {
        let (exercise, ids) = twoSlots(heavy: heavy, backOff: backOff)
        let folded = fold(exercise, logging: ids[2], at: 55)
        #expect(folded.sets.map(\.weightKg) == [80, 80, 55, 55])
    }

    @Test func aMirrorThatNamesNoSlotsCarriesToTheEndOfTheExerciseAsBefore() {
        let (exercise, ids) = twoSlots(heavy: 5...5, backOff: 5...5, named: false)
        let folded = fold(exercise, logging: ids[0], at: 85)
        #expect(folded.sets.map(\.weightKg) == [85, 85, 85, 85])
    }

    @Test func aDropKeepsItsOwnWeightAndTheSlotBoundaryStillHolds() {
        var (exercise, ids) = twoSlots(heavy: 5...5, backOff: 5...5)
        exercise.sets[1] = watchSet(ids[1], index: 1, weightKg: 70, continuation: true, slot: 0)
        let folded = fold(exercise, logging: ids[0], at: 85)
        #expect(folded.sets.map(\.weightKg) == [85, 70, 60, 60])
    }

    @Test func theSlotFieldIsOptionalOnTheWire() throws {
        let set = watchSet(slot: 1)
        let encoded = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(WatchSetSnapshot.self, from: encoded).slot == 1)

        let bare = try JSONEncoder().encode(watchSet())
        let keys = try #require(JSONSerialization.jsonObject(with: bare) as? [String: Any]).keys
        #expect(!keys.contains("slot"), "a row with no slot stores no key")
        #expect(try JSONDecoder().decode(WatchSetSnapshot.self, from: bare).slot == nil)
    }
}
