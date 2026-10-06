import Foundation
import Testing
@testable import GymTrack

/// Reading a set off the heart rate the wrist recorded (`SetEffortDetection`),
/// and choosing the window a set's heart rate is then read through
/// (`SetHeartRateAttribution`). Both are pure functions over plain samples, so
/// every trace here is made up and every run reads the same numbers; no watch,
/// Health or store is involved.
///
/// Most of these are traces that must be refused. A window placed on the wrong
/// effort travels into the export labelled as read off this set, which is worse
/// than the assumed tail it would have replaced.
@MainActor @Suite(.serialized)
struct SetHeartRateTests {

    nonisolated static let t0 = TestClock.reference

    /// A few beats of wrist noise, repeating, so every run reads the same trace.
    nonisolated static let wobble: [Double] = [0, 1.5, -1, 2, -1.5, 0.5, -2, 1]

    /// One rest and the set after it, loosely after what a wrist records:
    /// settling from whatever came before, flat through the rest, a quick jump
    /// at the first rep and a steadier climb, a couple of beats of creep after
    /// the bar is racked, then recovery. Times are seconds after `t0`.
    struct Effort: Sendable {
        var opens: TimeInterval = 0
        var restFrom: Double = 110
        var rest: Double = 95
        var begins: TimeInterval = 100
        var ends: TimeInterval = 140
        var peak: Double = 145

        func bpm(_ t: TimeInterval) -> Double {
            if t < begins { return rest + (restFrom - rest) * exp(-(t - opens) / 20) }
            if t <= ends { return rest + (peak - 2 - rest) * ((t - begins) / (ends - begins)).squareRoot() }
            if t <= ends + 5 { return peak - 2 + 2 * (t - ends) / 5 }
            return rest + (peak - rest) * exp(-(t - ends - 5) / 40)
        }
    }

    private static func trace(from start: TimeInterval = 0, to end: TimeInterval, every step: TimeInterval = 5,
                              noise: Double = 1, _ bpm: (TimeInterval) -> Double) -> [HeartRateSample] {
        stride(from: start, through: end, by: step).enumerated().map { index, t in
            HeartRateSample(at: t0.addingTimeInterval(t), bpm: bpm(t) + noise * wobble[index % wobble.count])
        }
    }

    private static func detect(_ samples: [HeartRateSample], after lowerBound: TimeInterval = 0,
                               loggedAt: TimeInterval) -> DetectedSetWindow? {
        SetEffortDetection.window(in: samples, after: at(lowerBound), loggedAt: at(loggedAt))
    }

    private static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private static func seconds(_ date: Date) -> TimeInterval { date.timeIntervalSince(t0) }

    // MARK: - Finding the set in the gap

    @Test func aPlainRestAndSetIsReadToWithinAReading() throws {
        let clean = Effort()
        let found = try #require(Self.detect(Self.trace(to: 150, clean.bpm), loggedAt: 150))
        #expect(abs(Self.seconds(found.start) - clean.begins) <= 5)
        #expect(abs(Self.seconds(found.end) - clean.ends) <= 5)
    }

    enum Unreadable: String, CaseIterable, Sendable {
        case flat, climbUnderTwelveBeats, singleReadingSpike, climbOverMinutes, readingsTwentySecondsApart
    }

    @Test(arguments: Unreadable.allCases)
    func aTraceWithoutOneClearClimbHasNoSetInIt(_ unreadable: Unreadable) {
        let samples: [HeartRateSample]
        let loggedAt: TimeInterval
        switch unreadable {
        case .flat:
            samples = Self.trace(to: 150) { _ in 95 }
            loggedAt = 150
        case .climbUnderTwelveBeats:
            // The rest wandering, not a set.
            samples = Self.trace(to: 150, Effort(restFrom: 95, peak: 101).bpm)
            loggedAt = 150
        case .singleReadingSpike:
            // A glitch, not a set.
            samples = Self.trace(to: 150) { $0 == 100 ? 130 : 95 }
            loggedAt = 150
        case .climbOverMinutes:
            samples = Self.trace(to: 400) { 90 + 40 * min(1, $0 / 360) }
            loggedAt = 400
        case .readingsTwentySecondsApart:
            // Too sparse to place the start.
            samples = Self.trace(to: 150, every: 20, Effort().bpm)
            loggedAt = 150
        }
        #expect(Self.detect(samples, loggedAt: loggedAt) == nil)
    }

