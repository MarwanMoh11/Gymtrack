import Foundation
import SwiftData

/// The last loose ends of the phone's watch-command path: which plan a Start
/// from the wrist begins, what the headless Finish and Discard leave in the
/// logger's saved memory, the headless undo of a carry the phone's logger made,
/// and the repair of starts another set's log overtook.
/// Run with scripts/test-watch-command-leftovers.sh; no simulator is needed.
@main
struct WatchCommandLeftoverTests {
    static let bench = "bench-leftover"

    @MainActor static func main() throws {
        try theRuleTakesTheActivePlanElseTheEarliest()
        try aStartFromTheWristBeginsThePlanTodayShows()
        try everyHeadlessEndClearsTheLoggersMemory()
        try aCarryThePhoneMadeIsUndoneFromTheWrist()
        try overtakenStartsAreRepairedFromTheStampsAlone()
        print("Watch command leftovers passed")
    }

    // MARK: - Fixtures

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A suite of its own per case, so one case's keys are never another's.
    @MainActor static func withDefaults(_ body: @MainActor (UserDefaults) throws -> Void) throws {
        let name = "gymtrack.leftover-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @MainActor static func plan(_ name: String, createdAt: Date, isActive: Bool,
                                in context: ModelContext) -> (Plan, PlanDay) {
        let plan = Plan(name: name, isActive: isActive)
        plan.createdAt = createdAt
        let day = PlanDay(name: name + " day", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        let item = PlanItem(catalogID: bench, name: bench, order: 0,
                            targetSets: 2, targetRepsLow: 8, targetRepsHigh: 8, targetWeightKg: 50)
        item.day = day
        context.insert(item)
        return (plan, day)
    }

    @MainActor static func row(_ index: Int, in session: WorkoutSession, weight: Double = 100,
                               context: ModelContext) -> SetLog {
        let set = SetLog(catalogID: bench, exerciseName: bench, exerciseOrder: 0, setIndex: index,
                         weightKg: weight, reps: 8, targetRepsLow: 8, targetRepsHigh: 10,
                         tracking: .weightReps)
        set.session = session
        context.insert(set)
        return set
    }

    @MainActor static func log(_ set: SetLog, at moment: Date) {
        set.isCompleted = true
        set.completedAt = moment
    }

    // MARK: - The plan pick

    @MainActor static func theRuleTakesTheActivePlanElseTheEarliest() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date.now
        let (older, _) = plan("Older", createdAt: now.addingTimeInterval(-200), isActive: false, in: context)
        let (newer, _) = plan("Newer", createdAt: now.addingTimeInterval(-100), isActive: false, in: context)
        precondition(Plan.displayed(among: []) == nil, "No plans, no answer")
        for order in [[older, newer], [newer, older]] {
            precondition(Plan.displayed(among: order) === older,
                         "With none active the earliest created is shown, in any order")
        }
        newer.isActive = true
        for order in [[older, newer], [newer, older]] {
            precondition(Plan.displayed(among: order) === newer, "The active plan wins over an earlier one")
        }
    }

    /// The store hands plans back in the order they were written, and the
    /// newer one is written first here, so an unsorted `first` finds the wrong one.
    @MainActor static func aStartFromTheWristBeginsThePlanTodayShows() throws {
        func startedDay(activeIsNewer: Bool?) throws -> String? {
            let container = try makeContainer()
            let context = container.mainContext
            let now = Date.now
            let (newer, _) = plan("Newer", createdAt: now.addingTimeInterval(-100),
                                  isActive: activeIsNewer == true, in: context)
            // Saved apart, so the store numbers the newer plan first.
            try context.save()
            _ = plan("Older", createdAt: now.addingTimeInterval(-200),
                     isActive: activeIsNewer == false, in: context)
            try context.save()
            let inStoreOrder = try context.fetch(FetchDescriptor<Plan>())
            precondition(inStoreOrder.first === newer, "Setup: the store returns the newer plan first")
            let center = WatchCommandCenter.shared
            center.uiHandler = nil
            center.configure(container: container)
            center.applyHeadless(.startToday)
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            precondition(sessions.count == 1, "The start began one session")
            let days = try context.fetch(FetchDescriptor<PlanDay>())
            return days.first { $0.id == sessions[0].planDayID }?.name
        }

        let none = try startedDay(activeIsNewer: nil)
        precondition(none == "Older day", "With no active plan the wrist starts the one Today shows, the earliest")
        let newerActive = try startedDay(activeIsNewer: true)
        precondition(newerActive == "Newer day", "The active plan is the one a wrist start begins")
        let olderActive = try startedDay(activeIsNewer: false)
        precondition(olderActive == "Older day", "An active earliest plan is the same answer by the same rule")
    }

