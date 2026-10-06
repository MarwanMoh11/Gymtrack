import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// A set logged on the wrist with the phone asleep in a locker must land in the
/// store exactly once, with the moment the wrist stamped, and must leave no
/// trace when the wrist takes it back. Here the center applies commands with no
/// view hierarchy and no `ActiveWorkout`, as iOS does when it wakes a terminated
/// app to hand over a watch message, and the assertions read the store. What the
/// center sends back to the watch cannot be seen from a test, so it is not
/// asserted.
///
/// Complements the legacy `Tests/test-wrist-redelivery-undo.swift` and
/// `Tests/test-late-wrist-logs.swift`, which cover the same rules against a
/// hand-built harness.

// MARK: - Harness

/// One in-memory store wired to the real center, with every process-wide
/// singleton the center reaches pointed at throwaway state and put back by
/// `tearDown`. `WatchLinkWireTests` drives the center through it too.
@MainActor
final class Rig {
    /// Containers outlive their test on purpose. A finish starts a task that
    /// goes on reading its session for up to twelve seconds, and a model read
    /// after its container is gone traps.
    private static var retained: [ModelContainer] = []

    private static let repairKeys = ["implausibleStartsRepaired", "overtakenStartsRepaired"]

    let container: ModelContainer
    let center = WatchCommandCenter.shared
    let defaults: UserDefaults

    /// An hour ago, to the whole second. `WorkoutSession.isStale` reads the wall
    /// clock, so a fixed date in the past would have every command retire the
    /// session it was meant to act on. Everything the tests stamp is an offset
    /// from this, so each stamp is in the past, as a wrist's always is.
    let started: Date

    private let savedRepairFlags: [String: Any?]
    private let savedUnit = AppSettings.shared.weightUnit
    private let savedTrackRPE = AppSettings.shared.trackRPE

    var context: ModelContext { container.mainContext }

