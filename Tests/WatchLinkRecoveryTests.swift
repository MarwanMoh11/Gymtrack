import Foundation
import SwiftData

/// Run with scripts/test-watch-link-recovery.sh.
///
/// LINK-02: a fresh phone process must not tell the watch anything before it
/// has read the store. LINK-03: the headless path retires a session left open
/// past twelve hours instead of handing it back to a wrist that asked to start.
@main
struct WatchLinkRecoveryTests {
    @MainActor
    static func main() throws {
        checkNothingSentBeforeTheStoreIsRead()
        try checkHeadlessRetiresStaleSessions()
        print("Watch link recovery checks passed")
    }

    @MainActor
    static func checkNothingSentBeforeTheStoreIsRead() {
        var state = WatchMirrorState()
        precondition(state.nextMirror(healthEnabled: true) == nil,
                     "A fresh process has no session to report, not a report of none")

        var idle = WatchIdleSnapshot.empty
        idle.todayTitle = "Push"
        precondition(state.update(idle: idle))
        precondition(state.nextMirror(healthEnabled: true) == nil,
                     "An idle screen alone does not say whether a workout is running")

        precondition(state.update(session: nil, ended: nil),
                     "Being told nothing is running is the first thing worth sending")
        let first = state.nextMirror(sentAt: Date(timeIntervalSince1970: 1), healthEnabled: true)
        precondition(first?.session == nil && first?.idle.todayTitle == "Push" && first?.revision == 1)
        precondition(!state.update(session: nil, ended: nil), "An unchanged answer is not resent")

        let snapshot = WatchSessionSnapshot(
            sessionID: UUID(), title: "Push", planName: "", startedAt: .now, exercises: [],
            preferredExerciseID: nil, currentSetID: nil, restEndsAt: nil, restStartedAt: nil,
            restTotalSeconds: 0, restAutoStart: false, volumeKg: 0, unit: .kg, effortEnabled: true
        )
        var running = WatchMirrorState()
        precondition(running.update(session: snapshot, ended: nil))
        precondition(running.nextMirror(healthEnabled: true)?.session == snapshot)
    }

    @MainActor
    static func checkHeadlessRetiresStaleSessions() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        func insertSession(startedHoursAgo hours: Double, loggedAfterMinutes minutes: Double?) -> WorkoutSession {
            let session = WorkoutSession(title: "Yesterday", startedAt: Date.now.addingTimeInterval(-hours * 3600))
            context.insert(session)
            if let minutes {
                let logged = SetLog(catalogID: "squat", exerciseName: "Squat",
                                    exerciseOrder: 0, setIndex: 0, weightKg: 60, reps: 5)
                logged.isCompleted = true
                logged.completedAt = session.startedAt.addingTimeInterval(minutes * 60)
                logged.session = session
                context.insert(logged)
            }
            let untouched = SetLog(catalogID: "squat", exerciseName: "Squat",
                                   exerciseOrder: 0, setIndex: 1, weightKg: 60, reps: 5)
            untouched.session = session
            context.insert(untouched)
            return session
        }

        // A background launch: the store is read while the link comes up, and
        // that read applies the twelve-hour rule before anything is mirrored.
        let abandoned = insertSession(startedHoursAgo: 13, loggedAfterMinutes: nil)
        let abandonedID = abandoned.id
        try context.save()
        WatchCommandCenter.shared.configure(container: container)
        let afterLaunch = try ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())
        precondition(!afterLaunch.contains { $0.id == abandonedID },
                     "A stale session with nothing logged is deleted when the link comes up")

        // A resident phone: yesterday's session is open when the wrist asks to
        // start. The start gets a session of its own.
        let yesterday = insertSession(startedHoursAgo: 13, loggedAfterMinutes: 40)
        let yesterdayID = yesterday.id
        let lastSet = yesterday.startedAt.addingTimeInterval(40 * 60)
        try context.save()
        WatchCommandCenter.shared.handle(.startFreestyle)

        let stored = try ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())
        guard let closed = stored.first(where: { $0.id == yesterdayID }) else {
            fatalError("A stale session with logged sets is closed, not deleted")
        }
        precondition(closed.endedAt == lastSet, "The stale session ends at its last set")
        precondition(closed.sets.count == 1, "Its unlifted sets go with the close")
        let open = stored.filter(\.isActive)
        precondition(open.count == 1 && open[0].id != yesterdayID && open[0].wasWatchDriven,
                     "The wrist's Start opens a new session instead of re-sending yesterday's")
    }
}
