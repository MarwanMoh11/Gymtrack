import Foundation

/// Run with scripts/test-health-cleanup-cap.sh; no simulator or Health store
/// is needed.
///
/// Two ways the cleanup list's attempt cap was wrong. A delete refused because
/// the user had switched Health sharing off counted like a delete Health
/// itself refused, so a few weeks of sharing off lost the cleanup for good. And
/// an entry whose session could not be relinked was never counted at all, so
/// it was retried at every foreground for as long as the app stayed installed.
@main
struct HealthCleanupCapTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// One occasion later than the last, past the spacing that merges bursts.
    static func occasion(_ n: Int) -> Date {
        t0.addingTimeInterval(Double(n) * (CleanupAttemptLedger.minimumSpacing + 60))
    }

    @MainActor static func main() async {
        withdrawnAccessCostsNothing()
        withdrawnAccessDoesNotDisturbTheCount()
        goneAfterWaitingClearsTheEntry()
        givenUpKeepsTheSuccessor()
        successorKeyIsAbsentWhenThereIsNone()
        await relinkThatNeverSucceedsIsGivenUp()
        await relinkThatSucceedsLaterIsNotGivenUp()
        await missingStoreCostsNoAttempt()
        await drainWithoutTheClosureNeverGivesUp()
        await withdrawnAccessKeepsTheEntryThroughDrain()
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("Health cleanup cap: access, relink and shape checks passed")
    }

    // MARK: Withdrawn write access

    static func withdrawnAccessCostsNothing() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        for n in 0..<20 {
            let leaves = ledger.record(.awaitingAccess, workoutID: workout, sessionID: session, at: occasion(n))
            check(!leaves, "Awaiting access keeps the entry on the list (occasion \(n))")
        }
        check(ledger.givenUp.isEmpty, "Twenty occasions without access give up on nothing")
        check(ledger.struggling.isEmpty, "Awaiting access leaves no failure count behind")
        // Access returns and Health then refuses for its own reasons: the full
        // cap is still available.
        for n in 20..<24 {
            check(!ledger.record(.refused, workoutID: workout, sessionID: session, at: occasion(n)),
                  "A real refusal after the wait counts as the first four, not the last")
        }
        check(ledger.record(.refused, workoutID: workout, sessionID: session, at: occasion(24)),
              "The fifth real refusal gives up")
    }

    static func withdrawnAccessDoesNotDisturbTheCount() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        for n in 0..<3 { _ = ledger.record(.refused, workoutID: workout, sessionID: session, at: occasion(n)) }
        for n in 3..<13 { _ = ledger.record(.awaitingAccess, workoutID: workout, sessionID: session, at: occasion(n)) }
        check(ledger.struggling.first?.failures == 3, "Waiting for access neither adds to nor clears the failures")
        check(!ledger.record(.refused, workoutID: workout, sessionID: session, at: occasion(13)), "The fourth refusal keeps trying")
        check(ledger.record(.refused, workoutID: workout, sessionID: session, at: occasion(14)), "The fifth gives up, however long access was off between")
    }

    static func goneAfterWaitingClearsTheEntry() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID()
        _ = ledger.record(.refused, workoutID: workout, sessionID: session, at: occasion(0))
        _ = ledger.record(.awaitingAccess, workoutID: workout, sessionID: session, at: occasion(1))
        check(ledger.record(.gone, workoutID: workout, sessionID: session, at: occasion(2)), "Gone leaves the list")
        check(ledger.struggling.isEmpty && ledger.givenUp.isEmpty, "Gone forgets the workout")
    }

    // MARK: What a Retry restores

    static func givenUpKeepsTheSuccessor() {
        var ledger = CleanupAttemptLedger()
        let workout = UUID(), session = UUID(), successor = UUID()
        for n in 0..<CleanupAttemptLedger.cap {
            _ = ledger.record(.refused, workoutID: workout, sessionID: session,
                              preferredWorkoutID: successor, at: occasion(n))
        }
        let reopened = ledger.reopen()
        check(reopened.first?.preferredWorkoutID == successor,
              "Retry gets the successor back, or it would delete the workout the session still points at")
        let decoded = try? JSONDecoder().decode(CleanupAttemptLedger.self, from: JSONEncoder().encode(ledger))
        check(decoded == ledger, "A ledger with a successor survives encoding")
    }

    static func successorKeyIsAbsentWhenThereIsNone() {
        let item = CleanupAttemptLedger.GivenUp(workoutID: UUID(), sessionID: UUID(),
                                                preferredWorkoutID: nil, at: t0)
        let text = (try? JSONEncoder().encode(item)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check(!text.contains("preferredWorkoutID"), "No successor stores no key, not a null")
        let old = "{\"workoutID\":\"\(UUID().uuidString)\",\"sessionID\":\"\(UUID().uuidString)\",\"at\":0}"
        let decoded = try? JSONDecoder().decode(CleanupAttemptLedger.GivenUp.self, from: Data(old.utf8))
        check(decoded != nil && decoded?.preferredWorkoutID == nil, "A given-up entry saved before the key existed still decodes")
    }

    // MARK: Relink through drain

    /// A stored list, a ledger and a scripted store, wired the way
    /// `HealthKitService` wires them, so a test reads as a sequence of passes.
    @MainActor final class Harness {
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
            let now = HealthCleanupCapTests.occasion(pass)
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
                                               prepare: { $0.preferredWorkoutID == nil || self.relinks }, delete: delete)
            }
        }
    }

    static func entry(preferred: UUID? = UUID()) -> PendingWorkoutCleanup {
        PendingWorkoutCleanup(workoutID: UUID(), sessionID: UUID(), preferredWorkoutID: preferred)
    }

    @MainActor static func relinkThatNeverSucceedsIsGivenUp() async {
        let stuck = entry(), other = entry(preferred: nil)
        let harness = Harness([stuck, other])
        harness.relinks = false
        harness.deleteAnswer = .gone
        for _ in 0..<(CleanupAttemptLedger.cap - 1) { await harness.run() }
        check(harness.queue.contains(stuck), "Four failed relinks keep the entry")
        check(!harness.deleteCalls.contains(stuck.workoutID), "A failed relink never reaches the delete")
        await harness.run()
        check(!harness.queue.contains(stuck), "The fifth failed relink drops the entry from the list")
        check(harness.ledger.givenUp.first?.workoutID == stuck.workoutID, "The dropped entry is remembered for Settings")
        check(harness.ledger.givenUp.first?.preferredWorkoutID == stuck.preferredWorkoutID,
              "It keeps its successor for a Retry")
        check(harness.ledger.givenUp.count == 1, "Only the stuck entry is given up")
        check(harness.deleteCalls == [other.workoutID], "An entry with no successor has nothing to link and is deleted as before")
    }

    @MainActor static func relinkThatSucceedsLaterIsNotGivenUp() async {
        let flaky = entry()
        let harness = Harness([flaky])
        harness.relinks = false
        for _ in 0..<3 { await harness.run() }
        harness.relinks = true
        harness.deleteAnswer = .gone
        await harness.run()
        check(harness.queue.isEmpty, "Once the link is made the workout is deleted and the entry leaves")
        check(harness.ledger.givenUp.isEmpty && harness.ledger.struggling.isEmpty, "Nothing is left in the ledger")
    }

    @MainActor static func missingStoreCostsNoAttempt() async {
        let waiting = entry()
        let harness = Harness([waiting])
        harness.relinks = false
        harness.storeConnected = false
        for _ in 0..<10 { await harness.run() }
        check(harness.queue == [waiting], "An entry with no store to relink in is never given up")
        check(harness.ledger.struggling.isEmpty, "It leaves no failure count")
    }

    @MainActor static func drainWithoutTheClosureNeverGivesUp() async {
        let stuck = entry()
        let harness = Harness([stuck])
        harness.relinks = false
        for _ in 0..<10 { await harness.run(useLinkFailed: false) }
        check(harness.queue == [stuck], "A caller that passes no closure keeps the old behaviour")
    }

    @MainActor static func withdrawnAccessKeepsTheEntryThroughDrain() async {
        let waiting = entry(preferred: nil)
        let harness = Harness([waiting])
        harness.deleteAnswer = .awaitingAccess
        for _ in 0..<12 { await harness.run() }
        check(harness.queue == [waiting], "Twelve passes without access keep the entry")
        check(harness.ledger.givenUp.isEmpty, "None of them gave up")
        harness.deleteAnswer = .gone
        await harness.run()
        check(harness.queue.isEmpty, "The first pass with access removes it")
    }
}
