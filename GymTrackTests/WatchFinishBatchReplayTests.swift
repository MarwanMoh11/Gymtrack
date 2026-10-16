import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What a wrist Finish writes when it replays the wrist's pending actions:
/// the undos it carries are held to the refusal an undo sent alone gets, and
/// the logs it carries take the machine the set was done on, as far as the
/// phone can vouch for it.
@MainActor @Suite(.serialized)
struct WatchFinishBatchReplayTests {

    // MARK: Undo stamps (R1)

    @Test func finishBatchMustRespectTheCompletionAnUndoNames() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let row = sets[0]
            let old = rig.at(30)
            let fresh = rig.at(90)
            rig.complete(row, at: fresh)
            try rig.context.save()
            var pending = WatchPendingActions()
            pending.adopt(session.id)
            pending.recordUndo(of: row.id, completedAt: old)
            #expect(!row.admitsWristUndo(of: old))
            let batch = pending.finishBatch(for: session.id, ratings: [])
            session.applyWatchFinish(batch)
            #expect(row.isCompleted, "A Finish carrying an undo of the old log must keep the fresh log")
            #expect(row.completedAt == fresh)
        }
    }

    @Test func aStampedUndoInAFinishTakesBackTheLogItNames() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let row = sets[0]
            rig.complete(row, at: rig.at(60))
            var pending = WatchPendingActions()
            pending.adopt(session.id)
            pending.recordUndo(of: row.id, completedAt: rig.at(60))
            let sent = pending.finishBatch(for: session.id, ratings: [])
            let batch = try JSONDecoder().decode(WatchFinishBatch.self, from: JSONEncoder().encode(sent))
            #expect(batch.undoStamps == [row.id: rig.at(60)])

            session.applyWatchFinish(batch)

            #expect(!row.isCompleted)
            #expect(row.completedAt == nil)
        }
    }

    @Test func aRefusedUndoLeavesTheNewerLogsStartAlone() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let row = sets[0]
            rig.complete(row, at: rig.at(90))
            row.startedAt = rig.at(70)
            var pending = WatchPendingActions()
            pending.adopt(session.id)
            pending.recordUndo(of: row.id, completedAt: rig.at(30))
            pending.cancels.insert(row.id)

            session.applyWatchFinish(pending.finishBatch(for: session.id, ratings: []))

            #expect(row.isCompleted)
            #expect(row.startedAt == rig.at(70), "A cancel beside a refused undo must not clear the newer log's start")
        }
    }

    /// An older watch sends no stamps, and its Finish still decodes and takes
    /// back whatever the row holds, as every batch used to.
    @Test func aBatchFromAnOlderWatchStillTakesItsUndosBack() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let row = sets[0]
            rig.complete(row, at: rig.at(90))
            let sent = WatchFinishBatch(sessionID: session.id, logs: [], undos: [row.id], starts: [:],
                                        cancels: [], ratings: [])
            let wire = try JSONEncoder().encode(sent)
            #expect(!String(decoding: wire, as: UTF8.self).contains("undoStamps"))
            let batch = try JSONDecoder().decode(WatchFinishBatch.self, from: wire)
            #expect(batch.undoStamps == nil)

            session.applyWatchFinish(batch)

            #expect(!row.isCompleted)
        }
    }

    @Test func aLateFinishKeepsARestoredRowItsStaleUndoDoesNotName() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let rowID = sets[0].id
            session.close(at: rig.at(600), in: rig.context)
            try rig.context.save()
            let restored = try #require(session.restoreDroppedSet(rowID, weightKg: 60, reps: 8, seconds: 0,
                                                                  loggedAt: rig.at(90), in: rig.context))
            var pending = WatchPendingActions()
            pending.adopt(session.id)
            pending.recordUndo(of: rowID, completedAt: rig.at(30))

            #expect(!session.applyLateWatchFinish(pending.finishBatch(for: session.id, ratings: []),
                                                  in: rig.context))
            #expect(restored.isCompleted)
            #expect(restored.completedAt == rig.at(90))
            #expect(session.sets.contains { $0.id == rowID })
        }
    }

    // MARK: The machine a wrist log was done on (R7)

    /// A machine with something to adjust, so a setup can hold a value.
    private static var adjustable: (MachineRig, RigAdjustment)? {
        MachineCatalog.all.lazy.compactMap { rig in rig.adjustments.first.map { (rig, $0) } }.first
    }

    private func finishLog(_ set: SetLog, in session: WorkoutSession, at moment: Date) {
        session.applyWatchFinish(WatchFinishBatch(
            sessionID: session.id,
            logs: [WatchPendingLog(setID: set.id, weightKg: 60, reps: 8, seconds: 0, completedAt: moment)],
            undos: [], starts: [:], cancels: [], ratings: []))
    }

    @Test func finishBatchMustKeepTheChosenMachineOnItsLogs() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let machine = try #require(MachineCatalog.all.first)
            MachineSetups.choose(machine.id, for: sets[0].catalogID, context: rig.context, at: rig.at(10))

            finishLog(sets[0], in: session, at: rig.at(60))

            #expect(sets[0].isCompleted)
            #expect(sets[0].machineID == machine.id, "A wrist log arriving in Finish must record the machine like a normal log")
            #expect(sets[0].machineSettingsRaw == nil)
        }
    }

    @Test func aFinishLogWithNoMachineChosenCarriesNone() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            finishLog(sets[0], in: session, at: rig.at(60))
            #expect(sets[0].isCompleted)
            #expect(sets[0].machineID == nil && sets[0].machineSettingsRaw == nil)
        }
    }

    @Test func aFinishLogKeepsTheAdjustmentsSetBeforeIt() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let (machine, adjustment) = try #require(Self.adjustable)
            let catalogID = sets[0].catalogID
            MachineSetups.choose(machine.id, for: catalogID, context: rig.context, at: rig.at(10))
            MachineSetups.set(adjustment.id, to: adjustment.range.lowerBound, for: catalogID,
                              context: rig.context, at: rig.at(20))

            finishLog(sets[0], in: session, at: rig.at(60))

            #expect(sets[0].machineID == machine.id)
            let settings = MachineSettings(raw: sets[0].machineSettingsRaw)
            #expect(settings.values[adjustment.id] == adjustment.range.lowerBound)
        }
    }

    /// A setup touched after the log says nothing certain about the set: it
    /// may be a moved seat or another machine altogether. The set carries no
    /// machine rather than one chosen later.
    @Test func aSetupChangedAfterTheLogIsNotStampedOnIt() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let (machine, adjustment) = try #require(Self.adjustable)
            let catalogID = sets[0].catalogID
            MachineSetups.choose(machine.id, for: catalogID, context: rig.context, at: rig.at(10))
            MachineSetups.set(adjustment.id, to: adjustment.range.lowerBound, for: catalogID,
                              context: rig.context, at: rig.at(120))

            finishLog(sets[0], in: session, at: rig.at(60))

            #expect(sets[0].isCompleted)
            #expect(sets[0].machineID == nil && sets[0].machineSettingsRaw == nil)
        }
    }

    /// The individual headless log and a row a late log puts back go through
    /// the same rule as a Finish.
    @Test(arguments: [(10.0, true), (120.0, false)])
    func everyWristLogPathStampsOnlyASetupFromBeforeIt(chosenAt: Double, stamped: Bool) throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 2)
            let machine = try #require(MachineCatalog.all.first)
            MachineSetups.choose(machine.id, for: sets[0].catalogID, context: rig.context, at: rig.at(chosenAt))
            let expected = stamped ? machine.id : nil

            rig.send(.logSet(id: sets[0].id, weightKg: 60, reps: 8, seconds: 0, at: rig.at(60)))
            #expect(sets[0].isCompleted)
            #expect(sets[0].machineID == expected)

            let droppedID = sets[1].id
            session.close(at: rig.at(600), in: rig.context)
            try rig.context.save()
            let restored = try #require(session.restoreDroppedSet(droppedID, weightKg: 60, reps: 8, seconds: 0,
                                                                  loggedAt: rig.at(90), in: rig.context))
            #expect(restored.machineID == expected)
        }
    }

    /// A wrist log that reaches the logger on screen can still be late, so it
    /// is held to the same rule; a tap on the phone is not (`MachineSetupTests`).
    @Test(arguments: [(60.0, true), (600.0, false)])
    func aWristLogThroughTheLoggerStampsOnlyASetupFromBeforeIt(chosenAfter: Double, stamped: Bool) throws {
        try WorkoutBench.run { bench in
            let session = bench.session()
            let rows = bench.addRows(to: session, count: 2, weightKg: 60, low: 6, high: 10)
            let workout = bench.open(session)
            let machine = try #require(MachineCatalog.all.first)
            MachineSetups.choose(machine.id, for: rows[0].catalogID, context: bench.context,
                                 at: WorkoutBench.t0.addingTimeInterval(chosenAfter))

            #expect(workout.apply(.logSet(id: rows[0].id, weightKg: 60, reps: 8, seconds: 0,
                                          at: WorkoutBench.t0.addingTimeInterval(300))))

            #expect(rows[0].isCompleted)
            #expect(rows[0].machineID == (stamped ? machine.id : nil))
        }
    }

    // MARK: An undo in the batch takes back what logging the set did

    /// Three 60 kg sets: the first logged and rated Easy, so an offer stands,
    /// and the second logged on the phone, at the offered rung or at 60, which
    /// answers it.
    private func answeredOffer(_ rig: WatchCommandRig, liftingTheOffer: Bool) throws
        -> (session: WorkoutSession, sets: [SetLog], logger: ActiveWorkout, offer: ActiveWorkout.LoadNudge) {
        let (session, sets) = try rig.seed(setsEach: 3)
        let logger = rig.logger(for: session)
        logger.complete(sets[0], restSeconds: nil, at: rig.at(30))
        logger.rate(sets[0], feel: .easy)
        let offer = try #require(logger.pendingNudge(for: sets[0].catalogID))
        if liftingTheOffer { sets[1].weightKg = offer.toKg }
        logger.complete(sets[1], restSeconds: nil, at: rig.at(200))
        try #require(sets[0].loadNudgeOutcome == (liftingTheOffer ? .taken : .declined))
        return (session, sets, logger, offer)
    }

    private func undoBatch(of set: SetLog, stamped stamp: Date?, in session: WorkoutSession) -> WatchFinishBatch {
        var batch = WatchFinishBatch(sessionID: session.id, logs: [], undos: [set.id], starts: [:],
                                     cancels: [], ratings: [])
        batch.undoStamps = stamp.map { [set.id: $0] }
        return batch
    }

    @Test(arguments: [false, true], [false, true])
    func aFinishBatchUndoTakesBackTheAnswerItsSetGave(liftingTheOffer: Bool, loggerRunning: Bool) throws {
        try WatchCommandRig.run { rig in
            let scene = try answeredOffer(rig, liftingTheOffer: liftingTheOffer)
            let batch = undoBatch(of: scene.sets[1], stamped: scene.sets[1].completedAt, in: scene.session)

            if loggerRunning {
                scene.session.applyWatchFinish(batch) { scene.logger.takeBack(replayed: $0) }
                #expect(!scene.sets[1].isCompleted)
                #expect(scene.logger.pendingNudge(for: scene.sets[0].catalogID)?.toKg == scene.offer.toKg,
                        "The offer is unanswered again")
            } else {
                rig.send(.finishSession(batch, metrics: nil))
                #expect(!scene.session.isActive)
            }
            #expect(scene.sets[0].loadNudgeOutcome == nil,
                    "An answer whose only evidence the batch erased must not stay on the record")
            #expect(scene.sets[0].loadNudgeToKg == nil)
        }
    }

    @Test func aRefusedFinishBatchUndoLeavesTheAnswerOnTheRecord() throws {
        try WatchCommandRig.run { rig in
            let scene = try answeredOffer(rig, liftingTheOffer: false)
            let stale = undoBatch(of: scene.sets[1], stamped: rig.at(100), in: scene.session)

            scene.session.applyWatchFinish(stale) { scene.logger.takeBack(replayed: $0) }

            #expect(scene.sets[1].isCompleted, "A stale undo keeps the newer log")
            #expect(scene.sets[0].loadNudgeOutcome == .declined, "and the answer that log gave")
        }
    }

    @Test func aFinishBatchUndoTakesTheLoggedDropBeneathWithIt() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 3)
            sets[2].continuesPreviousSet = true
            let logger = rig.logger(for: session)
            logger.complete(sets[1], restSeconds: nil, at: rig.at(60))
            logger.complete(sets[2], restSeconds: nil, at: rig.at(75))
            try #require(session.loggedContinuations(below: sets[1]).map(\.id) == [sets[2].id])

            session.applyWatchFinish(undoBatch(of: sets[1], stamped: sets[1].completedAt, in: session)) {
                logger.takeBack(replayed: $0)
            }

            #expect(!sets[1].isCompleted)
            #expect(!sets[2].isCompleted, "A drop off a set that was taken back is not a lift either")
        }
    }
}
