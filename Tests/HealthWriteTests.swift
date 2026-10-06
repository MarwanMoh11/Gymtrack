import Foundation
import SwiftData

/// Run with scripts/test-health-write.sh; no simulator, watch or Health access
/// needed.
///
/// Three things the phone's Health code decides without HealthKit: which
/// stretches of a session become the workout's activities, when a later pass
/// may replace a set's heart rate, and whether a session held across Health's
/// awaits is still there to write to.
@main
struct HealthWriteTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 780_000_000)

    static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    static func minutes(_ value: Double) -> Date { at(value * 60) }

    @MainActor static func main() throws {
        checkSegmentation()
        checkReplacement()
        checkLedger()
        try checkLiveness()
        print("Health write: segmentation, replacement, ledger and liveness checks passed")
    }

    // MARK: Activities

    static func stamp(_ exercise: String, _ minute: Double, startedAt: Double? = nil) -> ActivitySetStamp {
        ActivitySetStamp(id: UUID(), exercise: exercise, startedAt: startedAt.map(minutes),
                         completedAt: minutes(minute))
    }

    /// Runs as (exercise, start minute, end minute), for readable comparisons.
    static func shape(_ runs: [WorkoutActivityRun]) -> [String] {
        runs.map { "\($0.exercise) \(Int($0.start.timeIntervalSince(t0) / 60))-\(Int($0.end.timeIntervalSince(t0) / 60))" }
    }

    static func assertWellFormed(_ runs: [WorkoutActivityRun], _ label: String) {
        for (index, run) in runs.enumerated() {
            precondition(run.end > run.start, "\(label): a run runs forwards")
            precondition(run.start >= t0, "\(label): a run starts inside the session")
            if index > 0 {
                precondition(run.start >= runs[index - 1].end, "\(label): runs never overlap")
            }
        }
    }

    static func checkSegmentation() {
        // The plan is bench, squat, row. The bench was taken, so the lifter
        // squatted first. Sets arrive in the session's own order.
        let outOfOrder = [
            stamp("bench", 25), stamp("bench", 30), stamp("bench", 40),
            stamp("squat", 5), stamp("squat", 10), stamp("squat", 20),
            stamp("row", 45), stamp("row", 50), stamp("row", 60),
        ]
        let reordered = WorkoutActivitySegmentation.runs(of: outOfOrder, sessionStart: t0,
                                                         sessionEnd: minutes(62))
        precondition(shape(reordered) == ["squat 0-20", "bench 20-40", "row 40-60"],
                     "Exercises follow the order they were done in, not the plan's: \(shape(reordered))")
        assertWellFormed(reordered, "out of order")

        // One make-up bench set at the end gets its own activity, and the
        // exercises between keep theirs.
        let makeUp = [
            stamp("bench", 5), stamp("bench", 10), stamp("bench", 15), stamp("bench", 50),
            stamp("squat", 20), stamp("squat", 25), stamp("squat", 30),
            stamp("row", 35), stamp("row", 40),
        ]
        let withMakeUp = WorkoutActivitySegmentation.runs(of: makeUp, sessionStart: t0, sessionEnd: minutes(55))
        precondition(shape(withMakeUp) == ["bench 0-15", "squat 15-30", "row 30-40", "bench 40-50"],
                     "A make-up set neither swallows the session nor drops what came between: \(shape(withMakeUp))")
        assertWellFormed(withMakeUp, "make-up")
        precondition(withMakeUp[0].setIDs.count == 3 && withMakeUp[3].setIDs == [makeUp[3].id],
                     "Each run carries only its own sets")

        // A superset alternates, so each round is its own pair of activities.
        let superset = [stamp("curl", 2), stamp("curl", 6), stamp("dip", 4), stamp("dip", 8)]
        let rounds = WorkoutActivitySegmentation.runs(of: superset, sessionStart: t0, sessionEnd: minutes(9))
        precondition(shape(rounds) == ["curl 0-2", "dip 2-4", "curl 4-6", "dip 6-8"],
                     "A superset reads as its rounds: \(shape(rounds))")

        // An announced start is believed inside the gap it splits, and only
        // there.
        let announced = [stamp("bench", 10), stamp("squat", 20, startedAt: 17)]
        let fromAnnounced = WorkoutActivitySegmentation.runs(of: announced, sessionStart: t0,
                                                             sessionEnd: minutes(21))
        precondition(shape(fromAnnounced) == ["bench 0-10", "squat 17-20"],
                     "An announced start inside the gap starts the run: \(shape(fromAnnounced))")
        let early = [stamp("bench", 10), stamp("squat", 20, startedAt: 8)]
        let fromEarly = WorkoutActivitySegmentation.runs(of: early, sessionStart: t0, sessionEnd: minutes(21))
        precondition(shape(fromEarly) == ["bench 0-10", "squat 10-20"],
                     "A start before the previous run ended is not believed: \(shape(fromEarly))")

        // Two exercises logged at the same instant leave the second nothing
        // to show, and a set logged after the end is held to the end.
        let batch = [stamp("bench", 10), stamp("squat", 10), stamp("row", 30)]
        let batched = WorkoutActivitySegmentation.runs(of: batch, sessionStart: t0, sessionEnd: minutes(25))
        precondition(shape(batched) == ["bench 0-10", "row 10-25"],
                     "No empty run, and nothing past the session's end: \(shape(batched))")
        assertWellFormed(batched, "batch")
    }

    // MARK: Replacing a reading

    /// A rest settling from the set before, then one set climbing out of it.
    static func bpm(_ t: TimeInterval) -> Double {
        if t < 100 { return 95 + 15 * exp(-t / 20) }
        if t <= 140 { return 95 + 45 * ((t - 100) / 40).squareRoot() }
        return 140
    }

    static func trace(through end: TimeInterval) -> [HeartRateSample] {
        stride(from: 0, through: end, by: 5).map { HeartRateSample(at: at($0), bpm: bpm($0)) }
    }

    static func checkReplacement() {
        let id = UUID()
        let timing = SetTiming(id: id, startedAt: nil, completedAt: at(150), reps: 8, heldSeconds: 0)
        func pass(_ samples: [HeartRateSample], stored: StoredSetHeartRate) -> SetHeartRateUpdate? {
            let updates = SetHeartRateAttribution.updates(samples: samples, sets: [stored], sessionStart: t0)
            precondition(updates.count <= 1)
            return updates.first
        }

        // The first pass runs while the watch's samples are still arriving:
        // the trace stops partway up the climb.
        let fresh = StoredSetHeartRate(timing: timing, hasReading: false, readFrom: nil, mayDetect: true)
        guard let first = pass(trace(through: 120), stored: fresh), let early = first.detected else {
            fatalError("A partial trace still reads the part of the set it has")
        }
        precondition(first.heartRate.source == .detected)

        // Once the rest has synced, a pass that remembers the first count
        // replaces both the window and the numbers read through it.
        let partial = StoredSetHeartRate(timing: timing.reading(through: early), hasReading: true,
                                         readFrom: first.samples, mayDetect: true)
        guard let second = pass(trace(through: 150), stored: partial), let full = second.detected else {
            fatalError("A reading from strictly more samples replaces one read off a partial trace")
        }
        precondition(second.samples > first.samples && full.end > early.end,
                     "The later window reaches past where the partial trace stopped")
        precondition(second.heartRate.peak > first.heartRate.peak)

        // The same trace again gains nothing, so nothing is written.
        let settled = StoredSetHeartRate(timing: timing.reading(through: full), hasReading: true,
                                         readFrom: second.samples, mayDetect: true)
        precondition(pass(trace(through: 150), stored: settled) == nil,
                     "An equal count is not better, and a pass must not rewrite what it already has")

        // A reading nobody here remembers taking, restored or from an older
        // build, has no count to beat and is left alone.
        let restored = StoredSetHeartRate(timing: timing.reading(through: early), hasReading: true,
                                          readFrom: nil, mayDetect: true)
        precondition(pass(trace(through: 150), stored: restored) == nil,
                     "A reading with no remembered count is never replaced")

        // An inferred reading improves the same way, through the same window.
        let plain = SetTiming(id: id, startedAt: nil, completedAt: at(150), reps: 8, heldSeconds: 0)
        let inferredFresh = StoredSetHeartRate(timing: plain, hasReading: false, readFrom: nil, mayDetect: false)
        let flat = stride(from: 130.0, through: 150, by: 5).map { HeartRateSample(at: at($0), bpm: 120) }
        guard let thin = pass(Array(flat.prefix(2)), stored: inferredFresh) else {
            fatalError("Two beats in the window are a reading")
        }
        precondition(thin.heartRate.source == .inferred && thin.detected == nil && thin.samples == 2)
        let thinStored = StoredSetHeartRate(timing: plain, hasReading: true, readFrom: 2, mayDetect: false)
        precondition(pass(flat, stored: thinStored)?.samples == flat.count,
                     "More beats in the same inferred window replace the thin reading")

        // Nothing is ever read from nothing: no samples, or only dropped
        // readings of zero, write no key at all.
        precondition(pass([], stored: fresh) == nil)
        let dropped = stride(from: 0.0, through: 150, by: 5).map { HeartRateSample(at: at($0), bpm: 0) }
        precondition(pass(dropped, stored: fresh) == nil, "A zero heart rate is a dropped reading, never a value")

        precondition(SetHeartRateAttribution.mayReplace(hasReading: false, readFrom: nil, samples: 1))
        precondition(SetHeartRateAttribution.mayReplace(hasReading: false, readFrom: 9, samples: 1),
                     "A set with no reading is always open, whatever the ledger remembers")
        precondition(!SetHeartRateAttribution.mayReplace(hasReading: true, readFrom: nil, samples: 99))
        precondition(!SetHeartRateAttribution.mayReplace(hasReading: true, readFrom: 5, samples: 5))
        precondition(SetHeartRateAttribution.mayReplace(hasReading: true, readFrom: 5, samples: 6))
    }

    static func checkLedger() {
        let suite = "com.marwanmohamed.gymtrack.tests.health-write"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = SetHeartRateLedger(defaults: defaults)
        let first = UUID(), second = UUID()
        ledger.record([first: 3, second: 7], now: t0)
        precondition(ledger.samples(now: at(60)) == [first: 3, second: 7])
        ledger.record([first: 5], now: at(120))
        precondition(ledger.samples(now: at(180)) == [first: 5, second: 7], "A later count replaces the earlier")
        let later = at(120 + SetHeartRateLedger.keptFor + 1)
        precondition(ledger.samples(now: later).isEmpty, "Past two days every set is closed to further passes")

        let many = Dictionary(uniqueKeysWithValues: (0..<(SetHeartRateLedger.limit + 50)).map { (UUID(), $0) })
        ledger.record(many, now: t0)
        precondition(ledger.samples(now: t0).count == SetHeartRateLedger.limit, "The ledger stays bounded")
    }

    // MARK: Liveness

    @MainActor static func checkLiveness() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        func byID(_ id: UUID) -> FetchDescriptor<WorkoutSession> {
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        }

        // Deleted through the context that holds it: gone before the save,
        // and still gone after it, when `isDeleted` reads false again.
        let context = ModelContext(container)
        let held = WorkoutSession(title: "Held across Health")
        context.insert(held)
        try context.save()
        let heldID = held.id
        precondition(!held.isGoneFromStore && !held.isGone(fromStore: byID(heldID)), "A saved session is alive")
        context.delete(held)
        precondition(held.isGoneFromStore, "A deleted session is gone before the save")
        try context.save()
        precondition(!held.isDeleted, "SwiftData reads a saved delete as not deleted; the check must not rely on it")
        precondition(held.isGoneFromStore && held.isGone(fromStore: byID(heldID)),
                     "A saved delete is still gone")

        // Deleted through another context, the way an erase from the screen
        // meets a session the headless finish is holding.
        let headless = ModelContext(container)
        let finished = WorkoutSession(title: "Finished on the wrist")
        headless.insert(finished)
        try headless.save()
        let finishedID = finished.id
        let screen = ModelContext(container)
        for session in try screen.fetch(byID(finishedID)) { screen.delete(session) }
        try screen.save()
        precondition(!finished.isGoneFromStore, "Another context's delete leaves this instance looking alive")
        precondition(finished.isGone(fromStore: byID(finishedID)), "The store says it is gone")

        // Replaced by a restore: a new row with the same ID is not the model
        // that was held.
        let original = WorkoutSession(title: "Before restore")
        headless.insert(original)
        try headless.save()
        let originalID = original.id
        for session in try screen.fetch(byID(originalID)) { screen.delete(session) }
        let restored = WorkoutSession(title: "Restored")
        restored.id = originalID
        screen.insert(restored)
        try screen.save()
        precondition(original.isGone(fromStore: byID(originalID)),
                     "A restored row with the same ID is not the session that was held")
        precondition(!restored.isGone(fromStore: byID(originalID)), "The restored row itself is alive")

        // The pass that holds a session stops at the first check after the
        // delete, and writes nothing after it.
        let pass = ModelContext(container)
        let session = WorkoutSession(title: "Mid-pass")
        pass.insert(session)
        try pass.save()
        let sessionID = session.id
        var steps = 0
        for step in 0..<5 {
            if session.isGone(fromStore: byID(sessionID)) { break }
            steps += 1
            if step == 1 {
                pass.delete(session)
                try pass.save()
            }
        }
        precondition(steps == 2, "Stopped at the first check after the delete, not \(steps) steps in")
    }
}