    // MARK: - Memory on the way out

    /// Something for the store to hold, of the kind a phone logger leaves.
    static func memory(forSet setID: UUID, row rowID: UUID) -> LoggerMemory {
        LoggerMemory(carries: [.init(setID: setID, rows: [
            .init(rowID: rowID, kg: 100, seconds: 0, carriedKg: 105, carriedSeconds: 0)
        ])])
    }

    @MainActor static func everyHeadlessEndClearsTheLoggersMemory() throws {
        try withDefaults { defaults in
            let center = WatchCommandCenter.shared
            center.uiHandler = nil
            let store = LoggerMemoryStore(defaults: defaults)
            center.loggerMemory = store
            defer { center.loggerMemory = .standard }

            /// A running session with two rows, one logged, and a memory saved for it.
            @MainActor func running(_ container: ModelContainer, logged: Bool = true) -> WorkoutSession {
                let context = container.mainContext
                let session = WorkoutSession(title: "Running")
                session.wasWatchDriven = true
                context.insert(session)
                let first = row(0, in: session, context: context)
                let second = row(1, in: session, context: context)
                if logged { log(first, at: .now.addingTimeInterval(-60)) }
                store.save(memory(forSet: first.id, row: second.id), for: session.id)
                try? context.save()
                return session
            }
            let bystander = UUID()
            store.save(memory(forSet: UUID(), row: UUID()), for: bystander)

            var container = try makeContainer()
            var session = running(container)
            center.configure(container: container)
            precondition(store.load(for: session.id) != nil, "Setup: the memory is saved")
            center.applyHeadless(.finish(metrics: WatchWorkoutMetrics(sessionID: session.id)))
            precondition(session.endedAt != nil && store.load(for: session.id) == nil,
                         "A headless Finish clears the logger's memory of the session")

            container = try makeContainer()
            session = running(container)
            center.configure(container: container)
            center.applyHeadless(.finishSession(
                WatchFinishBatch(sessionID: session.id, logs: [], undos: [], starts: [:], cancels: [], ratings: []),
                metrics: nil))
            precondition(session.endedAt != nil && store.load(for: session.id) == nil,
                         "So does a Finish batch")

            container = try makeContainer()
            session = running(container, logged: false)
            let emptyID = session.id
            center.configure(container: container)
            center.applyHeadless(.finish(metrics: WatchWorkoutMetrics(sessionID: emptyID)))
            precondition(store.load(for: emptyID) == nil,
                         "A Finish with nothing logged is a Discard, and clears it too")

            container = try makeContainer()
            session = running(container)
            let discardedID = session.id
            center.configure(container: container)
            center.applyHeadless(.discardSession(id: discardedID))
            precondition(store.load(for: discardedID) == nil, "A headless Discard clears it")

            container = try makeContainer()
            session = running(container)
            session.startedAt = .now.addingTimeInterval(-14 * 3600)
            let staleID = session.id
            try container.mainContext.save()
            center.configure(container: container)
            center.retire(session, in: container.mainContext)
            precondition(store.load(for: staleID) == nil, "A stale session retired here loses its memory")

            precondition(store.load(for: bystander) != nil, "Another session's memory is not this path's to clear")
        }
    }

    // MARK: - Undoing a carry the phone's logger made

