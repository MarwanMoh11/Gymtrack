import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// The phone's load offer in a session run from the wrist. The wrist is sent
/// the offer, takes it through the phone's own take, and says with each log
/// whether it was drawing it. A log from a wrist that was not files no answer:
/// before the wrist drew offers, every set logged there at the old weight was
/// exported as the lifter turning down a rung they were never shown.
@MainActor @Suite(.serialized)
struct WatchLoadOfferTests {

    /// Three 60 kg sets for 8; the first is lifted at the top of its range and
    /// rated Easy, so the logger offers the next rung for the two still to do.
    private struct Scene {
        let session: WorkoutSession
        let sets: [SetLog]
        let logger: ActiveWorkout
        let offer: ActiveWorkout.LoadNudge
    }

    private func easyOpener(_ rig: WatchCommandRig) throws -> Scene {
        let (session, sets) = try rig.seed(setsEach: 3)
        let logger = rig.logger(for: session)
        logger.complete(sets[0], restSeconds: nil, at: rig.at(30))
        logger.rate(sets[0], feel: .easy)
        let offer = try #require(logger.pendingNudge(for: sets[0].catalogID))
        try #require(offer.toKg > 60)
        return Scene(session: session, sets: sets, logger: logger, offer: offer)
    }

    private func wristLog(_ set: SetLog, kg: Double, at moment: Date, showing offer: UUID?) -> WatchCommand {
        .logSet(id: set.id, weightKg: kg, reps: 8, seconds: 0, at: moment, offer: offer)
    }

    // MARK: What the wrist is sent