    init(_ name: String) throws {
        container = try TestStore.container()
        Self.retained.append(container)
        defaults = TestClock.freshDefaults(name)
        started = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 3600).rounded(.down))
        savedRepairFlags = Dictionary(uniqueKeysWithValues: Self.repairKeys.map {
            ($0, UserDefaults.standard.object(forKey: $0))
        })
        DroppedSetMemory.shared.replaceStore(with: defaults)
        center.loggerMemory = LoggerMemoryStore(defaults: defaults)
        center.uiHandler = nil
        center.configure(container: container)
    }

    func tearDown() {
        center.uiHandler = nil
        center.loggerMemory = .standard
        WatchBridge.shared.commandHandler = nil
        WatchBridge.shared.update(session: nil, ended: nil)
        DroppedSetMemory.shared.replaceStore(with: .standard)
        LoadScaleBook.shared.clearAll()
        AppSettings.shared.weightUnit = savedUnit
        AppSettings.shared.trackRPE = savedTrackRPE
        for (key, value) in savedRepairFlags {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    func at(_ seconds: TimeInterval) -> Date { started.addingTimeInterval(seconds) }

    /// An open session of unlogged, prescribed sets: 60 kg for 8, as a plan
    /// would have filled them in. Catalog IDs are made up so the real catalog's
    /// machines and tracking modes cannot change what a set is.
    @discardableResult
    func seed(exercises: [String] = ["test-bench"], setsEach: Int = 3,
              startedAt: Date? = nil) throws -> (session: WorkoutSession, sets: [SetLog]) {
        let session = WorkoutSession(title: "Push", startedAt: startedAt ?? started)
        context.insert(session)
        var sets: [SetLog] = []
        for (order, catalogID) in exercises.enumerated() {
            for index in 0..<setsEach {
                let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: order,
                                 setIndex: index, weightKg: 60, reps: 8, targetRepsLow: 6,
                                 targetRepsHigh: 8, tracking: .weightReps)
                set.session = session
                context.insert(set)
                sets.append(set)
            }
        }
        try context.save()
        return (session, sets)
    }

    func sessions() -> [WorkoutSession] {
        (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
    }

    func allSets() -> [SetLog] {
        (try? context.fetch(FetchDescriptor<SetLog>())) ?? []
    }

    func log(_ set: SetLog, weight: Double = 62.5, reps: Int = 6, at seconds: TimeInterval) -> WatchCommand {
        .logSet(id: set.id, weightKg: weight, reps: reps, seconds: 0, at: at(seconds))
    }

    func send(_ command: WatchCommand) { center.handle(command) }

    /// A set as the logger leaves it once logged, written by hand because the
    /// app's own helper for a wrist log is private to the app.
    func complete(_ set: SetLog, at moment: Date) {
        set.isCompleted = true
        set.completedAt = moment
    }
}

@MainActor
func withRig(_ name: String = #function, _ body: @MainActor (Rig) throws -> Void) throws {
    let rig = try Rig(name)
    defer { rig.tearDown() }
    try body(rig)
}

/// Counts what reaches a handler, in order.
@MainActor
private final class Recorder {
    var commands: [WatchCommand] = []
}

private func sameMoment(_ a: Date?, _ b: Date?) -> Bool { WatchCommand.isSameCompletion(a, as: b) }

// MARK: - Logging and undoing

@MainActor @Suite(.serialized)
struct WatchCommandCenterHeadlessTests {

    @Test func aWristLogCompletesAPrescribedSetWithTheWristsMoment() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            #expect(rig.center.uiHandler == nil)

            rig.send(rig.log(sets[0], weight: 62.5, reps: 6, at: 600))

            #expect(sets[0].isCompleted)
            #expect(sameMoment(sets[0].completedAt, rig.at(600)))
            #expect(sets[0].weightKg == 62.5)
            #expect(sets[0].reps == 6)
            #expect(sets[0].rpe == nil)
            #expect(!sets[1].isCompleted)
            #expect(session.isActive)
        }
    }

    @Test func aRedeliveredLogDoesNotLogTwiceOrCarryItsLoadAgain() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let command = rig.log(sets[0], weight: 80, reps: 5, at: 600)
            rig.send(command)

            // The lifter dials the next row by hand after the first log landed.
            sets[1].weightKg = 70
            rig.send(command)

            #expect(sameMoment(sets[0].completedAt, rig.at(600)))
            #expect(sets[0].weightKg == 80)
            #expect(sets[1].weightKg == 70)
            #expect(rig.allSets().filter(\.isCompleted).count == 1)

            // A different stamp is a different log, and does land.
            rig.send(rig.log(sets[0], weight: 82.5, reps: 4, at: 700))
            #expect(sameMoment(sets[0].completedAt, rig.at(700)))
            #expect(sets[0].weightKg == 82.5)
        }
    }

    @Test func aRedeliveredLogIsStillRecognisedByTheRowWhenTheMemoryOfItIsGone() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let command = rig.log(sets[0], weight: 80, reps: 5, at: 600)
            rig.send(command)
            sets[1].weightKg = 70

            // The remembered log expires after a week and is dropped with the rest
            // of the defaults; the row itself still holds the completion, and that
            // alone has to stop the load being carried a second time.
            DroppedSetMemory.shared.replaceStore(with: TestClock.freshDefaults("memoryGone"))
            #expect(!DroppedSetMemory.shared.wasHeardLog(sets[0].id, loggedAt: rig.at(600)))
            rig.send(command)

            #expect(sameMoment(sets[0].completedAt, rig.at(600)))
            #expect(sets[1].weightKg == 70)
        }
    }

    @Test func aLogRedeliveredAfterThePhoneUndidItStaysUndone() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let command = rig.log(sets[0], at: 600)
            rig.send(command)
            sets[0].unlog()

            rig.send(command)

            #expect(!sets[0].isCompleted)
            #expect(sets[0].completedAt == nil)
        }
    }

    @Test func aWristUndoLeavesNoTraceOnTheSet() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let set = sets[0]
            rig.send(.announceStart(id: set.id, at: rig.at(590)))
            rig.send(rig.log(set, at: 600))
            rig.send(.rateSet(WatchSetRating(sessionID: set.session!.id, setID: set.id,
                                             completedAt: rig.at(600), rpe: SetFeel.hard.rawValue)))
            #expect(set.rpe == SetFeel.hard.rawValue)
            #expect(set.startedAt != nil)

            rig.send(.undoSet(id: set.id, completedAt: rig.at(600)))

            #expect(!set.isCompleted)
            #expect(set.completedAt == nil)
            #expect(set.rpe == nil)
            #expect(set.startedAt == nil)
        }
    }

    @Test func anUndoAimedAtAnEarlierLogIsRefusedAndAnUnstampedOneIsNot() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            rig.send(rig.log(sets[0], weight: 65, reps: 5, at: 700))

            rig.send(.undoSet(id: sets[0].id, completedAt: rig.at(600)))
            #expect(sets[0].isCompleted)
            #expect(sameMoment(sets[0].completedAt, rig.at(700)))

            // Sent by a watch older than stamped undos, which cannot say which
            // log it answers.
            rig.send(.undoSet(id: sets[0].id, completedAt: nil))
            #expect(!sets[0].isCompleted)
        }
    }

    @Test func anUndoThatArrivesBeforeItsLogKeepsThatLogOutButNotTheNextOne() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            rig.send(.undoSet(id: sets[0].id, completedAt: rig.at(600)))

            rig.send(rig.log(sets[0], at: 600))
            #expect(!sets[0].isCompleted)

            rig.send(rig.log(sets[0], at: 800))
            #expect(sets[0].isCompleted)
            #expect(sameMoment(sets[0].completedAt, rig.at(800)))
        }
    }

    @Test func aRatingIsKeptOnlyForTheLogItAnswers() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            @MainActor func rate(_ set: SetLog, at seconds: TimeInterval, _ rpe: Double?) {
                rig.send(.rateSet(WatchSetRating(sessionID: session.id, setID: set.id,
                                                 completedAt: rig.at(seconds), rpe: rpe)))
            }

            // Ahead of its log: the set is not logged yet, so there is nothing to rate.
            rate(sets[0], at: 600, 8)
            rig.send(rig.log(sets[0], at: 600))
            #expect(sets[0].rpe == nil)

            rate(sets[0], at: 605, 8)
            #expect(sets[0].rpe == nil)
            rate(sets[0], at: 600, 3)
            #expect(sets[0].rpe == nil)

            rate(sets[0], at: 600, SetFeel.allOut.rawValue)
            #expect(sets[0].rpe == SetFeel.allOut.rawValue)
            rate(sets[0], at: 600, nil)
            #expect(sets[0].rpe == nil)

            rate(sets[1], at: 600, 8)
            #expect(sets[1].rpe == nil)

            rate(sets[0], at: 600, SetFeel.solid.rawValue)
            rig.send(.undoSet(id: sets[0].id, completedAt: rig.at(600)))
            rate(sets[0], at: 600, SetFeel.solid.rawValue)
            #expect(sets[0].rpe == nil)
        }
    }

    // MARK: - Announcing a start

    @Test func aStartIsAnnouncedOnceOnAnUnloggedSetAndNeverFromTheFuture() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()

            rig.send(.announceStart(id: sets[0].id, at: rig.at(500)))
            rig.send(.announceStart(id: sets[0].id, at: rig.at(550)))
            #expect(sameMoment(sets[0].startedAt, rig.at(500)))

            rig.send(.announceStart(id: sets[1].id, at: Date.now.addingTimeInterval(3600)))
            #expect(sets[1].startedAt == nil)

            rig.send(rig.log(sets[2], at: 600))
            rig.send(.announceStart(id: sets[2].id, at: rig.at(610)))
            #expect(sets[2].startedAt == nil)

            rig.send(.cancelStart(id: sets[0].id))
            #expect(sets[0].startedAt == nil)
        }
    }

    // MARK: - Finishing

    enum Finish: CaseIterable, Sendable {
        case beforeTheLastSet, afterTheLastSet, inTheFuture, unstamped
    }

    @Test(arguments: Finish.allCases)
    func aFinishEndsNoEarlierThanTheLastSetAndNoLaterThanNow(_ finish: Finish) throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            let stamp: Date? = switch finish {
            case .beforeTheLastSet: rig.at(100)
            case .afterTheLastSet: rig.at(900)
            case .inTheFuture: Date.now.addingTimeInterval(3600)
            case .unstamped: nil
            }
            let batch = WatchFinishBatch(sessionID: session.id, logs: [], undos: [], starts: [:],
                                         cancels: [], ratings: [], endedAt: stamp)

            let before = Date.now
            rig.send(.finishSession(batch, metrics: nil))
            let after = Date.now

            #expect(!session.isActive)
            let end = try #require(session.endedAt)
            switch finish {
            case .beforeTheLastSet: #expect(sameMoment(end, rig.at(600)))
            case .afterTheLastSet: #expect(sameMoment(end, rig.at(900)))
            case .inTheFuture, .unstamped: #expect((before...after).contains(end))
            }
            // The rows nobody lifted go, as the phone's own Finish drops them.
            #expect(session.sets.map(\.id) == [sets[0].id])
        }
    }

    @Test func aFinishWithNothingLoggedIsADiscardAndOneWithASetIsKept() throws {
        try withRig { rig in
            let empty = try rig.seed().session
            rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: empty.id)))
            #expect(rig.sessions().isEmpty)

            let (kept, sets) = try rig.seed()
            rig.send(rig.log(sets[0], at: 600))
            rig.send(.finish(metrics: WatchWorkoutMetrics(sessionID: kept.id)))
            #expect(rig.sessions().count == 1)
            #expect(!kept.isActive)
            #expect(kept.completedSets.count == 1)
        }
    }

    @Test func aWristFinishReplaysItsLogsRatingsAndUndosThenClosesTheRest() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let first = sets[0].id, second = sets[1].id
            let batch = WatchFinishBatch(
                sessionID: session.id,
                logs: [WatchPendingLog(setID: first, weightKg: 80, reps: 5, seconds: 0, completedAt: rig.at(300)),
                       WatchPendingLog(setID: second, weightKg: 80, reps: 5, seconds: 0, completedAt: rig.at(400))],
                undos: [second], starts: [:], cancels: [],
                ratings: [WatchSetRating(sessionID: session.id, setID: first,
                                         completedAt: rig.at(300), rpe: SetFeel.hard.rawValue)],
                endedAt: rig.at(500))

            rig.send(.finishSession(batch, metrics: nil))

            #expect(!session.isActive)
            #expect(sameMoment(session.endedAt, rig.at(500)))
            #expect(session.sets.map(\.id) == [first])
            let kept = try #require(session.sets.first)
            #expect(kept.isCompleted)
            #expect(kept.weightKg == 80 && kept.reps == 5)
            #expect(sameMoment(kept.completedAt, rig.at(300)))
            #expect(kept.rpe == SetFeel.hard.rawValue)
        }
    }

    @Test func aDiscardRemovesOnlyTheSessionItNames() throws {
        try withRig { rig in
            let history = try rig.seed(startedAt: rig.at(-7200)).session
            let historySets = history.sets
            rig.complete(historySets[0], at: rig.at(-6600))
            history.close(at: rig.at(-3600), in: rig.context)
            let historyID = history.id

            let current = try rig.seed().session
            let currentID = current.id

            rig.send(.discardSession(id: UUID()))
            #expect(Set(rig.sessions().map(\.id)) == [historyID, currentID])

            rig.send(.discardSession(id: currentID))
            #expect(rig.sessions().map(\.id) == [historyID])
        }
    }

    // MARK: - Late logs

    enum Route: CaseIterable, Sendable { case headless, loggerRunning }

    @Test(arguments: Route.allCases)
    func aLogAfterTheFinishIsPutBackAndItsUndoTakesItOutAgain(_ route: Route) throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let late = sets[1].id, tooLate = sets[2].id
            @MainActor func deliver(_ command: WatchCommand) {
                switch route {
                case .headless: rig.center.applyHeadless(command)
                case .loggerRunning: rig.center.applyToFinishedSession(command)
                }
            }
            rig.send(rig.log(sets[0], at: 300))
            // The phone's own Finish, which deletes the rows nobody logged.
            session.close(at: rig.at(900), in: rig.context)
            try rig.context.save()
            #expect(session.sets.count == 1)

            deliver(.logSet(id: late, weightKg: 70, reps: 5, seconds: 0, at: rig.at(600)))
            let restored = try #require(session.sets.first { $0.id == late })
            #expect(restored.isCompleted)
            #expect(restored.weightKg == 70 && restored.reps == 5)
            #expect(sameMoment(restored.completedAt, rig.at(600)))
            #expect(sameMoment(session.endedAt, rig.at(900)))

            // Stamped after the session ended: not a lift the session could hold.
            deliver(.logSet(id: tooLate, weightKg: 70, reps: 5, seconds: 0, at: rig.at(1000)))
            #expect(!session.sets.contains { $0.id == tooLate })

            deliver(.undoSet(id: late, completedAt: rig.at(600)))
            #expect(session.sets.map(\.id) == [sets[0].id])
        }
    }

    // MARK: - Stale sessions

    @Test func aSessionLeftOpenPastTheStaleMarkIsClosedAtItsLastSetByTheNextMirror() throws {
        try withRig { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let (session, sets) = try rig.seed(startedAt: longAgo)
            rig.complete(sets[0], at: longAgo.addingTimeInterval(600))
            let last = sets[0].id

            rig.send(.requestMirror)

            #expect(!session.isActive)
            #expect(sameMoment(session.endedAt, longAgo.addingTimeInterval(600)))
            #expect(session.sets.map(\.id) == [last])
        }
    }

    @Test func aStaleSessionIsNotHandedBackAsTheOneRunningWhenAStartArrives() throws {
        try withRig { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let stale = try rig.seed(startedAt: longAgo).session
            let staleID = stale.id

            rig.send(.startFreestyle)

            // Nothing was logged in the stale one, so it is deleted rather than kept.
            let open = rig.sessions().filter(\.isActive)
            #expect(open.count == 1)
            #expect(open.first?.id != staleID)
            #expect(open.first?.title == "Freestyle Session")
            #expect(rig.sessions().count == 1)
        }
    }

    @Test func retiringSaysHowTheWristShouldHearTheSessionEnded() throws {
        try withRig { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let kept = try rig.seed(startedAt: longAgo).session
            rig.complete(kept.sets[0], at: longAgo.addingTimeInterval(60))
            let keptID = kept.id
            let empty = try rig.seed(startedAt: longAgo.addingTimeInterval(-1000)).session
            let emptyID = empty.id
            let fresh = try rig.seed().session

            #expect(rig.center.retire(fresh, in: rig.context) == nil)
            #expect(fresh.isActive)
            #expect(rig.center.retire(kept, in: rig.context)
                    == WatchSessionEnd(sessionID: keptID, reason: .finished))
            #expect(rig.center.retire(empty, in: rig.context)
                    == WatchSessionEnd(sessionID: emptyID, reason: .discarded))
        }
    }

    // MARK: - The two ways in

    @Test func whenTheScreenTakesACommandTheCenterLeavesTheStoreAlone() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let screen = Recorder()
            rig.center.uiHandler = { screen.commands.append($0); return true }

            rig.send(rig.log(sets[0], at: 600))
            rig.send(.startFreestyle)

            #expect(screen.commands.count == 2)
            #expect(!sets[0].isCompleted)
            #expect(rig.sessions().count == 1)
        }
    }

    @Test func whenTheScreenDeclinesACommandItFallsThroughToTheHeadlessPath() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            let screen = Recorder()
            rig.center.uiHandler = { screen.commands.append($0); return false }

            rig.send(rig.log(sets[0], at: 600))

            #expect(screen.commands.count == 1)
            #expect(sets[0].isCompleted)
        }
    }

    @Test func aLogTheScreenTookIsRememberedSoALaterRedeliveryCannotResurrectIt() throws {
        try withRig { rig in
            let (_, sets) = try rig.seed()
            rig.center.uiHandler = { _ in true }
            // The logger wrote the row itself before the command was offered to it.
            rig.complete(sets[0], at: rig.at(600))

            rig.send(rig.log(sets[0], at: 600))
            sets[0].unlog()
            rig.center.uiHandler = nil
            rig.send(rig.log(sets[0], at: 600))

            #expect(DroppedSetMemory.shared.wasHeardLog(sets[0].id, loggedAt: rig.at(600)))
            #expect(!sets[0].isCompleted)
        }
    }

    // MARK: - Commands that repeat or have nothing to act on

    @Test(arguments: [WatchCommand.startFreestyle, .startToday])
    func aRedeliveredStartDoesNotOpenASecondSession(_ start: WatchCommand) throws {
        try withRig { rig in
            rig.send(start)
            rig.send(start)
            rig.send(.startFreestyle)
            rig.send(.startToday)

            let all = rig.sessions()
            #expect(all.count == 1)
            #expect(all.first?.isActive == true)
            #expect(all.first?.wasWatchDriven == true)
            #expect(all.first?.title == "Freestyle Session")
        }
    }

    static let ghost = UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!

    static let commandsForNothingThatExists: [WatchCommand] = [
        .logSet(id: ghost, weightKg: 60, reps: 8, seconds: 0, at: nil),
        .logSet(id: ghost, weightKg: 60, reps: 8, seconds: 0, at: TestClock.reference),
        .undoSet(id: ghost, completedAt: TestClock.reference),
        .undoSet(id: ghost, completedAt: nil),
        .rateSet(WatchSetRating(sessionID: ghost, setID: ghost, completedAt: TestClock.reference, rpe: 8)),
        .announceStart(id: ghost, at: TestClock.reference),
        .cancelStart(id: ghost),
        .addSet(catalogID: "not-in-this-session"),
        .focusExercise(catalogID: "not-in-this-session"),
        .finish(metrics: WatchWorkoutMetrics(sessionID: ghost)),
        .finish(metrics: nil),
        .finishSession(WatchFinishBatch(sessionID: ghost, logs: [], undos: [], starts: [:], cancels: [],
                                        ratings: []), metrics: nil),
        .discardSession(id: ghost),
        .discard,
        .metrics(WatchWorkoutMetrics(sessionID: ghost, currentHeartRate: 120)),
        .startRest(seconds: 60), .stopRest, .extendRest(seconds: 15),
    ]

    @Test(arguments: WatchCommandCenterHeadlessTests.commandsForNothingThatExists, [false, true])
    func aCommandForASessionThatIsGoneChangesNothing(_ command: WatchCommand, withARunningSession: Bool) throws {
        try withRig { rig in
            var runningID: UUID?
            if withARunningSession { runningID = try rig.seed().session.id }

            rig.send(command)

            let all = rig.sessions()
            #expect(all.map(\.id) == (runningID.map { [$0] } ?? []))
            #expect(all.first?.isActive ?? true)
            #expect(all.first?.preferredExerciseID == nil)
            let sets = rig.allSets()
            #expect(sets.count == (withARunningSession ? 3 : 0))
            #expect(sets.allSatisfy { !$0.isCompleted && $0.startedAt == nil && $0.rpe == nil })
        }
    }

    @Test func anAddedSetCopiesTheLastOneAndFocusNamesOnlyAnExerciseTheSessionHas() throws {
        try withRig { rig in
            let (session, _) = try rig.seed()

            rig.send(.addSet(catalogID: "test-bench"))
            #expect(session.sets.count == 4)
            let added = try #require(session.sets.max { $0.setIndex < $1.setIndex })
            #expect(added.setIndex == 3)
            #expect(added.weightKg == 60 && added.reps == 8)
            #expect(!added.isCompleted)

            rig.send(.addSet(catalogID: "test-squat"))
            #expect(session.sets.count == 4)

            rig.send(.focusExercise(catalogID: "test-bench"))
            #expect(session.preferredExerciseID == "test-bench")
            rig.send(.focusExercise(catalogID: "test-squat"))
            #expect(session.preferredExerciseID == nil)
        }
    }

    // MARK: - The mirror

    @Test(arguments: [(WeightUnit.kg, 1.25), (WeightUnit.lb, 2.5)])
    func theMirrorCarriesTheUnitAndEachMachinesScale(_ unit: WeightUnit, defaultStep: Double) throws {
        try withRig { rig in
            AppSettings.shared.weightUnit = unit
            AppSettings.shared.trackRPE = true
            let tuned = LoadScale(unit: unit, increment: 10)
            LoadScaleBook.shared.set(tuned, for: "test-leg-press")
            let (session, _) = try rig.seed(exercises: ["test-bench", "test-leg-press"])

            let snapshot = WatchSnapshotFactory.snapshot(
                for: session, rest: (nil, nil, 0), restSeconds: { _ in 90 }, lastTimeLabel: { _ in nil })

            #expect(snapshot.unit == unit)
            #expect(snapshot.effortEnabled == true)
            #expect(snapshot.exercises.map(\.id) == ["test-bench", "test-leg-press"])
            #expect(snapshot.exercises[0].scale == LoadScale(unit: unit, increment: defaultStep))
            #expect(snapshot.exercises[1].scale == tuned)
            #expect(snapshot.exercises[1].resolvedScale(sessionUnit: unit) == tuned)
            // Weights stay in kilograms on the wire; the scale is what shows them.
            let set = snapshot.exercises[0].sets[0]
            #expect(set.weightKg == 60)
            #expect(snapshot.exercises[0].resolvedScale(sessionUnit: unit).display(set.weightKg)
                    == unit.fromKg(60))
            #expect(snapshot.volumeKg == session.totalVolumeKg)
        }
    }
}