    /// Two sets done and both logged at the end.
    struct Batch: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let first: Effort
        let second: Effort
    }

    nonisolated static let batches: [Batch] = [
        Batch(testDescription: "second higher",
              first: Effort(restFrom: 95, begins: 60, ends: 100, peak: 140),
              second: Effort(opens: 150, restFrom: 110, rest: 100, begins: 190, ends: 230, peak: 150)),
        Batch(testDescription: "second lower",
              first: Effort(restFrom: 95, begins: 60, ends: 100, peak: 150),
              second: Effort(opens: 150, restFrom: 120, rest: 110, begins: 190, ends: 230, peak: 135)),
        Batch(testDescription: "rest dips below the first floor",
              first: Effort(restFrom: 100, rest: 100, begins: 60, ends: 100, peak: 140),
              second: Effort(opens: 150, restFrom: 110, rest: 88, begins: 190, ends: 230, peak: 145)),
    ]

    /// However the two climbs compare, the first log must not be handed either
    /// of them, and the second, logged seconds later, has no trace of its own.
    @Test(arguments: SetHeartRateTests.batches)
    func twoSetsLoggedTogetherGiveNeitherLogAClimb(_ batch: Batch) {
        let both = Self.trace(to: 240) { $0 < 150 ? batch.first.bpm($0) : batch.second.bpm($0) }
        #expect(Self.detect(both, loggedAt: 238) == nil)
        #expect(Self.detect(both, after: 238, loggedAt: 241) == nil)
    }

    /// The gap opens on the last set's heart rate still settling, a few beats of
    /// creep and then a long fall. The fall is not this set.
    @Test func theLastSetsRecoveryAtTheTopOfTheGapIsNotThisSet() throws {
        let settling = Effort(opens: 10, restFrom: 154, rest: 100, begins: 120, ends: 160, peak: 145)
        let afterglow = Self.trace(to: 170) { $0 < 10 ? 150 + 0.4 * $0 : settling.bpm($0) }

        let found = try #require(Self.detect(afterglow, loggedAt: 170))
        #expect(abs(Self.seconds(found.start) - settling.begins) <= 5)
        #expect(abs(Self.seconds(found.end) - settling.ends) <= 5)
    }

    /// Logged as the bar went back after a hard set: the heart rate goes on
    /// climbing well past the log before it turns. That climb is the last set's,
    /// and must neither be read as this one nor make the gap ambiguous.
    @Test func theLastSetsClimbPastItsLogIsNeitherThisSetNorAReasonToGiveUp() throws {
        let promptLog = Effort(opens: 15, restFrom: 158, rest: 100, begins: 120, ends: 160, peak: 145)
        let stillClimbing = Self.trace(to: 170) { $0 < 15 ? 140 + 18 * $0 / 15 : promptLog.bpm($0) }

        let found = try #require(Self.detect(stillClimbing, loggedAt: 170))
        #expect(abs(Self.seconds(found.start) - promptLog.begins) <= 5)
    }

    /// Straight back under the bar before the last set's climb had turned: no
    /// rest shows in the trace, so there is no floor to start the set from.
    @Test func aSetBegunBeforeTheLastOneSettledHasNoRestToStartFrom() {
        let noRest = Self.trace(to: 80, noise: 0) { $0 < 20 ? 140 + $0 : 160 + 0.4 * ($0 - 20) }
        #expect(Self.detect(noRest, loggedAt: 80) == nil)
    }

    @Test func aSetLoggedAMinuteLateStillEndedWhenTheBarWentBack() throws {
        let clean = Effort()
        let late = try #require(Self.detect(Self.trace(to: 200, clean.bpm), loggedAt: 200))
        #expect(abs(Self.seconds(late.end) - clean.ends) <= 5)
    }

    @Test func eachSetsGapOpensWhereTheOneBeforeWasLoggedAndOnlyTheSetsAskedAboutAreRead() throws {
        let first = Effort()
        let second = Effort(opens: 150, restFrom: first.bpm(150), rest: 97, begins: 250, ends: 280, peak: 140)
        let session = Self.trace(to: 290) { $0 < 150 ? first.bpm($0) : second.bpm($0) }
        let firstID = UUID(), secondID = UUID()
        // Out of order on purpose: the walk sorts by when each was logged.
        let timings = [
            SetTiming(id: secondID, startedAt: nil, completedAt: Self.at(290), reps: 8, heldSeconds: 0),
            SetTiming(id: firstID, startedAt: nil, completedAt: Self.at(150), reps: 8, heldSeconds: 0),
        ]

        let both = SetHeartRateAttribution.detectedWindows(samples: session, for: timings, sessionStart: Self.t0,
                                                           candidates: [firstID, secondID])
        #expect(both.count == 2)
        let secondWindow = try #require(both[secondID])
        #expect(abs(Self.seconds(secondWindow.start) - second.begins) <= 5)

        let onlySecond = SetHeartRateAttribution.detectedWindows(samples: session, for: timings,
                                                                 sessionStart: Self.t0, candidates: [secondID])
        #expect(Array(onlySecond.keys) == [secondID])
    }

    // MARK: - Which window a set is read through

    private func window(startedAt: Date?, detected: DetectedSetWindow?,
                        after previous: TimeInterval = 0) -> HeartRateWindow? {
        SetHeartRateAttribution.window(
            for: SetTiming(id: UUID(), startedAt: startedAt, completedAt: Self.at(150), reps: 8, heldSeconds: 0,
                           detected: detected),
            after: Self.at(previous))
    }

    /// Announced beats detected beats inferred, and each is held to the gap it
    /// claims to sit in.
    @Test func anAnnouncedStartOutranksADetectedWindowWhichOutranksTheAssumedTail() throws {
        let detected = try #require(Self.detect(Self.trace(to: 150, Effort().bpm), loggedAt: 150))

        let announced = try #require(window(startedAt: Self.at(98), detected: detected))
        #expect(announced.source == .measured)
        #expect(announced.start == Self.at(98) && announced.end == Self.at(150))

        let read = try #require(window(startedAt: nil, detected: detected))
        #expect(read.source == .detected)
        #expect(read.start == detected.start && read.end == detected.end)

        // A start outside its gap falls through to the detected window, not past it.
        let unbelievable = window(startedAt: Self.at(-30), detected: detected)
        #expect(unbelievable?.source == .detected)

        let assumed = try #require(window(startedAt: nil, detected: nil))
        #expect(assumed.source == .inferred)
        #expect(assumed.end == Self.at(150))

        // A detected window reaching into the set before is not believed.
        let stale = window(startedAt: nil, detected: detected, after: 110)
        #expect(stale?.source == .inferred)
    }

    @Test func aHeartRateReadThroughADetectedWindowSaysSoAndPeaksOnlyInsideIt() throws {
        let samples = Self.trace(to: 150, Effort().bpm)
        let detected = try #require(Self.detect(samples, loggedAt: 150))
        let id = UUID()
        let timing = SetTiming(id: id, startedAt: nil, completedAt: Self.at(150), reps: 8, heldSeconds: 0,
                               detected: detected)

        let heartRate = try #require(SetHeartRateAttribution.attribute(samples: samples, to: [timing],
                                                                       sessionStart: Self.t0)[id])

        #expect(heartRate.source == .detected)
        let inWindow = samples.filter { $0.start >= detected.start && $0.start <= detected.end }.map(\.bpm)
        #expect(heartRate.peak == inWindow.max())
    }
}
