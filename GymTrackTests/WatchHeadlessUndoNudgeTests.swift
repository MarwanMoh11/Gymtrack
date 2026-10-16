import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// Undoing the set a load increase was offered on, from the wrist, with the
/// phone's logger gone. The set must take back everything its acceptance did,
/// exactly as the phone's own undo does, and from the stored memory so that it
/// holds after a relaunch too.
@MainActor @Suite(.serialized)
struct WatchHeadlessUndoNudgeTests {

    /// Three 60 kg sets; the first is logged, rated Easy and its offer taken.
    private struct Scene {
        let session: WorkoutSession
        let sets: [SetLog]
        let offer: ActiveWorkout.LoadNudge
    }

    private func acceptedNudge(_ rig: WatchCommandRig) throws -> Scene {
        let (session, sets) = try rig.seed(setsEach: 3)
        let logger = rig.logger(for: session)
        logger.complete(sets[0], restSeconds: nil, at: rig.at(30))
        logger.rate(sets[0], feel: .easy)
        let offer = try #require(logger.pendingNudge(for: sets[0].catalogID))
        logger.apply(offer)
        try #require(sets[1].weightKg == offer.toKg)
        return Scene(session: session, sets: sets, offer: offer)
    }

    private func undoSource(_ scene: Scene, in rig: WatchCommandRig) {
        rig.send(.undoSet(id: scene.sets[0].id, completedAt: scene.sets[0].completedAt))
    }

    @Test func headlessUndoMustRestoreATakenLoadNudge() throws {
        try WatchCommandRig.run { rig in
            let scene = try acceptedNudge(rig)
            undoSource(scene, in: rig)

            #expect(!scene.sets[0].isCompleted)
            #expect(scene.sets[1].weightKg == 60 && scene.sets[2].weightKg == 60,
                    "An undone source set must also undo the load increase it produced")
            #expect(scene.sets[0].loadNudgeOutcome == nil, "The undone set keeps no answer on the record")
            #expect(rig.loggerMemory.load(for: scene.session.id)?.takes.isEmpty ?? true,
                    "The take is spent, so a later launch cannot offer to undo it again")
        }
    }

    @Test func aRelaunchBetweenAcceptingAndUndoingStillRestoresTheLoad() throws {
        try WatchCommandRig.run { rig in
            let scene = try acceptedNudge(rig)
            // The logger the app held is gone; a new one reads the memory.
            let relaunched = rig.logger(for: scene.session)
            try #require(relaunched.takenNudge(for: scene.sets[0].catalogID) != nil)

            undoSource(scene, in: rig)
            #expect(scene.sets[1].weightKg == 60 && scene.sets[2].weightKg == 60)

            let again = rig.logger(for: scene.session)
            #expect(again.takenNudge(for: scene.sets[0].catalogID) == nil)
            #expect(again.pendingNudge(for: scene.sets[0].catalogID) == nil,
                    "Nothing is left standing over a set that was never done")
            #expect(scene.sets[1].weightKg == 60)
        }
    }

    @Test func aRowTheLiftersTypedIntoAfterTheNudgeKeepsWhatTheyTyped() throws {
        try WatchCommandRig.run { rig in
            let scene = try acceptedNudge(rig)
            scene.sets[1].weightKg = 67.5

            undoSource(scene, in: rig)

            #expect(scene.sets[1].weightKg == 67.5, "A number the lifter chose is theirs")
            #expect(scene.sets[2].weightKg == 60, "The untouched row beside it still goes back")
        }
    }

    @Test func aRowAlreadyLoggedIsNeverMovedByTheUndo() throws {
        try WatchCommandRig.run { rig in
            let scene = try acceptedNudge(rig)
            rig.complete(scene.sets[1], at: rig.at(120))
            let lifted = scene.sets[1].weightKg

            undoSource(scene, in: rig)

            #expect(scene.sets[1].isCompleted)
            #expect(scene.sets[1].weightKg == lifted, "A weight that was lifted stays what it was")
            #expect(scene.sets[2].weightKg == 60)
        }
    }

    @Test func theUndoOfTheSetThatAnsweredAnOfferStandsTheOfferBackUp() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed(setsEach: 3)
            let logger = rig.logger(for: session)
            logger.complete(sets[0], restSeconds: nil, at: rig.at(30))
            logger.rate(sets[0], feel: .easy)
            let offer = try #require(logger.pendingNudge(for: sets[0].catalogID))
            sets[1].weightKg = offer.toKg
            logger.complete(sets[1], restSeconds: nil, at: rig.at(200))
            try #require(sets[0].loadNudgeOutcome == .taken)
            try #require(logger.pendingNudge(for: sets[0].catalogID) == nil)

            rig.send(.undoSet(id: sets[1].id, completedAt: sets[1].completedAt))

            #expect(!sets[1].isCompleted)
            #expect(sets[0].loadNudgeOutcome == nil, "The answer the lifted set gave goes with it")
            let relaunched = rig.logger(for: session)
            #expect(relaunched.pendingNudge(for: sets[0].catalogID)?.toKg == offer.toKg,
                    "The offer is unanswered again after the relaunch")
        }
    }
}
