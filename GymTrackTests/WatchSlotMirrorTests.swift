import Foundation
import Testing
@testable import GymTrack

/// The mirror names the plan slot of every row, as the phone's own
/// carry-forward counts them, so the wrist can stop a carried load where the
/// phone does. The wrist's side of it is in `WatchSlotCarryTests`.
@MainActor @Suite(.serialized)
struct WatchSlotMirrorTests {

    private func mirrorSlots(heavy: ClosedRange<Int>, backOff: ClosedRange<Int>) throws -> [Int?] {
        var slots: [Int?] = []
        try WorkoutBench.run { bench in
            let (plan, day) = bench.planDay(named: "Day", planName: "Slots", slots: [
                .init(catalogID: WorkoutBench.bench, sets: 2, low: heavy.lowerBound, high: heavy.upperBound, kg: 80),
                .init(catalogID: WorkoutBench.bench, sets: 3, low: backOff.lowerBound, high: backOff.upperBound, kg: 60),
            ])
            let session = SessionFactory.build(day: day, plan: plan, context: bench.context, history: [])
            let mirror = WatchSnapshotFactory.snapshot(for: session, rest: (nil, nil, 0),
                                                       restSeconds: { _ in 90 }, lastTimeLabel: { _ in nil })
            slots = mirror.exercises.flatMap(\.sets).map(\.slot)
        }
        return slots
    }

    @Test func rowsOfTwoSlotsWithDistinctRangesNameTheirSlots() throws {
        #expect(try mirrorSlots(heavy: 4...6, backOff: 10...12) == [0, 0, 1, 1, 1])
    }

    @Test func rowsOfTwoSlotsWithEqualRangesNameTheirSlotsByTheirCount() throws {
        #expect(try mirrorSlots(heavy: 8...8, backOff: 8...8) == [0, 0, 1, 1, 1])
    }

    @Test func aSessionWithNoPlanBehindItIsOneSlotPerExercise() throws {
        try WorkoutBench.run { bench in
            let session = bench.session()
            bench.addRows(WorkoutBench.bench, to: session, count: 3)
            let mirror = WatchSnapshotFactory.snapshot(for: session, rest: (nil, nil, 0),
                                                       restSeconds: { _ in 90 }, lastTimeLabel: { _ in nil })
            #expect(mirror.exercises.flatMap(\.sets).map(\.slot) == [0, 0, 0])
        }
    }

    @Test func aContinuationNamesTheSlotOfTheSetItContinues() throws {
        try WorkoutBench.run { bench in
            let (plan, day) = bench.planDay(named: "Day", planName: "Slots", slots: [
                .init(catalogID: WorkoutBench.bench, sets: 2, low: 4, high: 6, kg: 80),
                .init(catalogID: WorkoutBench.bench, sets: 2, low: 10, high: 12, kg: 60),
            ])
            let session = SessionFactory.build(day: day, plan: plan, context: bench.context, history: [])
            let workout = bench.open(session, history: [])
            let rows = session.exerciseGroups[0].sets
            workout.complete(rows[1], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            workout.continueSet(rows[1])
            let mirror = WatchSnapshotFactory.snapshot(for: session, rest: (nil, nil, 0),
                                                       restSeconds: { _ in 90 }, lastTimeLabel: { _ in nil })
            let sets = mirror.exercises[0].sets
            #expect(sets.map(\.isContinuation) == [false, false, true, false, false])
            #expect(sets.map(\.slot) == [0, 0, 0, 1, 1])
        }
    }
}