    @MainActor static func aCarryThePhoneMadeIsUndoneFromTheWrist() throws {
        try withDefaults { defaults in
            let center = WatchCommandCenter.shared
            center.uiHandler = nil
            let store = LoggerMemoryStore(defaults: defaults)
            center.loggerMemory = store
            defer { center.loggerMemory = .standard }

            let container = try makeContainer()
            let context = container.mainContext
            let session = WorkoutSession(title: "Carry")
            session.wasWatchDriven = true
            context.insert(session)
            let rows = (0..<4).map { row($0, in: session, context: context) }
            try context.save()

            // The phone's logger logs the top set, carrying its 105 kg down,
            // and is then gone: the app was reclaimed while the phone was down.
            do {
                let logger = ActiveWorkout(session: session, context: context, history: [], memory: store)
                rows[0].weightKg = 105
                logger.complete(rows[0], restSeconds: nil)
            }
            precondition(rows[1...].allSatisfy { $0.weightKg == 105 }, "Setup: the load was carried down")
            precondition(store.load(for: session.id)?.carries.isEmpty == false, "Setup: the logger kept the carry")
            rows[2].weightKg = 110

            center.configure(container: container)
            center.applyHeadless(.undoSet(id: rows[0].id, completedAt: rows[0].completedAt))
            precondition(!rows[0].isCompleted, "Setup: the wrist's undo took the set back")
            precondition(rows[1].weightKg == 100 && rows[3].weightKg == 100,
                         "The rows below open at what they held before the carry")
            precondition(rows[2].weightKg == 110, "A row typed into since keeps what was typed")
            precondition(store.load(for: session.id)?.carries.isEmpty ?? true,
                         "The record is spent, so it cannot put a weight back twice")
        }
    }

    // MARK: - Starts another set's log overtook

    @MainActor static func overtakenStartsAreRepairedFromTheStampsAlone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let base = Date.now.addingTimeInterval(-3600)
        func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }

        let session = WorkoutSession(title: "History")
        session.startedAt = base.addingTimeInterval(-60)
        context.insert(session)
        // Started at 0 and logged at 100, with another set logged at 50 between.
        let overtaken = row(0, in: session, context: context)
        overtaken.startedAt = at(0); log(overtaken, at: at(100))
        let between = row(1, in: session, context: context)
        log(between, at: at(50))
        // Nothing logged inside its own start and log.
        let clear = row(2, in: session, context: context)
        clear.startedAt = at(200); log(clear, at: at(260))
        let after = row(3, in: session, context: context)
        log(after, at: at(300))
        // Another set stamped the very instant this one was logged, and one
        // stamped the instant it started: neither is strictly inside.
        let tied = row(4, in: session, context: context)
        tied.startedAt = at(400); log(tied, at: at(460))
        let sameEnd = row(5, in: session, context: context)
        log(sameEnd, at: at(460))
        let sameStart = row(6, in: session, context: context)
        log(sameStart, at: at(400))
        // Another session's log at a moment inside is not this session's set.
        let other = WorkoutSession(title: "Elsewhere")
        other.startedAt = base.addingTimeInterval(-60)
        context.insert(other)
        let elsewhere = row(7, in: other, context: context)
        log(elsewhere, at: at(550))
        let lonely = row(8, in: session, context: context)
        lonely.startedAt = at(500); log(lonely, at: at(560))
        // Started and never logged is not the repair's to judge.
        let open = row(9, in: session, context: context)
        open.startedAt = at(20)
        try context.save()

        try withDefaults { defaults in
            // A phone the first repair already ran on, as every updated one is.
            defaults.set(true, forKey: "implausibleStartsRepaired")
            WatchCommandCenter.shared.repairStoredStartsOnce(in: context, defaults: defaults)
            precondition(overtaken.startedAt == nil, "A start with another set's log inside it is dropped")
            precondition(overtaken.isCompleted && overtaken.completedAt == at(100), "Only the start goes")
            precondition(between.startedAt == nil && between.isCompleted, "The set that overtook it is untouched")
            precondition(clear.startedAt == at(200), "A start nothing overtook is kept")
            precondition(tied.startedAt == at(400), "A log stamped at the same instant is arrival order, and not stored")
            precondition(sameStart.startedAt == nil && sameStart.isCompleted, "Nothing else changes")
            precondition(lonely.startedAt == at(500), "Another session's log does not overtake it")
            precondition(open.startedAt == at(20), "A set still open is not the repair's to judge")

            overtaken.startedAt = at(0)
            WatchCommandCenter.shared.repairStoredStartsOnce(in: context, defaults: defaults)
            precondition(overtaken.startedAt == at(0), "The repair runs once")
            precondition(SetLog.dropOvertakenStoredStarts(in: context) == 1, "Run directly it finds the same row")
        }
    }
}
