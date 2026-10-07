import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// A set logged on the wrist with the phone asleep in a locker must land in the
/// store exactly once, with the moment the wrist stamped, and must leave no
/// trace when the wrist takes it back. Here the center applies commands with no
/// view hierarchy and no `ActiveWorkout`, as iOS does when it wakes a terminated
/// app to hand over a watch message, and the assertions read the store. What the
/// center sends back to the watch cannot be seen from a test, so it is not
/// asserted.
///
/// A Finish on the phone deletes the rows nobody logged, and "Late logs" holds
/// the wrist's logs and undos to the rows such a close leaves behind. "Health
/// after a finish" reads what the center asked of Health through
/// `WatchCommandRig.health`, and "The widgets" reads the snapshot the Home
/// Screen draws back out of the shared store. Its pure half, and what the
/// widgets make of "today", is in `WidgetSnapshotTests`.

// MARK: - Harness

@MainActor
private func withRig(_ name: String = #function, _ body: @MainActor (WatchCommandRig) throws -> Void) throws {
    try WatchCommandRig.run(name, body)
}

/// Counts what reaches a handler, in order.
@MainActor
private final class Recorder {
    var commands: [WatchCommand] = []
}

private func sameMoment(_ a: Date?, _ b: Date?) -> Bool { WatchCommand.isSameCompletion(a, as: b) }

// MARK: - Logging and undoing

@MainActor @Suite(.serialized)
struct WatchCommandCenterHeadlessTests {

    @Test func aWristLogCompletesAPrescribedSetWithTheWristsMoment() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            #expect(rig.center.uiHandler == nil)

            rig.send(rig.log(sets[0], weight: 62.5, reps: 6, at: 600))

