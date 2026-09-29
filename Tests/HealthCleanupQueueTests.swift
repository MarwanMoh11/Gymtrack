import Foundation

/// Run with scripts/test-health-cleanup-queue.sh; no simulator, watch or
/// Health access needed.
///
/// HealthKit itself cannot be reached from here, so what is proven is the list
/// around it: what is queued, what may leave it, and how a pass behaves when
/// Health answers each way. That `deleteWorkout` reports a workout it cannot
/// find as gone, and that the watch's samples are visible to the phone at all,
/// only a device can show.
@main
struct HealthCleanupQueueTests {

    static func entry(_ workout: UUID = UUID(), session: UUID = UUID(),
                      preferred: UUID? = nil) -> PendingWorkoutCleanup {
        PendingWorkoutCleanup(workoutID: workout, sessionID: session, preferredWorkoutID: preferred)
    }

    /// A stored list and a scripted Health, wired the way the service wires
    /// them, so a test reads as a sequence of events.
    @MainActor final class Harness {
        var queue: [PendingWorkoutCleanup]
        /// How Health answers, by workout. True is gone, a missing key is a
        /// refused or failed delete.
        var gone: [UUID: Bool] = [:]
        var deleteCalls: [UUID] = []
        var blockedLinks: Set<UUID> = []
        /// Runs while Health is "answering", to add an entry mid-pass.
        var duringDelete: (() -> Void)?

        init(_ queue: [PendingWorkoutCleanup]) { self.queue = queue }

        func pass() async {
            await HealthCleanupQueue.drain(
                load: { self.queue },
                save: { self.queue = $0 },
                prepare: { !self.blockedLinks.contains($0.workoutID) },
                delete: { id in
                    self.deleteCalls.append(id)
                    self.duringDelete?()
                    self.duringDelete = nil
                    return self.gone[id] ?? false
                })
        }
    }

    @MainActor static func main() async {
        checkNotFoundIsDropped()
        checkFailureIsKept()
        checkDeleteFromHistory()
        checkOrphan()
        checkStoredShape()
        await checkRetryOnForeground()
        await checkUnpreparedEntryWaits()
        await checkEntryAddedMidPassSurvives()
        print("Health cleanup queue: drop, keep, history delete, orphan, retry and shape checks passed")
    }

    // MARK: Settling

    /// `deleteWorkout` answers true for a workout its query cannot find, and a
    /// pass takes true as gone. The entry must not outlive a workout that is
    /// already out of Health.
    static func checkNotFoundIsDropped() {
        let a = entry(), b = entry()
        let left = HealthCleanupQueue.settle([a, b], workoutID: a.workoutID, gone: true)
        precondition(left == [b], "a workout Health reports gone leaves the list")
        precondition(HealthCleanupQueue.settle([], workoutID: a.workoutID, gone: true).isEmpty,
                     "settling an entry that is already gone is harmless")
    }

    /// A refused or failed delete is not an answer about the workout. Dropping
    /// it would strand a copy in Fitness for good.
    static func checkFailureIsKept() {
        let a = entry(), b = entry()
        precondition(HealthCleanupQueue.settle([a, b], workoutID: a.workoutID, gone: false) == [a, b],
                     "a failed delete keeps every entry")
    }

    // MARK: Queueing

    /// Deleting a session from history queues its workout with no successor,
    /// since the session it would point at is gone.
    static func checkDeleteFromHistory() {
        let workout = UUID(), session = UUID()
        let queued = HealthCleanupQueue.orphaned(workoutID: workout, sessionID: session, sessionExists: false)
        precondition(queued == entry(workout, session: session, preferred: nil),
                     "a deleted session's workout is queued without a successor")
        let list = HealthCleanupQueue.enqueue(queued!, into: [])
        precondition(list.map(\.workoutID) == [workout], "the workout is on the list")

        let again = HealthCleanupQueue.enqueue(queued!, into: list)
        precondition(again.count == 1, "a workout is queued once")

        // A replaced fallback is queued with its successor; deleting the
        // session afterwards must not lose the entry or duplicate it.
        let fallback = entry(workout, session: session, preferred: UUID())
        let replaced = HealthCleanupQueue.enqueue(queued!, into: [fallback])
        precondition(replaced == [queued!], "the newer account of the workout wins")
    }

