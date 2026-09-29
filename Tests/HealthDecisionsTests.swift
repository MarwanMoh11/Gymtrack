import Foundation

/// Run with scripts/test-health-decisions.sh; no simulator or Health store is
/// needed.
///
/// The decisions `HealthKitService` makes about duplicate workouts, pulled out
/// of its HealthKit calls (XC-05): whether a session may be written, what to do
/// with a workout once it is written, which workouts go into a delete, whether
/// an entry's session needs relinking, and when the cleanup list is worked
/// through again. HealthCleanupQueueTests covers the list itself; this covers
/// what the service asks of it.
@main
struct HealthDecisionsTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    @MainActor
    static func main() async {
        writeOnlyWhatHasNoWorkout()
        writtenWorkoutOutcomes()
        relinkOnlyWhatStillPointsAtTheOldWorkout()
        deletePlanKeepsOthersAlone()
        gateCoalescesRequests()
        await requestDuringAPassRunsAnotherPass()
        await requestWhileRunningDoesNotOverlap()

        guard failures == 0 else {
            print("\(failures) health decision check(s) failed")
            exit(1)
        }
        print("Health decisions: write, outcome, relink, delete plan and retry gate checks passed")
    }

    static func writeOnlyWhatHasNoWorkout() {
        check(PhoneWorkoutWrite.shouldWrite(sessionGone: false, linkedWorkoutID: nil),
              "A live session with no workout is written")
        check(!PhoneWorkoutWrite.shouldWrite(sessionGone: false, linkedWorkoutID: UUID()),
              "A session the watch already saved must not get a second workout")
        check(!PhoneWorkoutWrite.shouldWrite(sessionGone: true, linkedWorkoutID: nil),
              "A deleted session is not written")
    }

    static func writtenWorkoutOutcomes() {
        let written = UUID(), watch = UUID()
        check(PhoneWorkoutWrite.outcome(written: nil, sessionGone: false, linkedWorkoutID: nil) == .nothing,
              "Health handing back nothing leaves nothing to keep or remove")
        check(PhoneWorkoutWrite.outcome(written: nil, sessionGone: true, linkedWorkoutID: watch) == .nothing,
              "No workout means nothing to queue whatever became of the session")
        check(PhoneWorkoutWrite.outcome(written: written, sessionGone: false, linkedWorkoutID: nil) == .link,
              "An unclaimed session takes the phone's workout")
        check(PhoneWorkoutWrite.outcome(written: written, sessionGone: true, linkedWorkoutID: nil)
              == .removeAsOrphan, "A session removed during the write leaves an orphan to remove")
        check(PhoneWorkoutWrite.outcome(written: written, sessionGone: true, linkedWorkoutID: watch)
              == .removeAsOrphan, "A gone session is an orphan even if it held a link when it went")
        check(PhoneWorkoutWrite.outcome(written: written, sessionGone: false, linkedWorkoutID: watch)
              == .removeAsDuplicate(keeping: watch),
              "A watch workout that landed mid-write stays and the phone's copy goes")
    }

    static func relinkOnlyWhatStillPointsAtTheOldWorkout() {
        let old = UUID(), next = UUID()
        check(CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: true, sessionLink: old, workoutID: old),
              "A session still pointing at the workout being removed moves to its successor")
        check(!CleanupRelink.isNeeded(preferredWorkoutID: nil, sessionFound: true, sessionLink: old, workoutID: old),
              "No successor, nothing to link")
        check(!CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: false, sessionLink: nil, workoutID: old),
              "A session that is gone has nothing to relink")
        check(!CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: true, sessionLink: UUID(), workoutID: old),
              "A session already pointing elsewhere is not overwritten")
        check(!CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: true, sessionLink: nil, workoutID: old),
              "A session with no link is not given one by a cleanup")
    }

    static func deletePlanKeepsOthersAlone() {
        let a = UUID(), b = UUID(), c = UUID(), missing = UUID()
        check(WorkoutDeletionPlan.unique([a, b, a, c, b]) == [a, b, c], "IDs are asked for once, in order")
        check(WorkoutDeletionPlan.unique([]).isEmpty, "Nothing asked, nothing planned")

        let found = [WorkoutDeletionPlan.Found(id: c, ours: true),
                     WorkoutDeletionPlan.Found(id: b, ours: false),
                     WorkoutDeletionPlan.Found(id: a, ours: true)]
        let wanted = [a, b, c, missing]
        check(Set(WorkoutDeletionPlan.toDelete(found: found)) == [a, c],
              "Only workouts this app or its watch wrote go into the delete")
        check(WorkoutDeletionPlan.remaining(wanted: wanted, found: found, deleteFailed: false) == [b],
              "Deleted and unfindable IDs are gone; another app's workout remains")
        check(WorkoutDeletionPlan.remaining(wanted: wanted, found: found, deleteFailed: true) == [a, b, c],
              "A refused batch removed nothing: every found ID remains, in the order asked, and the unfindable one is still gone")
        check(WorkoutDeletionPlan.remaining(wanted: [missing], found: [], deleteFailed: false).isEmpty,
              "A workout Health cannot find is already gone")
    }

    static func gateCoalescesRequests() {
        var gate = CleanupPassGate()
        check(gate.begin(), "The first request runs a pass")
        check(!gate.begin() && gate.requested, "A request during a pass is recorded, not run")
        gate.startPass()
        check(!gate.wantsAnotherPass, "Starting a pass consumes the requests made before it")
        check(!gate.begin() && gate.wantsAnotherPass, "A request made mid-pass asks for another")
        gate.end()
        check(gate.begin(), "After a pass ends the next request runs")
    }

    /// The loop `retryPendingWorkoutCleanup` runs, over a real drain.
    @MainActor
    final class Harness {
        var gate = CleanupPassGate()
        var stored: [PendingWorkoutCleanup]
        var passes = 0
        var deleting = 0
        var maxDeleting = 0
        var onDelete: ((Harness) -> Void)?

        init(_ stored: [PendingWorkoutCleanup]) { self.stored = stored }

        func run() async {
            guard gate.begin() else { return }
            defer { gate.end() }
            repeat {
                gate.startPass()
                passes += 1
                await HealthCleanupQueue.drain(
                    load: { self.stored }, save: { self.stored = $0 },
                    prepare: { _ in true },
                    delete: { _ in
                        self.deleting += 1
                        self.maxDeleting = max(self.maxDeleting, self.deleting)
                        self.onDelete?(self)
                        await Task.yield()
                        self.deleting -= 1
                        return true
                    })
            } while gate.wantsAnotherPass
        }
    }

    static func entry() -> PendingWorkoutCleanup {
        PendingWorkoutCleanup(workoutID: UUID(), sessionID: UUID(), preferredWorkoutID: nil)
    }

    /// An entry queued while a delete is in flight arrives after the pass has
    /// read the list, so only a second pass removes it.
    @MainActor
    static func requestDuringAPassRunsAnotherPass() async {
        let harness = Harness([entry()])
        harness.onDelete = { h in
            h.onDelete = nil
            h.stored = HealthCleanupQueue.enqueue(entry(), into: h.stored)
            Task { await h.run() }
        }
        await harness.run()
        check(harness.stored.isEmpty, "An entry added mid-pass is removed by the pass it asked for")
        check(harness.passes == 2, "That took exactly one extra pass, not more")
    }

    @MainActor
    static func requestWhileRunningDoesNotOverlap() async {
        let harness = Harness([entry(), entry(), entry()])
        async let first: Void = harness.run()
        async let second: Void = harness.run()
        _ = await (first, second)
        check(harness.maxDeleting == 1, "Two callers never run deletes at the same time")
        check(harness.stored.isEmpty, "The list is worked through")
    }
}
