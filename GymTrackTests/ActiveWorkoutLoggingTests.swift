import Foundation
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
// Counterparts: Tests/UnlogNoTraceTests.swift, Tests/LoggerEntryTests.swift,
// Tests/LoggerCorrectionTests.swift and Tests/LoggerFollowUpTests.swift check
// the same rules in a script against stubs. These drive the real `ActiveWorkout`
// and `RestTimer` in the hosted app. The lifecycle (start, resume, finish,
// discard) is in ActiveWorkoutLifecycleTests.

/// Records what the rest timer asked the system to do, so the timer can be run
/// for real without a notification centre behind it.
private final class SpyNotifier: RestNotifying {
    var scheduled: [(seconds: Int, id: String)] = []
    var cancelled: [String] = []

    func schedule(in seconds: Int, id: String) { scheduled.append((seconds, id)) }
    func cancel(id: String) { cancelled.append(id) }
    func requestPermission() {}
}

private final class ChangeCounter {
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

    @Test func aRatingOnAnUnloggedSetIsNotKept() throws {
        try WorkoutBench.run { testBench in
            let (_, rows, workout) = testBench.standard()
            // The screen never offers the question for a set that has not been
            // lifted, but the logger takes the answer as given: a rating on a
            // row with no lift would be exported with the set it later became.
            withKnownIssue("rate(_:feel:) has no isCompleted guard; the UI and the wrist command path add their own (#4)") {
                workout.rate(rows[0], feel: .hard)
                #expect(rows[0].rpe == nil)
            }
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
}