            #expect(sets[0].isCompleted)
            #expect(sameMoment(sets[0].completedAt, rig.at(600)))
            #expect(sets[0].weightKg == 62.5)
            #expect(sets[0].reps == 6)
            #expect(sets[0].rpe == nil)
            #expect(!sets[1].isCompleted)
            #expect(session.isActive)
        }
    }

    @Test func aRedeliveredLogDoesNotLogTwiceOrCarryItsLoadAgain() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let command = rig.log(sets[0], weight: 80, reps: 5, at: 600)
            rig.send(command)

            // The lifter dials the next row by hand after the first log landed.
            sets[1].weightKg = 70
            rig.send(command)

            #expect(sameMoment(sets[0].completedAt, rig.at(600)))
            #expect(sets[0].weightKg == 80)
            #expect(sets[1].weightKg == 70)
            #expect(rig.allSets().filter(\.isCompleted).count == 1)

            // A different stamp is a different log, and does land.
            rig.send(rig.log(sets[0], weight: 82.5, reps: 4, at: 700))
            #expect(sameMoment(sets[0].completedAt, rig.at(700)))
            #expect(sets[0].weightKg == 82.5)
        }
    }

    @Test func aRedeliveredLogIsStillRecognisedByTheRowWhenTheMemoryOfItIsGone() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let command = rig.log(sets[0], weight: 80, reps: 5, at: 600)
            rig.send(command)
            sets[1].weightKg = 70

            // The remembered log expires after a week and is dropped with the rest
            // of the defaults; the row itself still holds the completion, and that
            // alone has to stop the load being carried a second time.
            DroppedSetMemory.shared.replaceStore(with: TestClock.freshDefaults("memoryGone"))
            #expect(!DroppedSetMemory.shared.wasHeardLog(sets[0].id, loggedAt: rig.at(600)))
            rig.send(command)

            #expect(sameMoment(sets[0].completedAt, rig.at(600)))
            #expect(sets[1].weightKg == 70)
        }
    }

    @Test func aLogRedeliveredAfterThePhoneUndidItStaysUndone() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let command = rig.log(sets[0], at: 600)
            rig.send(command)
            sets[0].unlog()

            rig.send(command)

            #expect(!sets[0].isCompleted)
            #expect(sets[0].completedAt == nil)
        }
    }

    @Test func aWristUndoLeavesNoTraceOnTheSet() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let set = sets[0]
            rig.send(.announceStart(id: set.id, at: rig.at(590)))
            rig.send(rig.log(set, at: 600))
            rig.send(.rateSet(WatchSetRating(sessionID: set.session!.id, setID: set.id,
                                             completedAt: rig.at(600), rpe: SetFeel.hard.rawValue)))
            #expect(set.rpe == SetFeel.hard.rawValue)
            #expect(set.startedAt != nil)

            rig.send(.undoSet(id: set.id, completedAt: rig.at(600)))

            #expect(!set.isCompleted)
            #expect(set.completedAt == nil)
            #expect(set.rpe == nil)
            #expect(set.startedAt == nil)
        }
    }

    @Test func anUndoAimedAtAnEarlierLogIsRefusedAndAnUnstampedOneIsNot() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            rig.send(rig.log(sets[0], weight: 65, reps: 5, at: 700))

            rig.send(.undoSet(id: sets[0].id, completedAt: rig.at(600)))
            #expect(sets[0].isCompleted)
            #expect(sameMoment(sets[0].completedAt, rig.at(700)))

            // Sent by a watch older than stamped undos, which cannot say which
            // log it answers.
            rig.send(.undoSet(id: sets[0].id, completedAt: nil))
            #expect(!sets[0].isCompleted)
        }
    }

    @Test func anUndoThatArrivesBeforeItsLogKeepsThatLogOutButNotTheNextOne() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            rig.send(.undoSet(id: sets[0].id, completedAt: rig.at(600)))

            rig.send(rig.log(sets[0], at: 600))
            #expect(!sets[0].isCompleted)

            rig.send(rig.log(sets[0], at: 800))
            #expect(sets[0].isCompleted)
            #expect(sameMoment(sets[0].completedAt, rig.at(800)))
        }
    }

    @Test func aRatingIsKeptOnlyForTheLogItAnswers() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            @MainActor func rate(_ set: SetLog, at seconds: TimeInterval, _ rpe: Double?) {
                rig.send(.rateSet(WatchSetRating(sessionID: session.id, setID: set.id,
                                                 completedAt: rig.at(seconds), rpe: rpe)))
            }

            // Ahead of its log: the set is not logged yet, so there is nothing to rate.
            rate(sets[0], at: 600, 8)
            rig.send(rig.log(sets[0], at: 600))
            #expect(sets[0].rpe == nil)

            rate(sets[0], at: 605, 8)
            #expect(sets[0].rpe == nil)
            rate(sets[0], at: 600, 3)
            #expect(sets[0].rpe == nil)

            rate(sets[0], at: 600, SetFeel.allOut.rawValue)
            #expect(sets[0].rpe == SetFeel.allOut.rawValue)
            rate(sets[0], at: 600, nil)
            #expect(sets[0].rpe == nil)

            rate(sets[1], at: 600, 8)
            #expect(sets[1].rpe == nil)

            rate(sets[0], at: 600, SetFeel.solid.rawValue)
            rig.send(.undoSet(id: sets[0].id, completedAt: rig.at(600)))
            rate(sets[0], at: 600, SetFeel.solid.rawValue)
            #expect(sets[0].rpe == nil)
        }
    }

    // MARK: - Announcing a start

    @Test func aStartIsAnnouncedOnceOnAnUnloggedSetAndNeverFromTheFuture() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()

            rig.send(.announceStart(id: sets[0].id, at: rig.at(500)))
            rig.send(.announceStart(id: sets[0].id, at: rig.at(550)))
            #expect(sameMoment(sets[0].startedAt, rig.at(500)))

            rig.send(.announceStart(id: sets[1].id, at: Date.now.addingTimeInterval(3600)))
            #expect(sets[1].startedAt == nil)

            rig.send(rig.log(sets[2], at: 600))
            rig.send(.announceStart(id: sets[2].id, at: rig.at(610)))
            #expect(sets[2].startedAt == nil)

            rig.send(.cancelStart(id: sets[0].id))
            #expect(sets[0].startedAt == nil)
        }
    }

    // MARK: - Finishing

    enum Finish: CaseIterable, Sendable {
        case beforeTheLastSet, afterTheLastSet, inTheFuture, unstamped
    }

    @Test(arguments: Finish.allCases)
    func aFinishEndsNoEarlierThanTheLastSetAndNoLaterThanNow(_ finish: Finish) throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            let stamp: Date? = switch finish {
            case .beforeTheLastSet: rig.at(100)
            case .afterTheLastSet: rig.at(900)
            case .inTheFuture: Date.now.addingTimeInterval(3600)
            case .unstamped: nil
            }
            let batch = WatchFinishBatch(sessionID: session.id, logs: [], undos: [], starts: [:],
                                         cancels: [], ratings: [], endedAt: stamp)

            let before = Date.now
            rig.send(.finishSession(batch, metrics: nil))
            let after = Date.now

            #expect(!session.isActive)
            let end = try #require(session.endedAt)
            switch finish {
            case .beforeTheLastSet: #expect(sameMoment(end, rig.at(600)))
            case .afterTheLastSet: #expect(sameMoment(end, rig.at(900)))
            case .inTheFuture, .unstamped: #expect((before...after).contains(end))
            }
            // The rows nobody lifted go, as the phone's own Finish drops them.
            #expect(session.sets.map(\.id) == [sets[0].id])
        }
    }

    @Test func aFinishWithNothingLoggedIsADiscardAndOneWithASetIsKept() throws {
        try withRig { rig in
            let empty = try rig.seed().session
            rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: empty.id)))
            #expect(rig.sessions().isEmpty)

            let (kept, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: kept.id)))
            #expect(rig.sessions().count == 1)
            #expect(!kept.isActive)
            #expect(kept.completedSets.count == 1)
        }
    }

    @Test func aWristFinishReplaysItsLogsRatingsAndUndosThenClosesTheRest() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let first = sets[0].id, second = sets[1].id
            let batch = WatchFinishBatch(
                sessionID: session.id,
                logs: [WatchPendingLog(setID: first, weightKg: 80, reps: 5, seconds: 0, completedAt: rig.at(300)),
                       WatchPendingLog(setID: second, weightKg: 80, reps: 5, seconds: 0, completedAt: rig.at(400))],
                undos: [second], starts: [:], cancels: [],
                ratings: [WatchSetRating(sessionID: session.id, setID: first,
                                         completedAt: rig.at(300), rpe: SetFeel.hard.rawValue)],
                endedAt: rig.at(500))

            rig.send(.finishSession(batch, metrics: nil))

            #expect(!session.isActive)
            #expect(sameMoment(session.endedAt, rig.at(500)))
            #expect(session.sets.map(\.id) == [first])
            let kept = try #require(session.sets.first)
            #expect(kept.isCompleted)
            #expect(kept.weightKg == 80 && kept.reps == 5)
            #expect(sameMoment(kept.completedAt, rig.at(300)))
            #expect(kept.rpe == SetFeel.hard.rawValue)
        }
    }

    @Test func aDiscardRemovesOnlyTheSessionItNames() throws {
        try withRig { rig in
            let history = try rig.seed(startedAt: rig.at(-7200)).session
            let historySets = history.sets
            rig.complete(historySets[0], at: rig.at(-6600))
            history.close(at: rig.at(-3600), in: rig.context)
            let historyID = history.id

            let current = try rig.seed().session
            let currentID = current.id

            rig.send(.discardSession(id: UUID()))
            #expect(Set(rig.sessions().map(\.id)) == [historyID, currentID])

            rig.send(.discardSession(id: currentID))
            #expect(rig.sessions().map(\.id) == [historyID])
        }
    }

    // MARK: - Late logs

    enum Route: CaseIterable, Sendable { case headless, loggerRunning }

    @Test(arguments: Route.allCases)
    func aLogAfterTheFinishIsPutBackAndItsUndoTakesItOutAgain(_ route: Route) throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let late = sets[1].id, tooLate = sets[2].id
            @MainActor func deliver(_ command: WatchCommand) {
                switch route {
                case .headless: rig.center.applyHeadless(command)
                case .loggerRunning: rig.center.applyToFinishedSession(command)
                }
            }
            rig.send(rig.log(sets[0], at: 300))
            // The phone's own Finish, which deletes the rows nobody logged.
            session.close(at: rig.at(900), in: rig.context)
            try rig.context.save()
            #expect(session.sets.count == 1)

            deliver(.logSet(id: late, weightKg: 70, reps: 5, seconds: 0, at: rig.at(600)))
            let restored = try #require(session.sets.first { $0.id == late })
            #expect(restored.isCompleted)
            #expect(restored.weightKg == 70 && restored.reps == 5)
            #expect(sameMoment(restored.completedAt, rig.at(600)))
            #expect(sameMoment(session.endedAt, rig.at(900)))

            // Stamped after the session ended: not a lift the session could hold.
            deliver(.logSet(id: tooLate, weightKg: 70, reps: 5, seconds: 0, at: rig.at(1000)))
            #expect(!session.sets.contains { $0.id == tooLate })

            deliver(.undoSet(id: late, completedAt: rig.at(600)))
            #expect(session.sets.map(\.id) == [sets[0].id])
        }
    }

    // MARK: - Stale sessions

    @Test func aSessionLeftOpenPastTheStaleMarkIsClosedAtItsLastSetByTheNextMirror() throws {
        try withRig { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let (session, sets) = try rig.seed(startedAt: longAgo)
            rig.complete(sets[0], at: longAgo.addingTimeInterval(600))
            let last = sets[0].id

            rig.send(.requestMirror)

            #expect(!session.isActive)
            #expect(sameMoment(session.endedAt, longAgo.addingTimeInterval(600)))
            #expect(session.sets.map(\.id) == [last])
        }
    }

    @Test func aStaleSessionIsNotHandedBackAsTheOneRunningWhenAStartArrives() throws {
        try withRig { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let stale = try rig.seed(startedAt: longAgo).session
            let staleID = stale.id

            rig.send(.startFreestyle)

            // Nothing was logged in the stale one, so it is deleted rather than kept.
            let open = rig.sessions().filter(\.isActive)
            #expect(open.count == 1)
            #expect(open.first?.id != staleID)
            #expect(open.first?.title == "Freestyle Session")
            #expect(rig.sessions().count == 1)
        }
    }

    @Test func retiringSaysHowTheWristShouldHearTheSessionEnded() throws {
        try withRig { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let kept = try rig.seed(startedAt: longAgo).session
            rig.complete(kept.sets[0], at: longAgo.addingTimeInterval(60))
            let keptID = kept.id
            let empty = try rig.seed(startedAt: longAgo.addingTimeInterval(-1000)).session
            let emptyID = empty.id
            let fresh = try rig.seed().session

            #expect(rig.center.retire(fresh, in: rig.context) == nil)
            #expect(fresh.isActive)
            #expect(rig.center.retire(kept, in: rig.context)
                    == WatchSessionEnd(sessionID: keptID, reason: .finished))
            #expect(rig.center.retire(empty, in: rig.context)
                    == WatchSessionEnd(sessionID: emptyID, reason: .discarded))
        }
    }

    // MARK: - The two ways in

    @Test func whenTheScreenTakesACommandTheCenterLeavesTheStoreAlone() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let screen = Recorder()
            rig.center.uiHandler = { screen.commands.append($0); return true }

            rig.send(rig.log(sets[0], at: 600))
            rig.send(.startFreestyle)

            #expect(screen.commands.count == 2)
            #expect(!sets[0].isCompleted)
            #expect(rig.sessions().count == 1)
        }
    }

    @Test func whenTheScreenDeclinesACommandItFallsThroughToTheHeadlessPath() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let screen = Recorder()
            rig.center.uiHandler = { screen.commands.append($0); return false }

            rig.send(rig.log(sets[0], at: 600))

            #expect(screen.commands.count == 1)
            #expect(sets[0].isCompleted)
        }
    }

    @Test func aLogTheScreenTookIsRememberedSoALaterRedeliveryCannotResurrectIt() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            rig.center.uiHandler = { _ in true }
            // The logger wrote the row itself before the command was offered to it.
            rig.complete(sets[0], at: rig.at(600))

            rig.send(rig.log(sets[0], at: 600))
            sets[0].unlog()
            rig.center.uiHandler = nil
            rig.send(rig.log(sets[0], at: 600))

            #expect(DroppedSetMemory.shared.wasHeardLog(sets[0].id, loggedAt: rig.at(600)))
            #expect(!sets[0].isCompleted)
        }
    }

    // MARK: - Commands that repeat or have nothing to act on

    @Test(arguments: [WatchCommand.startFreestyle, .startToday])
    func aRedeliveredStartDoesNotOpenASecondSession(_ start: WatchCommand) throws {
        try withRig { rig in
            rig.send(start)
            rig.send(start)
            rig.send(.startFreestyle)
            rig.send(.startToday)

            let all = rig.sessions()
            #expect(all.count == 1)
            #expect(all.first?.isActive == true)
            #expect(all.first?.wasWatchDriven == true)
            #expect(all.first?.title == "Freestyle Session")
        }
    }

    static let ghost = UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!

    static let commandsForNothingThatExists: [WatchCommand] = [
        .logSet(id: ghost, weightKg: 60, reps: 8, seconds: 0, at: nil),
        .logSet(id: ghost, weightKg: 60, reps: 8, seconds: 0, at: TestClock.reference),
        .undoSet(id: ghost, completedAt: TestClock.reference),
        .undoSet(id: ghost, completedAt: nil),
        .rateSet(WatchSetRating(sessionID: ghost, setID: ghost, completedAt: TestClock.reference, rpe: 8)),
        .announceStart(id: ghost, at: TestClock.reference),
        .cancelStart(id: ghost),
        .addSet(catalogID: "not-in-this-session"),
        .focusExercise(catalogID: "not-in-this-session"),
        .finish(metrics: WatchWorkoutMetrics(sessionID: ghost)),
        .finish(metrics: nil),
        .finishSession(WatchFinishBatch(sessionID: ghost, logs: [], undos: [], starts: [:], cancels: [],
                                        ratings: []), metrics: nil),
        .discardSession(id: ghost),
        .discard,
        .metrics(WatchWorkoutMetrics(sessionID: ghost, currentHeartRate: 120)),
        .startRest(seconds: 60), .stopRest, .extendRest(seconds: 15),
    ]

    @Test(arguments: WatchCommandCenterHeadlessTests.commandsForNothingThatExists, [false, true])
    func aCommandForASessionThatIsGoneChangesNothing(_ command: WatchCommand, withARunningSession: Bool) throws {
        try withRig { rig in
            var runningID: UUID?
            if withARunningSession { runningID = try rig.seed().session.id }

            rig.send(command)

            let all = rig.sessions()
            #expect(all.map(\.id) == (runningID.map { [$0] } ?? []))
            #expect(all.first?.isActive ?? true)
            #expect(all.first?.preferredExerciseID == nil)
            let sets = rig.allSets()
            #expect(sets.count == (withARunningSession ? 3 : 0))
            #expect(sets.allSatisfy { !$0.isCompleted && $0.startedAt == nil && $0.rpe == nil })
        }
    }

    @Test func anAddedSetCopiesTheLastOneAndFocusNamesOnlyAnExerciseTheSessionHas() throws {
        try withRig { rig in
            let (session, _) = try rig.seed()

            rig.send(.addSet(catalogID: "test-bench"))
            #expect(session.sets.count == 4)
            let added = try #require(session.sets.max { $0.setIndex < $1.setIndex })
            #expect(added.setIndex == 3)
            #expect(added.weightKg == 60 && added.reps == 8)
            #expect(!added.isCompleted)

            rig.send(.addSet(catalogID: "test-squat"))
            #expect(session.sets.count == 4)

            rig.send(.focusExercise(catalogID: "test-bench"))
            #expect(session.preferredExerciseID == "test-bench")
            rig.send(.focusExercise(catalogID: "test-squat"))
            #expect(session.preferredExerciseID == nil)
        }
    }

    // MARK: - The mirror

    @Test(arguments: [(WeightUnit.kg, 1.25), (WeightUnit.lb, 2.5)])
    func theMirrorCarriesTheUnitAndEachMachinesScale(_ unit: WeightUnit, defaultStep: Double) throws {
        try withRig { rig in
            AppSettings.shared.weightUnit = unit
            AppSettings.shared.trackRPE = true
            let tuned = LoadScale(unit: unit, increment: 10)
            LoadScaleBook.shared.set(tuned, for: "test-leg-press")
            let (session, _) = try rig.seed(exercises: ["test-bench", "test-leg-press"])

            let snapshot = WatchSnapshotFactory.snapshot(
                for: session, rest: (nil, nil, 0), restSeconds: { _ in 90 }, lastTimeLabel: { _ in nil })

            #expect(snapshot.unit == unit)
            #expect(snapshot.effortEnabled == true)
            #expect(snapshot.exercises.map(\.id) == ["test-bench", "test-leg-press"])
            #expect(snapshot.exercises[0].scale == LoadScale(unit: unit, increment: defaultStep))
            #expect(snapshot.exercises[1].scale == tuned)
            #expect(snapshot.exercises[1].resolvedScale(sessionUnit: unit) == tuned)
            // Weights stay in kilograms on the wire; the scale is what shows them.
            let set = snapshot.exercises[0].sets[0]
            #expect(set.weightKg == 60)
            #expect(snapshot.exercises[0].resolvedScale(sessionUnit: unit).display(set.weightKg)
                    == unit.fromKg(60))
            #expect(snapshot.volumeKg == session.totalVolumeKg)
        }
    }

    // MARK: - Answers and undos that name another log

    @Test func anAnswerAboutAnotherCompletionDoesNotReplaceTheOneGiven() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            @MainActor func rate(at seconds: TimeInterval, _ feel: SetFeel) {
                rig.send(.rateSet(WatchSetRating(sessionID: session.id, setID: sets[0].id,
                                                 completedAt: rig.at(seconds), rpe: feel.rawValue)))
            }

            rate(at: 600, .hard)
            // About a log a minute before the one the row holds.
            rate(at: 540, .easy)

            #expect(sets[0].rpe == SetFeel.hard.rawValue)
        }
    }

    @Test func aLogTheWristTookBackStaysOutWhenAnotherCopyOfItArrives() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let command = rig.log(sets[0], at: 600)
            rig.send(command)
            rig.send(.undoSet(id: sets[0].id, completedAt: rig.at(600)))

            rig.send(command)

            #expect(!sets[0].isCompleted)
            #expect(sets[0].completedAt == nil)
        }
    }

    // MARK: - The load a wrist log carries

    @Test func aWristUndoPutsBackTheLoadItsLogCarriedDownTheCard() throws {
        try withRig { rig in
            let bench = try rig.seed(setsEach: 4).sets

            rig.send(rig.log(bench[0], weight: 65, at: 600))
            #expect(bench[1...].allSatisfy { $0.weightKg == 65 })
            rig.send(.undoSet(id: bench[0].id, completedAt: rig.at(600)))
            #expect(!bench[0].isCompleted)
            // A set never lifted leaves no load behind.
            #expect(bench[1...].allSatisfy { $0.weightKg == 60 })

            rig.send(rig.log(bench[0], weight: 67.5, at: 630))
            #expect(bench[1...].allSatisfy { $0.weightKg == 67.5 })
            // The first log's undo again, which the row no longer holds: nothing
            // is taken back, so nothing is put back either.
            rig.send(.undoSet(id: bench[0].id, completedAt: rig.at(600)))
            #expect(bench[0].isCompleted)
            #expect(bench[1...].allSatisfy { $0.weightKg == 67.5 })

            rig.send(.undoSet(id: bench[0].id, completedAt: rig.at(630)))
            #expect(bench[1...].allSatisfy { $0.weightKg == 60 })
        }
    }

    @Test func aRowTypedIntoSinceKeepsWhatWasTypedThroughAWristUndo() throws {
        try withRig { rig in
            let session = rig.session()
            let curl = (0..<3).map { rig.addRow("test-curl", index: $0, weightKg: 20, to: session) }
            try rig.context.save()

            rig.send(rig.log(curl[0], weight: 22.5, at: 600))
            curl[1].weightKg = 25
            rig.send(.undoSet(id: curl[0].id, completedAt: rig.at(600)))

            #expect(curl[1].weightKg == 25)
            // The row left alone goes back.
            #expect(curl[2].weightKg == 20)
        }
    }

    @Test func aLogThatCarriedNothingHasNothingToPutBack() throws {
        try withRig { rig in
            let session = rig.session()
            let rows = (0..<2).map { rig.addRow("test-row", index: $0, weightKg: 50, to: session) }
            try rig.context.save()

            rig.send(rig.log(rows[0], weight: 50, at: 600))
            rig.send(.undoSet(id: rows[0].id, completedAt: rig.at(600)))

            #expect(!rows[0].isCompleted)
            #expect(rows[1].weightKg == 50)
        }
    }

    @Test func aTimedSetCarriesItsHoldDownTheCardAndItsUndoTakesItBack() throws {
        try withRig { rig in
            let session = rig.session()
            let plank = (0..<3).map {
                rig.addRow("test-plank", index: $0, weightKg: 0, seconds: 30, tracking: .duration, to: session)
            }
            try rig.context.save()

            rig.send(.logSet(id: plank[0].id, weightKg: 0, reps: 0, seconds: 45, at: rig.at(600)))
            #expect(plank[1...].allSatisfy { $0.seconds == 45 })
            rig.send(.undoSet(id: plank[0].id, completedAt: rig.at(600)))
            #expect(plank[1...].allSatisfy { $0.seconds == 30 })
        }
    }

    @Test func aLogRedeliveredAfterThePhoneUndidItCarriesNothingAndALaterStampIsStillTaken() throws {
        try withRig { rig in
            let press = try rig.seed().sets
            let command = rig.log(press[0], at: 600)
            rig.send(command)
            press[0].unlog()
            // Dialled by hand once the set was taken back.
            press[1].weightKg = 70

            rig.send(command)
            #expect(press[1].weightKg == 70)
            #expect(press[2].weightKg == 62.5)

            // A genuine re-log, stamped anew.
            rig.send(rig.log(press[0], at: 620))
            #expect(press[0].isCompleted)
        }
    }

    @Test func aLogRedeliveredAfterTheLoggerOnScreenUndidItStaysUndone() throws {
        try withRig { rig in
            let (session, squat) = try rig.seed()
            let logger = rig.logger(for: session)
            rig.center.uiHandler = { logger.apply($0) }
            let command = rig.log(squat[0], weight: 62.5, at: 600)

            rig.send(command)
            #expect(squat[0].isCompleted)
            logger.uncomplete(squat[0])
            #expect(!squat[0].isCompleted)

            rig.send(command)
            #expect(!squat[0].isCompleted)
            // Answered as handled, so nothing else is owed it.
            #expect(logger.apply(command))
            #expect(!squat[0].isCompleted)
            #expect(squat[1...].allSatisfy { $0.weightKg == 60 })

            // Stamped anew, it is a new lift.
            rig.send(rig.log(squat[0], weight: 62.5, at: 605))
            #expect(squat[0].isCompleted)
        }
    }

    /// A day that repeats a movement prescribes each slot its own load. A top
    /// set logged on the wrist used to be carried onto the back-off sets as
    /// well, which the phone's logger has not done since SESS-01.
    @Test func aWristLogCarriesItsLoadOnlyAsFarAsTheEndOfItsSlot() throws {
        try withRig { rig in
            let plan = Plan(name: "Repeated slots")
            let day = PlanDay(name: "Strength", order: 0)
            day.plan = plan
            rig.context.insert(plan)
            rig.context.insert(day)
            for (order, count, load, reps) in [(0, 2, 30.0, 6), (1, 3, 45.0, 10)] {
                let item = PlanItem(catalogID: "test-repeat", name: "test-repeat", order: order,
                                    targetSets: count, targetRepsLow: reps, targetRepsHigh: reps,
                                    targetWeightKg: load)
                item.day = day
                rig.context.insert(item)
            }
            let session = SessionFactory.build(day: day, plan: plan, context: rig.context, history: [])
            session.startedAt = rig.started
            try rig.context.save()
            let built = session.sets.sorted(by: SetLog.precedesInSession)
            // The top pair, then the back-off three.
            try #require(built.map(\.reps) == [6, 6, 10, 10, 10])
            let backOffLoads = built[2...].map(\.weightKg)
            let loggedLoad = built[0].weightKg + 12.5

            rig.send(.logSet(id: built[0].id, weightKg: loggedLoad, reps: 6, seconds: 0, at: rig.at(600)))

            let stored = built.compactMap { rig.stored($0.id) }
            try #require(stored.count == 5)
            #expect(stored[0].isCompleted && stored[0].weightKg == loggedLoad)
            #expect(stored[1].weightKg == loggedLoad)
            #expect(stored[2...].map(\.weightKg) == backOffLoads)
        }
    }

    // MARK: - Starting, finishing and discarding, continued

    @Test func aStartWhileASessionIsRunningHandsBackThatSession() throws {
        try withRig { rig in
            let runningID = try rig.seed().session.id

            rig.send(.startFreestyle)
            rig.send(.startToday)

            #expect(rig.sessions().filter(\.isActive).map(\.id) == [runningID])
        }
    }

    @Test func aFinishFilesTheWatchsHeartRateAndARepeatOfItChangesNothing() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            var metrics = WatchWorkoutMetrics(sessionID: session.id)
            metrics.averageHeartRate = 118

            rig.send(.finish(metrics: metrics))
            #expect(!session.isActive)
            #expect(session.averageHeartRate == 118)
            let ended = session.endedAt

            rig.send(.finish(metrics: metrics))
            #expect(rig.sessions().map(\.id) == [session.id])
            #expect(session.endedAt == ended)
            #expect(session.completedSets.map(\.id) == [sets[0].id])
        }
    }

    @Test func aDiscardedSessionTakesItsRowsWithIt() throws {
        try withRig { rig in
            let sessionID = try rig.seed().session.id

            rig.send(.discardSession(id: sessionID))

            #expect(rig.sessions().isEmpty)
            #expect(try rig.reader().fetchCount(FetchDescriptor<SetLog>()) == 0)
        }
    }

    // MARK: - The two ways in, continued

    @Test func aCommandTheScreenTakesIsAppliedByTheLoggerOnIt() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let logger = rig.logger(for: session)
            let screen = Recorder()
            rig.center.uiHandler = { screen.commands.append($0); return logger.apply($0) }

            rig.send(rig.log(sets[0], weight: 55, reps: 8, at: 600))

            #expect(screen.commands.count == 1)
            #expect(sets[0].isCompleted)
            #expect(sets[0].weightKg == 55 && sets[0].reps == 8)
        }
    }

    /// LINK-09: the center used to write through a context of its own, and
    /// rows saved through one were not always visible in the other.
    @Test func theHeadlessPathFindsASessionSavedThroughAnotherContext() throws {
        try withRig { rig in
            let elsewhere = rig.reader()
            let late = WorkoutSession(title: "Added elsewhere", startedAt: rig.started)
            elsewhere.insert(late)
            try elsewhere.save()

            rig.send(.discardSession(id: late.id))

            #expect(rig.sessions().isEmpty)
        }
    }

    /// The headless path asks only for open sessions. The real recovery must
    /// still find the finished workout an empty duplicate sits inside.
    @Test func anUntouchedDuplicateInsideAFinishedSessionGoesBeforeACommandCanLogIntoIt() throws {
        try withRig { rig in
            let base = rig.started.addingTimeInterval(-2 * 3600)
            let finished = rig.session("Done", startedAt: base)
            finished.endedAt = base.addingTimeInterval(3600)
            let duplicate = rig.session("Duplicate", startedAt: base.addingTimeInterval(1800))
            let apart = rig.session("Later", startedAt: base.addingTimeInterval(2 * 3600))
            try rig.context.save()
            @MainActor func storedTitles() throws -> [String] {
                try rig.reader().fetch(FetchDescriptor<WorkoutSession>()).map(\.title).sorted()
            }

            let kept = WatchSessionRecovery.discardUntouchedOverlaps([duplicate, apart], in: rig.context)
            #expect(kept.map(\.title) == ["Later"])
            #expect(try storedTitles() == ["Done", "Later"])

            let ghost = rig.session("Ghost", startedAt: base.addingTimeInterval(600))
            let row = rig.addRow(index: 0, weightKg: 50, to: ghost)
            try rig.context.save()
            rig.send(.logSet(id: row.id, weightKg: 50, reps: 8, seconds: 0, at: rig.at(600)))

            #expect(try storedTitles() == ["Done", "Later"])
        }
    }

    // MARK: - Which plan a start from the wrist begins

    enum ActivePlan: CaseIterable, Sendable { case neither, newer, older }

    /// Saved one at a time, in both orders, so whichever plan an unsorted
    /// fetch hands back first, one of the cases has the wrong one there.
    @Test(arguments: ActivePlan.allCases, [true, false])
    func aStartFromTheWristBeginsThePlanTodayShows(_ active: ActivePlan, newerSavedFirst: Bool) throws {
        try withRig { rig in
            @MainActor func save(_ name: String, createdAt: Date, isActive: Bool) throws {
                let plan = Plan(name: name, isActive: isActive)
                plan.createdAt = createdAt
                let day = PlanDay(name: name + " day", order: 0)
                day.plan = plan
                rig.context.insert(plan)
                rig.context.insert(day)
                let item = PlanItem(catalogID: "test-bench", name: "test-bench", order: 0, targetSets: 2,
                                    targetRepsLow: 8, targetRepsHigh: 8, targetWeightKg: 50)
                item.day = day
                rig.context.insert(item)
                try rig.context.save()
            }
            let newer = ("Newer", rig.at(-100), active == .newer)
            let older = ("Older", rig.at(-200), active == .older)
            for (name, createdAt, isActive) in newerSavedFirst ? [newer, older] : [older, newer] {
                try save(name, createdAt: createdAt, isActive: isActive)
            }

            rig.send(.startToday)

            let sessions = rig.sessions()
            #expect(sessions.count == 1)
            let days = try rig.context.fetch(FetchDescriptor<PlanDay>())
            let begun = days.first { $0.id == sessions.first?.planDayID }?.name
            #expect(begun == (active == .newer ? "Newer day" : "Older day"))
        }
    }

    // MARK: - The logger's memory on the way out

    /// Something for the store to hold, of the kind a phone logger leaves.
    static func carry(by setID: UUID, onto rowID: UUID) -> LoggerMemory {
        LoggerMemory(carries: [.init(setID: setID, rows: [
            .init(rowID: rowID, kg: 100, seconds: 0, carriedKg: 105, carriedSeconds: 0),
        ])])
    }

    enum HeadlessEnd: CaseIterable, Sendable { case finish, finishBatch, emptyFinish, discard, staleRetire }

    /// No logger is left to clear it, and a key that outlived its session would
    /// be the one thing in the app still remembering sets nobody holds.
    @Test(arguments: HeadlessEnd.allCases)
    func everyEndOnThisPathClearsTheLoggersMemoryOfThatSessionAlone(_ end: HeadlessEnd) throws {
        try withRig { rig in
            let bystander = UUID()
            rig.loggerMemory.save(Self.carry(by: UUID(), onto: UUID()), for: bystander)
            let startedAt = end == .staleRetire
                ? rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600)) : rig.started
            let (session, sets) = try rig.seed(setsEach: 2, startedAt: startedAt)
            if end != .emptyFinish { rig.complete(sets[0], at: startedAt.addingTimeInterval(60)) }
            try rig.context.save()
            let sessionID = session.id
            rig.loggerMemory.save(Self.carry(by: sets[0].id, onto: sets[1].id), for: sessionID)
            try #require(rig.loggerMemory.load(for: sessionID) != nil)

            switch end {
            case .finish, .emptyFinish:
                rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: sessionID)))
            case .finishBatch:
                rig.send(.finishSession(finishBatch(sessionID), metrics: nil))
            case .discard:
                rig.send(.discardSession(id: sessionID))
            case .staleRetire:
                rig.center.retire(session, in: rig.context)
            }

            #expect(rig.loggerMemory.load(for: sessionID) == nil)
            #expect(rig.loggerMemory.load(for: bystander) != nil)
            switch end {
            case .finish, .finishBatch, .staleRetire: #expect(session.endedAt != nil)
            case .emptyFinish, .discard: #expect(rig.sessions().isEmpty)
            }
        }
    }

    @Test func aCarryThePhonesLoggerMadeIsPutBackByAWristUndo() throws {
        try withRig { rig in
            let (session, rows) = try rig.seed(setsEach: 4)
            // The phone's logger logs the top set, carrying its load down, and is
            // then gone: the app was reclaimed while the phone was down.
            do {
                let logger = ActiveWorkout(session: session, context: rig.context, history: [],
                                           memory: rig.loggerMemory)
                defer { logger.restTimer.stop() }
                rows[0].weightKg = 65
                logger.complete(rows[0], restSeconds: nil, at: rig.at(600))
            }
            try #require(rows[1...].allSatisfy { $0.weightKg == 65 })
            try #require(rig.loggerMemory.load(for: session.id)?.carries.isEmpty == false)
            rows[2].weightKg = 70

            rig.send(.undoSet(id: rows[0].id, completedAt: rows[0].completedAt))

            #expect(!rows[0].isCompleted)
            #expect(rows[1].weightKg == 60 && rows[3].weightKg == 60)
            #expect(rows[2].weightKg == 70)
            // Spent, so it cannot put a weight back twice.
            #expect(rig.loggerMemory.load(for: session.id)?.carries.isEmpty ?? true)
        }
    }

    // MARK: - Late logs

    @Test func aLogAfterThePhonesFinishPutsItsRowBackAsItWasAndNothingElse() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()
            let end = closed.end
            try #require(rig.stored(closed.press) == nil)

            rig.send(wristLog(closed.press, at: end.addingTimeInterval(-240)))
            let press = try #require(rig.stored(closed.press))
            #expect(press.session?.id == closed.session)
            #expect(press.isCompleted)
            // The wrist's moment, not the moment it arrived.
            #expect(press.completedAt == end.addingTimeInterval(-240))
            #expect(press.weightKg == 62.5 && press.reps == 9 && press.seconds == 0)
            #expect(press.trackingRaw == TrackingMode.weightReps.rawValue)
            #expect(press.setIndex == 1 && press.exerciseOrder == 0 && press.catalogID == "test-bench")
            #expect(press.targetRepsLow == 6 && press.targetRepsHigh == 10)
            #expect(press.startedAt == end.addingTimeInterval(-300))
            // Nothing the wrist didn't send is invented.
            #expect(press.rpe == nil && !press.hasHeartRate)

            rig.send(wristLog(closed.drop, weightKg: 45, reps: 6, at: end.addingTimeInterval(-200)))
            // A drop whose parent came back is still a drop.
            #expect(rig.stored(closed.drop)?.continuesPreviousSet == true)

            rig.send(wristLog(closed.plank, weightKg: 0, reps: 0, seconds: 50, at: end.addingTimeInterval(-100)))
            let plank = try #require(rig.stored(closed.plank))
            #expect(plank.seconds == 50 && plank.trackingRaw == TrackingMode.duration.rawValue)

            rig.send(wristLog(closed.press, weightKg: 99, at: end.addingTimeInterval(-240)))
            #expect(rig.stored(closed.press)?.weightKg == 62.5)
            // A row nobody lifted stays gone.
            #expect(rig.stored(closed.spare) == nil)

            rig.send(.rateSet(WatchSetRating(sessionID: closed.session, setID: closed.press,
                                             completedAt: end.addingTimeInterval(-240), rpe: 8)))
            #expect(rig.stored(closed.press)?.rpe == 8)
        }
    }

    @Test func aRowPutBackAndTakenBackLeavesForGoodAndItsDropStandsAlone() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()
            let end = closed.end
            rig.send(wristLog(closed.press, at: end.addingTimeInterval(-240)))
            rig.send(wristLog(closed.drop, weightKg: 45, reps: 6, at: end.addingTimeInterval(-200)))
            rig.send(wristLog(closed.plank, weightKg: 0, reps: 0, seconds: 50, at: end.addingTimeInterval(-100)))

            rig.send(.undoSet(id: closed.plank, completedAt: nil))
            #expect(rig.stored(closed.plank) == nil)
            // A set taken back cannot be put back again.
            rig.send(wristLog(closed.plank, seconds: 50, at: end.addingTimeInterval(-100)))
            #expect(rig.stored(closed.plank) == nil)

            rig.send(.undoSet(id: closed.press, completedAt: nil))
            #expect(rig.stored(closed.press) == nil)
            // A set of its own now, not a drop off whichever set sits above it.
            let drop = try #require(rig.stored(closed.drop))
            #expect(drop.continuesPreviousSet == nil)

            // A set the phone closed as logged is never rewritten by a queued command.
            rig.send(.undoSet(id: closed.logged, completedAt: nil))
            #expect(rig.stored(closed.logged)?.isCompleted == true)
        }
    }

    @Test func aLateLogStampedAfterTheEndOrNotAtAllIsNoCopyOfAnythingTheSessionHeld() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()

            rig.send(wristLog(closed.press, at: closed.end.addingTimeInterval(5)))
            rig.send(wristLog(closed.drop, at: nil))

            #expect(rig.stored(closed.press) == nil)
            // No stamp reads as now, which is after the end.
            #expect(rig.stored(closed.drop) == nil)
        }
    }

    /// The two channels the wrist sends on are not ordered.
    @Test func anUndoThatOvertookItsLateLogLeavesNoTrace() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()

            rig.send(.undoSet(id: closed.press, completedAt: nil))
            rig.send(wristLog(closed.press, at: closed.end.addingTimeInterval(-240)))

            #expect(rig.stored(closed.press) == nil)
        }
    }

    @Test func theWristsOwnFinishLandingAfterThePhonesPutsBackItsLogsAndHonoursItsUndos() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()
            let end = closed.end
            let batch = finishBatch(
                closed.session,
                logs: [pendingLog(closed.press, at: end.addingTimeInterval(-240)),
                       pendingLog(closed.drop, weightKg: 45, reps: 6, at: end.addingTimeInterval(-200)),
                       pendingLog(closed.plank, weightKg: 0, reps: 0, seconds: 50, at: end.addingTimeInterval(-100))],
                undos: [closed.plank],
                starts: [closed.drop: end.addingTimeInterval(-210)])

            rig.send(.finishSession(batch, metrics: nil))

            let press = try #require(rig.stored(closed.press))
            #expect(press.isCompleted && press.completedAt == end.addingTimeInterval(-240))
            let drop = try #require(rig.stored(closed.drop))
            #expect(drop.isCompleted && drop.startedAt == end.addingTimeInterval(-210))
            #expect(rig.stored(closed.plank) == nil)
            // A queued log cannot undo the batch's undo.
            rig.send(wristLog(closed.plank, seconds: 50, at: end.addingTimeInterval(-100)))
            #expect(rig.stored(closed.plank) == nil)
        }
    }

    @Test func aLateLogForASessionDeletedSinceRecreatesNothing() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()
            let screen = rig.reader()
            for session in try screen.fetch(FetchDescriptor<WorkoutSession>()) { screen.delete(session) }
            try screen.save()

            rig.send(wristLog(closed.press, at: closed.end.addingTimeInterval(-240)))

            #expect(rig.stored(closed.press) == nil)
        }
    }

    /// `DroppedSetMemory` stamps a row with the wall clock when it drops it, so
    /// the week is counted from now.
    @Test func theMemoryOfARowTheCloseDroppedLastsAWeekAndOutlivesARelaunch() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()
            // A relaunch: the memory reads its store afresh, and the center is set up again.
            DroppedSetMemory.shared.replaceStore(with: rig.defaults)
            rig.center.configure(container: rig.container)

            #expect(DroppedSetMemory.shared.row(for: closed.spare, now: .now.addingTimeInterval(6 * 86400)) != nil)
            #expect(DroppedSetMemory.shared.row(for: closed.spare, now: .now.addingTimeInterval(8 * 86400)) == nil)
            rig.send(wristLog(closed.press, at: closed.end.addingTimeInterval(-240)))
            #expect(rig.stored(closed.press)?.isCompleted == true)
        }
    }

    /// Every row the wrist counted was in its own Finish batch, so a later log
    /// for one it left unlogged is a stale one.
    @Test func aSessionTheWristsOwnFinishClosedKeepsNoMemoryOfItsRows() throws {
        try withRig { rig in
            let session = rig.session("Wrist finish")
            let takenID = rig.addRow(index: 0, to: session).id
            try rig.context.save()
            session.applyWatchFinish(finishBatch(session.id, undos: [takenID]))
            session.close(at: rig.ago(10), in: rig.context)
            try rig.context.save()

            #expect(DroppedSetMemory.shared.row(for: takenID) == nil)
            rig.send(wristLog(takenID, at: rig.ago(60)))
            #expect(rig.stored(takenID) == nil)
        }
    }

    @Test func withALoggerOnScreenALateLogReachesTheFinishedSessionAndNothingElse() throws {
        try withRig { rig in
            let closed = try rig.closeOneSetIn()
            // Opened after the close, so it is no duplicate of the finished one.
            let running = rig.session("Next workout", startedAt: rig.ago(5))
            let next = rig.addRow("test-squat", index: 0, to: running)
            try rig.context.save()
            let logger = rig.logger(for: running)
            let late = wristLog(closed.press, at: closed.end.addingTimeInterval(-240))

            // The logger has no row for either, and must not swallow them.
            #expect(!logger.apply(late))
            #expect(!logger.apply(.undoSet(id: closed.drop, completedAt: nil)))
            rig.center.applyToFinishedSession(late)

            #expect(rig.stored(closed.press)?.session?.id == closed.session)
            #expect(!next.isCompleted)
            #expect(running.sets.count == 1)
        }
    }

    /// The wrist's Finish still holds a log the phone applied and the lifter
    /// then took back on the phone, and must not return it. A log the phone
    /// never heard, in the same batch, still lands.
    @Test func aSetThePhoneTookBackStaysTakenBackThroughTheWristsFinish() throws {
        try withRig { rig in
            let session = rig.session("Undo then finish")
            let undone = rig.addRow(index: 0, to: session)
            let unheard = rig.addRow(index: 1, to: session)
            try rig.context.save()
            let ids = (undone: undone.id, unheard: unheard.id, session: session.id)
            let heardAt = rig.ago(300)

            rig.send(wristLog(ids.undone, at: heardAt))
            try #require(undone.isCompleted)
            undone.unlog()
            try rig.context.save()
            rig.send(.finishSession(finishBatch(ids.session, logs: [pendingLog(ids.undone, at: heardAt),
                                                                    pendingLog(ids.unheard, at: rig.ago(200))]),
                                    metrics: nil))

            #expect(rig.stored(ids.undone) == nil)
            #expect(rig.stored(ids.unheard)?.isCompleted == true)
        }
    }

    /// The same after the phone's own Finish: the row it dropped as unlogged is
    /// not owed to a copy of a log it already had, as a batch or a queued log.
    @Test func aRowThePhoneDroppedAfterItsOwnUndoIsNotOwedToACopyOfThatLog() throws {
        try withRig { rig in
            let session = rig.session("Undo, phone finish")
            let undone = rig.addRow(index: 0, to: session)
            let unheard = rig.addRow(index: 1, to: session)
            try rig.context.save()
            let ids = (undone: undone.id, unheard: unheard.id, session: session.id)
            let heardAt = rig.ago(300)

            rig.send(wristLog(ids.undone, at: heardAt))
            undone.unlog()
            session.close(at: rig.ago(10), in: rig.context)
            try rig.context.save()
            // The undone row was dropped at the close.
            try #require(DroppedSetMemory.shared.row(for: ids.undone) != nil)

            rig.send(wristLog(ids.undone, at: heardAt))
            #expect(rig.stored(ids.undone) == nil)
            rig.send(.finishSession(finishBatch(ids.session, logs: [pendingLog(ids.undone, at: heardAt),
                                                                    pendingLog(ids.unheard, at: rig.ago(200))]),
                                    metrics: nil))
            #expect(rig.stored(ids.undone) == nil)
            // A lift the phone never heard is still put back.
            #expect(rig.stored(ids.unheard)?.isCompleted == true)
        }
    }

    @Test func aLateLogItsUndoAndARelogLandWhicheverOrderTheFirstTwoArriveIn() throws {
        try withRig { rig in
            let session = rig.session("Late trio")
            let rows = (0..<3).map { rig.addRow(index: $0, to: session).id }
            try rig.context.save()
            session.close(at: rig.ago(10), in: rig.context)
            try rig.context.save()
            let (inOrder, overtaken, legacy) = (rows[0], rows[1], rows[2])
            let first = rig.ago(300), second = rig.ago(200)

            rig.send(wristLog(inOrder, weightKg: 60, at: first))
            #expect(rig.stored(inOrder)?.isCompleted == true)
            rig.send(.undoSet(id: inOrder, completedAt: first))
            #expect(rig.stored(inOrder) == nil)
            // The log that was taken back stays taken back,
            rig.send(wristLog(inOrder, weightKg: 60, at: first))
            #expect(rig.stored(inOrder) == nil)
            // and the re-log is not lost behind its undo.
            rig.send(wristLog(inOrder, weightKg: 65, at: second))
            #expect(rig.stored(inOrder)?.weightKg == 65)
            #expect(rig.stored(inOrder)?.completedAt == second)

            // An undo that overtook its log still wins, and the re-log after it lands.
            rig.send(.undoSet(id: overtaken, completedAt: first))
            rig.send(wristLog(overtaken, weightKg: 60, at: first))
            #expect(rig.stored(overtaken) == nil)
            rig.send(wristLog(overtaken, weightKg: 65, at: second))
            #expect(rig.stored(overtaken)?.completedAt == second)

            // An undo with no stamp still takes the row with it.
            rig.send(.undoSet(id: legacy, completedAt: nil))
            rig.send(wristLog(legacy, at: first))
            #expect(rig.stored(legacy) == nil)
        }
    }

    // MARK: - Starts, held to the live rules

    @Test func aFocusOnAnotherExerciseDropsTheStartAnnouncedOnThisOne() throws {
        try withRig { rig in
            let session = rig.session("Focus")
            let bench = rig.addRow("test-bench", index: 0, to: session)
            let squat = rig.addRow("test-squat", order: 1, index: 0, to: session)
            bench.startedAt = rig.ago(60)
            try rig.context.save()

            // An exercise the session lacks moves nothing.
            rig.send(.focusExercise(catalogID: "test-deadlift"))
            #expect(bench.startedAt != nil)
            rig.send(.focusExercise(catalogID: "test-squat"))
            #expect(bench.startedAt == nil)
            // Focusing where the set already is keeps its start.
            squat.startedAt = rig.ago(30)
            rig.send(.focusExercise(catalogID: "test-squat"))
            #expect(squat.startedAt != nil)
        }
    }

    @Test func aFinishBatchHoldsTheStartsItReplaysToTheLiveRules() throws {
        try withRig { rig in
            let session = rig.session("Batch")
            let slow = rig.addRow("test-bench", index: 0, to: session)
            let quick = rig.addRow("test-bench", index: 1, to: session)
            let abandoned = rig.addRow("test-squat", order: 1, index: 0, to: session)
            let survivor = rig.addRow("test-squat", order: 1, index: 1, to: session)
            try rig.context.save()
            let slowLog = rig.ago(600), quickLog = rig.ago(400)

            session.applyWatchFinish(finishBatch(
                session.id,
                logs: [pendingLog(slow.id, at: slowLog), pendingLog(quick.id, at: quickLog)],
                starts: [slow.id: slowLog.addingTimeInterval(-1200), quick.id: quickLog.addingTimeInterval(-70),
                         abandoned.id: rig.ago(900), survivor.id: rig.ago(100)]))

            // Twenty minutes before its log is not a set's length.
            #expect(slow.isCompleted && slow.startedAt == nil)
            #expect(quick.startedAt == quickLog.addingTimeInterval(-70))
            // Overtaken by another set's later log, as it is when live.
            #expect(abandoned.startedAt == nil)
            // Under way when the batch was sent.
            #expect(survivor.startedAt == rig.ago(100))
        }
    }

    @Test func aRowPutBackAfterTheCloseKeepsOnlyAStartItsLogCouldFollow() throws {
        try withRig { rig in
            let session = rig.session("Closed")
            rig.complete(rig.addRow(index: 0, to: session), at: rig.ago(900))
            let liveLate = rig.addRow(index: 1, to: session)
            let batchLate = rig.addRow(index: 2, to: session)
            liveLate.startedAt = rig.ago(1700)
            batchLate.startedAt = rig.ago(1600)
            try rig.context.save()
            let ids = (live: liveLate.id, batch: batchLate.id, session: session.id)
            session.close(at: rig.ago(10), in: rig.context)
            try rig.context.save()

            rig.send(wristLog(ids.live, at: rig.ago(300)))
            let live = try #require(rig.stored(ids.live))
            #expect(live.isCompleted)
            // Remembered from before the close, and too old for the log.
            #expect(live.startedAt == nil)

            rig.send(.finishSession(finishBatch(ids.session, logs: [pendingLog(ids.batch, at: rig.ago(200))],
                                                starts: [ids.batch: rig.ago(1600)]), metrics: nil))
            let replayed = try #require(rig.stored(ids.batch))
            #expect(replayed.isCompleted)
            #expect(replayed.startedAt == nil)
        }
    }

    // MARK: - Starts stored before the rules

    @Test func startsNoSetCouldHaveFilledAreDroppedOnceAndOnlyThose() throws {
        try withRig { rig in
            let logged = rig.ago(3600)
            let session = rig.session("History", startedAt: logged.addingTimeInterval(-1800))
            let honest = rig.addRow(index: 0, to: session)
            let detour = rig.addRow(index: 1, to: session)
            let backwards = rig.addRow(index: 2, to: session)
            let open = rig.addRow(index: 3, to: session)
            for set in [honest, detour, backwards] { rig.complete(set, at: logged) }
            honest.startedAt = logged.addingTimeInterval(-90)
            detour.startedAt = logged.addingTimeInterval(-1500)
            backwards.startedAt = logged.addingTimeInterval(30)
            open.startedAt = rig.ago(3000)
            try rig.context.save()
            let once = rig.freshDefaults("once")

            rig.center.repairStoredStartsOnce(in: rig.context, defaults: once)
            #expect(honest.startedAt == logged.addingTimeInterval(-90))
            // Too old for its log: dropped, not shortened.
            #expect(detour.startedAt == nil)
            // After its own log.
            #expect(backwards.startedAt == nil)
            // A set still open is not the repair's to judge.
            #expect(open.startedAt != nil)
            #expect(detour.isCompleted && detour.completedAt == logged)

            detour.startedAt = logged.addingTimeInterval(-1500)
            rig.center.repairStoredStartsOnce(in: rig.context, defaults: once)
            #expect(detour.startedAt != nil)
            #expect(SetLog.dropImplausibleStoredStarts(in: rig.context) == 1)
        }
    }

    @Test func overtakenStartsAreRepairedOnceFromTheStampsAlone() throws {
        try withRig { rig in
            let base = rig.at(60)
            func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }
            let session = rig.session("History", startedAt: at(-60))
            @MainActor @discardableResult
            func row(_ index: Int, of owner: WorkoutSession? = nil, start: TimeInterval? = nil,
                     loggedAt logged: TimeInterval? = nil) -> SetLog {
                let set = rig.addRow(index: index, to: owner ?? session)
                set.startedAt = start.map(at)
                if let logged { rig.complete(set, at: at(logged)) }
                return set
            }
            // Started at 0 and logged at 100, with another set logged at 50 between.
            let overtaken = row(0, start: 0, loggedAt: 100)
            let between = row(1, loggedAt: 50)
            // Nothing logged inside its own start and log.
            let clear = row(2, start: 200, loggedAt: 260)
            row(3, loggedAt: 300)
            // Another set logged the very instant this one was, and one the
            // instant it started: neither is strictly inside.
            let tied = row(4, start: 400, loggedAt: 460)
            row(5, loggedAt: 460)
            let sameStart = row(6, loggedAt: 400)
            // Another session's log at a moment inside is not this session's set.
            let other = rig.session("Elsewhere", startedAt: at(-60))
            row(7, of: other, loggedAt: 550)
            let lonely = row(8, start: 500, loggedAt: 560)
            // Started and never logged.
            let open = row(9, start: 20)
            try rig.context.save()
            // A phone the first repair already ran on, as every updated one has.
            let defaults = rig.freshDefaults("overtaken")
            defaults.set(true, forKey: "implausibleStartsRepaired")

            rig.center.repairStoredStartsOnce(in: rig.context, defaults: defaults)
            #expect(overtaken.startedAt == nil)
            // Only the start goes.
            #expect(overtaken.isCompleted && overtaken.completedAt == at(100))
            #expect(between.startedAt == nil && between.isCompleted)
            #expect(clear.startedAt == at(200))
            // Arrival order would decide a tie, and that is not stored.
            #expect(tied.startedAt == at(400))
            #expect(sameStart.startedAt == nil && sameStart.isCompleted)
            #expect(lonely.startedAt == at(500))
            #expect(open.startedAt == at(20))

            overtaken.startedAt = at(0)
            rig.center.repairStoredStartsOnce(in: rig.context, defaults: defaults)
            #expect(overtaken.startedAt == at(0))
            #expect(SetLog.dropOvertakenStoredStarts(in: rig.context) == 1)
        }
    }

    // MARK: - The start rules, pinned

    struct PlausibleLength: Sendable, CustomTestStringConvertible {
        let tracking: TrackingMode
        let amount: Int
        let bound: TimeInterval
        var testDescription: String { "\(tracking) \(amount)" }
    }

    nonisolated static let plausibleLengths: [PlausibleLength] = [
        .init(tracking: .weightReps, amount: 1, bound: 180), .init(tracking: .weightReps, amount: 12, bound: 180),
        .init(tracking: .weightReps, amount: 18, bound: 240), .init(tracking: .weightReps, amount: 30, bound: 360),
        .init(tracking: .duration, amount: 10, bound: 180), .init(tracking: .duration, amount: 45, bound: 180),
        .init(tracking: .duration, amount: 120, bound: 300),
    ]

    /// The rules have one copy, in `SessionClosing`, which the logger and the
    /// replay both call. Literal numbers here, so a change to the cap fails
    /// here and not silently in both paths at once.
    @Test(arguments: WatchCommandCenterHeadlessTests.plausibleLengths)
    func theLongestASetCanTakeIsPinned(_ length: PlausibleLength) {
        let timed = length.tracking == .duration
        let set = SetLog(catalogID: "test-x", exerciseName: "test-x", exerciseOrder: 0, setIndex: 0,
                         weightKg: 0, reps: timed ? 0 : length.amount, seconds: timed ? length.amount : 0,
                         targetRepsLow: 1, targetRepsHigh: 1, tracking: length.tracking)
        #expect(set.longestPlausibleLength == length.bound)

        let base = TestClock.reference
        for (gap, fits) in [(-5.0, false), (0, true), (length.bound, true), (length.bound + 1, false)] {
            set.startedAt = base
            #expect(set.startStillDescribes(loggedAt: base.addingTimeInterval(gap)) == fits, "\(gap) s")
        }
        set.startedAt = nil
        #expect(!set.startStillDescribes(loggedAt: base))
    }

    @Test func onlyAnUnloggedStartBeforeTheLogIsOvertaken() throws {
        try withRig { rig in
            let session = rig.session("Rule")
            let base = rig.ago(3000)
            let sets = (0..<4).map { rig.addRow(index: $0, to: session) }
            sets[0].startedAt = base.addingTimeInterval(-50)
            sets[1].startedAt = base.addingTimeInterval(10)
            sets[2].isCompleted = true
            sets[2].startedAt = base.addingTimeInterval(-20)

            let dropped = session.dropOvertakenStarts(besides: sets[3], at: base)

            #expect(dropped == [sets[0].id])
            // A later start and a logged set's own start are left alone.
            #expect(sets.map { $0.startedAt != nil } == [false, true, true, false])
        }
    }

    // MARK: - Health after a finish

    /// The write runs from a task that outlives the command. A session deleted
    /// meanwhile through another context must be let go: noting a phone
    /// workout or reading vitals for it writes onto a row nothing can find.
    @Test func theHealthWriteLetsGoOfASessionDeletedWhileItWasUnderWay() async throws {
        try await WatchCommandRig.run { rig in
            let session = rig.session("Finished on the watch")
            rig.complete(rig.addRow(index: 0, to: session), at: rig.at(600))
            try rig.context.save()
            let sessionID = session.id
            let container = rig.container
            rig.health.workoutToWrite = UUID()
            rig.health.duringSave = { _ in
                // An erase from the screen, through a context of its own.
                let screen = ModelContext(container)
                let rows = (try? screen.fetch(FetchDescriptor<WorkoutSession>(
                    predicate: #Predicate { $0.id == sessionID }))) ?? []
                rows.forEach(screen.delete)
                try? screen.save()
            }

            // The watch's own workout ID lets the write skip its wait for one.
            rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: sessionID, healthWorkoutID: UUID())))
            await rig.center.healthFollowUp?.value

            #expect(rig.health.saves == 1)
            #expect(rig.health.notedPhoneWorkouts.isEmpty)
            #expect(rig.health.backfills == 0)
        }
    }

    /// The other side of the one above, so its silence is the deletion's doing.
    /// The recorder reports whatever workout it is told to; whether Health
    /// would write one is `HealthKitService`'s question.
    @Test func theHealthWriteForASessionStillThereTellsTheWatchAndReadsItsVitals() async throws {
        try await WatchCommandRig.run { rig in
            let session = rig.session("Finished on the watch")
            rig.complete(rig.addRow(index: 0, to: session), at: rig.at(600))
            try rig.context.save()
            let phoneWorkout = UUID()
            rig.health.workoutToWrite = phoneWorkout

            rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: session.id, healthWorkoutID: UUID())))
            await rig.center.healthFollowUp?.value

            #expect(rig.health.saves == 1)
            #expect(rig.health.notedPhoneWorkouts == [phoneWorkout])
            #expect(rig.health.backfills == 1)
        }
    }

    // MARK: - A watch workout nothing owns

    /// Nothing else could remove it: no session holds its ID, so no erase or
    /// later delete would find it.
    @Test func aWorkoutTheWatchSavedForASessionThatIsGoneIsHandedToHealthsCleanup() throws {
        try withRig { rig in
            let workout = UUID()
            rig.send(.metrics(WatchWorkoutMetrics(sessionID: UUID(), healthWorkoutID: workout)))
            #expect(rig.health.orphanWorkouts == [workout])

            // A live reading for a missing session carries no workout to hand over.
            rig.send(.metrics(WatchWorkoutMetrics(sessionID: UUID(), currentHeartRate: 120)))
            #expect(rig.health.orphanWorkouts == [workout])

            let session = rig.session()
            try rig.context.save()
            session.endedAt = rig.at(1800)
            try rig.context.save()
            rig.send(.metrics(WatchWorkoutMetrics(sessionID: session.id, healthWorkoutID: UUID())))
            #expect(rig.health.orphanWorkouts == [workout])
        }
    }

    @Test func aFinishForASessionThatIsGoneHandsItsWatchWorkoutToHealthsCleanup() throws {
        try withRig { rig in
            let finishWorkout = UUID(), batchWorkout = UUID(), gone = UUID()

            rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: UUID(), healthWorkoutID: finishWorkout)))
            #expect(rig.health.orphanWorkouts == [finishWorkout])
            rig.send(.finishSession(finishBatch(gone),
                                    metrics: WatchWorkoutMetrics(sessionID: gone, healthWorkoutID: batchWorkout)))
            #expect(rig.health.orphanWorkouts == [finishWorkout, batchWorkout])

            // No workout, nothing to hand over.
            rig.send(.finishSession(finishBatch(gone), metrics: WatchWorkoutMetrics(sessionID: gone)))
            #expect(rig.health.orphanWorkouts == [finishWorkout, batchWorkout])
        }
    }

    // MARK: - The widgets

    /// HK-08: a wrist logging and undoing a set, discarding the session and
    /// starting another, with no logger on the phone. Each change reaches the
    /// snapshot the Home Screen draws, and once: the same change again writes
    /// nothing. The Discard restamps the whole snapshot itself.
    ///
    /// The Lock Screen card is told in the same breath, but Live Activities do
    /// nothing in a test host, so only the snapshot is read here.
    @Test func eachChangeTheWristMakesWithNoLoggerReachesTheWidgetsOnce() throws {
        try withRig { rig in
            let before = SharedStore.readSnapshot()
            defer { Self.putBack(before) }
            let session = try WidgetSnapshotTests.plannedSession(in: rig.context, sets: [3, 2])
            session.startedAt = rig.started
            try rig.context.save()
            let plans = try rig.context.fetch(FetchDescriptor<Plan>())
            let first = session.sets.sorted(by: SetLog.precedesInSession)[0]

            // A baseline with no plan, which only a full restamp would add. Written
            // over one with the plan, so it is written whatever this process wrote
            // last. Publishing with no logger also stands down one another test
            // left behind.
            WidgetPublisher.publish(plans: plans, sessions: [], running: nil)
            WidgetPublisher.publish(plans: [], sessions: [], running: nil)
            try #require(!WidgetPublisher.isLoggerRunning)
            try #require(SharedStore.readSnapshot()?.hasPlan == false)

            rig.send(rig.log(first, weight: 42.5, reps: 8, at: 600))
            let logged = try #require(SharedStore.readSnapshot())
            let position = SessionPosition(session)
            #expect(logged.session?.title == session.title)
            #expect(logged.session?.completedSets == 1)
            #expect(logged.session?.totalSets == 5)
            #expect(logged.session?.exercise == position.currentGroup?.name)
            #expect(logged.session?.target == position.nextTargetLabel)
            #expect(logged.session?.restEndsAt == nil)
            // Only the running session is restamped.
            #expect(!logged.hasPlan)

            // Marked, so a second write would show. The same log again changes
            // nothing a widget draws, and writes nothing.
            var marked = logged
            marked.streak = -1
            SharedStore.write(marked)
            rig.send(rig.log(first, weight: 42.5, reps: 8, at: 600))
            #expect(SharedStore.readSnapshot()?.streak == -1)

            rig.send(.undoSet(id: first.id, completedAt: nil))
            #expect(SharedStore.readSnapshot()?.session?.completedSets == 0)

            rig.send(.discardSession(id: session.id))
            let discarded = try #require(SharedStore.readSnapshot())
            #expect(discarded.session == nil)
            #expect(discarded.hasPlan)

            rig.send(.startFreestyle)
            let started = try #require(rig.sessions().filter(\.isActive).first)
            let running = try #require(SharedStore.readSnapshot()?.session)
            #expect(running.title == "Freestyle Session")
            #expect(abs(running.startedAt.timeIntervalSince(started.startedAt)) < 0.001)
            #expect(running.completedSets == 0)
        }
    }

    /// Puts the shared store back as the test found it. `SharedStore` has no
    /// way to remove a snapshot, so the key it keeps one under is named here,
    /// and checked, in case it is renamed. `WidgetPublisher`'s memory of what
    /// it last wrote is out of reach; every snapshot it holds is a real one.
    static func putBack(_ snapshot: GymTrackSnapshot?) {
        if let snapshot {
            SharedStore.write(snapshot)
            return
        }
        UserDefaults(suiteName: SharedStore.appGroup)?.removeObject(forKey: "gymtrack.snapshot")
        #expect(SharedStore.readSnapshot() == nil)
    }
}

