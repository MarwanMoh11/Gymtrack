import Foundation
import Observation
import SwiftData
import Testing
@testable import GymTrack

// What this file protects: what happens to a set while it is being lifted. A
// set is logged once, can be corrected without losing when it happened, and can
// be taken back, and a taken-back set leaves nothing behind, because a
// mis-tap that survives in the export is false detail to whoever reads it.
// The load offer a rating can make follows the same rule: taking it and then
// undoing it, or clearing the rating that produced it, files no decision.
//
// These drive the real `ActiveWorkout` and `RestTimer` in the hosted app. The
// lifecycle (start, resume, finish, discard) is in ActiveWorkoutLifecycleTests,
// and what a number typed into a stepper may become is in StepperEntryTests.

/// Records what the rest timer asked the system to do, so the timer can be run
/// for real without a notification centre behind it.
private final class SpyNotifier: RestNotifying {
    var scheduled: [(seconds: Int, id: String)] = []
    var cancelled: [String] = []
    var permissionAsks = 0

    func schedule(in seconds: Int, id: String) { scheduled.append((seconds, id)) }
    func cancel(id: String) { cancelled.append(id) }
    func requestPermission() { permissionAsks += 1 }
}

private final class ChangeCounter {
    var count = 0
}

/// Counts what an observation scope heard. A class because the `onChange`
/// closure is `@Sendable` and cannot mutate a captured local.
private final class ObservationCounter: @unchecked Sendable {
    var count = 0
}

@MainActor @Suite(.serialized)
struct ActiveWorkoutLoggingTests {
    private let bench = WorkoutBench.bench

    private func at(_ seconds: Double) -> Date { WorkoutBench.t0.addingTimeInterval(seconds) }

    /// Four bench sets at 100 kg, the first lifted at the top of its range and
    /// answered Easy, which is what makes the logger offer a heavier rung for
    /// the three still to do.
    private func easyOpener(_ testBench: WorkoutBench) throws
        -> (rows: [SetLog], workout: ActiveWorkout, offer: ActiveWorkout.LoadNudge) {
        let (_, rows, workout) = testBench.standard()
        rows[0].reps = 10
        workout.complete(rows[0], restSeconds: nil, at: at(60))
        workout.rate(rows[0], feel: .easy)
        let offer = try #require(workout.pendingNudge(for: bench))
        return (rows, workout, offer)
    }

    private func removable(_ testBench: WorkoutBench, _ workout: ActiveWorkout,
                           _ catalogID: String = WorkoutBench.bench) throws -> SetLog? {
        workout.removableSet(in: try testBench.group(workout, catalogID))
    }

    private func canRemoveAdded(_ testBench: WorkoutBench, _ workout: ActiveWorkout) throws -> Bool {
        workout.canRemove(try testBench.group(workout, WorkoutBench.row))
    }

