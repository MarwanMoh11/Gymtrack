import Foundation
import SwiftData

/// Run with scripts/test-watch-headless-follow-up.sh; no simulator is needed.
///
/// The headless path is what runs when a watch message wakes the app with
/// the phone locked. It has to behave as the logger does, and it has to let
/// go of a session deleted while it was waiting on Health.
@main
struct WatchHeadlessFollowUpTests {
    @MainActor static func main() async throws {
        try wristLogCarriesLoadOnlyWithinItsSlot()
        try await headlessHealthWriteStopsForADeletedSession()
        print("Headless load carry and Health write liveness passed")
    }

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A day that repeats a movement prescribes each slot its own load. A top
    /// set logged on the wrist used to be carried onto the back-off sets as
    /// well, which the phone's logger has not done since SESS-01.
    @MainActor static func wristLogCarriesLoadOnlyWithinItsSlot() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plan = Plan(name: "Repeated slots")
        let day = PlanDay(name: "Strength", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        for (order, count, load, reps) in [(0, 2, 30.0, 6), (1, 3, 45.0, 10)] {
            let row = PlanItem(catalogID: "repeat-test", name: "repeat-test", order: order,
                               targetSets: count, targetRepsLow: reps,
                               targetRepsHigh: reps, targetWeightKg: load)
            row.day = day
            context.insert(row)
        }
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [])
        try context.save()

        let built = session.sets.sorted(by: SetLog.precedesInSession)
        precondition(built.count == 5 && built.map(\.reps) == [6, 6, 10, 10, 10],
                     "The session holds the top pair and then the back-off three")
        let backOffLoads = built[2...].map(\.weightKg)
        let topSet = built[0]
        let loggedLoad = topSet.weightKg + 12.5

        WatchCommandCenter.shared.configure(container: container)
        WatchCommandCenter.shared.handle(.logSet(id: topSet.id, weightKg: loggedLoad,
                                                 reps: 6, seconds: 0, at: .now))

        let stored = try ModelContext(container).fetch(FetchDescriptor<SetLog>())
            .sorted(by: SetLog.precedesInSession)
        precondition(stored[0].isCompleted && stored[0].weightKg == loggedLoad)
        precondition(stored[1].weightKg == loggedLoad,
                     "The rest of the logged set's own slot takes its load")
        precondition(stored[2...].map(\.weightKg) == backOffLoads,
                     "A wrist log must not move the next slot's load")
    }

    /// A session finished on the wrist is written to Health from a task that
    /// outlives the command. Deleted meanwhile through another context, it
    /// must be dropped: noting a phone workout or reading vitals for it
    /// writes onto a row nothing can find again.
    @MainActor static func headlessHealthWriteStopsForADeletedSession() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = WorkoutSession(title: "Finished on the watch")
        let set = SetLog(catalogID: "bench-test", exerciseName: "bench-test",
                         exerciseOrder: 0, setIndex: 0, weightKg: 60, reps: 8)
        set.isCompleted = true
        set.completedAt = .now
        set.session = session
        context.insert(session)
        context.insert(set)
        try context.save()
        let sessionID = session.id

        let health = HealthKitService.shared
        health.workoutToWrite = UUID()
        health.duringSave = { _ in
            // An erase from the screen, through a context of its own.
            let screen = ModelContext(container)
            let rows = (try? screen.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == sessionID }))) ?? []
            rows.forEach(screen.delete)
            try? screen.save()
        }

        WatchCommandCenter.shared.configure(container: container)
        // The watch's own workout ID lets the write skip its wait for one.
        let metrics = WatchWorkoutMetrics(sessionID: sessionID, healthWorkoutID: UUID())
        WatchCommandCenter.shared.handle(.finish(metrics: metrics))
        try await Task.sleep(for: .milliseconds(500))

        precondition(health.saveCalls == 1, "The finish reaches the Health write")
        precondition(WatchBridge.shared.notedPhoneWorkouts.isEmpty,
                     "A session deleted during the write must not be noted as holding a phone workout")
        precondition(health.backfillCalls == 0,
                     "A session deleted during the write must not have its vitals read")
    }
}