// MARK: - Late-log fixtures

/// The rows of a session the phone's Finish closed one set in, by ID: `close`
/// deletes the rows nobody logged, and a deleted model cannot be read.
private struct ClosedSession {
    let session: UUID
    /// Logged on the phone before the close.
    let logged: UUID
    /// Announced, so it carries a start, and left for the wrist to log.
    let press: UUID
    /// A drop off `press`.
    let drop: UUID
    /// A timed set of another exercise.
    let plank: UUID
    /// Nobody lifted it.
    let spare: UUID
    let end: Date
}

private extension WatchCommandRig {
    /// Built and closed through a context of its own, as the logger's Finish
    /// is, ten seconds before the rig was set up.
    func closeOneSetIn() throws -> ClosedSession {
        let phone = reader()
        let end = ago(10)
        let session = WorkoutSession(title: "Phone finish", startedAt: started)
        phone.insert(session)
        func row(_ catalogID: String = "test-bench", order: Int = 0, index: Int, seconds: Int = 0,
                 tracking: TrackingMode = .weightReps) -> SetLog {
            let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: order,
                             setIndex: index, weightKg: 60, reps: 8, seconds: seconds,
                             targetRepsLow: 6, targetRepsHigh: 10, tracking: tracking)
            set.session = session
            phone.insert(set)
            return set
        }
        let logged = row(index: 0)
        complete(logged, at: end.addingTimeInterval(-600))
        let press = row(index: 1)
        press.startedAt = end.addingTimeInterval(-300)
        let drop = row(index: 2)
        drop.continuesPreviousSet = true
        let spare = row(index: 3)
        let plank = row("test-plank", order: 1, index: 0, seconds: 45, tracking: .duration)
        try phone.save()
        let closed = ClosedSession(session: session.id, logged: logged.id, press: press.id, drop: drop.id,
                                   plank: plank.id, spare: spare.id, end: end)
        session.close(at: end, in: phone)
        try phone.save()
        return closed
    }
}

