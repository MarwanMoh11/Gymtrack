import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// The decisions `HealthKitService` makes without HealthKit, run against
/// made-up answers from Health: the cleanup list and its attempt cap, whether a
/// session may be written and what becomes of the workout once it is, which
/// workouts go into a delete, the workout's activities, when a set's heart rate
/// may be read again, the energy a session keeps, and whether a session held
/// across Health's awaits is still there.
///
/// The Health store can't be reached from a test, so what is proven is the code
/// around it. That `deleteWorkout` reports a workout it cannot find as gone, and
/// that the watch's samples reach the phone at all, only a device can show. That
/// a restore never asks Health to delete anything is in `BackupRestoreTests`.
///
/// `CapHarness` and `PassHarness` copy private loops of the service
/// (`deleteForCleanup`, `settleFailedLink` and `retryPendingWorkoutCleanup`)
/// and run them over the real `HealthCleanupQueue.drain`, so a change to those
/// loops has to be made here as well.
@MainActor @Suite(.serialized)
struct HealthKitServiceTests {

    static let t0 = TestClock.reference

    static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    static func minutes(_ value: Double) -> Date { at(value * 60) }

    /// Far enough apart that each refusal counts as an occasion of its own.
    static let spaced = CleanupAttemptLedger.minimumSpacing + 1

    /// One occasion later than the last, past the spacing that merges bursts.
    static func occasion(_ n: Int) -> Date {
        t0.addingTimeInterval(Double(n) * (CleanupAttemptLedger.minimumSpacing + 60))
    }

    static func entry(_ workout: UUID = UUID(), session: UUID = UUID(),
                      preferred: UUID? = nil) -> PendingWorkoutCleanup {
        PendingWorkoutCleanup(workoutID: workout, sessionID: session, preferredWorkoutID: preferred)
    }

    // MARK: - Settling the cleanup list