// MARK: - What the mirror says before and after a workout

@MainActor @Suite(.serialized)
struct WatchMirrorStateTests {

    private static let t0 = TestClock.reference
    private static let sessionID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    private func snapshot(_ id: UUID = WatchMirrorStateTests.sessionID) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: id, title: "Push", planName: "", startedAt: Self.t0, exercises: [],
            restTotalSeconds: 0, restAutoStart: false, volumeKg: 0, unit: .kg)
    }

    @Test func nothingIsSentUntilThePhoneHasSaidWhatIsRunning() {
        var state = WatchMirrorState()
        let beforeAnything = state.nextMirror(healthEnabled: true)
        #expect(beforeAnything == nil)

        // The idle screen alone is not an answer: a mirror that said "no session"
        // before the store was read is what ended a recording mid-workout.
        var idle = WatchIdleSnapshot.empty
        idle.streak = 4
        let changed = state.update(idle: idle)
        let repeated = state.update(idle: idle)
        #expect(changed)
        #expect(!repeated)
        #expect(!state.isEstablished)
        let afterIdleOnly = state.nextMirror(healthEnabled: true)
        #expect(afterIdleOnly == nil)

        let established = state.update(session: nil, ended: nil)
        #expect(established)
        #expect(state.isEstablished)
        let first = state.nextMirror(sentAt: Self.t0, healthEnabled: true)
        #expect(first?.revision == 1)
        #expect(first?.idle.streak == 4)
        #expect(first?.session == nil)
        #expect(first?.healthEnabled == true)
        let second = state.nextMirror(sentAt: Self.t0, healthEnabled: false)
        #expect(second?.revision == 2)
    }

    @Test func aSessionKeepsItsEndedMarkerUntilAnotherSessionStarts() {
        var state = WatchMirrorState()
        let end = WatchSessionEnd(sessionID: Self.sessionID, reason: .finished)

        let started = state.update(session: snapshot(), ended: nil)
        let unchanged = state.update(session: snapshot(), ended: nil)
        #expect(started)
        #expect(!unchanged)

        let ended = state.update(session: nil, ended: end)
        #expect(ended)
        #expect(state.endedSession == end)
        let quiet = state.update(session: nil, ended: nil)
        #expect(!quiet)
        #expect(state.endedSession == end)

        let next = state.update(session: snapshot(UUID()), ended: end)
        #expect(next)
        #expect(state.endedSession == nil)
    }

    @Test func thePhonesHealthWorkoutIsNotedOnlyForTheFinishedSessionItBelongsTo() {
        var state = WatchMirrorState()
        let workout = UUID()
        _ = state.update(session: nil, ended: WatchSessionEnd(sessionID: Self.sessionID, reason: .finished))

        let wrongSession = state.notePhoneHealthWorkout(workout, for: UUID())
        #expect(!wrongSession)
        #expect(state.endedSession?.phoneHealthWorkoutID == nil)
        let rightSession = state.notePhoneHealthWorkout(workout, for: Self.sessionID)
        #expect(rightSession)
        #expect(state.endedSession?.phoneHealthWorkoutID == workout)

        _ = state.update(session: nil, ended: WatchSessionEnd(sessionID: Self.sessionID, reason: .discarded))
        let discarded = state.notePhoneHealthWorkout(workout, for: Self.sessionID)
        #expect(!discarded)
    }
}