private func wristLog(_ id: UUID, weightKg: Double = 62.5, reps: Int = 9, seconds: Int = 0,
                      at moment: Date?) -> WatchCommand {
    .logSet(id: id, weightKg: weightKg, reps: reps, seconds: seconds, at: moment)
}

private func pendingLog(_ id: UUID, weightKg: Double = 62.5, reps: Int = 9, seconds: Int = 0,
                        at moment: Date) -> WatchPendingLog {
    WatchPendingLog(setID: id, weightKg: weightKg, reps: reps, seconds: seconds, completedAt: moment)
}

private func finishBatch(_ session: UUID, logs: [WatchPendingLog] = [], undos: Set<UUID> = [],
                         starts: [UUID: Date] = [:]) -> WatchFinishBatch {
    WatchFinishBatch(sessionID: session, logs: logs, undos: undos, starts: starts, cancels: [], ratings: [])
}

// MARK: - What the mirror says before and after a workout

@MainActor @Suite(.serialized)
struct WatchMirrorStateTests {

    private static let t0 = TestClock.reference
    private static let sessionID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    private func snapshot(_ id: UUID = WatchMirrorStateTests.sessionID) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: id, title: "Push", planName: "", startedAt: Self.t0, exercises: [],
            restTotalSeconds: 0, restAutoStart: false, volumeKg: 0, unit: .kg)
    }

    @Test func nothingIsSentUntilThePhoneHasSaidWhatIsRunning() {
        var state = WatchMirrorState()
        let beforeAnything = state.nextMirror(healthEnabled: true)
        #expect(beforeAnything == nil)

        // The idle screen alone is not an answer: a mirror that said "no session"
        // before the store was read is what ended a recording mid-workout.
        var idle = WatchIdleSnapshot.empty
        idle.streak = 4
        let changed = state.update(idle: idle)
        let repeated = state.update(idle: idle)
        #expect(changed)
        #expect(!repeated)
        #expect(!state.isEstablished)
        let afterIdleOnly = state.nextMirror(healthEnabled: true)
        #expect(afterIdleOnly == nil)

        let established = state.update(session: nil, ended: nil)
        #expect(established)
        #expect(state.isEstablished)
        let first = state.nextMirror(sentAt: Self.t0, healthEnabled: true)
        #expect(first?.revision == 1)
        #expect(first?.idle.streak == 4)
        #expect(first?.session == nil)
        #expect(first?.healthEnabled == true)
        let second = state.nextMirror(sentAt: Self.t0, healthEnabled: false)
        #expect(second?.revision == 2)
    }

    @Test func aSessionKeepsItsEndedMarkerUntilAnotherSessionStarts() {
        var state = WatchMirrorState()
        let end = WatchSessionEnd(sessionID: Self.sessionID, reason: .finished)

        let started = state.update(session: snapshot(), ended: nil)
        let unchanged = state.update(session: snapshot(), ended: nil)
        #expect(started)
        #expect(!unchanged)

        let ended = state.update(session: nil, ended: end)
        #expect(ended)
        #expect(state.endedSession == end)
        let quiet = state.update(session: nil, ended: nil)
        #expect(!quiet)
        #expect(state.endedSession == end)

        let next = state.update(session: snapshot(UUID()), ended: end)
        #expect(next)
        #expect(state.endedSession == nil)
    }

    @Test func thePhonesHealthWorkoutIsNotedOnlyForTheFinishedSessionItBelongsTo() {
        var state = WatchMirrorState()
        let workout = UUID()
        _ = state.update(session: nil, ended: WatchSessionEnd(sessionID: Self.sessionID, reason: .finished))

        let wrongSession = state.notePhoneHealthWorkout(workout, for: UUID())
        #expect(!wrongSession)
        #expect(state.endedSession?.phoneHealthWorkoutID == nil)
        let rightSession = state.notePhoneHealthWorkout(workout, for: Self.sessionID)
        #expect(rightSession)
        #expect(state.endedSession?.phoneHealthWorkoutID == workout)

        _ = state.update(session: nil, ended: WatchSessionEnd(sessionID: Self.sessionID, reason: .discarded))
        let discarded = state.notePhoneHealthWorkout(workout, for: Self.sessionID)
        #expect(!discarded)
    }
}

