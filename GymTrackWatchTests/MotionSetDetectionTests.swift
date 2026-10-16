import Foundation
import Testing
@testable import GymTrackWatch

/// Finding a set in the wrist's movement (`MotionSetDetection`), and the rules
/// around it: when the sensor runs, which gap a log closes, and how long the
/// "Log set?" line stands. Every trace here is made up at 25 readings a second
/// with a fixed wobble, so every run reads the same numbers.
///
/// Most of these are traces that must be refused. A window placed on the wrong
/// movement goes to the phone as a reading of this set, which is worse than
/// no window at all.
@MainActor @Suite(.serialized)
struct MotionSetDetectionTests {

    nonisolated static let t0 = WatchTestClock.reference
    nonisolated static let wobble: [Double] = [0, 0.6, -0.4, 0.9, -0.7, 0.2, -0.9, 0.4]

    /// How the wrist moves over one stretch of the trace.
    enum Motion: Sendable {
        /// Resting: near-still, a little sensor noise.
        case still
        /// Reps: each rep's lift and lower is a swing of the acceleration.
        case reps(period: Double)
        /// Walking: a step every half-second.
        case walking
        /// A single short movement: a re-rack, a plate, a wrist raised to look.
        case jolt

        func magnitude(_ t: Double, noise: Double) -> Double {
            switch self {
            case .still: 0.008 + 0.004 * noise
            case .reps(let period): 0.01 + 0.15 * abs(sin(2 * .pi * t / period)) + 0.005 * noise
            case .walking: 0.25 + 0.15 * sin(2 * .pi * 2 * t) + 0.01 * noise
            case .jolt: 0.2 + 0.03 * noise
            }
        }
    }

    /// Readings at 25 a second over consecutive stretches, in seconds after `t0`.
    static func trace(_ stretches: [(until: Double, motion: Motion)]) -> [MotionSample] {
        var samples: [MotionSample] = []
        var t = 0.0
        var index = 0
        for stretch in stretches {
            while t < stretch.until {
                samples.append(MotionSample(time: at(t), magnitude: stretch.motion.magnitude(t, noise: wobble[index % wobble.count])))
                t += 0.04
                index += 1
            }
        }
        return samples
    }

    static func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
    static func seconds(_ date: Date) -> Double { date.timeIntervalSince(t0) }

    static func find(_ samples: [MotionSample], after floor: Double = -1, until cutoff: Double,
                     quiet: TimeInterval = MotionSetDetection.settle) -> MotionBout? {
        MotionSetDetection.bout(in: samples, after: at(floor), until: at(cutoff), quiet: quiet)
    }

    // MARK: - Finding the set

    @Test func aSetBetweenRestsIsFoundToWithinASecondAtEachEnd() throws {
        let samples = Self.trace([(30, .still), (60, .reps(period: 2.5)), (80, .still)])
        let bout = try #require(Self.find(samples, until: 80))
        #expect(abs(Self.seconds(bout.start) - 30) <= 1.5)
        #expect(abs(Self.seconds(bout.end) - 60) <= 1.5)
        #expect(bout.swings >= MotionSetDetection.fewestSwings)
    }

    @Test(arguments: [1.6, 2.5, 4.0, 6.0])
    func repsAtAnyOrdinaryTempoAreFound(period: Double) {
        let samples = Self.trace([(20, .still), (50, .reps(period: period)), (70, .still)])
        #expect(Self.find(samples, until: 70) != nil)
    }

    @Test func theOfferWaitsForTheWristToSettleButALogNeedsOnlyTheMovementToHaveStopped() {
        let samples = Self.trace([(30, .still), (60, .reps(period: 2.5)), (80, .still)])
        // Three seconds after the last rep: maybe re-racking, not offered yet.
        #expect(Self.find(samples, until: 63) == nil)
        #expect(Self.find(samples, until: 68) != nil)
        // A log three seconds after says the set is over.
        #expect(Self.find(samples, until: 63, quiet: 0) != nil)
        // But not one landing while the wrist is still moving.
        #expect(Self.find(samples, until: 59, quiet: 0) == nil)
    }

    @Test func aWalkBeforeTheSetIsIgnoredAndTheSetStillFound() throws {
        let samples = Self.trace([(10, .still), (30, .walking), (45, .still), (75, .reps(period: 2.5)), (95, .still)])
        let bout = try #require(Self.find(samples, until: 95))
        #expect(abs(Self.seconds(bout.start) - 45) <= 1.5)
    }

    @Test func aSetFromBeforeThePreviousLogIsNotThisGapsSet() {
        let samples = Self.trace([(10, .still), (40, .reps(period: 2.5)), (60, .still)])
        #expect(Self.find(samples, after: 45, until: 60) == nil)
    }