// MARK: - A payload through the bridge

@MainActor @Suite(.serialized)
struct WatchBridgePayloadTests {

    private func payload(_ command: WatchCommand, stampedFor session: UUID? = nil, sentAt: Date? = nil) -> [String: Any] {
        var result = command.watchPayload(key: WatchLink.commandKey)
        let riders = WatchCommandDelivery(sentAt: sentAt, sessionID: session).payload
        result.merge(riders) { _, new in new }
        return result
    }

    @Test func aPayloadFromTheWristReachesTheStoreAndGarbageDoesNot() throws {
        try withRig { rig in
            let (session, sets) = try rig.seed()
            let handler = Recorder()
            let center = rig.center
            WatchBridge.shared.commandHandler = { handler.commands.append($0); center.handle($0) }

            // Teaches the bridge which session the phone has open, as a real
            // watch's first request does.
            WatchBridge.shared.handle(payload(.requestMirror))
            WatchBridge.shared.handle(payload(rig.log(sets[0], weight: 70, reps: 5, at: 600)))
            #expect(sets[0].isCompleted)
            #expect(sets[0].weightKg == 70)

            WatchBridge.shared.handle(payload(.addSet(catalogID: "test-bench"), stampedFor: session.id))
            #expect(session.sets.count == 4)
            #expect(handler.commands.count == 3)

            let accepted = handler.commands.count
            WatchBridge.shared.handle([:])
            WatchBridge.shared.handle([WatchLink.commandKey: Data("junk".utf8)])
            WatchBridge.shared.handle([WatchLink.commandKey: "requestMirror"])
            #expect(handler.commands.count == accepted)
            #expect(session.sets.count == 4)
        }
    }

    @Test func aCommandStampedForAnotherSessionOrGoneStaleIsRefusedBeforeAnyoneHandlesIt() throws {
        try withRig { rig in
            let (session, _) = try rig.seed()
            let handler = Recorder()
            let center = rig.center
            WatchBridge.shared.commandHandler = { handler.commands.append($0); center.handle($0) }
            WatchBridge.shared.handle(payload(.requestMirror))
            handler.commands.removeAll()

            WatchBridge.shared.handle(payload(.addSet(catalogID: "test-bench"), stampedFor: UUID()))
            #expect(session.sets.count == 3)
            #expect(handler.commands.isEmpty)

            let staleBy = WatchCommandDelivery.startShelfLife + 60
            WatchBridge.shared.handle(payload(.startFreestyle, sentAt: Date.now.addingTimeInterval(-staleBy)))
            #expect(handler.commands.isEmpty)

            WatchBridge.shared.handle(payload(.addSet(catalogID: "test-bench"), stampedFor: session.id))
            #expect(session.sets.count == 4)
            #expect(handler.commands == [.addSet(catalogID: "test-bench")])
        }
    }
}
