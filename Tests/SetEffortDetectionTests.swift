import Foundation

/// Run with scripts/test-set-detection.sh; no simulator, watch or Health access needed.
@main
struct SetEffortDetectionTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 780_000_000)

    /// A few beats of wrist noise, repeating, so every run reads the same trace.
    static let wobble: [Double] = [0, 1.5, -1, 2, -1.5, 0.5, -2, 1]

    /// One rest and the set after it, loosely after what a wrist records:
    /// settling from whatever came before, flat through the rest, a quick jump
    /// at the first rep and a steadier climb, a couple of beats of creep after
    /// the bar is racked, then recovery.
    struct Effort {
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

    static func trace(from start: TimeInterval = 0, to end: TimeInterval, every step: TimeInterval = 5,
                      noise: Double = 1, _ bpm: (TimeInterval) -> Double) -> [HeartRateSample] {
        stride(from: start, through: end, by: step).enumerated().map { index, t in
            HeartRateSample(at: t0.addingTimeInterval(t), bpm: bpm(t) + noise * wobble[index % wobble.count])
        }
    }

    static func detect(_ samples: [HeartRateSample], after lowerBound: TimeInterval = 0,
                       loggedAt: TimeInterval) -> DetectedSetWindow? {
        SetEffortDetection.window(in: samples, after: t0.addingTimeInterval(lowerBound),
                                  loggedAt: t0.addingTimeInterval(loggedAt))
    }

    static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    static func seconds(_ date: Date) -> TimeInterval { date.timeIntervalSince(t0) }

    static func main() {
        let clean = Effort()

        guard let found = detect(trace(to: 150, clean.bpm), loggedAt: 150) else {
            fatalError("A plain rest and set must be read")
        }
        precondition(abs(seconds(found.start) - clean.begins) <= 5,
                     "Start \(seconds(found.start)) is more than a reading from \(clean.begins)")
        precondition(abs(seconds(found.end) - clean.ends) <= 5,
                     "End \(seconds(found.end)) is more than a reading from \(clean.ends)")

        precondition(detect(trace(to: 150) { _ in 95 }, loggedAt: 150) == nil,
                     "A flat trace has no set in it")
        let wobbleOnly = Effort(restFrom: 95, peak: 101)
        precondition(detect(trace(to: 150, wobbleOnly.bpm), loggedAt: 150) == nil,
                     "A climb under twelve beats is the rest wandering, not a set")
        let spike = trace(to: 150) { $0 == 100 ? 130 : 95 }
        precondition(detect(spike, loggedAt: 150) == nil, "A single-reading spike is a glitch, not a set")
        let drift = trace(to: 400) { 90 + 40 * min(1, $0 / 360) }
        precondition(detect(drift, loggedAt: 400) == nil, "A climb over minutes is not one set")

        // Batch logging: two sets done, both logged at the end. However the two
        // climbs compare, the first set must not be handed either of them.
        let batches: [(name: String, a: Effort, b: Effort)] = [
            ("second higher", Effort(restFrom: 95, begins: 60, ends: 100, peak: 140),
             Effort(opens: 150, restFrom: 110, rest: 100, begins: 190, ends: 230, peak: 150)),
            ("second lower", Effort(restFrom: 95, begins: 60, ends: 100, peak: 150),
             Effort(opens: 150, restFrom: 120, rest: 110, begins: 190, ends: 230, peak: 135)),
            ("rest dips below the first floor", Effort(restFrom: 100, rest: 100, begins: 60, ends: 100, peak: 140),
             Effort(opens: 150, restFrom: 110, rest: 88, begins: 190, ends: 230, peak: 145)),
        ]
        for batch in batches {
            let both = trace(to: 240) { $0 < 150 ? batch.a.bpm($0) : batch.b.bpm($0) }
            precondition(detect(both, loggedAt: 238) == nil, "Batch logging (\(batch.name)) must detect nothing")
            precondition(detect(both, after: 238, loggedAt: 241) == nil,
                         "A set logged seconds after the one before has no trace of its own")
        }

        precondition(detect(trace(to: 150, every: 20, clean.bpm), loggedAt: 150) == nil,
                     "Readings twenty seconds apart can't place the start")

        // The gap opens on the last set's heart rate still settling, a few
        // beats of creep and then a long fall. The fall is not this set.
        let settling = Effort(opens: 10, restFrom: 154, rest: 100, begins: 120, ends: 160, peak: 145)
        let afterglow = trace(to: 170) { $0 < 10 ? 150 + 0.4 * $0 : settling.bpm($0) }
        guard let recovered = detect(afterglow, loggedAt: 170) else {
            fatalError("A set after a recovering heart rate must still be read")
        }
        precondition(abs(seconds(recovered.start) - settling.begins) <= 5,
                     "The recovery at the top of the gap was read as the set")
        precondition(abs(seconds(recovered.end) - settling.ends) <= 5)

        // Logged as the bar went back after a hard set: the heart rate goes on
        // climbing well past the log before it turns. That climb is the last
        // set's, and must neither be read as this one nor make the gap ambiguous.
        let promptLog = Effort(opens: 15, restFrom: 158, rest: 100, begins: 120, ends: 160, peak: 145)
        let stillClimbing = trace(to: 170) { $0 < 15 ? 140 + 18 * $0 / 15 : promptLog.bpm($0) }
        guard let afterPrompt = detect(stillClimbing, loggedAt: 170) else {
            fatalError("A set after the last one's heart rate kept climbing past its log must still be read")
        }
        precondition(abs(seconds(afterPrompt.start) - promptLog.begins) <= 5,
                     "The last set's climb past its log was read as this set")

        // Straight back under the bar before the last set's climb had turned:
        // no rest shows in the trace, so there is no floor to start the set from.
        let noRest = trace(to: 80, noise: 0) { $0 < 20 ? 140 + $0 : 160 + 0.4 * ($0 - 20) }
        precondition(detect(noRest, loggedAt: 80) == nil,
                     "A set begun inside the last one's settling has no rest to start from")

        // Logged a minute after the bar went back: the set still ended then.
        guard let late = detect(trace(to: 200, clean.bpm), loggedAt: 200) else {
            fatalError("A set logged late must still be read")
        }
        precondition(abs(seconds(late.end) - clean.ends) <= 5,
                     "End \(seconds(late.end)) follows the log instead of the plateau")

        // Each set's gap opens where the one before it was logged.
        let first = Effort()
        let second = Effort(opens: 150, restFrom: first.bpm(150), rest: 97, begins: 250, ends: 280, peak: 140)
        let session = trace(to: 290) { $0 < 150 ? first.bpm($0) : second.bpm($0) }
        let firstID = UUID(), secondID = UUID()
        let timings = [
            SetTiming(id: secondID, startedAt: nil, completedAt: at(290), reps: 8, heldSeconds: 0),
            SetTiming(id: firstID, startedAt: nil, completedAt: at(150), reps: 8, heldSeconds: 0),
        ]
        let both = SetHeartRateAttribution.detectedWindows(samples: session, for: timings, sessionStart: t0,
                                                           candidates: [firstID, secondID])
        precondition(both.count == 2, "Two plain sets in a row are both read")
        precondition(abs(seconds(both[secondID]!.start) - second.begins) <= 5,
                     "The second set's gap must open at the first set's log")
        let onlySecond = SetHeartRateAttribution.detectedWindows(samples: session, for: timings,
                                                                 sessionStart: t0, candidates: [secondID])
        precondition(onlySecond.keys.elementsEqual([secondID]), "Only the sets asked about are read")

        checkPrecedence(detected: found)
        print("Set detection: clean, flat, wobble, spike, drift, batch, sparse, recovery, prompt-log, no-rest, late-log, walk and precedence checks passed")
    }

    /// Announced beats detected beats inferred, and each is held to the gap it
    /// claims to sit in.
    static func checkPrecedence(detected: DetectedSetWindow) {
        let id = UUID()
        func window(startedAt: Date?, detected: DetectedSetWindow?, after previous: TimeInterval = 0) -> HeartRateWindow? {
            SetHeartRateAttribution.window(
                for: SetTiming(id: id, startedAt: startedAt, completedAt: at(150), reps: 8, heldSeconds: 0,
                               detected: detected),
                after: at(previous))
        }

        let announced = window(startedAt: at(98), detected: detected)
        precondition(announced?.source == .measured && announced?.start == at(98) && announced?.end == at(150),
                     "An announced start outranks anything read off the heart rate")

        let read = window(startedAt: nil, detected: detected)
        precondition(read?.source == .detected && read?.start == detected.start && read?.end == detected.end,
                     "A detected window outranks the assumed tail")

        let unbelievable = window(startedAt: at(-30), detected: detected)
        precondition(unbelievable?.source == .detected,
                     "A start outside its gap falls through to the detected window, not past it")

        let assumed = window(startedAt: nil, detected: nil)
        precondition(assumed?.source == .inferred && assumed?.end == at(150))

        let stale = window(startedAt: nil, detected: detected, after: 110)
        precondition(stale?.source == .inferred, "A detected window reaching into the set before is not believed")

        let samples = trace(to: 150, Effort().bpm)
        let timing = SetTiming(id: id, startedAt: nil, completedAt: at(150), reps: 8, heldSeconds: 0,
                               detected: detected)
        let heartRate = SetHeartRateAttribution.attribute(samples: samples, to: [timing], sessionStart: t0)[id]
        precondition(heartRate?.source == .detected, "A heart rate read through a detected window says so")
        let inWindow = samples.filter { $0.start >= detected.start && $0.start <= detected.end }.map(\.bpm)
        precondition(heartRate?.peak == inWindow.max(), "The peak is read over the detected window and nothing else")
    }
}