    /// A watch workout ID for a session that no longer exists is queued, and
    /// one for a session that does exist is not: a restore may have put it
    /// back, and the workout is then its own.
    static func checkOrphan() {
        let workout = UUID(), session = UUID()
        guard let orphan = HealthCleanupQueue.orphaned(workoutID: workout, sessionID: session,
                                                       sessionExists: false) else {
            preconditionFailure("an orphan workout is queued")
        }
        precondition(HealthCleanupQueue.enqueue(orphan, into: [entry()]).contains(orphan),
                     "the orphan joins the list")
        precondition(HealthCleanupQueue.orphaned(workoutID: workout, sessionID: session,
                                                 sessionExists: true) == nil,
                     "a workout whose session is still there is left alone")
    }

    // MARK: Passes

    /// The failure the retry exists for: refused while the phone is locked,
    /// then removed by the next foreground. Queue, fail, foreground, retry,
    /// drained.
    @MainActor static func checkRetryOnForeground() async {
        let workout = UUID()
        let harness = Harness([entry(workout)])
        await harness.pass()
        precondition(harness.queue.map(\.workoutID) == [workout], "a refused delete stays queued")

        harness.gone[workout] = true
        await harness.pass()
        precondition(harness.queue.isEmpty, "the next attempt drains it")
        precondition(harness.deleteCalls == [workout, workout], "each pass tried it once")

        await harness.pass()
        precondition(harness.deleteCalls.count == 2, "an empty list asks Health nothing")

        // One pass keeps the failing entry and drops the ones Health settled.
        let gone = entry(), stuck = entry(), removed = entry()
        let mixed = Harness([gone, stuck, removed])
        mixed.gone[gone.workoutID] = true      // not found counts as gone
        mixed.gone[removed.workoutID] = true
        await mixed.pass()
        precondition(mixed.queue == [stuck], "only the unsettled entry remains")
    }

    /// A session that could not be pointed at its successor keeps its old
    /// workout: removing it first would leave the link pointing at nothing.
    @MainActor static func checkUnpreparedEntryWaits() async {
        let blocked = entry(preferred: UUID())
        let harness = Harness([blocked])
        harness.gone[blocked.workoutID] = true
        harness.blockedLinks = [blocked.workoutID]
        await harness.pass()
        precondition(harness.deleteCalls.isEmpty, "no delete before the link is safe")
        precondition(harness.queue == [blocked], "and the entry waits")

        harness.blockedLinks = []
        await harness.pass()
        precondition(harness.queue.isEmpty, "it goes once the link is saved")
    }

    /// The service can be handed a new entry while Health is answering. The
    /// pass settles against the list as it is then, not as it was when the pass
    /// began, or the new entry would be written over.
    @MainActor static func checkEntryAddedMidPassSurvives() async {
        let first = entry(), late = entry()
        let harness = Harness([first])
        harness.gone[first.workoutID] = true
        harness.duringDelete = { harness.queue = HealthCleanupQueue.enqueue(late, into: harness.queue) }
        await harness.pass()
        precondition(harness.queue == [late], "the entry added mid-pass survives, the settled one is gone")
    }

    // MARK: Storage

    /// Entries written before the successor became optional must still
    /// decode, and one without a successor must store no key for it.
    static func checkStoredShape() {
        let workout = UUID(), session = UUID(), preferred = UUID()
        let old = """
        [{"workoutID":"\(workout.uuidString)","sessionID":"\(session.uuidString)",\
        "preferredWorkoutID":"\(preferred.uuidString)"}]
        """
        let decoded = try? JSONDecoder().decode([PendingWorkoutCleanup].self, from: Data(old.utf8))
        precondition(decoded == [entry(workout, session: session, preferred: preferred)],
                     "an entry from before the change decodes")

        let none = try! JSONEncoder().encode([entry(workout, session: session)])
        let text = String(decoding: none, as: UTF8.self)
        precondition(!text.contains("preferredWorkoutID"), "no successor stores no key")
        precondition(!text.contains("null"), "and no null")
        precondition((try? JSONDecoder().decode([PendingWorkoutCleanup].self, from: none))
                     == [entry(workout, session: session)], "and it reads back")
    }
}
