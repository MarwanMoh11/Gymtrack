import Foundation
import SwiftData

/// Run with scripts/test-widget-publishing.sh; no simulator is needed.
///
/// What reaches the Lock Screen and the Home Screen, and when. The Dynamic
/// Island's rest ring must run empty to full as a rest is used up (HK-10). A
/// change made while the phone is asleep must be described to both surfaces
/// (HK-08), and a session nobody finished must stop showing as running once
/// the app would have closed it. And a snapshot that says nothing new must not
/// spend one of WidgetKit's daily reloads (HK-09), nor must a change that
/// only one widget can draw reload the other.
///
/// Nothing here draws a widget; that stays a check for a device.
@main
struct WidgetPublishingTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    @MainActor static func main() throws {
        restProgressRunsFromEmptyToFull()
        reloadFollowsWhatChanged()
        staleSessionLeavesTheWidgets()
        staleRuleIsTheModelsRule()
        try headlessCommandsReachTheWidgets()
        try positionAgreesWithTheLogger()

        guard failures == 0 else {
            print("\(failures) widget publishing check(s) failed")
            exit(1)
        }
        print("Widget publishing tests passed")
    }

    // MARK: HK-10

    static func restProgressRunsFromEmptyToFull() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(90)

        check(RestProgress.fraction(startedAt: start, endsAt: end, now: start) == 0,
              "A rest that has just begun is 0 of the way through")
        check(RestProgress.fraction(startedAt: start, endsAt: end, now: start.addingTimeInterval(45)) == 0.5,
              "Half the rest gone reads 0.5, not the ring left full")
        check(RestProgress.fraction(startedAt: start, endsAt: end, now: start.addingTimeInterval(67.5)) == 0.75,
              "Three quarters gone reads 0.75")
        check(RestProgress.fraction(startedAt: start, endsAt: end, now: end) == 1,
              "A rest that has just run out is all the way through")
        check(RestProgress.fraction(startedAt: start, endsAt: end, now: end.addingTimeInterval(600)) == 1,
              "Time past the end stays at 1")
        check(RestProgress.fraction(startedAt: start, endsAt: end, now: start.addingTimeInterval(-5)) == 0,
              "A clock a little behind the phone's stays at 0")
        check(RestProgress.fraction(startedAt: start, endsAt: start, now: start) == 1,
              "A rest with no length is already done")
    }

    // MARK: HK-09

    static let stamp = Date(timeIntervalSince1970: 1_800_000_000)

    static func snapshot(completed: Int = 3, streak: Int = 4, restEndsAt: Date? = nil,
                         running: Bool = true, updatedAt: Date = stamp,
                         startedAt: Date = stamp.addingTimeInterval(-1800)) -> GymTrackSnapshot {
        GymTrackSnapshot(
            updatedAt: updatedAt,
            hasPlan: true,
            todayTitle: "Push Day",
            streak: streak,
            session: running
                ? .init(title: "Push Day", startedAt: startedAt, completedSets: completed,
                        totalSets: 20, exercise: "Bench Press", target: "60 kg × 8", restEndsAt: restEndsAt)
                : nil
        )
    }

    static func reloadFollowsWhatChanged() {
        let base = snapshot()
        let both = GymTrackWidgetKind.all
        let today: Set<String> = [GymTrackWidgetKind.today]

        check(snapshot(updatedAt: stamp.addingTimeInterval(60)).widgetKindsToReload(replacing: base).isEmpty,
              "A snapshot that differs only in when it was written reloads nothing")
        check(base.widgetKindsToReload(replacing: nil) == both,
              "With nothing known to be on screen, both widgets reload")
        check(snapshot(completed: 4).widgetKindsToReload(replacing: base) == today,
              "A set logged reloads the Today widget and leaves the Streak widget alone")
        check(snapshot(restEndsAt: stamp.addingTimeInterval(90)).widgetKindsToReload(replacing: base) == today,
              "A rest starting is drawn by the Today widget alone")
        check(snapshot(running: false).widgetKindsToReload(replacing: base) == both,
              "A session ending changes the Streak widget's \"Session running\" too")
        check(base.widgetKindsToReload(replacing: snapshot(running: false)) == both,
              "A session starting does as well")
        check(snapshot(streak: 5).widgetKindsToReload(replacing: base) == both,
              "A streak that moved is drawn by both")

        // A fraction of a millisecond is not a change. A process woken in the
        // background has no memory of what it wrote, so it compares against
        // what it reads back from the store.
        let precise = snapshot(startedAt: Date(timeIntervalSince1970: 1_799_998_200.000_4))
        let coarse = snapshot(startedAt: Date(timeIntervalSince1970: 1_799_998_200.000_1))
        check(coarse.widgetKindsToReload(replacing: precise).isEmpty,
              "Sub-millisecond noise in a date is not something a widget can draw")
        if let stored = try? roundTrip(precise) {
            check(precise.widgetKindsToReload(replacing: stored).isEmpty,
                  "A snapshot read back from the store must read as unchanged against itself")
        } else {
            check(false, "The snapshot could not be encoded")
        }
    }

    static func roundTrip(_ snapshot: GymTrackSnapshot) throws -> GymTrackSnapshot {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(GymTrackSnapshot.self, from: encoder.encode(snapshot))
    }

    // MARK: HK-08, the abandoned session

    static func staleSessionLeavesTheWidgets() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let morning = utc.startOfDay(for: stamp).addingTimeInterval(9 * 3600)
        let twelve = GymTrackSnapshot.Running.staleAfter

        // Stamped this morning with no day at all, which is how a snapshot from
        // an older build reads and skips every day-based rule.
        let undated = snapshot(startedAt: morning)
        check(undated.asOf(morning.addingTimeInterval(twelve - 60), calendar: utc).session != nil,
              "A session open under twelve hours is still running")
        check(undated.asOf(morning.addingTimeInterval(twelve), calendar: utc).session != nil,
              "Exactly twelve hours is not yet stale, as the app counts it")
        check(undated.asOf(morning.addingTimeInterval(twelve + 60), calendar: utc).session == nil,
              "A session open past twelve hours must stop showing as running")

        // The same evening, on the day it began: stale by the clock while the
        // day rule has nothing to say.
        var dated = snapshot(startedAt: morning)
        dated.day = utc.startOfDay(for: morning)
        let evening = morning.addingTimeInterval(14 * 3600)
        check(utc.isDate(evening, inSameDayAs: morning), "The check needs an evening on the same day")
        check(dated.asOf(evening, calendar: utc).session == nil,
              "A session left open all day stops showing before midnight, not only after it")
        check(dated.asOf(evening, calendar: utc).streak == dated.streak,
              "Retiring the session must not touch the rest of the snapshot")

        let running = undated.session!
        check(running.isStale(at: running.staleAt), "The moment the timeline stops at must read stale")
        check(!running.isStale(at: running.startedAt.addingTimeInterval(twelve)),
              "The turn itself is not stale, which is why the entry sits a second after it")
    }

    /// The widgets can't see `WorkoutSession`, so they repeat its number.
    static func staleRuleIsTheModelsRule() {
        check(GymTrackSnapshot.Running.staleAfter == WorkoutSession.staleAfter,
              "The widgets and the app must agree how long a session may stay open")
    }

    // MARK: HK-08, the headless path

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A planned session with a pair of exercises, the shape a routine builds.
    @MainActor static func plannedSession(in context: ModelContext, sets: [Int]) throws -> WorkoutSession {
        let plan = Plan(name: "Widget plan")
        let day = PlanDay(name: "Push", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        for (order, count) in sets.enumerated() {
            let row = PlanItem(catalogID: "widget-\(order)", name: "Widget lift \(order)", order: order,
                               targetSets: count, targetRepsLow: 8, targetRepsHigh: 12, targetWeightKg: 40)
            row.day = day
            context.insert(row)
        }
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [])
        try context.save()
        return session
    }

    /// A wrist logging and undoing sets, and a session started from it, while
    /// the phone has no logger: each is described once to the widgets and the
    /// Lock Screen, and a Discard, which restamps everything itself, is not
    /// described a second time.
    @MainActor static func headlessCommandsReachTheWidgets() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = try plannedSession(in: context, sets: [3, 2])
        let first = session.sets.sorted(by: SetLog.precedesInSession)[0]

        WatchCommandCenter.shared.configure(container: container)
        WidgetPublisher.headlessPublishes = []

        WatchCommandCenter.shared.handle(.logSet(id: first.id, weightKg: 42.5, reps: 8, seconds: 0, at: .now))
        check(WidgetPublisher.headlessPublishes == [session.id],
              "A set logged from the wrist while the app is asleep must be described to the widgets once")

        WatchCommandCenter.shared.handle(.undoSet(id: first.id))
        check(WidgetPublisher.headlessPublishes == [session.id, session.id],
              "So must the same set being taken back")

        WatchCommandCenter.shared.handle(.discardSession(id: session.id))
        check(WidgetPublisher.headlessPublishes.count == 2,
              "A Discard restamps the whole snapshot itself and is not announced a second time")

        WidgetPublisher.headlessPublishes = []
        WatchCommandCenter.shared.handle(.startFreestyle)
        let started = try ModelContext(container).fetch(FetchDescriptor<WorkoutSession>()).first(where: \.isActive)
        check(started != nil && WidgetPublisher.headlessPublishes == [started?.id],
              "A workout started from the wrist must reach the widgets as running")
    }

    // MARK: Agreement with the logger

    /// `SessionPosition` answers what `ActiveWorkout` answers, by the same
    /// rules; a card and a logger that disagree about which set is up would
    /// send the lifter to the wrong bar.
    @MainActor static func positionAgreesWithTheLogger() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let session = try plannedSession(in: context, sets: [3, 2, 2])
        let workout = ActiveWorkout(session: session, context: context, history: [])
        let ordered = session.sets.sorted(by: SetLog.precedesInSession)

        func compare(_ moment: String) {
            let position = SessionPosition(session)
            check(position.currentGroup?.catalogID == workout.currentGroup?.catalogID,
                  "\(moment): the exercise that is up")
            check(position.nextSet?.id == workout.nextSet?.id, "\(moment): the set that is up")
            check(position.nextSetNumber == workout.nextSetNumber, "\(moment): its number")
            check(position.currentSetTotal == workout.currentSetTotal, "\(moment): the exercise's set count")
            check(position.nextTargetLabel == workout.nextTargetLabel, "\(moment): its target")
            check(position.upNextName == workout.upNextName, "\(moment): what is queued behind it")
            check(position.completedCount == workout.completedCount, "\(moment): sets done")
            check(position.totalCount == workout.totalCount, "\(moment): sets in all")
        }

        compare("Fresh session")

        ordered[0].isCompleted = true
        ordered[0].completedAt = .now
        compare("After the first set")

        for set in ordered.prefix(3) {
            set.isCompleted = true
            set.completedAt = .now
        }
        compare("After the first exercise")

        session.preferredExerciseID = "widget-2"
        compare("With the last exercise picked out of order")

        for set in ordered {
            set.isCompleted = true
            set.completedAt = .now
        }
        compare("With every set logged")
    }
}