    enum Unreadable: String, CaseIterable, Sendable {
        case stillness, walking, twoSets, tooShort, reRack, alreadyMovingWhenTheTraceBegins, tooLong
    }

    @Test(arguments: Unreadable.allCases)
    func tracesThatCouldBeReadTwoWaysAreRefused(_ trace: Unreadable) {
        let samples: [MotionSample]
        var cutoff = 80.0
        switch trace {
        case .stillness:
            samples = Self.trace([(80, .still)])
        case .walking:
            samples = Self.trace([(20, .still), (60, .walking), (80, .still)])
        case .twoSets:
            samples = Self.trace([(20, .still), (45, .reps(period: 2.5)), (75, .still),
                                  (100, .reps(period: 2.5)), (120, .still)])
            cutoff = 120
        case .tooShort:
            samples = Self.trace([(20, .still), (24, .reps(period: 2.5)), (80, .still)])
        case .reRack:
            // Still for four seconds, then a jolt: the last rep, or the re-rack?
            samples = Self.trace([(20, .still), (50, .reps(period: 2.5)), (54, .still), (56, .jolt), (80, .still)])
        case .alreadyMovingWhenTheTraceBegins:
            samples = Self.trace([(30, .reps(period: 2.5)), (80, .still)])
        case .tooLong:
            samples = Self.trace([(20, .still), (200, .reps(period: 2.5)), (220, .still)])
            cutoff = 220
        }
        #expect(Self.find(samples, until: cutoff) == nil)
        #expect(Self.find(samples, until: cutoff, quiet: 0) == nil)
    }

    // MARK: - When the sensor runs

    @Test(arguments: [
        (enabled: nil as Bool?, recording: true, live: true, announced: false, reads: true),
        (enabled: true as Bool?, recording: true, live: true, announced: false, reads: true),
        (enabled: false as Bool?, recording: true, live: true, announced: false, reads: false),
        (enabled: true as Bool?, recording: false, live: true, announced: false, reads: false),
        (enabled: true as Bool?, recording: true, live: false, announced: false, reads: false),
        (enabled: true as Bool?, recording: true, live: true, announced: true, reads: false),
    ])
    func theSensorRunsOnlyForALiveRecordedSessionWithNothingAnnounced(enabled: Bool?, recording: Bool, live: Bool,
                                                                      announced: Bool, reads: Bool) {
        var session = watchSession(sets: [watchSet(index: 0, completedAt: Self.at(60), startedAt: Self.at(20)),
                                          watchSet(index: 1, startedAt: announced ? Self.at(100) : nil)])
        session.motionSetDetection = enabled
        #expect(MotionSetDetection.shouldRead(enabled: enabled, recording: recording,
                                              session: live ? session : nil) == reads)
    }

    @Test func theGapALogClosesOpenedAtTheLatestOtherLogOrTheSessionsStart() {
        let first = watchSet(index: 0, completedAt: Self.at(100))
        let second = watchSet(index: 1, completedAt: Self.at(300))
        let third = watchSet(index: 2)
        let session = watchSession(startedAt: Self.at(0), sets: [first, second, third])
        #expect(MotionSetDetection.gapOpened(in: session, before: third.id) == Self.at(300))
        // Logged again, a set's own earlier log is not the edge of its gap.
        #expect(MotionSetDetection.gapOpened(in: session, before: second.id) == Self.at(100))
        #expect(MotionSetDetection.gapOpened(in: watchSession(startedAt: Self.at(0), sets: [third])) == Self.at(0))
    }

    // MARK: - The line on the logger

    @Test(arguments: [
        (after: 0.0, sameSet: true, shows: true),
        (after: 59.0, sameSet: true, shows: true),
        (after: 60.0, sameSet: true, shows: false),
        (after: -1.0, sameSet: true, shows: false),
        (after: 5.0, sameSet: false, shows: false),
    ])
    func theOfferStandsForAMinuteOnTheSetItWasMadeFor(after: Double, sameSet: Bool, shows: Bool) {
        let id = UUID()
        let offer = MotionSetOffer(bout: MotionBout(start: Self.at(0), end: Self.at(42), swings: 16),
                                   setID: id, madeAt: Self.at(50))
        #expect(offer.isShowing(on: sameSet ? id : UUID(), at: Self.at(50 + after)) == shows)
    }

    @Test(arguments: [(42.0, "0:42"), (75.4, "1:15"), (0.0, "0:00"), (-3.0, "0:00")])
    func theOfferWritesTheSetsLengthAsAClock(seconds: Double, text: String) {
        #expect(WatchMotionOfferRow.clock(seconds) == text)
    }
}
