import Foundation

/// Run with scripts/test-health-leftovers.sh; no simulator or Health store is
/// needed.
///
/// Two decisions `HealthKitService` used to leave to chance. The cleanup list
/// retried a refused delete forever and told nobody (HK-06), and a session's
/// energy was added up from every wrist slice, so two watch apps writing the
/// same minutes counted twice (DATA-10).
@main
struct HealthLeftoversTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func main() {
        refusalsCountOnSeparateOccasions()
        capGivesUpAndRemembers()
        lockedPhoneCostsNothing()
        goneClearsTheCount()
        reopenGivesOneMoreAttempt()
        givenUpListIsBounded()
        ledgerSurvivesEncoding()
        trustedSourcesAreWristOnly()
        energyIsNilWithoutAMeasurement()
        energyKeepsTheSumAndTheSpan()

        guard failures == 0 else {
            print("\(failures) health leftover check(s) failed")
            exit(1)
        }
        print("Health leftovers: cleanup cap and wrist energy checks passed")
    }

    static let workout = UUID()
    static let session = UUID()
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Fails `count` times, each `gap` seconds after the last.
    static func refuse(_ ledger: inout CleanupAttemptLedger, _ count: Int, gap: TimeInterval,
                       workout: UUID = workout, from start: Date = t0) -> [Bool] {
        (0..<count).map { i in
            ledger.record(.refused, workoutID: workout, sessionID: session,
                          at: start.addingTimeInterval(Double(i) * gap))
        }
    }

    static func refusalsCountOnSeparateOccasions() {
        var ledger = CleanupAttemptLedger()
        // A burst of passes inside one minute is one occasion, however many.
        let burst = refuse(&ledger, 20, gap: 3)
        check(burst.allSatisfy { !$0 }, "A burst of refusals within one occasion never gives up")
        check(ledger.struggling.first?.failures == 1, "A burst counts as one failure")
        check(ledger.givenUp.isEmpty, "Nothing is given up after a burst")
    }

    static func capGivesUpAndRemembers() {
        var ledger = CleanupAttemptLedger()
        let gap = CleanupAttemptLedger.minimumSpacing + 1
        let answers = refuse(&ledger, CleanupAttemptLedger.cap, gap: gap)
        check(Array(answers.dropLast()).allSatisfy { !$0 }, "The entry stays on the list until the cap")
        check(answers.last == true, "The last failure the cap allows takes the entry off the list")
        check(ledger.givenUp.map(\.workoutID) == [workout], "The workout it stopped on is kept")
        check(ledger.givenUp.first?.sessionID == session, "The session is kept with it")
        check(ledger.struggling.isEmpty, "A workout given up is no longer counted as struggling")
    }

    static func lockedPhoneCostsNothing() {
        var ledger = CleanupAttemptLedger()
        for i in 0..<50 {
            let leaves = ledger.record(.deferred, workoutID: workout, sessionID: session,
                                       at: t0.addingTimeInterval(Double(i) * 3600))
            check(!leaves, "A deferred delete keeps the entry")
        }
        check(ledger == CleanupAttemptLedger(), "A locked phone leaves no count behind")
    }

    static func goneClearsTheCount() {
        var ledger = CleanupAttemptLedger()
        _ = refuse(&ledger, 3, gap: CleanupAttemptLedger.minimumSpacing + 1)
        check(ledger.record(.gone, workoutID: workout, sessionID: session, at: t0), "Gone leaves the list")
        check(ledger == CleanupAttemptLedger(), "Gone forgets the earlier failures")
        // The count starts over: one refusal now is the first, not the fourth.
        _ = refuse(&ledger, 1, gap: 1)
        check(ledger.struggling.first?.failures == 1, "A later refusal starts a new count")
    }

    static func reopenGivesOneMoreAttempt() {
        var ledger = CleanupAttemptLedger()
        _ = refuse(&ledger, CleanupAttemptLedger.cap, gap: CleanupAttemptLedger.minimumSpacing + 1)
        let later = t0.addingTimeInterval(100_000)
        let reopened = ledger.reopen()
        check(reopened.map(\.workoutID) == [workout], "Reopen hands back what was given up")
        check(ledger.givenUp.isEmpty, "Reopen empties the notice while the attempt runs")
        check(ledger.record(.refused, workoutID: workout, sessionID: session, at: later),
              "One refusal after Retry gives up again at once")
        check(ledger.givenUp.count == 1, "The notice comes back, not another five tries")

        _ = ledger.reopen()
        check(ledger.record(.gone, workoutID: workout, sessionID: session, at: later), "A Retry that works leaves the list")
        check(ledger == CleanupAttemptLedger(), "A Retry that works leaves no notice and no count")
        check(ledger.reopen().isEmpty, "Nothing to reopen once everything is gone")
    }

    static func givenUpListIsBounded() {
        var ledger = CleanupAttemptLedger()
        let ids = (0..<(CleanupAttemptLedger.remembered + 5)).map { _ in UUID() }
        for id in ids {
            _ = refuse(&ledger, CleanupAttemptLedger.cap, gap: CleanupAttemptLedger.minimumSpacing + 1, workout: id)
        }
        check(ledger.givenUp.count == CleanupAttemptLedger.remembered, "The notice is bounded")
        check(ledger.givenUp.last?.workoutID == ids.last, "The newest is kept")
        check(!ledger.givenUp.contains { $0.workoutID == ids[0] }, "The oldest is forgotten")
    }

    static func ledgerSurvivesEncoding() {
        var ledger = CleanupAttemptLedger()
        _ = refuse(&ledger, 2, gap: CleanupAttemptLedger.minimumSpacing + 1)
        _ = refuse(&ledger, CleanupAttemptLedger.cap, gap: CleanupAttemptLedger.minimumSpacing + 1, workout: UUID())
        guard let data = try? JSONEncoder().encode(ledger),
              let decoded = try? JSONDecoder().decode(CleanupAttemptLedger.self, from: data) else {
            check(false, "The ledger encodes and decodes")
            return
        }
        check(decoded == ledger, "The ledger decodes to what was stored, so a relaunch keeps the count")
        check((try? JSONDecoder().decode(CleanupAttemptLedger.self,
                                         from: Data("{\"struggling\":[],\"givenUp\":[]}".utf8))) == CleanupAttemptLedger(),
              "An empty stored ledger decodes to an empty one")
    }

    // MARK: Energy

    static func slice(_ source: String, wrist: Bool, kcal: Double = 20, start: Double = 0, end: Double = 600) -> EnergySlice {
        EnergySlice(start: t0.addingTimeInterval(start), end: t0.addingTimeInterval(end),
                    kilocalories: kcal, sourceID: source, isFromWrist: wrist)
    }

    static func trustedSourcesAreWristOnly() {
        let slices = [slice("watch.workout", wrist: true), slice("watch.gymtrack", wrist: true),
                      slice("phone", wrist: false),
                      slice("mixed", wrist: true), slice("mixed", wrist: false)]
        check(WristEnergyRead.trustedSources(in: slices) == ["watch.workout", "watch.gymtrack"],
              "Two watch sources are trusted; the phone and a source that wrote both are not")
        check(WristEnergyRead.trustedSources(in: [slice("watch", wrist: true), slice("phone", wrist: false, kcal: 0)]) == ["watch"],
              "A zero slice from another device does not spoil a source")
        check(WristEnergyRead.trustedSources(in: []).isEmpty, "No slices, no sources")
    }

    static func energyIsNilWithoutAMeasurement() {
        let watch = [slice("watch", wrist: true)]
        check(WristEnergyRead.result(slices: watch, trusted: ["watch"], cumulativeSum: nil) == nil,
              "No answer from Health is no energy")
        check(WristEnergyRead.result(slices: watch, trusted: ["watch"], cumulativeSum: 0) == nil,
              "A zero sum is no energy, not a workout that cost nothing")
        check(WristEnergyRead.result(slices: watch, trusted: ["watch"], cumulativeSum: -3) == nil, "A negative sum is no energy")
        check(WristEnergyRead.result(slices: watch, trusted: ["watch"], cumulativeSum: .nan) == nil, "A NaN sum is no energy")
        check(WristEnergyRead.result(slices: [slice("phone", wrist: false)], trusted: [], cumulativeSum: 300) == nil,
              "A total with no trusted slice behind it is not kept")
        check(WristEnergyRead.result(slices: [slice("watch", wrist: true, kcal: 0)], trusted: ["watch"], cumulativeSum: 40) == nil,
              "A source that only wrote zeros has nothing to vouch for a sum")
    }

    static func energyKeepsTheSumAndTheSpan() {
        // Two watch apps wrote the same ten minutes, 20 kcal each. Adding the
        // slices gave 40; Health's de-duplicated sum says 20, and that is what
        // is kept.
        let slices = [slice("watch.workout", wrist: true, kcal: 20, start: 0, end: 600),
                      slice("watch.gymtrack", wrist: true, kcal: 20, start: 0, end: 600),
                      slice("phone", wrist: false, kcal: 500, start: 0, end: 3000)]
        let naive = slices.filter(\.isFromWrist).reduce(0) { $0 + $1.kilocalories }
        check(naive == 40, "The old sum counted the overlap twice")
        let trusted = WristEnergyRead.trustedSources(in: slices)
        let kept = WristEnergyRead.result(slices: slices, trusted: trusted, cumulativeSum: 20)
        check(kept?.kilocalories == 20, "The de-duplicated sum is what is kept")
        check(kept?.start == t0 && kept?.end == t0.addingTimeInterval(600),
              "The span is the wrist's, not stretched by the phone's slice")
    }
}