    @Test func theWristIsSentTheOfferOverTheRowsItWouldMove() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            let sent = scene.logger.watchSnapshot.exercises.first?.loadOffer
            #expect(sent == WatchLoadOffer(subjectID: scene.sets[0].id, fromKg: 60, toKg: scene.offer.toKg,
                                           rows: [scene.sets[1].id, scene.sets[2].id], taken: false))

            scene.logger.apply(scene.offer)
            #expect(scene.logger.watchSnapshot.exercises.first?.loadOffer?.taken == true,
                    "A take still open to undo is drawn as one")

            let taken = try #require(scene.logger.takenNudge(for: scene.sets[0].catalogID))
            scene.logger.undoTakenNudge(taken)
            #expect(scene.logger.watchSnapshot.exercises.first?.loadOffer?.taken == false)

            scene.logger.clearRating(scene.sets[0])
            #expect(scene.logger.watchSnapshot.exercises.first?.loadOffer == nil,
                    "An exercise with no offer carries no key")
        }
    }

    // MARK: A log answers only an offer the wrist drew

    /// The 2026-10-16 preacher curl: rated Easy, the offer stood on the phone,
    /// and the next set was logged on a wrist that only ever showed the old
    /// weight. Nothing may be filed, at the old weight or the offered rung.
    @Test(arguments: [false, true])
    func aWristLogThatWasNotDrawingTheOfferFilesNoAnswer(atTheOfferedRung: Bool) throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)
            let kg = atTheOfferedRung ? scene.offer.toKg : 60

            #expect(scene.logger.apply(wristLog(scene.sets[1], kg: kg, at: rig.at(200), showing: nil)))

            #expect(scene.sets[1].isCompleted)
            #expect(scene.sets[0].loadNudgeOutcome == nil, "A decline nobody was shown is a decision nobody made")
            #expect(scene.sets[0].loadNudgeToKg == nil)
            let standing = try #require(scene.logger.pendingNudge(for: scene.sets[0].catalogID),
                                        "The offer is still unanswered, over the set still to come")
            #expect(standing.toKg == scene.offer.toKg)
            #expect(standing.setCount == 1)
            #expect(scene.logger.watchSnapshot.exercises.first?.loadOffer?.rows == [scene.sets[2].id])
        }
    }

    @Test func anOfferNobodySawGoesUnansweredOnceItsSetsAreDone() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            scene.logger.apply(wristLog(scene.sets[1], kg: 60, at: rig.at(200), showing: nil))
            scene.logger.apply(wristLog(scene.sets[2], kg: 60, at: rig.at(400), showing: nil))

            #expect(scene.sets[0].loadNudgeOutcome == nil)
            #expect(scene.sets[0].loadNudgeToKg == nil)
            #expect(scene.logger.pendingNudge(for: scene.sets[0].catalogID) == nil,
                    "With no set left to move there is nothing left to offer")
        }
    }

    @Test func aLogNamingAnotherOfferDoesNotAnswerThisOne() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            scene.logger.apply(wristLog(scene.sets[1], kg: 60, at: rig.at(200), showing: UUID()))

            #expect(scene.sets[0].loadNudgeOutcome == nil)
            #expect(scene.logger.pendingNudge(for: scene.sets[0].catalogID) != nil)
        }
    }

    /// Drawn on the wrist, the offer is answered exactly as on the phone's
    /// card: lifted at the offered rung it was taken, at the old weight not.
    @Test(arguments: [false, true])
    func aWristLogDrawingTheOfferAnswersItAsThePhoneDoes(atTheOfferedRung: Bool) throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)
            let kg = atTheOfferedRung ? scene.offer.toKg : 60

            scene.logger.apply(wristLog(scene.sets[1], kg: kg, at: rig.at(200), showing: scene.offer.setID))

            #expect(scene.sets[0].loadNudgeOutcome == (atTheOfferedRung ? .taken : .declined))
            #expect(scene.sets[0].loadNudgeToKg == scene.offer.toKg)
            #expect(scene.logger.pendingNudge(for: scene.sets[0].catalogID) == nil)
        }
    }

    @Test func aPhoneLogStillAnswersTheOfferItsCardShows() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            scene.logger.complete(scene.sets[1], restSeconds: nil, at: rig.at(200))

            #expect(scene.sets[0].loadNudgeOutcome == .declined)
        }
    }

    // MARK: Taking it on the wrist

    @Test func takingTheOfferOnTheWristIsThePhonesTakeAndItsUndoLeavesNoDecision() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            #expect(scene.logger.apply(.takeLoadOffer(setID: scene.offer.setID, toKg: scene.offer.toKg)))

            #expect(scene.sets[1].weightKg == scene.offer.toKg && scene.sets[2].weightKg == scene.offer.toKg)
            #expect(scene.sets[0].loadNudgeOutcome == .taken)
            #expect(scene.sets[0].loadNudgeToKg == scene.offer.toKg)
            #expect(scene.logger.pendingNudge(for: scene.sets[0].catalogID) == nil)
            #expect(scene.logger.takenNudge(for: scene.sets[0].catalogID) != nil)

            #expect(scene.logger.apply(.undoLoadOffer(setID: scene.offer.setID)))

            #expect(scene.sets[1].weightKg == 60 && scene.sets[2].weightKg == 60)
            #expect(scene.sets[0].loadNudgeOutcome == nil)
            #expect(scene.sets[0].loadNudgeToKg == nil)
            #expect(scene.logger.pendingNudge(for: scene.sets[0].catalogID) == scene.offer)
        }
    }

    @Test func aTakeOfAnOfferNoLongerStandingMovesNothing() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            // Another rung than the one standing: the wrist drew an older offer.
            scene.logger.apply(.takeLoadOffer(setID: scene.offer.setID, toKg: scene.offer.toKg + 5))
            #expect(scene.sets[1].weightKg == 60)
            #expect(scene.sets[0].loadNudgeOutcome == nil)

            // Withdrawn on the phone before the wrist's take arrived.
            scene.logger.clearRating(scene.sets[0])
            scene.logger.apply(.takeLoadOffer(setID: scene.offer.setID, toKg: scene.offer.toKg))
            #expect(scene.sets[1].weightKg == 60 && scene.sets[2].weightKg == 60)
            #expect(scene.sets[0].loadNudgeOutcome == nil)
            #expect(scene.logger.takenNudge(for: scene.sets[0].catalogID) == nil)
        }
    }

    @Test func anUndoWithNoTakeOpenChangesNothing() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            scene.logger.apply(.undoLoadOffer(setID: scene.offer.setID))

            #expect(scene.sets[1].weightKg == 60)
            #expect(scene.logger.pendingNudge(for: scene.sets[0].catalogID) == scene.offer)
            #expect(scene.sets[0].loadNudgeOutcome == nil)
        }
    }

    // MARK: With no logger running

    @Test(arguments: [false, true])
    func aHeadlessWristLogAnswersTheStoredOfferOnlyIfItDrewIt(drawn: Bool) throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            rig.send(wristLog(scene.sets[1], kg: 60, at: rig.at(200), showing: drawn ? scene.offer.setID : nil))

            #expect(scene.sets[1].isCompleted)
            #expect(scene.sets[0].loadNudgeOutcome == (drawn ? .declined : nil))
            #expect(scene.sets[0].loadNudgeToKg == (drawn ? scene.offer.toKg : nil))
            let stored = rig.loggerMemory.load(for: scene.session.id)
            #expect((stored?.offers.map(\.setID) ?? []) == (drawn ? [] : [scene.offer.setID]),
                    "An offer nobody saw stands on for the next launch to read again")
        }
    }

    @Test func aHeadlessTakeMovesNothingAndFilesNothing() throws {
        try WatchCommandRig.run { rig in
            let scene = try easyOpener(rig)

            rig.send(.takeLoadOffer(setID: scene.offer.setID, toKg: scene.offer.toKg))

            #expect(scene.sets[1].weightKg == 60 && scene.sets[2].weightKg == 60)
            #expect(scene.sets[0].loadNudgeOutcome == nil)
        }
    }
}
