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
}