// MARK: - A payload through the bridge

@MainActor @Suite(.serialized)
struct WatchBridgePayloadTests {

    private func payload(_ command: WatchCommand, stampedFor session: UUID? = nil, sentAt: Date? = nil) -> [String: Any] {
        var result = command.watchPayload(key: WatchLink.commandKey)
        let riders = WatchCommandDelivery(sentAt: sentAt, sessionID: session).payload
        result.merge(riders) { _, new in new }
        return result
    }

    @Test func aPayloadFromTheWristReachesTheStoreAndGarbageDoesNot() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let handler = Recorder()
            let center = rig.center
            WatchBridge.shared.commandHandler = { handler.commands.append($0); center.handle($0) }

            // Teaches the bridge which session the phone has open, as a real
            // watch's first request does.
            WatchBridge.shared.handle(payload(.requestMirror))
            WatchBridge.shared.handle(payload(rig.log(sets[0], weight: 70, reps: 5, at: 600)))
            #expect(sets[0].isCompleted)
            #expect(sets[0].weightKg == 70)

            WatchBridge.shared.handle(payload(.addSet(catalogID: "test-bench"), stampedFor: session.id))
            #expect(session.sets.count == 4)
            #expect(handler.commands.count == 3)

            let accepted = handler.commands.count
            WatchBridge.shared.handle([:])
            WatchBridge.shared.handle([WatchLink.commandKey: Data("junk".utf8)])
            WatchBridge.shared.handle([WatchLink.commandKey: "requestMirror"])
            #expect(handler.commands.count == accepted)
            #expect(session.sets.count == 4)
        }
    }

    @Test func aCommandStampedForAnotherSessionOrGoneStaleIsRefusedBeforeAnyoneHandlesIt() throws {
        try withRig { rig in
            let (session, _) = try rig.seed()
            let handler = Recorder()
            let center = rig.center
            WatchBridge.shared.commandHandler = { handler.commands.append($0); center.handle($0) }
            WatchBridge.shared.handle(payload(.requestMirror))
            handler.commands.removeAll()

            WatchBridge.shared.handle(payload(.addSet(catalogID: "test-bench"), stampedFor: UUID()))
            #expect(session.sets.count == 3)
            #expect(handler.commands.isEmpty)

            let staleBy = WatchCommandDelivery.startShelfLife + 60
            WatchBridge.shared.handle(payload(.startFreestyle, sentAt: Date.now.addingTimeInterval(-staleBy)))
            #expect(handler.commands.isEmpty)

            WatchBridge.shared.handle(payload(.addSet(catalogID: "test-bench"), stampedFor: session.id))
            #expect(session.sets.count == 4)
            #expect(handler.commands == [.addSet(catalogID: "test-bench")])
        }
    }
}

