import Foundation
import SwiftData
import Testing
@testable import GymTrack

// What this file protects: that the rest on screen belongs to the set that
// started it, and that a start is only kept while it can still describe the
// set it was announced on. An undo, a drop row taken back off, or a move to
// another exercise must not stop a rest that is somebody else's or bring back
// one that is over, and a start left behind must not pair with a log minutes
// later into a set that took as long as the detour (LOG-05, LOG-09, LOG-10).
//
// The same start rules on the wrist's headless path are in
// WatchCommandCenterHeadlessTests; the rules on their own, with no logger, in
// EntityPersistenceTests. The plainer rest and start cases are in
// ActiveWorkoutLoggingTests.

@MainActor @Suite(.serialized)
struct ActiveWorkoutRestAndStartTests {

    /// Three exercises of one set list each: three bench sets and three rows at
    /// 50 kg for exactly ten, then a five-minute hold. Ten reps puts a bench
    /// set's longest believable length at the three-minute floor.
    private struct Day {
        let session: WorkoutSession
        let bench: [SetLog]
        let row: [SetLog]
        let hold: SetLog
        let workout: ActiveWorkout
    }

    private func makeDay(_ testBench: WorkoutBench) throws -> Day {
        let session = testBench.session()
        let bench = testBench.addRows(WorkoutBench.bench, to: session, count: 3, order: 0,
                                      weightKg: 50, reps: 10, low: 10, high: 10)
        let row = testBench.addRows(WorkoutBench.row, to: session, count: 3, order: 1,
                                    weightKg: 50, reps: 10, low: 10, high: 10)
        let hold = try #require(testBench.addRows(WorkoutBench.plank, to: session, count: 1, order: 2,
                                                  weightKg: 0, reps: 0, low: 0, high: 0, tracking: .duration).first)
        hold.seconds = 300
        try testBench.context.save()
        return Day(session: session, bench: bench, row: row, hold: hold, workout: testBench.open(session))
    }

    /// The drop row `continueSet` added.
    private func continuation(in session: WorkoutSession) throws -> SetLog {
        try #require(session.sets.first { $0.isContinuation })
    }

    /// Moments for the tests that don't involve a rest. A rest only starts for
    /// a set logged at a live moment, so the tests about rests use `Date.now`.
    private func at(_ seconds: Double) -> Date { WorkoutBench.t0.addingTimeInterval(seconds) }

    // MARK: - Whose rest an undo stops (LOG-05)

    @Test func undoingAnotherExercisesSetLeavesTheRestRunningExactlyWhereItWas() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            let now = Date.now
            day.workout.complete(day.bench[0], restSeconds: 120, at: now)
            day.workout.complete(day.bench[1], restSeconds: 120, at: now)
            day.workout.complete(day.row[0], restSeconds: 45, at: now)
            let rowRest = try #require(day.workout.restTimer.endsAt)

            day.workout.uncomplete(day.bench[0])
            #expect(!day.bench[0].isCompleted)
            #expect(day.workout.restTimer.endsAt == rowRest)

            // The set whose rest it is stops it.
            day.workout.uncomplete(day.row[0])
            #expect(!day.workout.restTimer.isRunning)
        }
    }

    @Test func undoingAParentStopsTheRestOfTheDropTakenBackWithIt() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            let now = Date.now
            day.workout.complete(day.bench[0], restSeconds: 120, at: now)
            day.workout.continueSet(day.bench[0])
            let drop = try continuation(in: day.session)
            day.workout.complete(drop, restSeconds: 120, at: now.addingTimeInterval(1))
            #expect(day.workout.restTimer.isRunning)

            day.workout.uncomplete(day.bench[0])

            #expect(!drop.isCompleted)
            #expect(!day.bench[0].isCompleted)
            #expect(!day.workout.restTimer.isRunning)
        }
    }

    @Test func undoingAParentLeavesARestThatBeganAfterItsDrop() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            let now = Date.now
            day.workout.complete(day.bench[0], restSeconds: 120, at: now)
            day.workout.continueSet(day.bench[0])
            let drop = try continuation(in: day.session)
            day.workout.complete(drop, restSeconds: 120, at: now.addingTimeInterval(1))
            day.workout.complete(day.row[0], restSeconds: 45, at: now.addingTimeInterval(2))
            let rowRest = try #require(day.workout.restTimer.endsAt)

            day.workout.uncomplete(day.bench[0])

            #expect(!drop.isCompleted)
            #expect(day.workout.restTimer.endsAt == rowRest)
        }
    }

    // MARK: - The rest a drop row stopped (LOG-09)

    @Test func removingAContinuationBringsBackTheRestItStoppedToTheSecond() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            day.workout.complete(day.bench[0], restSeconds: 120, at: .now)
            let before = try #require(day.workout.restTimer.endsAt)
            day.workout.continueSet(day.bench[0])
            #expect(!day.workout.restTimer.isRunning)

            day.workout.removeContinuation(try continuation(in: day.session))

            // The mis-tap costs nothing, the countdown included.
            #expect(day.workout.restTimer.endsAt == before)
            #expect(day.workout.restTimer.totalSeconds == 120)
        }
    }

    @Test func removingAContinuationLeavesARestStartedSince() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            let now = Date.now
            day.workout.complete(day.bench[0], restSeconds: 120, at: now)
            day.workout.continueSet(day.bench[0])
            let drop = try continuation(in: day.session)
            day.workout.complete(day.row[0], restSeconds: 30, at: now.addingTimeInterval(1))
            let newer = try #require(day.workout.restTimer.endsAt)

            day.workout.removeContinuation(drop)

            #expect(day.workout.restTimer.endsAt == newer)
            #expect(day.workout.restTimer.totalSeconds == 30)
        }
    }

    @Test func removingAContinuationRevivesNoRestForASetTakenBack() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            day.workout.complete(day.bench[0], restSeconds: 120, at: .now)
            day.workout.continueSet(day.bench[0])
            let drop = try continuation(in: day.session)
            day.workout.uncomplete(day.bench[0])

            day.workout.removeContinuation(drop)

            #expect(!day.workout.restTimer.isRunning)
        }
    }

    // MARK: - A start left behind (LOG-10, SESS-06)

    @Test func movingToAnotherExerciseAbandonsTheStartAndStayingKeepsIt() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            day.workout.announceStart(day.bench[0], at: at(100))
            #expect(day.bench[0].startedAt == at(100))

            day.workout.focus(on: WorkoutBench.bench)
            #expect(day.bench[0].startedAt == at(100))

            day.workout.focus(on: WorkoutBench.row)
            #expect(day.bench[0].startedAt == nil)
        }
    }

    /// With no focus in between, and a gap short enough for the length bound
    /// to allow.
    @Test func aLogOfAnotherExercisesSetOvertakesAStartAnnouncedBeforeIt() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            day.workout.announceStart(day.bench[0], at: at(100))
            day.workout.complete(day.row[0], restSeconds: nil, at: at(150))
            #expect(day.bench[0].startedAt == nil)

            day.workout.complete(day.bench[0], restSeconds: nil, at: at(200))

            #expect(day.bench[0].startedAt == nil)
            #expect(day.bench[0].timeUnderTension == nil)
        }
    }

    /// The rest an abandoned start cut short belongs to nobody any more, and a
    /// late cancel from the wrist must not put that old countdown back.
    @Test func aLateCancelOfAnAbandonedStartPutsNoRestBack() throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            let now = Date.now
            day.workout.complete(day.row[2], restSeconds: 120, at: now)
            day.workout.announceStart(day.bench[0], at: now.addingTimeInterval(-10))
            #expect(!day.workout.restTimer.isRunning)

            day.workout.focus(on: WorkoutBench.row)
            day.workout.cancelStart(day.bench[0])

            #expect(!day.workout.restTimer.isRunning)
        }
    }

    /// The bound is relative to the set: what ten reps could fill, or twice a
    /// five-minute hold. Over it the start is dropped, not shortened to fit.
    enum Gap: CaseIterable, Sendable {
        case twentyFiveMinutesBeforeTenReps, sevenMinutesBeforeTenReps
        case justUnderThreeMinutesBeforeTenReps, sevenMinutesBeforeAFiveMinuteHold

        var seconds: Double {
            switch self {
            case .twentyFiveMinutesBeforeTenReps: 1_500
            case .sevenMinutesBeforeTenReps, .sevenMinutesBeforeAFiveMinuteHold: 400
            case .justUnderThreeMinutesBeforeTenReps: 170
            }
        }

        var isHold: Bool { self == .sevenMinutesBeforeAFiveMinuteHold }

        var kept: Bool {
            switch self {
            case .twentyFiveMinutesBeforeTenReps, .sevenMinutesBeforeTenReps: false
            case .justUnderThreeMinutesBeforeTenReps, .sevenMinutesBeforeAFiveMinuteHold: true
            }
        }
    }

    @Test(arguments: Gap.allCases)
    func aStartIsKeptOnlyIfTheSetCouldHaveFilledTheGapToItsLog(_ gap: Gap) throws {
        try WorkoutBench.run { testBench in
            let day = try makeDay(testBench)
            let set = gap.isHold ? day.hold : day.bench[0]
            let start = at(100)

            day.workout.announceStart(set, at: start)
            day.workout.complete(set, restSeconds: nil, at: start.addingTimeInterval(gap.seconds))

            #expect(set.isCompleted)
            #expect(set.startedAt == (gap.kept ? start : nil))
            #expect(set.timeUnderTension == (gap.kept ? gap.seconds : nil))
        }
    }
}
