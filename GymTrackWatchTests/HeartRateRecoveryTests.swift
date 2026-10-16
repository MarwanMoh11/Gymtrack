import Foundation
import Testing
@testable import GymTrackWatch

/// When the wrist tells the lifter their heart rate has settled. Every case is
/// a made-up trace on the clock below, so the decision is held to its edges
/// without a sensor.
@MainActor @Suite(.serialized)
struct HeartRateRecoveryTests {

    private let start = WatchTestClock.restReference

    /// Readings at the given seconds after the rest began (negative: before it).
    private func trace(_ points: [(Double, Double)]) -> [HeartRateReading] {
        points.map { HeartRateReading(date: start.addingTimeInterval($0.0), bpm: $0.1) }
    }

    private func settled(_ points: [(Double, Double)], at seconds: Double) -> Bool {
        HeartRateRecovery.hasSettled(readings: trace(points), restStartedAt: start,
                                     now: start.addingTimeInterval(seconds))
    }

    /// A set's climb to 150, a fall of about thirty beats, then a flat rest.
    private let recovered: [(Double, Double)] = [
        (-5, 150), (0, 148), (5, 140), (10, 132), (15, 126), (20, 122), (25, 120),
        (30, 120), (35, 121), (40, 119), (45, 120), (50, 121), (55, 120), (60, 120),
    ]

    @Test func aHeartRateThatFellAndLevelledOffIsSettled() {
        #expect(settled(recovered, at: 60))
    }

    @Test func aHeartRateStillFallingFastIsNot() {
        let falling = (-5...12).map { (Double($0 * 5), 150 - Double($0 * 5)) }
        #expect(!settled(falling, at: 60))
    }

    @Test func aSlowSlideAcrossTheWindowIsStillFalling() {
        // Spread of six passes on its own; the half-to-half fall is what refuses it.
        let sliding: [(Double, Double)] = [(-5, 150), (0, 146), (35, 124), (40, 123), (45, 121),
                                          (50, 120), (55, 119), (60, 118)]
        #expect(!settled(sliding, at: 60))
    }

    @Test func aHeartRateClimbingAgainIsNot() {
        let rising: [(Double, Double)] = [(-5, 150), (0, 140), (35, 118), (40, 119), (45, 121),
                                         (50, 122), (55, 123), (60, 124)]
        #expect(!settled(rising, at: 60))
    }

    @Test(arguments: [0.0, 10, 39])
    func nothingFiresBeforeTheMinimumRest(_ seconds: Double) {
        // Flat the whole way: only the clock says it is too soon.
        let flat: [(Double, Double)] = [(-5, 150)] + (0...10).map { (Double($0 * 5), 120) }
        #expect(!settled(flat, at: seconds))
        #expect(settled(flat, at: 40))
    }

    @Test func aRestThatNeverDroppedMuchIsNotSettled() {
        let light: [(Double, Double)] = [(-5, 132)] + (0...12).map { (Double($0 * 5), 120) }
        #expect(!settled(light, at: 60), "twelve beats off the peak is wander, not recovery")
    }

    @Test func tooFewReadingsInTheWindowIsNotSettled() {
        let sparse: [(Double, Double)] = [(-5, 150), (0, 140), (40, 120), (50, 120), (60, 120)]
        #expect(!settled(sparse, at: 60))
    }

    @Test func aGapInsideTheWindowIsNotSettled() {
        let gappy: [(Double, Double)] = [(-5, 150), (0, 140), (35, 120), (38, 120), (41, 120),
                                        (58, 120), (59, 120), (60, 120)]
        #expect(!settled(gappy, at: 60))
    }

    @Test func aTraceThatWentQuietBeforeNowIsNotSettled() {
        let stale = recovered.filter { $0.0 <= 45 }
        #expect(!settled(stale, at: 60), "the last reading is fifteen seconds old")
    }

    @Test func aTraceThatStartsLateInTheWindowIsNotSettled() {
        let late = recovered.filter { $0.0 < 0 || $0.0 >= 52 }
        #expect(!settled(late, at: 60))
    }

    @Test func aZeroReadingInTheWindowIsNotSettled() {
        var zero = recovered
        zero[10] = (45, 0)
        #expect(!settled(zero, at: 60))
    }

    @Test func noReadingsIsNotSettled() {
        #expect(!settled([], at: 120))
    }

    @Test func aPeakJustBeforeTheRestStartedCountsTowardTheDrop() {
        let rest = recovered.filter { $0.0 >= 15 }
        #expect(settled([(-10, 150)] + rest, at: 60))
        #expect(!settled([(-20, 150)] + rest, at: 60), "a peak older than the lookback belongs to the set before")
    }

    // MARK: - The cue

    private func cue(_ taps: Counter) -> WatchRecoveryCue {
        WatchRecoveryCue(tap: { taps.count += 1 })
    }

    private final class Counter { var count = 0 }

    private func feed(_ cue: WatchRecoveryCue, _ points: [(Double, Double)]) {
        for (offset, bpm) in points {
            let date = start.addingTimeInterval(offset)
            cue.record(bpm: bpm, at: date, now: date)
        }
    }

    @Test func theCueFiresOnceNoMatterHowLongTheHeartRateStaysFlat() {
        let taps = Counter()
        let cue = cue(taps)
        cue.beginRest(at: start)
        feed(cue, recovered + (13...30).map { (Double($0 * 5), 120) })
        #expect(cue.isSettled)
        #expect(taps.count == 1)
    }

    @Test func theNextRestGetsItsOwnCueAndEndingARestClearsIt() {
        let taps = Counter()
        let cue = cue(taps)
        cue.beginRest(at: start)
        feed(cue, recovered)
        #expect(taps.count == 1)
        cue.endRest()
        #expect(!cue.isSettled, "the cue goes with the rest")

        let next = start.addingTimeInterval(200)
        cue.beginRest(at: next)
        for (offset, bpm) in recovered {
            let date = next.addingTimeInterval(offset)
            cue.record(bpm: bpm, at: date, now: date)
        }
        #expect(taps.count == 2)
    }

    @Test func noRestMeansNoCue() {
        let taps = Counter()
        let cue = cue(taps)
        feed(cue, recovered)
        #expect(taps.count == 0)
        #expect(!cue.isSettled)
    }

    @Test func aCueTurnedOffStaysSilent() {
        let taps = Counter()
        let cue = cue(taps)
        cue.isEnabled = false
        cue.beginRest(at: start)
        feed(cue, recovered)
        #expect(taps.count == 0)
        #expect(!cue.isSettled)
    }

    @Test func theRestTimerStartsAndEndsTheCueWithoutTouchingTheCountdown() {
        let taps = Counter()
        let timer = WatchRestTimer(restOver: {}, recovery: cue(taps))
        timer.startLocal(seconds: 600, now: start)
        feed(timer.recovery, recovered)
        #expect(timer.recovery.isSettled)
        #expect(timer.isRunning, "settling does not end the rest")
        #expect(timer.endsAt == start.addingTimeInterval(600))

        timer.stop(silently: true)
        #expect(!timer.recovery.isSettled)
    }
}