// MARK: - How the wrist hears a session end, and what can still reach it

/// What the wrist is told when a session ends with no logger on screen is read
/// from `WatchBridge.mirrorState`, the mirror the bridge would send next: a
/// test host never activates the link, so nothing leaves the phone. The Live
/// Activity is switched off under test and Health here is the real service,
/// so neither is asserted.
@MainActor
extension WatchCommandCenterHeadlessTests {

    private var endTheWristHeard: WatchSessionEnd? { WatchBridge.shared.mirrorState.endedSession }

    @Test func aWristFinishWithNothingLoggedIsADiscardAndTheWristHearsOne() throws {
        try withRig { rig in
            let id = try rig.seed().session.id
            let batch = WatchFinishBatch(sessionID: id, logs: [], undos: [], starts: [:], cancels: [],
                                         ratings: [], endedAt: rig.at(900))

            rig.send(.finishSession(batch, metrics: nil))

            #expect(rig.sessions().isEmpty)
            #expect(rig.allSets().isEmpty)
            #expect(endTheWristHeard == WatchSessionEnd(sessionID: id, reason: .discarded))
        }
    }

    /// The batch's own log counts: a Finish that overtook the wrist's only log
    /// is not an empty one.
    @Test func aWristFinishCarryingItsOnlyLogKeepsTheSessionAndTheSet() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let log = WatchPendingLog(setID: sets[0].id, weightKg: 60, reps: 8, seconds: 0,
                                      completedAt: rig.at(600))
            let batch = WatchFinishBatch(sessionID: session.id, logs: [log], undos: [], starts: [:], cancels: [],
                                         ratings: [], endedAt: rig.at(900))