    /// `deleteWorkout` answers true for a workout its query cannot find, and a
    /// pass takes true as gone. The entry must not outlive a workout that is
    /// already out of Health.
    @Test func aWorkoutHealthReportsGoneLeavesTheList() {
        let a = Self.entry(), b = Self.entry()
        #expect(HealthCleanupQueue.settle([a, b], workoutID: a.workoutID, gone: true) == [b])
        #expect(HealthCleanupQueue.settle([], workoutID: a.workoutID, gone: true).isEmpty,
                "Settling an entry that is already gone is harmless")
    }

    /// A refused or failed delete is not an answer about the workout. Dropping
    /// it would strand a copy in Fitness for good.
    @Test func aFailedDeleteKeepsEveryEntry() {
        let a = Self.entry(), b = Self.entry()
        #expect(HealthCleanupQueue.settle([a, b], workoutID: a.workoutID, gone: false) == [a, b])
    }

    // MARK: - Queueing

    /// Deleting a session from history queues its workout with no successor,
    /// since the session it would point at is gone.
    @Test func aDeletedSessionsWorkoutIsQueuedOnceWithoutASuccessor() throws {
        let workout = UUID(), session = UUID()
        let orphan = HealthCleanupQueue.orphaned(workoutID: workout, sessionID: session, sessionExists: false)
        #expect(orphan == Self.entry(workout, session: session, preferred: nil))
        let queued = try #require(orphan)
        let list = HealthCleanupQueue.enqueue(queued, into: [])
        #expect(list.map(\.workoutID) == [workout])
        #expect(HealthCleanupQueue.enqueue(queued, into: list).count == 1, "A workout is queued once")

        // A replaced fallback is queued with its successor; deleting the
        // session afterwards must not lose the entry or duplicate it.
        let fallback = Self.entry(workout, session: session, preferred: UUID())
        #expect(HealthCleanupQueue.enqueue(queued, into: [fallback]) == [queued],
                "The newer account of the workout wins")
    }

    /// A watch workout ID for a session that no longer exists is queued, and
    /// one for a session that does exist is not: a restore may have put it
    /// back, and the workout is then its own.
    @Test func anOrphanWorkoutJoinsTheListAndOneWhoseSessionIsThereIsLeftAlone() throws {
        let workout = UUID(), session = UUID()
        let orphan = try #require(HealthCleanupQueue.orphaned(workoutID: workout, sessionID: session,
                                                               sessionExists: false))
        #expect(HealthCleanupQueue.enqueue(orphan, into: [Self.entry()]).contains(orphan))
        #expect(HealthCleanupQueue.orphaned(workoutID: workout, sessionID: session, sessionExists: true) == nil)
    }

    /// Entries written before the successor became optional must still
    /// decode, and one without a successor must store no key for it.
    @Test func anOldEntryDecodesAndOneWithNoSuccessorStoresNoKey() throws {
        let workout = UUID(), session = UUID(), preferred = UUID()
        let old = """
        [{"workoutID":"\(workout.uuidString)","sessionID":"\(session.uuidString)",\
        "preferredWorkoutID":"\(preferred.uuidString)"}]
        """
        let decoded = try JSONDecoder().decode([PendingWorkoutCleanup].self, from: Data(old.utf8))
        #expect(decoded == [Self.entry(workout, session: session, preferred: preferred)])

        let none = try JSONEncoder().encode([Self.entry(workout, session: session)])
        let text = String(decoding: none, as: UTF8.self)
        #expect(!text.contains("preferredWorkoutID"), "No successor stores no key")
        #expect(!text.contains("null"), "And no null")
        #expect(try JSONDecoder().decode([PendingWorkoutCleanup].self, from: none)
                == [Self.entry(workout, session: session)])
    }

    // MARK: - Passes over the list

    /// A stored list and a scripted Health, wired the way the service wires
    /// them, so a test reads as a sequence of events.
    @MainActor
    private final class QueueHarness {
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

    /// The failure the retry exists for: refused while the phone is locked,
    /// then removed by the next foreground. Queue, fail, foreground, retry,
    /// drained.
    @Test func aDeleteRefusedWhileLockedIsRemovedByTheNextPass() async {
        let workout = UUID()
        let harness = QueueHarness([Self.entry(workout)])
        await harness.pass()
        #expect(harness.queue.map(\.workoutID) == [workout], "A refused delete stays queued")

        harness.gone[workout] = true
        await harness.pass()
        #expect(harness.queue.isEmpty, "The next attempt drains it")
        #expect(harness.deleteCalls == [workout, workout], "Each pass tried it once")

        await harness.pass()
        #expect(harness.deleteCalls.count == 2, "An empty list asks Health nothing")
    }

    @Test func onePassDropsWhatHealthSettledAndKeepsWhatItRefused() async {
        let gone = Self.entry(), stuck = Self.entry(), removed = Self.entry()
        let harness = QueueHarness([gone, stuck, removed])
        // Not found counts as gone.
        harness.gone[gone.workoutID] = true
        harness.gone[removed.workoutID] = true
        await harness.pass()
        #expect(harness.queue == [stuck])
    }

    /// A session that could not be pointed at its successor keeps its old
    /// workout: removing it first would leave the link pointing at nothing.
    @Test func anEntryWhoseSessionCouldNotBeRelinkedWaitsForTheLink() async {
        let blocked = Self.entry(preferred: UUID())
        let harness = QueueHarness([blocked])
        harness.gone[blocked.workoutID] = true
        harness.blockedLinks = [blocked.workoutID]
        await harness.pass()
        #expect(harness.deleteCalls.isEmpty, "No delete before the link is safe")
        #expect(harness.queue == [blocked], "And the entry waits")

        harness.blockedLinks = []
        await harness.pass()
        #expect(harness.queue.isEmpty, "It goes once the link is saved")
    }

    /// The service can be handed a new entry while Health is answering. The
    /// pass settles against the list as it is then, not as it was when the pass
    /// began, or the new entry would be written over.
    @Test func anEntryAddedWhileHealthAnswersSurvivesThePass() async {
        let first = Self.entry(), late = Self.entry()
        let harness = QueueHarness([first])
        harness.gone[first.workoutID] = true
        harness.duringDelete = { harness.queue = HealthCleanupQueue.enqueue(late, into: harness.queue) }
        await harness.pass()
        #expect(harness.queue == [late], "The entry added mid-pass survives, the settled one is gone")
    }

    // MARK: - The attempt cap

    @Test func refusalsInOneBurstCountAsOneOccasion() {
        var ledger = CleanupAttemptLedger()
        // A burst of passes inside one minute is one occasion, however many.
        let burst = Self.refuse(&ledger, 20, gap: 3, workout: UUID(), session: UUID())
        #expect(burst.allSatisfy { !$0 }, "A burst of refusals within one occasion never gives up")
        #expect(ledger.struggling.first?.failures == 1, "A burst counts as one failure")
        #expect(ledger.givenUp.isEmpty)
    }

    @Test func theCapGivesUpAndRemembersTheWorkoutAndItsSession() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        let answers = Self.refuse(&ledger, CleanupAttemptLedger.cap, gap: Self.spaced, workout: workout, session: session)
        #expect(answers.dropLast().allSatisfy { !$0 }, "The entry stays on the list until the cap")
        #expect(answers.last == true, "The last failure the cap allows takes the entry off the list")
        #expect(ledger.givenUp.map(\.workoutID) == [workout])
        #expect(ledger.givenUp.first?.sessionID == session)
        #expect(ledger.struggling.isEmpty, "A workout given up is no longer counted as struggling")
    }

    @Test func aLockedPhoneCostsNothing() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        for i in 0..<50 {
            let leaves = ledger.record(.deferred, workoutID: workout, sessionID: session,
                                       at: Self.at(Double(i) * 3600))
            #expect(!leaves, "A deferred delete keeps the entry")
        }
        #expect(ledger == CleanupAttemptLedger(), "A locked phone leaves no count behind")
    }

    @Test func goneForgetsTheEarlierFailures() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        _ = Self.refuse(&ledger, 3, gap: Self.spaced, workout: workout, session: session)
        let leaves = ledger.record(.gone, workoutID: workout, sessionID: session, at: Self.t0)
        #expect(leaves, "Gone leaves the list")
        #expect(ledger == CleanupAttemptLedger())
        // The count starts over: one refusal now is the first, not the fourth.
        _ = Self.refuse(&ledger, 1, gap: 1, workout: workout, session: session)
        #expect(ledger.struggling.first?.failures == 1)
    }

    /// A delete refused because Health sharing was off used to count like one
    /// Health itself refused, so a few weeks with sharing off lost the cleanup
    /// for good.
    @Test func withdrawnWriteAccessCostsNoAttemptAndLeavesTheWholeCap() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        for n in 0..<20 {
            let leaves = ledger.record(.awaitingAccess, workoutID: workout, sessionID: session, at: Self.occasion(n))
            #expect(!leaves, "Awaiting access keeps the entry on the list (occasion \(n))")
        }
        #expect(ledger.givenUp.isEmpty, "Twenty occasions without access give up on nothing")
        #expect(ledger.struggling.isEmpty, "Awaiting access leaves no failure count behind")
        // Access returns and Health then refuses for its own reasons: the full
        // cap is still available.
        for n in 20..<24 {
            let leaves = ledger.record(.refused, workoutID: workout, sessionID: session, at: Self.occasion(n))
            #expect(!leaves, "A real refusal after the wait counts as the first four, not the last")
        }
        let fifth = ledger.record(.refused, workoutID: workout, sessionID: session, at: Self.occasion(24))
        #expect(fifth, "The fifth real refusal gives up")
    }

    @Test func waitingForAccessNeitherAddsToNorClearsTheFailures() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        for n in 0..<3 { _ = ledger.record(.refused, workoutID: workout, sessionID: session, at: Self.occasion(n)) }
        for n in 3..<13 { _ = ledger.record(.awaitingAccess, workoutID: workout, sessionID: session, at: Self.occasion(n)) }
        #expect(ledger.struggling.first?.failures == 3)
        let fourth = ledger.record(.refused, workoutID: workout, sessionID: session, at: Self.occasion(13))
        #expect(!fourth, "The fourth refusal keeps trying")
        let fifth = ledger.record(.refused, workoutID: workout, sessionID: session, at: Self.occasion(14))
        #expect(fifth, "The fifth gives up, however long access was off between")
    }

    @Test func goneAfterWaitingForAccessForgetsTheWorkout() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        _ = ledger.record(.refused, workoutID: workout, sessionID: session, at: Self.occasion(0))
        _ = ledger.record(.awaitingAccess, workoutID: workout, sessionID: session, at: Self.occasion(1))
        let leaves = ledger.record(.gone, workoutID: workout, sessionID: session, at: Self.occasion(2))
        #expect(leaves, "Gone leaves the list")
        #expect(ledger.struggling.isEmpty && ledger.givenUp.isEmpty, "Gone forgets the workout")
    }

    @Test func aRetryGivesOneMoreAttemptAndTheNoticeComesBackIfItFails() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        _ = Self.refuse(&ledger, CleanupAttemptLedger.cap, gap: Self.spaced, workout: workout, session: session)
        let later = Self.at(100_000)
        let reopened = ledger.reopen()
        #expect(reopened.map(\.workoutID) == [workout], "Reopen hands back what was given up")
        #expect(ledger.givenUp.isEmpty, "Reopen empties the notice while the attempt runs")
        let refusedAgain = ledger.record(.refused, workoutID: workout, sessionID: session, at: later)
        #expect(refusedAgain, "One refusal after Retry gives up again at once")
        #expect(ledger.givenUp.count == 1, "The notice comes back, not another five tries")

        _ = ledger.reopen()
        let gone = ledger.record(.gone, workoutID: workout, sessionID: session, at: later)
        #expect(gone, "A Retry that works leaves the list")
        #expect(ledger == CleanupAttemptLedger(), "A Retry that works leaves no notice and no count")
        let nothingLeft = ledger.reopen()
        #expect(nothingLeft.isEmpty, "Nothing to reopen once everything is gone")
    }

    @Test func theGivenUpListKeepsOnlyTheNewest() {
        var ledger = CleanupAttemptLedger()
        let session = UUID()
        let ids = (0..<(CleanupAttemptLedger.remembered + 5)).map { _ in UUID() }
        for id in ids {
            _ = Self.refuse(&ledger, CleanupAttemptLedger.cap, gap: Self.spaced, workout: id, session: session)
        }
        #expect(ledger.givenUp.count == CleanupAttemptLedger.remembered, "The notice is bounded")
        #expect(ledger.givenUp.last?.workoutID == ids.last, "The newest is kept")
        #expect(!ledger.givenUp.contains(where: { $0.workoutID == ids[0] }), "The oldest is forgotten")
    }

    /// A relaunch must keep the count.
    @Test func theLedgerDecodesToWhatWasStored() throws {
        var ledger = CleanupAttemptLedger()
        _ = Self.refuse(&ledger, 2, gap: Self.spaced, workout: UUID(), session: UUID())
        _ = Self.refuse(&ledger, CleanupAttemptLedger.cap, gap: Self.spaced, workout: UUID(), session: UUID())
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(CleanupAttemptLedger.self, from: data) == ledger)
        let empty = Data(#"{"struggling":[],"givenUp":[]}"#.utf8)
        #expect(try JSONDecoder().decode(CleanupAttemptLedger.self, from: empty) == CleanupAttemptLedger())
    }

    /// Retry must get the successor back, or it would delete the workout the
    /// session still points at.
    @Test func aGivenUpEntryKeepsItsSuccessorForARetry() throws {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID(), successor = UUID()
        for n in 0..<CleanupAttemptLedger.cap {
            _ = ledger.record(.refused, workoutID: workout, sessionID: session,
                              preferredWorkoutID: successor, at: Self.occasion(n))
        }
        let reopened = ledger.reopen()
        #expect(reopened.first?.preferredWorkoutID == successor)
        #expect(try JSONDecoder().decode(CleanupAttemptLedger.self, from: JSONEncoder().encode(ledger)) == ledger,
                "A ledger with a successor survives encoding")
    }

    @Test func aGivenUpEntryWithNoSuccessorStoresNoKeyAndOldEntriesStillDecode() throws {
        let item = CleanupAttemptLedger.GivenUp(workoutID: UUID(), sessionID: UUID(),
                                                preferredWorkoutID: nil, at: Self.t0)
        let text = try String(decoding: JSONEncoder().encode(item), as: UTF8.self)
        #expect(!text.contains("preferredWorkoutID"), "No successor stores no key, not a null")
        let old = "{\"workoutID\":\"\(UUID().uuidString)\",\"sessionID\":\"\(UUID().uuidString)\",\"at\":0}"
        let decoded = try JSONDecoder().decode(CleanupAttemptLedger.GivenUp.self, from: Data(old.utf8))
        #expect(decoded.preferredWorkoutID == nil)
    }

    // MARK: - The cap through a pass

    /// A stored list, a ledger and a scripted store, wired the way
    /// `HealthKitService` wires them, so a test reads as a sequence of passes.
    /// `linkFailed` is a copy of the service's private `settleFailedLink`, and
    /// `delete` of its `deleteForCleanup`.
    @MainActor
    private final class CapHarness {
        var queue: [PendingWorkoutCleanup]
        var ledger = CleanupAttemptLedger()
        var relinks = true
        var storeConnected = true
        var deleteAnswer = CleanupAttemptLedger.Outcome.gone
        var deleteCalls: [UUID] = []
        var pass = 0

        init(_ queue: [PendingWorkoutCleanup]) { self.queue = queue }

        func run(useLinkFailed: Bool = true) async {
            pass += 1
            let now = HealthKitServiceTests.occasion(pass)
            let linkFailed: (PendingWorkoutCleanup) -> Bool = { entry in
                guard self.queue.contains(where: { $0.workoutID == entry.workoutID }) else { return false }
                return self.ledger.record(self.storeConnected ? .refused : .deferred,
                                          workoutID: entry.workoutID, sessionID: entry.sessionID,
                                          preferredWorkoutID: entry.preferredWorkoutID, at: now)
            }
            let delete: (UUID) async -> Bool = { id in
                self.deleteCalls.append(id)
                guard let entry = self.queue.first(where: { $0.workoutID == id }) else { return false }
                return self.ledger.record(self.deleteAnswer, workoutID: id, sessionID: entry.sessionID, at: now)
            }
            if useLinkFailed {
                await HealthCleanupQueue.drain(load: { self.queue }, save: { self.queue = $0 },
                                               prepare: { $0.preferredWorkoutID == nil || self.relinks },
                                               linkFailed: linkFailed, delete: delete)
            } else {
                await HealthCleanupQueue.drain(load: { self.queue }, save: { self.queue = $0 },
                                               prepare: { $0.preferredWorkoutID == nil || self.relinks },
                                               delete: delete)
            }
        }
    }

    /// An entry whose session could never be relinked used to be retried at
    /// every foreground for as long as the app stayed installed.
    @Test func aRelinkThatNeverSucceedsIsGivenUpOnTheSameCap() async {
        let stuck = Self.entry(preferred: UUID()), other = Self.entry()
        let harness = CapHarness([stuck, other])
        harness.relinks = false
        harness.deleteAnswer = .gone
        for _ in 0..<(CleanupAttemptLedger.cap - 1) { await harness.run() }
        #expect(harness.queue.contains(stuck), "Four failed relinks keep the entry")
        #expect(!harness.deleteCalls.contains(stuck.workoutID), "A failed relink never reaches the delete")

        await harness.run()
        #expect(!harness.queue.contains(stuck), "The fifth failed relink drops the entry from the list")
        #expect(harness.ledger.givenUp.first?.workoutID == stuck.workoutID, "The dropped entry is remembered for Settings")
        #expect(harness.ledger.givenUp.first?.preferredWorkoutID == stuck.preferredWorkoutID,
                "It keeps its successor for a Retry")
        #expect(harness.ledger.givenUp.count == 1, "Only the stuck entry is given up")
        #expect(harness.deleteCalls == [other.workoutID],
                "An entry with no successor has nothing to link and is deleted as before")
    }

    @Test func aRelinkThatSucceedsLaterIsNotGivenUp() async {
        let flaky = Self.entry(preferred: UUID())
        let harness = CapHarness([flaky])
        harness.relinks = false
        for _ in 0..<3 { await harness.run() }
        harness.relinks = true
        harness.deleteAnswer = .gone
        await harness.run()
        #expect(harness.queue.isEmpty, "Once the link is made the workout is deleted and the entry leaves")
        #expect(harness.ledger.givenUp.isEmpty && harness.ledger.struggling.isEmpty, "Nothing is left in the ledger")
    }

    @Test func anEntryWithNoStoreToRelinkInCostsNoAttempt() async {
        let waiting = Self.entry(preferred: UUID())
        let harness = CapHarness([waiting])
        harness.relinks = false
        harness.storeConnected = false
        for _ in 0..<10 { await harness.run() }
        #expect(harness.queue == [waiting], "An entry with no store to relink in is never given up")
        #expect(harness.ledger.struggling.isEmpty, "It leaves no failure count")
    }

    @Test func aCallerThatPassesNoLinkFailedClosureNeverGivesUp() async {
        let stuck = Self.entry(preferred: UUID())
        let harness = CapHarness([stuck])
        harness.relinks = false
        for _ in 0..<10 { await harness.run(useLinkFailed: false) }
        #expect(harness.queue == [stuck])
    }

    @Test func withdrawnWriteAccessKeepsTheEntryThroughEveryPassUntilItIsBack() async {
        let waiting = Self.entry()
        let harness = CapHarness([waiting])
        harness.deleteAnswer = .awaitingAccess
        for _ in 0..<12 { await harness.run() }
        #expect(harness.queue == [waiting], "Twelve passes without access keep the entry")
        #expect(harness.ledger.givenUp.isEmpty, "None of them gave up")
        harness.deleteAnswer = .gone
        await harness.run()
        #expect(harness.queue.isEmpty, "The first pass with access removes it")
    }

    // MARK: - Coalescing passes

    @Test func theGateRecordsARequestDuringAPassAndRunsTheNextOneAfter() {
        var gate = CleanupPassGate()
        let first = gate.begin()
        #expect(first, "The first request runs a pass")
        let during = gate.begin()
        #expect(!during && gate.requested, "A request during a pass is recorded, not run")
        gate.startPass()
        #expect(!gate.wantsAnotherPass, "Starting a pass consumes the requests made before it")
        let midPass = gate.begin()
        #expect(!midPass && gate.wantsAnotherPass, "A request made mid-pass asks for another")
        gate.end()
        let after = gate.begin()
        #expect(after, "After a pass ends the next request runs")
    }

    /// A copy of the service's private `retryPendingWorkoutCleanup` loop, over
    /// a real drain.
    @MainActor
    private final class PassHarness {
        var gate = CleanupPassGate()
        var stored: [PendingWorkoutCleanup]
        var passes = 0
        var deleting = 0
        var maxDeleting = 0
        /// Runs once, inside the next delete, while that delete is in flight.
        var onDelete: ((PassHarness) async -> Void)?

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
                        if let onDelete = self.onDelete {
                            self.onDelete = nil
                            await onDelete(self)
                        }
                        await Task.yield()
                        self.deleting -= 1
                        return true
                    })
            } while gate.wantsAnotherPass
        }
    }

    /// An entry queued while a delete is in flight arrives after the pass has
    /// read the list, so only a second pass removes it.
    @Test func aRequestDuringAPassRunsExactlyOneMorePass() async {
        let harness = PassHarness([Self.entry()])
        harness.onDelete = { h in
            h.stored = HealthCleanupQueue.enqueue(Self.entry(), into: h.stored)
            // A second caller asks on a task of its own. Waiting for it here
            // puts the request inside the pass every time, rather than whenever
            // the scheduler next runs the task.
            await Task { await h.run() }.value
        }
        await harness.run()
        #expect(harness.stored.isEmpty, "An entry added mid-pass is removed by the pass it asked for")
        #expect(harness.passes == 2, "That took exactly one extra pass, not more")
    }

    @Test func twoCallersNeverRunDeletesAtTheSameTime() async {
        let harness = PassHarness([Self.entry(), Self.entry(), Self.entry()])
        async let first: Void = harness.run()
        async let second: Void = harness.run()
        _ = await (first, second)
        #expect(harness.maxDeleting == 1)
        #expect(harness.stored.isEmpty, "The list is worked through")
    }

    // MARK: - Writing a session, and what becomes of the workout

    @Test func onlyALiveSessionWithNoWorkoutIsWritten() {
        #expect(PhoneWorkoutWrite.shouldWrite(sessionGone: false, linkedWorkoutID: nil))
        #expect(!PhoneWorkoutWrite.shouldWrite(sessionGone: false, linkedWorkoutID: UUID()),
                "A session the watch already saved must not get a second workout")
        #expect(!PhoneWorkoutWrite.shouldWrite(sessionGone: true, linkedWorkoutID: nil), "A deleted session is not written")
    }

    @Test func aWrittenWorkoutIsLinkedOrQueuedForRemoval() {
        let written = UUID(), watch = UUID()
        #expect(PhoneWorkoutWrite.outcome(written: nil, sessionGone: false, linkedWorkoutID: nil) == .nothing,
                "Health handing back nothing leaves nothing to keep or remove")
        #expect(PhoneWorkoutWrite.outcome(written: nil, sessionGone: true, linkedWorkoutID: watch) == .nothing,
                "No workout means nothing to queue whatever became of the session")
        #expect(PhoneWorkoutWrite.outcome(written: written, sessionGone: false, linkedWorkoutID: nil) == .link,
                "An unclaimed session takes the phone's workout")
        #expect(PhoneWorkoutWrite.outcome(written: written, sessionGone: true, linkedWorkoutID: nil) == .removeAsOrphan,
                "A session removed during the write leaves an orphan to remove")
        #expect(PhoneWorkoutWrite.outcome(written: written, sessionGone: true, linkedWorkoutID: watch) == .removeAsOrphan,
                "A gone session is an orphan even if it held a link when it went")
        #expect(PhoneWorkoutWrite.outcome(written: written, sessionGone: false, linkedWorkoutID: watch)
                == .removeAsDuplicate(keeping: watch),
                "A watch workout that landed mid-write stays and the phone's copy goes")
    }

    @Test func onlyASessionStillPointingAtTheOldWorkoutIsRelinked() {
        let old = UUID(), next = UUID()
        #expect(CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: true, sessionLink: old, workoutID: old))
        #expect(!CleanupRelink.isNeeded(preferredWorkoutID: nil, sessionFound: true, sessionLink: old, workoutID: old),
                "No successor, nothing to link")
        #expect(!CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: false, sessionLink: nil, workoutID: old),
                "A session that is gone has nothing to relink")
        #expect(!CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: true, sessionLink: UUID(), workoutID: old),
                "A session already pointing elsewhere is not overwritten")
        #expect(!CleanupRelink.isNeeded(preferredWorkoutID: next, sessionFound: true, sessionLink: nil, workoutID: old),
                "A session with no link is not given one by a cleanup")
    }

    @Test func aBatchDeleteTakesOnlyOurWorkoutsAndReportsWhatRemains() {
        let a = UUID(), b = UUID(), c = UUID(), missing = UUID()
        #expect(WorkoutDeletionPlan.unique([a, b, a, c, b]) == [a, b, c], "IDs are asked for once, in order")
        #expect(WorkoutDeletionPlan.unique([]).isEmpty)

        let found = [WorkoutDeletionPlan.Found(id: c, ours: true),
                     WorkoutDeletionPlan.Found(id: b, ours: false),
                     WorkoutDeletionPlan.Found(id: a, ours: true)]
        let wanted = [a, b, c, missing]
        #expect(Set(WorkoutDeletionPlan.toDelete(found: found)) == Set([a, c]),
                "Only workouts this app or its watch wrote go into the delete")
        #expect(WorkoutDeletionPlan.remaining(wanted: wanted, found: found, deleteFailed: false) == [b],
                "Deleted and unfindable IDs are gone; another app's workout remains")
        #expect(WorkoutDeletionPlan.remaining(wanted: wanted, found: found, deleteFailed: true) == [a, b, c],
                "A refused batch removed nothing: every found ID remains, in the order asked, and the unfindable one is still gone")
        #expect(WorkoutDeletionPlan.remaining(wanted: [missing], found: [], deleteFailed: false).isEmpty,
                "A workout Health cannot find is already gone")
    }

    // MARK: - The workout's activities

    static func stamp(_ exercise: String, _ minute: Double, startedAt: Double? = nil) -> ActivitySetStamp {
        ActivitySetStamp(id: UUID(), exercise: exercise, startedAt: startedAt.map(minutes),
                         completedAt: minutes(minute))
    }

    /// Runs as "exercise start-end", in minutes, for readable comparisons.
    static func shape(_ runs: [WorkoutActivityRun]) -> [String] {
        runs.map { "\($0.exercise) \(Int($0.start.timeIntervalSince(t0) / 60))-\(Int($0.end.timeIntervalSince(t0) / 60))" }
    }

    static func expectWellFormed(_ runs: [WorkoutActivityRun]) {
        for (index, run) in runs.enumerated() {
            #expect(run.end > run.start, "A run runs forwards")
            #expect(run.start >= t0, "A run starts inside the session")
            if index > 0 {
                #expect(run.start >= runs[index - 1].end, "Runs never overlap")
            }
        }
    }

    /// The plan is bench, squat, row. The bench was taken, so the lifter
    /// squatted first. Sets arrive in the session's own order.
    @Test func exercisesFollowTheOrderTheyWereDoneInNotThePlans() {
        let outOfOrder = [
            Self.stamp("bench", 25), Self.stamp("bench", 30), Self.stamp("bench", 40),
            Self.stamp("squat", 5), Self.stamp("squat", 10), Self.stamp("squat", 20),
            Self.stamp("row", 45), Self.stamp("row", 50), Self.stamp("row", 60),
        ]
        let runs = WorkoutActivitySegmentation.runs(of: outOfOrder, sessionStart: Self.t0, sessionEnd: Self.minutes(62))
        #expect(Self.shape(runs) == ["squat 0-20", "bench 20-40", "row 40-60"])
        Self.expectWellFormed(runs)
    }

    /// One make-up bench set at the end gets its own activity, and the
    /// exercises between keep theirs.
    @Test func aMakeUpSetNeitherSwallowsTheSessionNorDropsWhatCameBetween() throws {
        let makeUp = [
            Self.stamp("bench", 5), Self.stamp("bench", 10), Self.stamp("bench", 15), Self.stamp("bench", 50),
            Self.stamp("squat", 20), Self.stamp("squat", 25), Self.stamp("squat", 30),
            Self.stamp("row", 35), Self.stamp("row", 40),
        ]
        let runs = WorkoutActivitySegmentation.runs(of: makeUp, sessionStart: Self.t0, sessionEnd: Self.minutes(55))
        #expect(Self.shape(runs) == ["bench 0-15", "squat 15-30", "row 30-40", "bench 40-50"])
        Self.expectWellFormed(runs)
        try #require(runs.count == 4)
        #expect(runs[0].setIDs.count == 3 && runs[3].setIDs == [makeUp[3].id], "Each run carries only its own sets")
    }

    /// A superset alternates, so each round is its own pair of activities.
    @Test func aSupersetReadsAsItsRounds() {
        let superset = [Self.stamp("curl", 2), Self.stamp("curl", 6), Self.stamp("dip", 4), Self.stamp("dip", 8)]
        let runs = WorkoutActivitySegmentation.runs(of: superset, sessionStart: Self.t0, sessionEnd: Self.minutes(9))
        #expect(Self.shape(runs) == ["curl 0-2", "dip 2-4", "curl 4-6", "dip 6-8"])
    }

    @Test func anAnnouncedStartIsBelievedInsideTheGapItSplitsAndOnlyThere() {
        let announced = [Self.stamp("bench", 10), Self.stamp("squat", 20, startedAt: 17)]
        let fromAnnounced = WorkoutActivitySegmentation.runs(of: announced, sessionStart: Self.t0,
                                                             sessionEnd: Self.minutes(21))
        #expect(Self.shape(fromAnnounced) == ["bench 0-10", "squat 17-20"])

        let early = [Self.stamp("bench", 10), Self.stamp("squat", 20, startedAt: 8)]
        let fromEarly = WorkoutActivitySegmentation.runs(of: early, sessionStart: Self.t0, sessionEnd: Self.minutes(21))
        #expect(Self.shape(fromEarly) == ["bench 0-10", "squat 10-20"],
                "A start before the previous run ended is not believed")
    }

    /// Two exercises logged at the same instant leave the second nothing to
    /// show, and a set logged after the end is held to the end.
    @Test func noRunIsEmptyAndNoneRunsPastTheSessionsEnd() {
        let batch = [Self.stamp("bench", 10), Self.stamp("squat", 10), Self.stamp("row", 30)]
        let runs = WorkoutActivitySegmentation.runs(of: batch, sessionStart: Self.t0, sessionEnd: Self.minutes(25))
        #expect(Self.shape(runs) == ["bench 0-10", "row 10-25"])
        Self.expectWellFormed(runs)
    }

    // MARK: - Reading a set's heart rate again

    /// A rest settling from the set before, then one set climbing out of it.
    static func bpm(_ t: TimeInterval) -> Double {
        if t < 100 { return 95 + 15 * exp(-t / 20) }
        if t <= 140 { return 95 + 45 * ((t - 100) / 40).squareRoot() }
        return 140
    }

    static func trace(through end: TimeInterval) -> [HeartRateSample] {
        stride(from: 0, through: end, by: 5).map { HeartRateSample(at: at($0), bpm: bpm($0)) }
    }

    /// One later pass over a single set: what it would write, if anything.
    static func pass(_ samples: [HeartRateSample], stored: StoredSetHeartRate) -> SetHeartRateUpdate? {
        let updates = SetHeartRateAttribution.updates(samples: samples, sets: [stored], sessionStart: t0)
        #expect(updates.count <= 1)
        return updates.first
    }

    @Test func aReadingFromAPartialTraceIsReplacedOnlyByOneFromStrictlyMoreSamples() throws {
        let timing = SetTiming(id: UUID(), startedAt: nil, completedAt: Self.at(150), reps: 8, heldSeconds: 0)

        // The first pass runs while the watch's samples are still arriving:
        // the trace stops partway up the climb.
        let fresh = StoredSetHeartRate(timing: timing, hasReading: false, readFrom: nil, mayDetect: true)
        let first = try #require(Self.pass(Self.trace(through: 120), stored: fresh),
                                 "A partial trace still reads the part of the set it has")
        let early = try #require(first.detected)
        #expect(first.heartRate.source == .detected)

        // Once the rest has synced, a pass that remembers the first count
        // replaces both the window and the numbers read through it.
        let partial = StoredSetHeartRate(timing: timing.reading(through: early), hasReading: true,
                                         readFrom: first.samples, mayDetect: true)
        let second = try #require(Self.pass(Self.trace(through: 150), stored: partial),
                                  "A reading from strictly more samples replaces one read off a partial trace")
        let full = try #require(second.detected)
        #expect(second.samples > first.samples && full.end > early.end,
                "The later window reaches past where the partial trace stopped")
        #expect(second.heartRate.peak > first.heartRate.peak)

        // The same trace again gains nothing, so nothing is written.
        let settled = StoredSetHeartRate(timing: timing.reading(through: full), hasReading: true,
                                         readFrom: second.samples, mayDetect: true)
        #expect(Self.pass(Self.trace(through: 150), stored: settled) == nil,
                "An equal count is not better, and a pass must not rewrite what it already has")

        // A reading nobody here remembers taking, restored or from an older
        // build, has no count to beat and is left alone.
        let restored = StoredSetHeartRate(timing: timing.reading(through: early), hasReading: true,
                                          readFrom: nil, mayDetect: true)
        #expect(Self.pass(Self.trace(through: 150), stored: restored) == nil,
                "A reading with no remembered count is never replaced")
    }

    @Test func anInferredReadingImprovesTheSameWayThroughTheSameWindow() throws {
        let plain = SetTiming(id: UUID(), startedAt: nil, completedAt: Self.at(150), reps: 8, heldSeconds: 0)
        let fresh = StoredSetHeartRate(timing: plain, hasReading: false, readFrom: nil, mayDetect: false)
        let flat = stride(from: 130.0, through: 150, by: 5).map { HeartRateSample(at: Self.at($0), bpm: 120) }
        let thin = try #require(Self.pass(Array(flat.prefix(2)), stored: fresh), "Two beats in the window are a reading")
        #expect(thin.heartRate.source == .inferred && thin.detected == nil && thin.samples == 2)

        let thinStored = StoredSetHeartRate(timing: plain, hasReading: true, readFrom: 2, mayDetect: false)
        #expect(Self.pass(flat, stored: thinStored)?.samples == flat.count,
                "More beats in the same inferred window replace the thin reading")
    }

    /// No samples, or only dropped readings of zero, write no key at all.
    @Test func nothingIsReadFromNothing() {
        let timing = SetTiming(id: UUID(), startedAt: nil, completedAt: Self.at(150), reps: 8, heldSeconds: 0)
        let fresh = StoredSetHeartRate(timing: timing, hasReading: false, readFrom: nil, mayDetect: true)
        #expect(Self.pass([], stored: fresh) == nil)
        let dropped = stride(from: 0.0, through: 150, by: 5).map { HeartRateSample(at: Self.at($0), bpm: 0) }
        #expect(Self.pass(dropped, stored: fresh) == nil, "A zero heart rate is a dropped reading, never a value")
    }

    @Test func aSetIsOpenWithNoReadingOrToAStrictlyLargerRememberedCount() {
        #expect(SetHeartRateAttribution.mayReplace(hasReading: false, readFrom: nil, samples: 1))
        #expect(SetHeartRateAttribution.mayReplace(hasReading: false, readFrom: 9, samples: 1),
                "A set with no reading is always open, whatever the ledger remembers")
        #expect(!SetHeartRateAttribution.mayReplace(hasReading: true, readFrom: nil, samples: 99))
        #expect(!SetHeartRateAttribution.mayReplace(hasReading: true, readFrom: 5, samples: 5))
        #expect(SetHeartRateAttribution.mayReplace(hasReading: true, readFrom: 5, samples: 6))
    }

    @Test func theSampleLedgerKeepsTheLatestCountForTwoDaysAndStaysBounded() {
        let suite = "HealthKitServiceTests.sampleLedger"
        let defaults = TestClock.freshDefaults(suite)
        defer { UserDefaults().removePersistentDomain(forName: "GymTrackTests." + suite) }

        let ledger = SetHeartRateLedger(defaults: defaults)
        let first = UUID(), second = UUID()
        ledger.record([first: 3, second: 7], now: Self.t0)
        #expect(ledger.samples(now: Self.at(60)) == [first: 3, second: 7])
        ledger.record([first: 5], now: Self.at(120))
        #expect(ledger.samples(now: Self.at(180)) == [first: 5, second: 7], "A later count replaces the earlier")
        let later = Self.at(120 + SetHeartRateLedger.keptFor + 1)
        #expect(ledger.samples(now: later).isEmpty, "Past two days every set is closed to further passes")

        let many = Dictionary(uniqueKeysWithValues: (0..<(SetHeartRateLedger.limit + 50)).map { (UUID(), $0) })
        ledger.record(many, now: Self.t0)
        #expect(ledger.samples(now: Self.t0).count == SetHeartRateLedger.limit, "The ledger stays bounded")
    }

    // MARK: - Energy the wrist recorded

    static func slice(_ source: String, wrist: Bool, kcal: Double = 20,
                      start: Double = 0, end: Double = 600) -> EnergySlice {
        EnergySlice(start: at(start), end: at(end), kilocalories: kcal, sourceID: source, isFromWrist: wrist)
    }

    @Test func onlySourcesThatWroteNothingButWristSlicesAreTrusted() {
        let slices = [Self.slice("watch.workout", wrist: true), Self.slice("watch.gymtrack", wrist: true),
                      Self.slice("phone", wrist: false),
                      Self.slice("mixed", wrist: true), Self.slice("mixed", wrist: false)]
        #expect(WristEnergyRead.trustedSources(in: slices) == ["watch.workout", "watch.gymtrack"],
                "Two watch sources are trusted; the phone and a source that wrote both are not")
        #expect(WristEnergyRead.trustedSources(in: [Self.slice("watch", wrist: true),
                                                    Self.slice("phone", wrist: false, kcal: 0)]) == ["watch"],
                "A zero slice from another device does not spoil a source")
        #expect(WristEnergyRead.trustedSources(in: []).isEmpty)
    }

    /// No answer from Health is no energy, and nor is a zero, negative or NaN
    /// sum: a workout that cost nothing would be a value Health never measured.
    @Test(arguments: [nil, 0, -3, Double.nan] as [Double?])
    func aSumThatIsNotAMeasurementKeepsNoEnergy(_ sum: Double?) {
        let watch = [Self.slice("watch", wrist: true)]
        #expect(WristEnergyRead.result(slices: watch, trusted: ["watch"], cumulativeSum: sum) == nil)
    }

    @Test func aSumWithNoTrustedSliceBehindItKeepsNoEnergy() {
        #expect(WristEnergyRead.result(slices: [Self.slice("phone", wrist: false)], trusted: [], cumulativeSum: 300) == nil,
                "A total with no trusted slice behind it is not kept")
        #expect(WristEnergyRead.result(slices: [Self.slice("watch", wrist: true, kcal: 0)], trusted: ["watch"],
                                       cumulativeSum: 40) == nil,
                "A source that only wrote zeros has nothing to vouch for a sum")
    }

    /// Two watch apps wrote the same ten minutes, 20 kcal each. Adding the
    /// slices gave 40; Health's de-duplicated sum says 20, and that is what is
    /// kept.
    @Test func theDeduplicatedSumIsKeptOverTheWristsOwnSpan() {
        let slices = [Self.slice("watch.workout", wrist: true, kcal: 20, start: 0, end: 600),
                      Self.slice("watch.gymtrack", wrist: true, kcal: 20, start: 0, end: 600),
                      Self.slice("phone", wrist: false, kcal: 500, start: 0, end: 3000)]
        let naive = slices.filter(\.isFromWrist).reduce(0) { $0 + $1.kilocalories }
        #expect(naive == 40, "The old sum counted the overlap twice")
        let trusted = WristEnergyRead.trustedSources(in: slices)
        let kept = WristEnergyRead.result(slices: slices, trusted: trusted, cumulativeSum: 20)
        #expect(kept?.kilocalories == 20)
        #expect(kept?.start == Self.t0 && kept?.end == Self.at(600),
                "The span is the wrist's, not stretched by the phone's slice")
    }

    // MARK: - Holding a session across Health's awaits

    static func byID(_ id: UUID) -> FetchDescriptor<WorkoutSession> {
        FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
    }

    /// Deleted through the context that holds it: gone before the save, and
    /// still gone after it, when `isDeleted` reads false again.
    @Test func aSessionDeletedThroughItsOwnContextIsGoneBeforeAndAfterTheSave() throws {
        let context = try TestStore.context()
        let held = WorkoutSession(title: "Held across Health")
        context.insert(held)
        try context.save()
        let heldID = held.id
        #expect(!held.isGoneFromStore && !held.isGone(fromStore: Self.byID(heldID)), "A saved session is alive")

        context.delete(held)
        #expect(held.isGoneFromStore, "A deleted session is gone before the save")
        try context.save()
        #expect(!held.isDeleted, "SwiftData reads a saved delete as not deleted; the check must not rely on it")
        #expect(held.isGoneFromStore && held.isGone(fromStore: Self.byID(heldID)), "A saved delete is still gone")
    }

    /// The way an erase from the screen meets a session the headless finish
    /// is holding.
    @Test func aDeleteThroughAnotherContextIsSeenByAskingTheStore() throws {
        let headless = try TestStore.context()
        let finished = WorkoutSession(title: "Finished on the wrist")
        headless.insert(finished)
        try headless.save()
        let finishedID = finished.id
        let screen = ModelContext(headless.container)
        for session in try screen.fetch(Self.byID(finishedID)) { screen.delete(session) }
        try screen.save()
        #expect(!finished.isGoneFromStore, "Another context's delete leaves this instance looking alive")
        #expect(finished.isGone(fromStore: Self.byID(finishedID)), "The store says it is gone")
    }

    @Test func aRowARestorePutBackWithTheSameIDIsNotTheSessionThatWasHeld() throws {
        let headless = try TestStore.context()
        let screen = ModelContext(headless.container)
        let original = WorkoutSession(title: "Before restore")
        headless.insert(original)
        try headless.save()
        let originalID = original.id
        for session in try screen.fetch(Self.byID(originalID)) { screen.delete(session) }
        let restored = WorkoutSession(title: "Restored")
        restored.id = originalID
        screen.insert(restored)
        try screen.save()
        #expect(original.isGone(fromStore: Self.byID(originalID)))
        #expect(!restored.isGone(fromStore: Self.byID(originalID)), "The restored row itself is alive")
    }

    /// The pass that holds a session stops at the first check after the
    /// delete, and writes nothing after it.
    @Test func aPassHoldingASessionStopsAtTheFirstCheckAfterTheDelete() throws {
        let pass = try TestStore.context()
        let session = WorkoutSession(title: "Mid-pass")
        pass.insert(session)
        try pass.save()
        let sessionID = session.id
        var steps = 0
        for step in 0..<5 {
            if session.isGone(fromStore: Self.byID(sessionID)) { break }
            steps += 1
            if step == 1 {
                pass.delete(session)
                try pass.save()
            }
        }
        #expect(steps == 2, "Stopped at the first check after the delete, not \(steps) steps in")
    }

    // MARK: - Helpers

    /// Records `count` refusals of `workout`, each `gap` seconds after the last.
    static func refuse(_ ledger: inout CleanupAttemptLedger, _ count: Int, gap: TimeInterval,
                       workout: UUID, session: UUID) -> [Bool] {
        (0..<count).map { i in
            ledger.record(.refused, workoutID: workout, sessionID: session, at: at(Double(i) * gap))
        }
    }
}