    /// One row written straight onto the models, logged or not, so a test about
    /// what comes after does not lean on how logging or undo got there. A
    /// continuation has no rep range, as `continueSet` makes one.
    @discardableResult
    private func insertRow(_ testBench: WorkoutBench, _ catalogID: String = WorkoutBench.bench,
                           order: Int = 0, index: Int, in session: WorkoutSession,
                           kg: Double = 80, reps: Int = 8, seconds: Int = 0, low: Int = 8, high: Int = 12,
                           tracking: TrackingMode = .weightReps, loggedAt: Date? = nil,
                           continuation: Bool = false) -> SetLog {
        let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: order, setIndex: index,
                         weightKg: kg, reps: reps, seconds: seconds,
                         targetRepsLow: continuation ? 0 : low, targetRepsHigh: continuation ? 0 : high,
                         tracking: tracking)
        if let loggedAt {
            set.isCompleted = true
            set.completedAt = loggedAt
        }
        if continuation { set.continuesPreviousSet = true }
        set.session = session
        testBench.context.insert(set)
        return set
    }

    /// One exercise's rows, top to bottom.
    private func card(_ catalogID: String, of session: WorkoutSession) -> [SetLog] {
        session.sets.filter { $0.catalogID == catalogID }.sorted { $0.setIndex < $1.setIndex }
    }

    /// Whether a row reads as never logged.
    private func isErased(_ set: SetLog) -> Bool {
        !set.isCompleted && set.completedAt == nil && set.rpe == nil && set.startedAt == nil
    }

    /// Bench and row, 3 × 8–10 at 100 and 60 kg, then two 60 s planks, started
    /// from the plan the way the app starts a day.
    private func upperDay(_ testBench: WorkoutBench) -> ActiveWorkout {
        let (plan, day) = testBench.planDay(named: "Upper", planName: "Offers", slots: [
            .init(catalogID: bench, sets: 3, low: 8, high: 10, kg: 100),
            .init(catalogID: WorkoutBench.row, sets: 3, low: 8, high: 10, kg: 60),
        ])
        let plank = PlanItem(catalogID: WorkoutBench.plank, name: WorkoutBench.plank, order: 2,
                             targetSets: 2, targetSeconds: 60)
        plank.trackingRaw = TrackingMode.duration.rawValue
        plank.day = day
        testBench.context.insert(plank)
        return testBench.start(day: day, plan: plan)
    }

    /// The bench opener of `upperDay` cleared the top of its range and felt
    /// easy, so the logger offers the next rung for the two bench sets to come.
    private func upperOpener(_ workout: ActiveWorkout) throws -> (opener: SetLog, offer: ActiveWorkout.LoadNudge) {
        let opener = card(bench, of: workout.session)[0]
        opener.reps = 10
        workout.complete(opener, restSeconds: nil, at: at(60))
        workout.rate(opener, feel: .easy)
        let offer = try #require(workout.pendingNudge(for: bench))
        try #require(offer.setID == opener.id)
        try #require(offer.setCount == 2)
        return (opener, offer)
    }

    // MARK: Logging

    @Test func completeMarksTheSetAndStampsTheMomentItWasGiven() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: nil, at: at(90))

            #expect(rows[0].isCompleted)
            #expect(rows[0].completedAt == at(90))
            #expect(workout.lastLoggedSetID == rows[0].id)
            #expect(workout.completedCount == 1)
            #expect(workout.totalCount == 4)
            #expect(!rows[1].isCompleted && rows[1].completedAt == nil)

            // Written as it happens, so a force-quit costs nothing.
            let stored = try testBench.stored(rows[0])
            #expect(stored.isCompleted)
            #expect(stored.completedAt == at(90))
        }
    }

    @Test func loggingASetTwiceDoesNotCountItTwice() throws {
        try WorkoutBench.run { testBench in
            let (session, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.complete(rows[0], restSeconds: nil, at: at(120))

            #expect(workout.completedCount == 1)
            #expect(session.completedSets.count == 1)
            #expect(session.sets.count == 4)
        }
    }

    @Test func loggingPastThePlannedCountKeepsCountingAndProgressStopsAtOne() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = testBench.addRows(to: session, count: 3)
            let workout = testBench.open(session)
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.complete(rows[1], restSeconds: nil, at: at(120))
            // Set after the first logs, which carry their own load down the card.
            rows[2].weightKg = 105
            rows[2].reps = 9
            workout.complete(rows[2], restSeconds: nil, at: at(180))
            #expect(workout.progress == 1)

            // "Add set" copies the last working set, not the plan's.
            workout.addSet(to: try testBench.group(workout))
            let extra = try #require(session.sets.first { $0.setIndex == 3 })
            #expect(session.sets.count == 4)
            #expect(extra.weightKg == 105 && extra.reps == 9)
            #expect(extra.targetRepsLow == 8 && extra.targetRepsHigh == 10)
            #expect(!extra.isCompleted)
            #expect(workout.progress < 1)

            workout.complete(extra, restSeconds: nil, at: at(300))
            workout.addSet(to: try testBench.group(workout))
            let another = try #require(session.sets.first { $0.setIndex == 4 })
            workout.complete(another, restSeconds: nil, at: at(360))
            #expect(workout.completedCount == 5)
            #expect(workout.totalCount == 5)
            #expect(workout.progress == 1)
        }
    }

    // MARK: The rest

    @Test(arguments: [(given: 120 as Int?, expected: 120), (given: nil as Int?, expected: 75)])
    func loggingStartsARestOfTheSlotsLengthOrTheDefault(given: Int?, expected: Int) throws {
        try WorkoutBench.run { testBench in
            AppSettings.shared.defaultRestSeconds = 75
            let (_, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: given, at: .now)

            #expect(workout.restTimer.isRunning)
            #expect(workout.restTimer.totalSeconds == expected)
        }
    }

    @Test func withAutoStartOffLoggingStartsNoRest() throws {
        try WorkoutBench.run { testBench in
            AppSettings.shared.restTimerAutoStart = false
            let (_, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: 90, at: .now)

            #expect(rows[0].isCompleted)
            #expect(!workout.restTimer.isRunning)
        }
    }

    @Test func aRestIsPickedUpWhereItActuallyIsForASetLoggedEarlier() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            // Logged on the wrist out of range, long since rested through:
            // starting a fresh countdown would put the whole app back to resting.
            workout.complete(rows[0], restSeconds: 90, at: at(60))
            #expect(!workout.restTimer.isRunning)

            workout.complete(rows[1], restSeconds: 90, at: Date.now.addingTimeInterval(-30))
            #expect(workout.restTimer.isRunning)
            #expect(workout.restTimer.totalSeconds == 90)
            let left = workout.restTimer.remaining
            #expect(left > 0 && left <= 60)
        }
    }

    @Test func undoingTheLatestSetStopsItsRestButAnOlderUndoLeavesTheNewerRestAlone() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            let now = Date.now
            workout.complete(rows[0], restSeconds: 60, at: now)
            workout.complete(rows[1], restSeconds: 90, at: now)
            #expect(workout.restTimer.totalSeconds == 90)

            // The countdown running is the second set's, and it keeps running.
            workout.uncomplete(rows[0])
            #expect(workout.restTimer.isRunning)
            #expect(workout.restTimer.totalSeconds == 90)

            workout.uncomplete(rows[1])
            #expect(!workout.restTimer.isRunning)
        }
    }

    // MARK: Taking a set back

    @Test func undoingASetLeavesNoTraceOfTheLogInMemoryOrOnDisk() throws {
        try WorkoutBench.run { testBench in
            // A lighter lift on record is what makes 100 kg a PR to be taken back.
            let before = testBench.finishedSession(startedAt: at(-7 * 86_400), lifts: [(kg: 80, reps: 8)])
            let session = testBench.session()
            let rows = testBench.addRows(to: session, count: 4)
            let workout = testBench.open(session, history: [before])
            let set = rows[0]
            workout.announceStart(set, at: at(30))
            workout.complete(set, restSeconds: nil, at: at(90))
            workout.rate(set, feel: .hard)
            // What a watch would have read through that window, and the offer
            // a rating may have produced; all of it came with the log.
            set.averageHeartRate = 132
            set.maxHeartRate = 151
            set.heartRateWindowRaw = "announced"
            set.detectedStartedAt = at(35)
            set.detectedEndedAt = at(88)
            set.recordLoadNudge(.declined, toKg: 102.5)
            #expect(set.startedAt == at(30))
            #expect(workout.isPR(set))

            workout.uncomplete(set)

            for held in [set, try testBench.stored(set)] {
                #expect(!held.isCompleted)
                #expect(held.completedAt == nil)
                #expect(held.rpe == nil)
                #expect(held.startedAt == nil)
                #expect(held.averageHeartRate == nil && held.maxHeartRate == nil)
                #expect(held.heartRateWindowRaw == nil)
                #expect(held.detectedStartedAt == nil && held.detectedEndedAt == nil)
                #expect(held.loadNudgeOutcomeRaw == nil && held.loadNudgeToKg == nil)
                // The row itself is what it was: only the log is taken back.
                #expect(held.weightKg == 100 && held.reps == 8)
            }
            #expect(!workout.recentPRs.contains(set.id))
            #expect(workout.lastLoggedSetID == nil)
            #expect(workout.completedCount == 0)
        }
    }

    @Test func unlogErasesEverythingTheLogGainedButKeepsWhatTheRowIs() {
        let set = SetLog(catalogID: WorkoutBench.bench, exerciseName: "Bench", exerciseOrder: 0, setIndex: 2,
                         weightKg: 60, reps: 8, targetRepsLow: 6, targetRepsHigh: 8, tracking: .weightReps)
        set.isCompleted = true
        set.completedAt = at(100)
        set.rpe = 9
        set.startedAt = at(60)
        set.averageHeartRate = 120
        set.maxHeartRate = 140
        set.heartRateWindowRaw = "announced"
        set.detectedStartedAt = at(62)
        set.detectedEndedAt = at(98)
        set.recordLoadNudge(.taken, toKg: 62.5)
        set.continuesPreviousSet = true

        set.unlog()

        #expect(!set.isCompleted && set.completedAt == nil)
        #expect(set.rpe == nil && set.startedAt == nil)
        #expect(!set.hasHeartRate && set.heartRateWindowRaw == nil)
        #expect(set.detectedStartedAt == nil && set.detectedEndedAt == nil)
        #expect(set.loadNudgeOutcome == nil && set.loadNudgeToKg == nil)
        // A drop's second row is a continuation whether or not it holds a lift.
        #expect(set.continuesPreviousSet == true)
        #expect(set.setIndex == 2 && set.weightKg == 60 && set.reps == 8)
    }

    @Test func undoingAParentTakesTheLoggedDropBelowItBackToo() throws {
        try WorkoutBench.run { testBench in
            let (session, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.continueSet(rows[0])
            let drop = try #require(session.sets.first { $0.isContinuation })
            workout.complete(drop, restSeconds: nil, at: at(100))
            #expect(workout.completedCount == 1)
            #expect(session.completedSets.count == 2)

            workout.uncomplete(rows[0])

            #expect(!rows[0].isCompleted)
            #expect(!drop.isCompleted && drop.completedAt == nil)
            // Still a continuation: undoing the lift does not promote the row.
            #expect(drop.isContinuation)
        }
    }

    @Test func aRepeatedUndoOfTheParentDoesNotTakeBackADropLoggedSince() throws {
        try WorkoutBench.run { testBench in
            let (session, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.continueSet(rows[0])
            let drop = try #require(session.sets.first { $0.isContinuation })
            workout.complete(drop, restSeconds: nil, at: at(100))
            workout.uncomplete(rows[0])
            #expect(!rows[0].isCompleted && !drop.isCompleted)

            // The rows keep their numbers, so the drop can be lifted again on its
            // own. A second undo of the parent, from a stale button or a message
            // delivered twice, is about a log that is already gone.
            workout.complete(drop, restSeconds: nil, at: at(200))
            workout.uncomplete(rows[0])

            #expect(drop.isCompleted)
            #expect(drop.completedAt == at(200))
        }
    }

    @Test func undoingASetErasesItsDropAndTheRestTheDropStartedButNothingAroundIt() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = (0..<3).map { insertRow(testBench, index: $0, in: session) }
            let workout = testBench.open(session)
            // Live moments, because only a set logged now starts a rest, and the
            // last check is that the undo leaves none running.
            let now = Date.now
            workout.complete(rows[0], restSeconds: nil, at: now.addingTimeInterval(-240))
            workout.complete(rows[1], restSeconds: nil, at: now.addingTimeInterval(-60))
            workout.continueSet(rows[1])
            let drop = try #require(card(bench, of: session).first { $0.isContinuation })
            drop.weightKg = 60
            drop.startedAt = now.addingTimeInterval(-25)
            workout.complete(drop, restSeconds: nil, at: now)
            workout.rate(drop, feel: .allOut)
            try #require(drop.isCompleted && drop.rpe != nil)
            try #require(workout.restTimer.isRunning)

            workout.uncomplete(rows[1])

            // Left logged, the drop would be a lift taken without rest off a set
            // that was never done. Its numbers stay, so logging it again is one
            // tap, and it is no longer the latest lift.
            #expect(isErased(rows[1]) && isErased(drop))
            #expect(drop.weightKg == 60 && drop.reps == 8)
            #expect(workout.lastLoggedSetID == nil)
            #expect(rows[0].isCompleted)
            #expect(!rows[2].isCompleted)
            #expect(!workout.restTimer.isRunning)
        }
    }

    @Test func undoingASetTakesEveryLoggedDropInItsRunButNotTheNextSet() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = (0..<2).map { insertRow(testBench, index: $0, in: session) }
            let workout = testBench.open(session)
            workout.complete(rows[0], restSeconds: nil, at: at(0))
            workout.continueSet(rows[0])
            let first = card(bench, of: session)[1]
            workout.complete(first, restSeconds: nil, at: at(30))
            workout.continueSet(first)
            let second = card(bench, of: session)[2]
            workout.complete(second, restSeconds: nil, at: at(60))
            workout.complete(rows[1], restSeconds: nil, at: at(240))
            // The set, two drops, then the next working set.
            try #require(first.isContinuation && second.isContinuation && rows[1].setIndex == 3)

            workout.uncomplete(rows[0])

            #expect(isErased(rows[0]) && isErased(first) && isErased(second))
            // The next working set is not part of the effort.
            #expect(rows[1].isCompleted)
        }
    }

    @Test func undoingADropTakesTheDropBelowItButNotTheSetItCameOff() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let set = insertRow(testBench, index: 0, in: session)
            let workout = testBench.open(session)
            workout.complete(set, restSeconds: nil, at: at(0))
            workout.continueSet(set)
            let first = card(bench, of: session)[1]
            workout.complete(first, restSeconds: nil, at: at(30))
            workout.continueSet(first)
            let second = card(bench, of: session)[2]
            workout.complete(second, restSeconds: nil, at: at(60))

            workout.uncomplete(first)

            #expect(set.isCompleted)
            #expect(isErased(first) && isErased(second))
        }
    }

    @Test func undoingASetPutsBackTheLoadItCarriedUnlessTheRowWasTypedIntoSince() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = (0..<3).map { insertRow(testBench, index: $0, in: session, kg: 50) }
            let workout = testBench.open(session)
            rows[0].weightKg = 60
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            #expect(rows[1].weightKg == 60 && rows[2].weightKg == 60)

            // Kept, the next row of a set that never happened opens at its
            // weight, as though it had been lifted.
            workout.uncomplete(rows[0])
            #expect(rows[1].weightKg == 50 && rows[2].weightKg == 50)

            // A row the lifter has since typed into is theirs and stays.
            workout.complete(rows[0], restSeconds: nil, at: at(120))
            rows[1].weightKg = 65
            workout.uncomplete(rows[0])
            #expect(rows[1].weightKg == 65 && rows[2].weightKg == 50)
        }
    }

    // MARK: Correcting a set

    @Test func correctChangesTheNumbersButNotWhenOrHowTheSetHappened() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            let set = rows[0]
            workout.announceStart(set, at: at(30))
            workout.complete(set, restSeconds: nil, at: at(90))
            workout.rate(set, feel: .solid)

            workout.correct(set, weightKg: 102.5, reps: 7, seconds: 99)

            #expect(set.weightKg == 102.5 && set.reps == 7)
            #expect(set.completedAt == at(90))
            #expect(set.startedAt == at(30))
            #expect(set.rpe == SetFeel.solid.rawValue)
            // A hold time is written only for a timed set; on a bench press it
            // would be exported as a length nobody timed.
            #expect(set.seconds == 0)

            workout.correct(set, weightKg: -5, reps: -2, seconds: 0)
            #expect(set.weightKg == 0 && set.reps == 0)
            workout.correct(set, weightKg: .nan, reps: 9, seconds: 0)
            #expect(set.weightKg == 0 && set.reps == 0)
        }
    }

    @Test func correctingASetThatWasNeverLoggedChangesNothing() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            workout.correct(rows[0], weightKg: 200, reps: 1, seconds: 0)
            #expect(rows[0].weightKg == 100 && rows[0].reps == 8)
            #expect(!rows[0].isCompleted)
        }
    }

    @Test func aCorrectionKeepsTheSetsPlaceAndRestsAndAsksTheRecordQuestionAgain() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session(startedAt: at(-60))
            let rows = (0..<4).map { insertRow(testBench, index: $0, in: session) }
            let other = insertRow(testBench, WorkoutBench.row, order: 1, index: 0, in: session, kg: 60, reps: 10)
            let workout = testBench.open(session)
            workout.complete(rows[0], restSeconds: nil, at: at(0))
            workout.complete(rows[1], restSeconds: nil, at: at(180))
            // 80 typed, 100 lifted: the set every later one on this exercise has
            // to clear goes into the record 20 kg short.
            let typo = rows[2]
            typo.startedAt = at(320)
            workout.complete(typo, restSeconds: nil, at: at(360))
            typo.rpe = SetFeel.solid.rawValue
            typo.averageHeartRate = 142
            typo.maxHeartRate = 161
            // Logging carries each load down the card, so the heavier set is
            // dialled in just before it is lifted, as it would be on the day.
            rows[3].weightKg = 90
            workout.complete(rows[3], restSeconds: nil, at: at(540))
            workout.complete(other, restSeconds: nil, at: at(1_200))
            // 90 kg beats the 80s logged before it.
            try #require(!workout.isPR(typo) && workout.isPR(rows[3]))

            func liftedOrder() -> [UUID] {
                session.sets.filter(\.isCompleted)
                    .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }.map(\.id)
            }
            let restBefore = session.typicalRestSeconds
            let orderBefore = liftedOrder()

            workout.correct(typo, weightKg: 100, reps: 8, seconds: 45)

            // A correction is not an undo, and not the latest lift.
            #expect(typo.isCompleted)
            #expect(typo.averageHeartRate == 142 && typo.maxHeartRate == 161)
            #expect(workout.lastLoggedSetID == other.id)
            // Every rest either side is untouched, and the set keeps its place.
            #expect(session.typicalRestSeconds == restBefore)
            #expect(liftedOrder() == orderBefore)
            // 100 kg beats everything logged before it, and the 90 after it no
            // longer clears the bar.
            #expect(workout.isPR(typo))
            #expect(!workout.isPR(rows[3]))

            workout.correct(typo, weightKg: 80, reps: 8, seconds: 0)
            #expect(!workout.isPR(typo) && workout.isPR(rows[3]))
        }
    }

    @Test func aTimedSetsCorrectionWritesItsSecondsAndKeepsItsMoment() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let holds = (0..<2).map {
                insertRow(testBench, WorkoutBench.plank, index: $0, in: session, kg: 0, reps: 0, seconds: 60,
                          tracking: .duration)
            }
            let workout = testBench.open(session)
            workout.complete(holds[0], restSeconds: nil, at: at(90))

            workout.correct(holds[0], weightKg: 0, reps: 0, seconds: 75)

            #expect(holds[0].seconds == 75)
            #expect(holds[0].completedAt == at(90))
        }
    }

    @Test func correctingTheNumbersAnOfferWasReadOffWithdrawsItWithoutADecision() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let source = insertRow(testBench, index: 0, in: session, kg: 40, reps: 12, loggedAt: at(0))
            insertRow(testBench, index: 1, in: session, kg: 40)
            insertRow(testBench, index: 2, in: session, kg: 40)
            let workout = testBench.open(session)
            workout.rate(source, feel: .easy)
            // Twelve easy reps at the top of 8–12 offers more weight.
            try #require(workout.pendingNudge(for: bench)?.setID == source.id)

            workout.correct(source, weightKg: 40, reps: 9, seconds: 0)

            #expect(workout.pendingNudge(for: bench) == nil)
            // The answer itself stays, and nobody turned anything down.
            #expect(source.rpe == SetFeel.easy.rawValue)
            #expect(source.loadNudgeOutcome == nil)
        }
    }

    // MARK: Saying a set is starting

    @Test func aStartAnnouncedBeforeTheLogIsKeptAndGivesTheTimeUnderTension() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            workout.announceStart(rows[0], at: at(30))
            workout.complete(rows[0], restSeconds: nil, at: at(70))

            let startedAt = try #require(rows[0].startedAt)
            let completedAt = try #require(rows[0].completedAt)
            #expect(startedAt == at(30))
            #expect(startedAt < completedAt)
            #expect(rows[0].timeUnderTension == 40)
        }
    }

    @Test(arguments: [(afterStart: -1.0, kept: false), (afterStart: 0.0, kept: true),
                      (afterStart: 180.0, kept: true), (afterStart: 181.0, kept: false)])
    func aStartIsKeptOnlyIfALifterCouldHaveFilledTheTimeBetween(afterStart: Double, kept: Bool) throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            workout.announceStart(rows[0], at: at(30))
            #expect(rows[0].startedAt == at(30))

            // 8 reps is a plausible 180 s at most. Logged inside the count-in
            // (before the start) or long after, the pair would describe a set
            // nobody lifted, so the start goes and the log stays.
            workout.complete(rows[0], restSeconds: nil, at: at(30 + afterStart))
            #expect(rows[0].isCompleted)
            #expect((rows[0].startedAt != nil) == kept)
        }
    }

    @Test func announcingStartRefusesLoggedSetsRepeatsAndMomentsFromTheFuture() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()

            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.announceStart(rows[0], at: at(500))
            #expect(rows[0].startedAt == nil)

            workout.announceStart(rows[1], at: at(600))
            workout.announceStart(rows[1], at: at(650))
            #expect(rows[1].startedAt == at(600))

            // Two devices disagreeing about the time is not a moment.
            workout.announceStart(rows[2], at: Date.now.addingTimeInterval(3_600))
            #expect(rows[2].startedAt == nil)
        }
    }

    @Test func aLaterStartOvertakesTheOneBeforeItWhichWasAbandoned() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            workout.announceStart(rows[2], at: at(100))
            workout.announceStart(rows[3], at: at(200))

            #expect(rows[2].startedAt == nil)
            #expect(rows[3].startedAt == at(200))
        }
    }

    @Test func cancellingAStartLeavesNoTraceAndTheSetLogsWithoutOne() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            workout.announceStart(rows[0], at: at(10))
            workout.cancelStart(rows[0])

            #expect(rows[0].startedAt == nil)
            let read1 = try testBench.stored(rows[0]).startedAt
            #expect(read1 == nil)
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            #expect(rows[0].startedAt == nil)
            #expect(rows[0].timeUnderTension == nil)
        }
    }

    @Test func cancellingAStartPutsBackTheRestItCutShortButOnlyForThatSet() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            let now = Date.now
            workout.complete(rows[0], restSeconds: 90, at: now)
            #expect(workout.restTimer.isRunning)

            // Saying you are starting is the end of the rest.
            workout.announceStart(rows[1], at: now.addingTimeInterval(3))
            #expect(!workout.restTimer.isRunning)

            // A different set's cancel has nothing to give back.
            workout.cancelStart(rows[2])
            #expect(!workout.restTimer.isRunning)

            workout.cancelStart(rows[1])
            #expect(workout.restTimer.isRunning)
            #expect(workout.restTimer.totalSeconds == 90)
            #expect(rows[1].startedAt == nil)
        }
    }

    // MARK: How hard it was

    @Test(arguments: [(feel: SetFeel.easy, raw: 6.0), (feel: SetFeel.solid, raw: 8.0),
                      (feel: SetFeel.hard, raw: 9.0), (feel: SetFeel.allOut, raw: 10.0)])
    func ratingStoresTheNumberTheProgressionAlwaysRead(feel: SetFeel, raw: Double) throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: nil, at: at(60))

            workout.rate(rows[0], feel: feel)
            #expect(rows[0].rpe == raw)
            #expect(rows[0].feel == feel)

            // The same answer again is taking it back, so the one gesture does both.
            workout.rate(rows[0], feel: feel)
            #expect(rows[0].rpe == nil)
        }
    }

    @Test(arguments: SetFeel.allCases)
    func aRatingOnAnUnloggedSetIsNotKept(feel: SetFeel) throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            // The screen never offers the question for a set that has not been
            // lifted, and the logger refuses it too: a rating on a row with no
            // lift would be exported with the set it later became. Top of the
            // range, so an Easy here would otherwise offer a heavier rung.
            rows[0].reps = 10
            workout.rate(rows[0], feel: feel)
            #expect(rows[0].rpe == nil)
            #expect(workout.pendingNudge(for: bench) == nil)
            #expect(rows[0].loadNudgeOutcome == nil)
        }
    }

    @Test func clearingTheRatingTakesAwayTheOfferItMade() throws {
        try WorkoutBench.run { testBench in
            let (rows, workout, _) = try easyOpener(testBench)

            workout.clearRating(rows[0])

            #expect(rows[0].rpe == nil)
            #expect(workout.pendingNudge(for: bench) == nil)
            #expect(rows[0].loadNudgeOutcome == nil)
        }
    }

    @Test func clearingTheRatingAlsoTakesBackADeclinedOffer() throws {
        try WorkoutBench.run { testBench in
            let (rows, workout, offer) = try easyOpener(testBench)
            workout.dismissNudge(offer)
            #expect(rows[0].loadNudgeOutcome == .declined)
            #expect(rows[0].loadNudgeToKg == offer.toKg)

            // The decline was an answer to the rating; with the rating gone
            // there was never anything to turn down.
            workout.clearRating(rows[0])

            #expect(rows[0].loadNudgeOutcome == nil)
            #expect(rows[0].loadNudgeToKg == nil)
        }
    }

    // MARK: The load offer

    @Test func takingAnOfferMovesTheSetsToComeAndUndoingItLeavesNoDecision() throws {
        try WorkoutBench.run { testBench in
            let (rows, workout, offer) = try easyOpener(testBench)
            let scale = rows[0].loadScale
            #expect(offer.toKg == scale.step(kg: 100, by: 1))
            #expect(offer.toKg > 100)
            #expect(offer.setCount == 3)
            #expect(offer.feel == .easy)

            workout.apply(offer)
            #expect(rows[1...].allSatisfy { $0.weightKg == offer.toKg })
            #expect(rows[0].weightKg == 100)
            #expect(rows[0].loadNudgeOutcome == .taken)
            #expect(rows[0].loadNudgeToKg == offer.toKg)
            #expect(workout.pendingNudge(for: bench) == nil)
            let taken = try #require(workout.takenNudge(for: bench))

            workout.undoTakenNudge(taken)
            #expect(rows[1...].allSatisfy { $0.weightKg == 100 })
            // Off the record entirely, not filed as a decline: the screen reads
            // as if the button was never pressed, and so must the export.
            #expect(rows[0].loadNudgeOutcome == nil)
            #expect(rows[0].loadNudgeToKg == nil)
            #expect(workout.takenNudge(for: bench) == nil)
            #expect(workout.pendingNudge(for: bench) == offer)

            // A second undo of the same take has nothing left to undo.
            workout.undoTakenNudge(taken)
            #expect(rows[1...].allSatisfy { $0.weightKg == 100 })
            #expect(workout.pendingNudge(for: bench) == offer)
        }
    }

    @Test func aDeclinedOfferIsRecordedOnceAndAStaleTapAddsNothing() throws {
        try WorkoutBench.run { testBench in
            let (rows, workout, offer) = try easyOpener(testBench)

            workout.dismissNudge(offer)
            #expect(rows[0].loadNudgeOutcome == .declined)
            #expect(workout.pendingNudge(for: bench) == nil)

            // The rating is cleared, which withdraws the decline with it. A
            // second tap on the cross that was still on screen finds the offer
            // gone and must not file the refusal again.
            workout.clearRating(rows[0])
            workout.dismissNudge(offer)
            #expect(rows[0].loadNudgeOutcome == nil)
            #expect(rows[0].loadNudgeToKg == nil)
        }
    }

    @Test func onlyTheOffersOwnNextWorkingSetAnswersIt() throws {
        try WorkoutBench.run { testBench in
            let workout = upperDay(testBench)
            let (opener, offer) = try upperOpener(workout)

            // A superset partner's set says nothing about what the bench should
            // weigh, and filing a decline for it would be a refusal nobody made.
            workout.complete(card(WorkoutBench.row, of: workout.session)[0], restSeconds: nil, at: at(120))
            #expect(opener.loadNudgeOutcome == nil)
            #expect(workout.pendingNudge(for: bench)?.setID == opener.id)

            // Nor does a drop row of the bench itself.
            workout.continueSet(opener)
            let drop = card(bench, of: workout.session)[1]
            #expect(drop.isContinuation)
            drop.weightKg = 80
            workout.complete(drop, restSeconds: nil, at: at(150))
            #expect(opener.loadNudgeOutcome == nil)
            #expect(workout.pendingNudge(for: bench)?.setID == opener.id)

            // The next working set, at the weight that stood, is a decline.
            let next = card(bench, of: workout.session)[2]
            #expect(!next.isContinuation && next.weightKg == 100)
            workout.complete(next, restSeconds: nil, at: at(300))
            #expect(opener.loadNudgeOutcome == .declined)
            #expect(opener.loadNudgeToKg == offer.toKg)
            #expect(workout.pendingNudge(for: bench) == nil)
        }
    }

    @Test func aLiftDialledToTheOfferedRungByHandTookTheOffer() throws {
        try WorkoutBench.run { testBench in
            let workout = upperDay(testBench)
            let (opener, offer) = try upperOpener(workout)
            let second = card(bench, of: workout.session)[1]
            // Typed in pounds and converted back, as a lifter on a pound-marked
            // bench would dial it: the same rung, not necessarily the same bits.
            second.weightKg = WeightUnit.lb.toKg(WeightUnit.lb.fromKg(offer.toKg))
            workout.complete(second, restSeconds: nil, at: at(240))

            #expect(opener.loadNudgeOutcome == .taken)
            #expect(opener.loadNudgeToKg == offer.toKg)
            #expect(workout.pendingNudge(for: bench) == nil)
        }
    }

    @Test(arguments: [false, true])
    func undoingTheSetThatAnsweredAnOfferStandsItBackUpUnanswered(takesTheRung: Bool) throws {
        try WorkoutBench.run { testBench in
            let workout = upperDay(testBench)
            let (opener, offer) = try upperOpener(workout)
            let second = card(bench, of: workout.session)[1]
            if takesTheRung { second.weightKg = offer.toKg }
            workout.complete(second, restSeconds: nil, at: at(240))
            try #require(opener.loadNudgeOutcome != nil)

            workout.uncomplete(second)

            #expect(opener.loadNudgeOutcome == nil && opener.loadNudgeToKg == nil)
            #expect(workout.pendingNudge(for: bench) == offer)
        }
    }

    @Test func aTakenOffersUndoLastsUntilAMovedSetIsLiftedAndComesBackWithItsUndo() throws {
        try WorkoutBench.run { testBench in
            let workout = upperDay(testBench)
            let (opener, offer) = try upperOpener(workout)
            workout.apply(offer)
            try #require(workout.takenNudge(for: bench) != nil && opener.loadNudgeOutcome == .taken)

            workout.complete(card(WorkoutBench.row, of: workout.session)[0], restSeconds: nil, at: at(120))
            // Another exercise's set leaves the undo open.
            #expect(workout.takenNudge(for: bench) != nil)

            // Lifting a moved set closes it: undoing the take after that would
            // move a weight off a finished set.
            let second = card(bench, of: workout.session)[1]
            #expect(second.weightKg == opener.loadNudgeToKg)
            workout.complete(second, restSeconds: nil, at: at(240))
            #expect(workout.takenNudge(for: bench) == nil)
            #expect(opener.loadNudgeOutcome == .taken)

            // Undoing that set opens it again, and the take's undo puts back
            // every weight, the set logged and undone included.
            workout.uncomplete(second)
            let reopened = try #require(workout.takenNudge(for: bench))
            workout.undoTakenNudge(reopened)
            #expect(card(bench, of: workout.session)[1...].allSatisfy { $0.weightKg == 100 })
            #expect(opener.loadNudgeOutcome == nil)
            #expect(workout.pendingNudge(for: bench)?.setID == opener.id)
        }
    }

    @Test func aSupersetPartnersRatingLeavesTheOtherOfferAndItsUndoStanding() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session(title: "Superset")
            let first = (0..<3).map { insertRow(testBench, index: $0, in: session, kg: 40, reps: $0 == 0 ? 12 : 8) }
            let partner = (0..<3).map {
                insertRow(testBench, WorkoutBench.row, order: 1, index: $0, in: session, kg: 40, reps: $0 == 0 ? 12 : 8)
            }
            let workout = testBench.open(session)
            workout.complete(first[0], restSeconds: nil, at: at(60))
            workout.rate(first[0], feel: .easy)
            workout.complete(partner[0], restSeconds: nil, at: at(90))
            workout.rate(partner[0], feel: .easy)

            // Rating the partner used to overwrite the offer standing on the
            // other card.
            let offerA = try #require(workout.pendingNudge(for: bench))
            let offerB = try #require(workout.pendingNudge(for: WorkoutBench.row))
            workout.apply(offerA)
            workout.apply(offerB)
            // And the second take used to cost the first its undo.
            let takenA = try #require(workout.takenNudge(for: bench))
            #expect(workout.takenNudge(for: WorkoutBench.row) != nil)

            workout.undoTakenNudge(takenA)
            #expect(first[1].weightKg == 40 && partner[1].weightKg == offerB.toKg)
            #expect(workout.pendingNudge(for: bench) != nil)
            #expect(workout.pendingNudge(for: WorkoutBench.row) == nil)

            // Re-rating the same exercise still replaces its own offer.
            workout.rate(first[0], feel: .solid)
            #expect(workout.pendingNudge(for: bench) == nil)
        }
    }

    @Test func aMovementTheDayRepeatsReadsAndOffersPerSlot() throws {
        try WorkoutBench.run { testBench in
            // A top pair and a back-off three of one movement, last done as three
            // heavy sets and two back-offs, so the slots' histories differ in size.
            let (plan, day) = testBench.planDay(named: "Day", planName: "Slots", slots: [
                .init(catalogID: bench, sets: 2, low: 6, high: 6, kg: 60),
                .init(catalogID: bench, sets: 3, low: 10, high: 10, kg: 40),
            ])
            let past = testBench.session(title: "Last week", startedAt: at(-7 * 86_400))
            past.endedAt = past.startedAt.addingTimeInterval(3_600)
            let lastWeek: [(kg: Double, reps: Int)] = [(60, 6), (60, 6), (60, 6), (40, 10), (45, 10)]
            for (index, lift) in lastWeek.enumerated() {
                insertRow(testBench, index: index, in: past, kg: lift.kg, reps: lift.reps, low: lift.reps,
                          high: lift.reps, loggedAt: past.startedAt.addingTimeInterval(Double(index + 1) * 120))
            }
            let session = SessionFactory.build(day: day, plan: plan, context: testBench.context, history: [past])
            let workout = testBench.open(session, history: [past])
            let rows = session.exerciseGroups[0].sets
            try #require(rows.count == 5)
            let (top0, top1, back0, back1) = (rows[0], rows[1], rows[2], rows[3])
            let topLoad = top0.weightKg
            let backLoad = back0.weightKg

            // The card reads its own slot: the prescription, and last time's share.
            #expect(workout.planItem(for: top0)?.targetSets == 2)
            #expect(workout.planItem(for: back0)?.targetSets == 3)
            #expect(workout.lastPerformance(for: top0).map(\.weightKg) == [60, 60, 60])
            #expect(workout.lastPerformance(for: back1).map(\.weightKg) == [40, 45])
            // Paired by position within the slot; the merged position gave a heavy set.
            #expect(workout.previousSet(for: back0)?.weightKg == 40)
            #expect(workout.previousSet(for: back1)?.weightKg == 45)

            // An offer made on the top set covers the top slot and nothing else.
            top0.reps = 6
            workout.complete(top0, restSeconds: nil, at: at(60))
            workout.rate(top0, feel: .easy)
            let offer = try #require(workout.pendingNudge(for: bench))
            #expect(offer.setCount == 1)
            workout.apply(offer)
            #expect(top1.weightKg == offer.toKg)
            #expect([back0, back1, rows[4]].allSatisfy { $0.weightKg == backLoad })

            // Lifting a back-off set does not settle the top slot's take.
            workout.complete(back0, restSeconds: nil, at: at(300))
            let taken = try #require(workout.takenNudge(for: bench))
            workout.undoTakenNudge(taken)
            #expect(top1.weightKg == topLoad && back1.weightKg == back0.weightKg)
        }
    }

    @Test func oneWalkOfTheHistoryAnswersWhatOneReadPerExerciseDoes() throws {
        try WorkoutBench.run { testBench in
            var history: [WorkoutSession] = []
            for (age, ids) in [(1, ["hw-a"]), (2, ["hw-a", "hw-b"]), (3, ["hw-c", "hw-b"])] {
                let past = testBench.session(title: "Past \(age)", startedAt: at(-86_400 * Double(age)))
                past.endedAt = past.startedAt.addingTimeInterval(3_000)
                for id in ids {
                    for index in 0..<2 {
                        insertRow(testBench, id, index: index, in: past, kg: Double(age) * 10 + Double(index),
                                  loggedAt: past.startedAt.addingTimeInterval(Double(index + 1) * 120))
                    }
                }
                history.append(past)
            }
            // A session still running is not history.
            history.append(testBench.session(title: "Open"))
            let wanted: Set<String> = ["hw-a", "hw-b", "hw-c", "hw-never"]

            let walked = SessionFactory.lastPerformances(of: wanted, in: history)

            for id in wanted {
                let oneRead = TrainingStats.lastPerformance(of: id, in: history).map(\.id)
                #expect(walked[id]?.map(\.id) == oneRead, "History walk disagrees for \(id)")
            }
            #expect(walked["hw-never"] == [])
            #expect(walked["hw-a"]?.first?.weightKg == 10)
            let without = SessionFactory.lastPerformances(of: ["hw-a"], in: history, excluding: history[0].id)
            #expect(without["hw-a"]?.first?.weightKg == 20)
        }
    }

    // MARK: Editing the shape of the session

    @Test func removeLastSetRefusesALoggedSetAndNeverEmptiesACard() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = testBench.addRows(to: session, count: 3)
            let workout = testBench.open(session)
            let read2 = try removable(testBench, workout)?.id
            #expect(read2 == rows[2].id)

            workout.removeLastSet(from: try testBench.group(workout))
            #expect(session.sets.count == 2)
            #expect(session.sets.map(\.setIndex).sorted() == [0, 1])

            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.complete(rows[1], restSeconds: nil, at: at(120))
            let read3 = try removable(testBench, workout)
            #expect(read3 == nil)
            workout.removeLastSet(from: try testBench.group(workout))
            #expect(session.sets.count == 2)

            // A card with one row left keeps it.
            let single = testBench.addRows(WorkoutBench.row, to: session, count: 1, order: 1)
            let read4 = try removable(testBench, workout, WorkoutBench.row)
            #expect(read4 == nil)
            #expect(single.count == 1)
        }
    }

    @Test func theRemovableSetSkipsRowsLoggedBelowItAndThoseHoldingUpADrop() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = testBench.addRows(to: session, count: 3)
            let workout = testBench.open(session)

            workout.complete(rows[2], restSeconds: nil, at: at(60))
            let read5 = try removable(testBench, workout)?.id
            #expect(read5 == rows[1].id)

            // A logged set with a drop under it is held up by that drop.
            workout.complete(rows[0], restSeconds: nil, at: at(100))
            workout.continueSet(rows[0])
            let read6 = try removable(testBench, workout)?.id
            #expect(read6 == rows[1].id)
        }
    }

    @Test func aPlannedExerciseCannotBeRemovedAndAnAddedOneCanUntilItIsLogged() throws {
        try WorkoutBench.run { testBench in
            let (plan, day) = testBench.planDay(named: "Push", slots: [
                .init(catalogID: bench, sets: 3, low: 6, high: 8, kg: 80),
            ])
            let workout = testBench.start(day: day, plan: plan)

            let planned = try testBench.group(workout)
            #expect(!workout.canRemove(planned))
            workout.removeExercise(planned)
            #expect(workout.session.sets.count == 3)

            let row = try #require(ExerciseCatalog.shared.exercise(id: WorkoutBench.row))
            workout.addExercise(row, sets: 2)
            workout.writeNote("tight left elbow", about: try testBench.group(workout, WorkoutBench.row))
            let read7 = try testBench.count(ExerciseNote.self)
            #expect(read7 == 1)

            let first = try #require(try testBench.group(workout, WorkoutBench.row).sets.first)
            workout.complete(first, restSeconds: nil, at: at(60))
            let read8 = try canRemoveAdded(testBench, workout)
            #expect(read8 == false)
            workout.removeExercise(try testBench.group(workout, WorkoutBench.row))
            #expect(workout.session.sets.count == 5)

            workout.uncomplete(first)
            let added = try testBench.group(workout, WorkoutBench.row)
            #expect(workout.canRemove(added))
            workout.removeExercise(added)
            #expect(workout.session.sets.count == 3)
            // The note was about an exercise the record no longer holds.
            let read9 = try testBench.count(ExerciseNote.self)
            #expect(read9 == 0)
        }
    }

    @Test func aContinuationIsOneEffortAndOnlyAnUnloggedOneCanBeRemoved() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = testBench.addRows(to: session, count: 3)
            let workout = testBench.open(session)

            // There is nothing to take on from until the set is lifted.
            workout.continueSet(rows[0])
            #expect(session.sets.count == 3)

            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.continueSet(rows[0])
            let drop = try #require(session.sets.first { $0.isContinuation })
            #expect(drop.setIndex == 1)
            #expect(drop.weightKg == 100 && drop.reps == 8)
            #expect(rows[1].setIndex == 2 && rows[2].setIndex == 3)
            #expect(workout.totalCount == 3)

            workout.complete(drop, restSeconds: nil, at: at(90))
            #expect(workout.completedCount == 1)
            #expect(session.completedSets.count == 2)

            workout.removeContinuation(drop)
            #expect(session.sets.count == 4)

            workout.uncomplete(drop)
            workout.removeContinuation(drop)
            #expect(session.sets.count == 3)
            #expect(session.sets.map(\.setIndex).sorted() == [0, 1, 2])
            #expect(rows[0].isCompleted)
        }
    }

    @Test func removeAfterAnUndoMidCardTakesTheEmptyRowAndNotTheLoggedOneBelow() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let rows = (0..<3).map { insertRow(testBench, index: $0, in: session, loggedAt: at(Double($0) * 120)) }
            let workout = testBench.open(session)

            // Set 2 taken back to fix it. Remove used to delete the logged set 3.
            rows[1].unlog()
            let read1 = try removable(testBench, workout)?.id
            #expect(read1 == rows[1].id)
            workout.removeLastSet(from: try testBench.group(workout))

            let left = try testBench.group(workout).sets
            #expect(left.map(\.id) == [rows[0].id, rows[2].id])
            #expect(left.map(\.setIndex) == [0, 1])
            let read2 = try removable(testBench, workout)
            #expect(read2 == nil)
        }
    }

    @Test func removeTakesAnEmptyWorkingSetBeforeAnUnliftedDropRow() throws {
        try WorkoutBench.run { testBench in
            // Set 2 skipped for a busy rack, set 3 logged and taken further, the
            // drop not lifted yet. *Add set* adds working sets; its pair takes one.
            let session = testBench.session()
            let first = insertRow(testBench, index: 0, in: session, loggedAt: at(0))
            let skipped = insertRow(testBench, index: 1, in: session)
            let third = insertRow(testBench, index: 2, in: session, loggedAt: at(200))
            let drop = insertRow(testBench, index: 3, in: session, kg: 60, continuation: true)
            let workout = testBench.open(session)
            let read1 = try removable(testBench, workout)?.id
            #expect(read1 == skipped.id)

            workout.removeLastSet(from: try testBench.group(workout))

            let left = try testBench.group(workout).sets
            #expect(left.map(\.id) == [first.id, third.id, drop.id])
            #expect(drop.isContinuation)
            #expect(left.map(\.setIndex) == [0, 1, 2])
        }
    }

    @Test func removePassesOverARowHoldingUpADropAndNeverTakesALoggedDrop() throws {
        try WorkoutBench.run { testBench in
            // Set 2 taken back with its drop still under it. Removing set 2 would
            // leave the drop claiming to continue set 1.
            let held = testBench.session()
            let first = insertRow(testBench, index: 0, in: held, loggedAt: at(0))
            let undone = insertRow(testBench, index: 1, in: held)
            let heldDrop = insertRow(testBench, index: 2, in: held, kg: 60, continuation: true)
            let heldWorkout = testBench.open(held)
            let read1 = try removable(testBench, heldWorkout)?.id
            #expect(read1 == heldDrop.id)
            heldWorkout.removeLastSet(from: try testBench.group(heldWorkout))
            let read2 = try testBench.group(heldWorkout).sets.map(\.id)
            #expect(read2 == [first.id, undone.id])

            // With the drop logged there is nothing Remove may take.
            let logged = testBench.session(title: "Logged drop")
            insertRow(testBench, index: 0, in: logged, loggedAt: at(0))
            insertRow(testBench, index: 1, in: logged)
            insertRow(testBench, index: 2, in: logged, kg: 60, loggedAt: at(300), continuation: true)
            let loggedWorkout = testBench.open(logged)
            let read3 = try removable(testBench, loggedWorkout)
            #expect(read3 == nil)
            loggedWorkout.removeLastSet(from: try testBench.group(loggedWorkout))
            let read4 = try testBench.group(loggedWorkout).sets.count
            #expect(read4 == 3)
        }
    }

    @Test func aRowCarriesOnlyTheMeasureItsExerciseIsLoggedIn() throws {
        try WorkoutBench.run { testBench in
            let workout = upperDay(testBench)
            let benchRows = card(bench, of: workout.session)
            let planks = card(WorkoutBench.plank, of: workout.session)
            // A weighted row opens with reps and no hold time, a timed one with
            // its hold and no reps: either other number would be exported as
            // measured.
            #expect(benchRows.allSatisfy { $0.seconds == 0 && $0.reps == 8 })
            #expect(planks.count == 2)
            #expect(planks.allSatisfy { $0.seconds == 60 && $0.reps == 0 })

            workout.complete(benchRows[0], restSeconds: nil, at: at(60))
            workout.continueSet(benchRows[0])
            let drop = card(bench, of: workout.session)[1]
            #expect(drop.isContinuation && drop.seconds == 0 && drop.reps == 8)
            #expect(drop.targetRepsLow == 0 && drop.targetRepsHigh == 0)

            // A row saved before sessions stopped seeding a hold onto every row:
            // its drop does not copy the unmeasured hold forward.
            benchRows[1].seconds = 45
            workout.complete(benchRows[1], restSeconds: nil, at: at(240))
            workout.continueSet(benchRows[1])
            let olderDrop = card(bench, of: workout.session).first { $0.isContinuation && $0.setIndex > 2 }
            #expect(olderDrop?.seconds == 0)

            workout.complete(planks[0], restSeconds: nil, at: at(600))
            workout.continueSet(planks[0])
            let plankContinuation = card(WorkoutBench.plank, of: workout.session)[1]
            #expect(plankContinuation.isContinuation)
            #expect(plankContinuation.seconds == 60 && plankContinuation.reps == 0)
        }
    }

    @Test func anExerciseAddedOnTheFloorHasNoInventedTargetOrMeasure() throws {
        try WorkoutBench.run { testBench in
            let workout = upperDay(testBench)
            let curl = CatalogExercise(id: "curl-test", name: "curl-test", category: "strength",
                                       muscleGroups: [], equipment: [], details: nil,
                                       difficulty: nil, tracking: .weightReps)
            workout.addExercise(curl, sets: 2)
            let curls = card("curl-test", of: workout.session)
            #expect(curls.count == 2)
            #expect(curls.allSatisfy {
                $0.targetRepsLow == 0 && $0.targetRepsHigh == 0 && $0.seconds == 0 && $0.reps == 10
            })

            let hold = CatalogExercise(id: "hold-test", name: "hold-test", category: "core",
                                       muscleGroups: [], equipment: [], details: nil,
                                       difficulty: nil, tracking: .duration)
            workout.addExercise(hold, sets: 1)
            let holds = card("hold-test", of: workout.session)
            #expect(holds.count == 1)
            #expect(holds.allSatisfy { $0.reps == 0 && $0.seconds == 45 })

            // More of a planned exercise keeps the range the plan gave it.
            let press = try #require(ExerciseCatalog.shared.exercise(id: bench))
            workout.addExercise(press, sets: 1)
            let extra = try #require(card(bench, of: workout.session).last)
            #expect(extra.targetRepsLow == 8 && extra.targetRepsHigh == 10)

            // No range reads as no range: an all-out set fell short of nothing,
            // and an easy one still offers the next rung.
            curls[0].weightKg = 20
            curls[0].reps = 6
            workout.complete(curls[0], restSeconds: nil, at: at(900))
            #expect(!curls[0].hitTopOfRange && !curls[0].fellShortOfRange)
            workout.rate(curls[0], feel: .allOut)
            #expect(workout.pendingNudge(for: "curl-test") == nil)
            workout.rate(curls[0], feel: .easy)
            let offer = workout.pendingNudge(for: "curl-test")
            #expect(offer?.setID == curls[0].id)
            #expect(offer?.toKg == curls[0].loadScale.step(kg: 20, by: 1))
        }
    }

    @Test func addingTheSurvivorOfAMergeJoinsTheCardHoldingTheOldID() throws {
        try WorkoutBench.run { testBench in
            let losing = "dumbbell-pullover-chest"
            let session = testBench.session()
            insertRow(testBench, losing, index: 0, in: session, kg: 20)
            insertRow(testBench, order: 1, index: 0, in: session)
            let survivor = try #require(ExerciseCatalog.shared.exercise(id: "dumbbell-pullover"))
            try #require(ExerciseCatalog.canonicalID(for: losing) == survivor.id)
            let workout = testBench.open(session)

            workout.addExercise(survivor, sets: 2)

            // One card for one lift, and the new rows follow on in it, at its
            // place and its load.
            let pullovers = workout.groups.filter { ExerciseCatalog.canonicalID(for: $0.catalogID) == survivor.id }
            #expect(pullovers.count == 1)
            #expect(workout.groups.count == 2)
            let rows = card(losing, of: session)
            #expect(rows.count == 3)
            #expect(rows.map(\.setIndex) == [0, 1, 2])
            #expect(rows.allSatisfy { $0.exerciseOrder == 0 })
            #expect(rows.dropFirst().allSatisfy { $0.weightKg == 20 })
        }
    }

    @Test func addingADifferentMovementStillOpensACardBelowTheLast() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            insertRow(testBench, "dumbbell-pullover-chest", index: 0, in: session)
            let press = try #require(ExerciseCatalog.shared.exercise(id: bench))
            let workout = testBench.open(session)

            workout.addExercise(press, sets: 3)

            #expect(workout.groups.count == 2)
            #expect(card(bench, of: session).map(\.exerciseOrder) == [1, 1, 1])
        }
    }

    // MARK: Which exercise the session is on

    @Test func lookingBackAtAFinishedExerciseLeavesTheWorkingPositionWhereItWas() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            insertRow(testBench, "A-review", order: 0, index: 0, in: session, loggedAt: at(0))
            insertRow(testBench, "B-review", order: 1, index: 0, in: session)
            let picked = insertRow(testBench, "C-review", order: 2, index: 0, in: session)
            insertRow(testBench, "C-review", order: 2, index: 1, in: session)
            let workout = testBench.open(session)
            #expect(workout.currentGroup?.catalogID == "B-review")

            // B's rack is taken, so the lifter picks C and lifts.
            #expect(!workout.openFromQueue("C-review"))
            #expect(workout.currentGroup?.catalogID == "C-review")
            workout.complete(picked, restSeconds: nil, at: at(400))

            // During the rest they look back at A to rate its last set. The
            // wrist, the Lock Screen and the dock stay on C.
            #expect(workout.openFromQueue("A-review"))
            #expect(session.preferredExerciseID == "C-review")
            #expect(workout.currentGroup?.catalogID == "C-review")
            #expect(workout.nextSet?.catalogID == "C-review")

            // Picking an unfinished exercise still moves it, and one the session
            // does not hold moves nothing.
            #expect(!workout.openFromQueue("B-review"))
            #expect(workout.currentGroup?.catalogID == "B-review")
            #expect(!workout.openFromQueue("missing-review"))
            #expect(workout.currentGroup?.catalogID == "B-review")
        }
    }

    @Test func theCurrentExerciseFromGroupsTakenOnceAgreesWithAFreshReadThroughEveryMove() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session(title: "Eight lifts")
            let exerciseCount = 8
            let setsEach = 4
            for exercise in 0..<exerciseCount {
                testBench.addRows("lift-\(exercise)", to: session, count: setsEach, order: exercise,
                                  weightKg: 40, reps: 8, low: 8, high: 8)
            }
            let workout = testBench.open(session)

            // The rule as it stood before the logger took its groups once per
            // pass, written out over a fresh build, so the two are compared
            // rather than each trusted.
            @MainActor func reference() -> String? {
                let groups = session.exerciseGroups
                if let preferred = session.preferredExerciseID,
                   let group = groups.first(where: { $0.catalogID == preferred && !$0.isComplete }) {
                    return group.catalogID
                }
                return (groups.first { !$0.isComplete } ?? groups.last)?.catalogID
            }
            @MainActor func agree(_ what: String) {
                let groups = workout.groups
                let once = workout.currentGroup(in: groups)
                #expect(once?.catalogID == reference(), "\(what): currentGroup(in:) left the rule")
                #expect(workout.currentGroup?.catalogID == once?.catalogID, "\(what): currentGroup")
                guard let once else { return }
                let next = once.sets.first { !$0.isCompleted }
                #expect(workout.nextSetNumber(in: once) == workout.nextSetNumber, "\(what): set number")
                #expect(workout.nextSet?.id == next?.id, "\(what): next set")
                #expect(workout.currentSetTotal == once.effortCount, "\(what): set total")
            }

            agree("fresh session")
            #expect(workout.currentGroup?.catalogID == "lift-0")

            // A pick out of order.
            session.preferredExerciseID = "lift-3"
            agree("preferred exercise")
            #expect(workout.currentGroup?.catalogID == "lift-3")

            // Nothing is remembered between reads: finishing the preferred
            // exercise moves "current" on the very next read, with no step to
            // invalidate anything.
            for set in session.sets where set.catalogID == "lift-3" { set.isCompleted = true }
            agree("preferred exercise finished")
            #expect(workout.currentGroup?.catalogID == "lift-0")

            // A set logged, then undone, on the first exercise.
            let first = card("lift-0", of: session)
            first[0].isCompleted = true
            agree("one set logged")
            #expect(workout.nextSetNumber == 2)
            first[0].unlog()
            agree("that set undone")
            #expect(workout.nextSetNumber == 1)

            // A set added to an exercise, and every exercise finished outright.
            workout.addSet(to: try testBench.group(workout, "lift-0"))
            agree("set added")
            #expect(workout.currentSetTotal == setsEach + 1)
            for set in session.sets { set.isCompleted = true }
            agree("everything logged")
            // With nothing left the last exercise stays current.
            #expect(workout.currentGroup?.catalogID == "lift-\(exerciseCount - 1)")
            #expect(workout.upNextName == "")
        }
    }

    // MARK: Notes

    @Test func aNoteIsWrittenOnlyWhereSomethingWasSaidAndPrunedWhenEmptied() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            let group = try testBench.group(workout)
            #expect(rows.count == 4)

            workout.writeNote("   ", about: group)
            let read10 = try testBench.count(ExerciseNote.self)
            #expect(read10 == 0)

            workout.writeNote("felt strong", about: group)
            let read11 = try testBench.count(ExerciseNote.self)
            #expect(read11 == 1)
            #expect(workout.note(for: bench)?.text == "felt strong")

            workout.writeNote("", about: group)
            #expect(workout.note(for: bench)?.isEmpty == true)
            workout.pruneEmptyNotes()
            let read12 = try testBench.count(ExerciseNote.self)
            #expect(read12 == 0)
        }
    }

    @Test func finishingKeepsTheNoteOfALoggedExerciseAndDropsOneForWorkNeverDone() throws {
        try WorkoutBench.run { testBench in
            let session = testBench.session()
            let benchRows = testBench.addRows(to: session, count: 2)
            testBench.addRows(WorkoutBench.row, to: session, count: 2, order: 1)
            let workout = testBench.open(session)
            workout.writeNote("shoulder pinched", about: try testBench.group(workout))
            workout.writeNote("skipped, no time", about: try testBench.group(workout, WorkoutBench.row))
            let read13 = try testBench.count(ExerciseNote.self)
            #expect(read13 == 2)

            workout.complete(benchRows[0], restSeconds: nil, at: at(60))
            #expect(workout.finish(at: at(600)))

            let read14 = try testBench.count(ExerciseNote.self)
            #expect(read14 == 1)
            #expect(session.exerciseNotes.map(\.catalogID) == [bench])
        }
    }

    // MARK: Commands from the wrist

    @Test func aWristLogGivesTheSameRecordAsALogOnThePhone() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            let stamp = at(120)

            // The wrist sends a hold time for every set it logs, including a
            // bench press, which has none to report.
            #expect(workout.apply(.logSet(id: rows[0].id, weightKg: 102.5, reps: 9, seconds: 45, at: stamp)))
            rows[1].weightKg = 102.5
            rows[1].reps = 9
            workout.complete(rows[1], restSeconds: nil, at: stamp)

            for row in rows[0...1] {
                #expect(row.isCompleted)
                #expect(row.weightKg == 102.5 && row.reps == 9)
                #expect(row.seconds == 0)
                #expect(row.completedAt == stamp)
                #expect(row.startedAt == nil && row.rpe == nil)
            }
        }
    }

    @Test func aWristLogDeliveredTwiceOrForAnUnknownSetChangesNothingMore() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            let stamp = at(120)
            let log = WatchCommand.logSet(id: rows[0].id, weightKg: 102.5, reps: 9, seconds: 0, at: stamp)

            #expect(workout.apply(log))
            workout.rate(rows[0], feel: .solid)
            // The wrist never heard the answer and sends it again. Applied a
            // second time it would file a decline nobody made.
            #expect(workout.apply(log))
            #expect(workout.completedCount == 1)
            #expect(rows[0].completedAt == stamp)
            #expect(rows[0].rpe == SetFeel.solid.rawValue)

            #expect(workout.apply(.logSet(id: UUID(), weightKg: 50, reps: 5, seconds: 0, at: stamp)) == false)
            #expect(workout.completedCount == 1)
            #expect(workout.session.sets.count == 4)
        }
    }

    @Test func aWristUndoErasesTheLogAndALateCopyOfTheLogDoesNotBringItBack() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            let stamp = at(120)
            let log = WatchCommand.logSet(id: rows[0].id, weightKg: 102.5, reps: 9, seconds: 0, at: stamp)
            #expect(workout.apply(log))
            workout.rate(rows[0], feel: .hard)

            // An undo that names some other completion of the row is not for this log.
            #expect(workout.apply(.undoSet(id: rows[0].id, completedAt: stamp.addingTimeInterval(60))))
            #expect(rows[0].isCompleted && rows[0].rpe == SetFeel.hard.rawValue)

            #expect(workout.apply(.undoSet(id: rows[0].id, completedAt: stamp)))
            #expect(!rows[0].isCompleted)
            #expect(rows[0].completedAt == nil && rows[0].rpe == nil && rows[0].startedAt == nil)

            // Delivery is not ordered: the log arrives again after its undo.
            #expect(workout.apply(log))
            #expect(!rows[0].isCompleted)

            #expect(workout.apply(.undoSet(id: UUID(), completedAt: stamp)) == false)
        }
    }

    @Test func aWristRatingIsAppliedOnlyToTheLogItWasAnsweringAndIsNotToggledByRepeats() throws {
        try WorkoutBench.run { testBench in
            let (session, rows, workout) = testBench.standard()
            let stamp = at(120)
            #expect(workout.apply(.logSet(id: rows[0].id, weightKg: 100, reps: 8, seconds: 0, at: stamp)))

            func rating(_ rpe: Double?, setID: UUID? = nil, at completion: Date? = nil,
                        session id: UUID? = nil) -> WatchCommand {
                .rateSet(WatchSetRating(sessionID: id ?? session.id, setID: setID ?? rows[0].id,
                                        completedAt: completion ?? stamp, rpe: rpe))
            }

            #expect(workout.apply(rating(8)))
            #expect(rows[0].rpe == 8)
            // Delivery may repeat; the phone's tap toggles, a repeated message must not.
            #expect(workout.apply(rating(8)))
            #expect(rows[0].rpe == 8)

            #expect(workout.apply(rating(7)))
            #expect(rows[0].rpe == 8)
            #expect(workout.apply(rating(10, at: stamp.addingTimeInterval(5))))
            #expect(rows[0].rpe == 8)
            #expect(workout.apply(rating(10, session: UUID())) == false)
            #expect(rows[0].rpe == 8)

            // A rating for a set that was never logged has nothing to be about.
            #expect(workout.apply(rating(8, setID: rows[1].id)))
            #expect(rows[1].rpe == nil)

            #expect(workout.apply(rating(nil)))
            #expect(rows[0].rpe == nil)
        }
    }

    @Test func aWristStartAndItsCancelRoundTripAndIgnoreSetsThatAreNotHere() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()

            #expect(workout.apply(.announceStart(id: rows[0].id, at: at(30))))
            #expect(rows[0].startedAt == at(30))
            #expect(workout.apply(.cancelStart(id: rows[0].id)))
            #expect(rows[0].startedAt == nil)

            #expect(workout.apply(.announceStart(id: UUID(), at: at(30))))
            #expect(workout.apply(.cancelStart(id: UUID())))
            #expect(rows.allSatisfy { $0.startedAt == nil })
        }
    }

    // MARK: Undo, field by field

    /// What logging a set does to one stored property.
    private enum Kind {
        /// Written by logging a set, or by the readings taken through its
        /// window. Must be exactly what it was before once the set is un-logged.
        case loggedByTheSet
        /// Never written by logging. Must be untouched by log plus un-log.
        case identity
        /// The numbers on the row. They are also the prefill for the next
        /// attempt, so un-logging keeps them on purpose (see `SetLog.unlog`).
        case keptOnPurpose
    }

    private typealias Field<Model> = (name: String, kind: Kind, read: (Model) -> String)

    private static func text(_ value: Any?) -> String { String(describing: value) }

    /// One entry per stored property of `SetLog`. A property added to the model
    /// fails `everyStoredPropertyOfASetAndASessionIsClassifiedForUndo` until it
    /// is listed here, which is the moment to decide whether logging can write
    /// it and whether `SetLog.unlog()` has to erase it. If logging can, give it
    /// a value in `simulateLogging` that differs from a fresh row's.
    private static let setFields: [Field<SetLog>] = [
        ("isCompleted", .loggedByTheSet, { text($0.isCompleted) }),
        ("completedAt", .loggedByTheSet, { text($0.completedAt) }),
        ("startedAt", .loggedByTheSet, { text($0.startedAt) }),
        ("rpe", .loggedByTheSet, { text($0.rpe) }),
        ("averageHeartRate", .loggedByTheSet, { text($0.averageHeartRate) }),
        ("maxHeartRate", .loggedByTheSet, { text($0.maxHeartRate) }),
        ("heartRateWindowRaw", .loggedByTheSet, { text($0.heartRateWindowRaw) }),
        ("detectedStartedAt", .loggedByTheSet, { text($0.detectedStartedAt) }),
        ("detectedEndedAt", .loggedByTheSet, { text($0.detectedEndedAt) }),
        ("loadNudgeOutcomeRaw", .loggedByTheSet, { text($0.loadNudgeOutcomeRaw) }),
        ("loadNudgeToKg", .loggedByTheSet, { text($0.loadNudgeToKg) }),
        ("id", .identity, { text($0.id) }),
        ("catalogID", .identity, { text($0.catalogID) }),
        ("exerciseName", .identity, { text($0.exerciseName) }),
        ("exerciseOrder", .identity, { text($0.exerciseOrder) }),
        ("setIndex", .identity, { text($0.setIndex) }),
        ("trackingRaw", .identity, { text($0.trackingRaw) }),
        ("targetRepsLow", .identity, { text($0.targetRepsLow) }),
        ("targetRepsHigh", .identity, { text($0.targetRepsHigh) }),
        ("session", .identity, { text($0.session?.id) }),
        // A drop's second row is a continuation before it is logged and after
        // it is taken back; only removing the row un-makes it.
        ("continuesPreviousSet", .identity, { text($0.continuesPreviousSet) }),
        ("weightKg", .keptOnPurpose, { text($0.weightKg) }),
        ("reps", .keptOnPurpose, { text($0.reps) }),
        ("seconds", .keptOnPurpose, { text($0.seconds) }),
    ]

    /// One entry per stored property of `WorkoutSession`. Logging a set writes
    /// none of them, so every one is `.identity`: the session after log plus
    /// undo is the session before. Health metrics arrive at finish, not here.
    private static let sessionFields: [Field<WorkoutSession>] = [
        ("id", .identity, { text($0.id) }),
        ("title", .identity, { text($0.title) }),
        ("startedAt", .identity, { text($0.startedAt) }),
        ("endedAt", .identity, { text($0.endedAt) }),
        ("notes", .identity, { text($0.notes) }),
        ("noteTagsRaw", .identity, { text($0.noteTagsRaw) }),
        ("planDayID", .identity, { text($0.planDayID) }),
        ("planName", .identity, { text($0.planName) }),
        ("preferredExerciseID", .identity, { text($0.preferredExerciseID) }),
        ("healthWorkoutID", .identity, { text($0.healthWorkoutID) }),
        ("averageHeartRate", .identity, { text($0.averageHeartRate) }),
        ("maxHeartRate", .identity, { text($0.maxHeartRate) }),
        ("activeEnergyKcal", .identity, { text($0.activeEnergyKcal) }),
        ("wasWatchDriven", .identity, { text($0.wasWatchDriven) }),
        ("heartRateSourceRaw", .identity, { text($0.heartRateSourceRaw) }),
        ("energySourceRaw", .identity, { text($0.energySourceRaw) }),
        ("heartRateReadings", .identity, { text($0.heartRateReadings) }),
        ("isLoggedAfterwards", .identity, { text($0.isLoggedAfterwards) }),
        ("plannedSlotsData", .identity, { text($0.plannedSlotsData) }),
        ("sets", .identity, { text($0.sets.map(\.id).sorted { $0.uuidString < $1.uuidString }) }),
        ("exerciseNotes", .identity, { text($0.exerciseNotes.map(\.id)) }),
    ]

    private static func snapshot<Model>(_ model: Model, _ fields: [Field<Model>]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.read(model)) })
    }

    /// Two exercises, three sets of the first. The second row of the first is
    /// a continuation, so the identity of that flag is tried on a row that has it.
    private func unlogFixture(_ testBench: WorkoutBench) -> (session: WorkoutSession, rows: [SetLog]) {
        let session = testBench.session(title: "Today")
        var rows = testBench.addRows(to: session, count: 3, weightKg: 60, reps: 8, low: 8, high: 12)
        rows[1].continuesPreviousSet = true
        rows += testBench.addRows(WorkoutBench.row, to: session, count: 1, order: 1,
                                  weightKg: 50, reps: 10, low: 8, high: 12)
        return (session, rows)
    }

    /// Everything logging a set, and the readings taken through its window, can
    /// write, each to a value different from a fresh row's.
    private func simulateLogging(_ set: SetLog, at moment: Date) {
        set.startedAt = moment.addingTimeInterval(-40)
        set.rpe = SetFeel.hard.rawValue
        set.apply(SetHeartRate(average: 131, peak: 149, source: .measured))
        set.recordDetectedWindow(DetectedSetWindow(start: moment.addingTimeInterval(-38),
                                                   end: moment.addingTimeInterval(-2)))
        set.recordLoadNudge(.taken, toKg: 62.5)
    }

    @Test func everyStoredPropertyOfASetAndASessionIsClassifiedForUndo() throws {
        // A stored property nobody has classified is a field somebody added
        // without deciding whether logging can write it.
        let schema = try TestStore.container().schema
        let known = [("SetLog", Set(Self.setFields.map(\.name))),
                     ("WorkoutSession", Set(Self.sessionFields.map(\.name)))]
        for (entity, classified) in known {
            let stored = Set(schema.entities.first { $0.name == entity }?.storedProperties.map(\.name) ?? [])
            let unclassified = stored.subtracting(classified).sorted()
            let gone = classified.subtracting(stored).sorted()
            #expect(!stored.isEmpty, "The schema has no entity \(entity)")
            #expect(unclassified.isEmpty,
                    """
                    \(entity) has stored properties this test has not classified: \(unclassified). \
                    Decide whether logging can write each, and whether unlog() must erase it, \
                    then add it to the tables in this file.
                    """)
            #expect(gone.isEmpty, "\(entity) is listed with properties the model no longer has: \(gone)")
        }
    }

    @Test func unlogPutsEveryFieldTheLogWroteBackAndKeepsOnlyTheRowsNumbers() throws {
        // `SetLog.unlog()` alone, which is what the wrist's undo runs with no logger.
        try WorkoutBench.run { testBench in
            let (session, rows) = unlogFixture(testBench)
            let set = rows[0]
            let setBefore = Self.snapshot(set, Self.setFields)
            let sessionBefore = Self.snapshot(session, Self.sessionFields)
            let siblingsBefore = rows.dropFirst().map { Self.snapshot($0, Self.setFields) }

            let moment = at(600)
            set.isCompleted = true
            set.completedAt = moment
            simulateLogging(set, at: moment)
            set.weightKg = 62.5
            set.reps = 10

            // The simulation has to reach every field it claims to, or the
            // comparison below is vacuous.
            let logged = Self.snapshot(set, Self.setFields)
            for field in Self.setFields where field.kind == .loggedByTheSet {
                #expect(logged[field.name] != setBefore[field.name],
                        "The simulated log did not change SetLog.\(field.name), so nothing is proved about it")
            }

            set.unlog()

            let after = Self.snapshot(set, Self.setFields)
            for field in Self.setFields {
                let expected = field.kind == .keptOnPurpose ? logged[field.name] : setBefore[field.name]
                #expect(after[field.name] == expected,
                        "unlog() left SetLog.\(field.name) as \(after[field.name] ?? "?"), not \(expected ?? "?")")
            }
            #expect(Self.snapshot(session, Self.sessionFields) == sessionBefore, "unlog() changed the session")
            #expect(rows.dropFirst().map { Self.snapshot($0, Self.setFields) } == siblingsBefore,
                    "unlog() changed another set")
            // No key: an un-logged set is indistinguishable from one never logged.
            #expect(set.averageHeartRate == nil && set.heartRateWindowRaw == nil && set.detectedWindow == nil
                    && set.loadNudgeOutcome == nil && set.rpe == nil && set.startedAt == nil)

            // Repeating it is harmless.
            set.unlog()
            #expect(Self.snapshot(set, Self.setFields) == after)
        }
    }

    @Test func loggingRatingAndUndoingOnThePhoneLeaveTheSetTheSessionAndTheOtherRowsAsTheyWere() throws {
        try WorkoutBench.run { testBench in
            // No rest in play, so only the log is compared. The bench puts the
            // setting back when the test ends, however it ends.
            AppSettings.shared.restTimerAutoStart = false
            let (session, rows) = unlogFixture(testBench)
            let workout = testBench.open(session)
            let set = rows[0]
            let setBefore = Self.snapshot(set, Self.setFields)
            let sessionBefore = Self.snapshot(session, Self.sessionFields)
            let othersBefore = rows.dropFirst().map { Self.snapshot($0, Self.setFields) }

            let moment = Date.now
            set.startedAt = moment.addingTimeInterval(-40)
            workout.complete(set, restSeconds: nil, at: moment)
            workout.rate(set, feel: .hard)
            set.apply(SetHeartRate(average: 131, peak: 149, source: .measured))
            set.recordDetectedWindow(DetectedSetWindow(start: moment.addingTimeInterval(-38),
                                                       end: moment.addingTimeInterval(-2)))
            set.recordLoadNudge(.declined, toKg: 62.5)
            try #require(set.isCompleted && set.rpe != nil && set.hasHeartRate)

            workout.uncomplete(set)

            let after = Self.snapshot(set, Self.setFields)
            for field in Self.setFields where field.kind != .keptOnPurpose {
                #expect(after[field.name] == setBefore[field.name],
                        "uncomplete() left SetLog.\(field.name) as \(after[field.name] ?? "?"); it was \(setBefore[field.name] ?? "?")")
            }
            let sessionAfter = Self.snapshot(session, Self.sessionFields)
            let changed = Self.sessionFields.map(\.name).filter { sessionAfter[$0] != sessionBefore[$0] }
            #expect(sessionAfter == sessionBefore, "Logging and undoing a set changed the session: \(changed)")
            // Other rows may take the weight forward as a prefill, so only what
            // logging writes is compared: none of them may hold any of it.
            for (row, before) in zip(rows.dropFirst(), othersBefore) {
                let now = Self.snapshot(row, Self.setFields)
                for field in Self.setFields where field.kind == .loggedByTheSet {
                    #expect(now[field.name] == before[field.name],
                            "Logging and undoing one set left \(field.name) changed on another row")
                }
            }
            #expect(workout.lastLoggedSetID != set.id)
            #expect(!workout.isPR(set))
        }
    }

    // MARK: Units

    @Test func theStoredWeightIsKilogramsWhateverTheUnitAndTheWatchIsToldTheUnit() throws {
        try WorkoutBench.run { testBench in
            AppSettings.shared.weightUnit = .lb
            let (_, rows, workout) = testBench.standard()
            workout.complete(rows[0], restSeconds: nil, at: at(60))

            #expect(rows[0].weightKg == 100)
            #expect(workout.watchSnapshot.unit == .lb)

            AppSettings.shared.weightUnit = .kg
            #expect(workout.watchSnapshot.unit == .kg)
            #expect(rows[0].weightKg == 100)
        }
    }

    // MARK: The rest timer on its own

    @Test func theRestTimerSchedulesOneNotificationAndStopCancelsIt() throws {
        let spy = SpyNotifier()
        let timer = RestTimer(notifier: spy)
        defer { timer.stop() }
        let changes = ChangeCounter()
        timer.onChange = { changes.count += 1 }
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: WorkoutBench.t0) == 0)

        timer.start(seconds: 90)
        #expect(timer.isRunning)
        #expect(timer.totalSeconds == 90)
        #expect(spy.scheduled.map(\.seconds) == [90])
        #expect(spy.scheduled.map(\.id) == ["gymtrack.rest"])

        let end = try #require(timer.endsAt)
        let began = try #require(timer.startedAt)
        #expect(abs(end.timeIntervalSince(began) - 90) < 1)
        #expect(timer.remaining(at: end.addingTimeInterval(-30)) == 30)
        #expect(timer.remaining(at: end.addingTimeInterval(10)) == 0)
        #expect(abs(timer.progress(at: end.addingTimeInterval(-30)) - (1 - 30.0 / 90.0)) < 1e-9)

        let cancelledBefore = spy.cancelled.count
        timer.stop()
        #expect(!timer.isRunning)
        #expect(timer.endsAt == nil && timer.startedAt == nil && timer.totalSeconds == 0)
        #expect(spy.cancelled.count == cancelledBefore + 1)
        #expect(changes.count == 2)

        // Stopping a rest that is not running tells nobody anything.
        timer.stop()
        #expect(changes.count == 2)
    }

    @Test func theRestTimerIgnoresInputsThatCouldNotBeARest() throws {
        let spy = SpyNotifier()
        let timer = RestTimer(notifier: spy)
        defer { timer.stop() }

        timer.start(seconds: 0)
        timer.start(seconds: -5)
        timer.add(seconds: 30)
        timer.restore(endingAt: WorkoutBench.t0.addingTimeInterval(90), totalSeconds: 90)
        timer.restore(endingAt: Date.now.addingTimeInterval(60), totalSeconds: 0)
        #expect(!timer.isRunning)
        #expect(spy.scheduled.isEmpty)

        let end = Date.now.addingTimeInterval(60)
        timer.restore(endingAt: end, totalSeconds: 90)
        #expect(timer.isRunning)
        #expect(timer.endsAt == end)
        #expect(timer.startedAt == end.addingTimeInterval(-90))

        timer.add(seconds: 30)
        #expect(timer.totalSeconds == 120)
        #expect(timer.endsAt == end.addingTimeInterval(30))
        let rescheduled = try #require(spy.scheduled.last)
        #expect((88...90).contains(rescheduled.seconds))

        // Taking away more than is left is ending the rest.
        timer.add(seconds: -600)
        #expect(!timer.isRunning)
    }

    @Test func aRestFoundOverUpToTwoSecondsLateStillChimesAndNoLater() {
        // Later than that, the app was not running at the end and the "Rest
        // over" notification already did the announcing.
        let end = WorkoutBench.t0
        #expect(RestChimeRules.lateTolerance == 2)
        #expect(RestChimeRules.chimesOnExpiry(endsAt: end, now: end.addingTimeInterval(2)))
        #expect(!RestChimeRules.chimesOnExpiry(endsAt: end, now: end.addingTimeInterval(2.01)))
    }

    @Test func aRunningRestChangesNothingAViewCouldSeeUntilItsEndWhichItAnnouncesOnce() throws {
        let idle = RestTimer(notifier: SpyNotifier())
        #expect(idle.progress(at: WorkoutBench.t0) == 0)

        let spy = SpyNotifier()
        let timer = RestTimer(notifier: spy)
        defer { timer.stop() }
        // A "Rest over" left by a process that died is cleared at start-up.
        #expect(spy.cancelled == ["gymtrack.rest"])
        let changes = ChangeCounter()
        timer.onChange = { changes.count += 1 }

        // A rest of 90 s with 60 to go, put back where it is. Live, because a
        // rest whose end has gone by is over and `restore` puts nothing back.
        let started = Date.now
        let end = started.addingTimeInterval(60)
        timer.restore(endingAt: end, totalSeconds: 90)
        #expect(changes.count == 1 && timer.isRunning)
        #expect(spy.scheduled.map(\.seconds) == [60])
        // Answered for a moment, never stored, and never negative.
        #expect(abs(timer.remaining(at: started) - 60) < 0.001)
        #expect(abs(timer.progress(at: started.addingTimeInterval(15)) - 0.5) < 0.001)
        #expect(timer.remaining(at: started.addingTimeInterval(120)) == 0)

        // Everything a view could read, in one tracking scope, the way a
        // SwiftUI body watches it. A `remaining` written four times a second
        // used to draw every view that read it again four times a second.
        let observed = ObservationCounter()
        withObservationTracking {
            _ = timer.endsAt; _ = timer.startedAt; _ = timer.totalSeconds
            _ = timer.remaining; _ = timer.progress; _ = timer.isRunning
        } onChange: {
            observed.count += 1
        }
        // The end timer can fire a hair early, and then only re-arms.
        for second in [1.0, 15, 30, 59.9] {
            timer.expireIfDue(now: started.addingTimeInterval(second))
        }
        #expect(observed.count == 0)
        #expect(timer.isRunning && changes.count == 1)

        // The end: one change, the rest is gone, and the watcher hears of it.
        timer.expireIfDue(now: end.addingTimeInterval(0.3))
        #expect(!timer.isRunning && timer.endsAt == nil && timer.remaining == 0)
        #expect(changes.count == 2)
        #expect(observed.count == 1)
    }

    @Test func anExtendedRestOutlivesItsOldEndAndAStoppedOneHasNoEndToFire() throws {
        let spy = SpyNotifier()
        let timer = RestTimer(notifier: spy)
        defer { timer.stop() }
        let changes = ChangeCounter()
        timer.onChange = { changes.count += 1 }

        // +30 s on a rest with 30 to go: the earlier end must not stop it, and
        // the later one does.
        let extended = Date.now
        timer.restore(endingAt: extended.addingTimeInterval(30), totalSeconds: 60)
        // Whether this first rest asked for permission depends on whether an
        // earlier test in this process started one, because the flag is a
        // private static. Whichever it was, no rest after it asks again.
        let asked = spy.permissionAsks
        #expect(asked <= 1)
        timer.add(seconds: 30)
        timer.expireIfDue(now: extended.addingTimeInterval(30.3))
        #expect(timer.isRunning)
        timer.expireIfDue(now: extended.addingTimeInterval(60.3))
        #expect(!timer.isRunning)

        // Stopping takes the end with it: start and stop are announced, and
        // nothing at the old end.
        let before = changes.count
        let cancelled = Date.now
        timer.restore(endingAt: cancelled.addingTimeInterval(30), totalSeconds: 60)
        #expect(spy.permissionAsks == asked)
        timer.stop()
        timer.expireIfDue(now: cancelled.addingTimeInterval(30.3))
        #expect(changes.count == before + 2)
    }
}