            rig.send(.finishSession(batch, metrics: nil))

            #expect(rig.sessions().map(\.id) == [session.id])
            #expect(!session.isActive)
            #expect(session.completedSets.map(\.id) == [sets[0].id])
            #expect(endTheWristHeard == WatchSessionEnd(sessionID: session.id, reason: .finished))
        }
    }

    /// Told as finished when it kept a set, so a watch still recording keeps
    /// its workout rather than throwing it away; as discarded when it was
    /// deleted for being empty.
    @Test(arguments: [false, true])
    func aStaleSessionTheNextMirrorRetiresIsToldToTheWristAsItEnded(withASet: Bool) throws {
        try withRig { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let (session, sets) = try rig.seed(startedAt: longAgo)
            let id = session.id
            let lastSet = longAgo.addingTimeInterval(40 * 60)
            if withASet {
                rig.complete(sets[0], at: lastSet)
                try rig.context.save()
            }

            rig.send(.requestMirror)

            if withASet {
                #expect(sameMoment(session.endedAt, lastSet))
                #expect(endTheWristHeard == WatchSessionEnd(sessionID: id, reason: .finished))
            } else {
                #expect(rig.sessions().isEmpty)
                #expect(endTheWristHeard == WatchSessionEnd(sessionID: id, reason: .discarded))
            }
        }
    }

    /// The Finish carried the wrist's final state of the set. A queued undo or
    /// log delivered after it must not rewrite that closed record.
    @Test func aQueuedUndoOrLogCannotRewriteASetInAClosedSession() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let set = sets[0]
            set.weightKg = 55
            rig.complete(set, at: rig.at(600))
            session.close(at: rig.at(900), in: rig.context)
            try rig.context.save()

            rig.send(.undoSet(id: set.id, completedAt: nil))
            rig.send(.undoSet(id: set.id, completedAt: rig.at(600)))
            rig.send(.logSet(id: set.id, weightKg: 20, reps: 2, seconds: 0, at: rig.at(1000)))

            // What was saved, not what this context holds.
            let reader = ModelContext(rig.container)
            let stored = try #require(reader.fetch(FetchDescriptor<SetLog>()).first { $0.id == set.id })
            #expect(stored.isCompleted)
            #expect(stored.weightKg == 55 && stored.reps == 8)
            #expect(sameMoment(stored.completedAt, rig.at(600)))
        }
    }

    // MARK: The logger's start rules, with no logger (LOG-10, SESS-06)

    /// With the phone asleep, a start abandoned for another exercise is exactly
    /// what the queue delivers minutes before the log that used to close it.
    @Test func aWristLogOfAnotherSetOvertakesAStartAnnouncedBeforeIt() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed(exercises: ["test-bench", "test-row"])
            let bench = sets[0], row = sets[3]

            rig.send(.announceStart(id: bench.id, at: rig.at(500)))
            rig.send(rig.log(row, at: 550))
            rig.send(rig.log(bench, at: 600))

            #expect(bench.isCompleted && row.isCompleted)
            #expect(bench.startedAt == nil)
        }
    }

    @Test(arguments: [(gap: 1_500.0, kept: false), (gap: 60.0, kept: true)])
    func aWristStartIsKeptOnlyIfTheSetCouldHaveFilledTheGapToItsLog(gap: Double, kept: Bool) throws {
        try withRig { rig in
            let set = try rig.seed().sets[0]
            let start = rig.at(2_000 - gap)

            rig.send(.announceStart(id: set.id, at: start))
            rig.send(rig.log(set, at: 2_000))

            #expect(set.isCompleted)
            if kept {
                #expect(sameMoment(set.startedAt, start))
                #expect(set.timeUnderTension != nil)
            } else {
                // Dropped, not clamped.
                #expect(set.startedAt == nil)
                #expect(set.timeUnderTension == nil)
            }
        }
    }

    @Test func aLaterWristStartSupersedesAnEarlierOne() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed(exercises: ["test-bench", "test-row"])

            rig.send(.announceStart(id: sets[4].id, at: rig.at(500)))
            rig.send(.announceStart(id: sets[5].id, at: rig.at(570)))

            #expect(sets[4].startedAt == nil)
            #expect(sameMoment(sets[5].startedAt, rig.at(570)))
        }
    }

    /// As the phone's own undo takes them: left logged, the drops went into
    /// the record as lifts taken without rest off a set that was never done.
    @Test func aWristUndoTakesTheLoggedDropBelowItBackAndNothingElse() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            for (offset, set) in sets.enumerated() {
                rig.complete(set, at: rig.at(300 + Double(offset) * 20))
                set.rpe = SetFeel.solid.rawValue
            }
            sets[1].continuesPreviousSet = true
            sets[1].startedAt = rig.at(305)
            try rig.context.save()

            rig.send(.undoSet(id: sets[0].id, completedAt: sets[0].completedAt))

            #expect(!sets[0].isCompleted)
            #expect(sets[0].rpe == nil)
            #expect(!sets[1].isCompleted)
            #expect(sets[1].completedAt == nil && sets[1].rpe == nil && sets[1].startedAt == nil)
            // Still a continuation: the undo takes back the lift, not what the row is.
            #expect(sets[1].isContinuation)
            // Not a continuation, so not this undo's to take back.
            #expect(sets[2].isCompleted)
        }
    }
}
