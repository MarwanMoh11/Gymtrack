import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What the Home Screen and Lock Screen widgets are told, built and compared
/// with no widget in sight. The code under test is the app's own:
/// `WidgetPublisher.snapshot`, `GymTrackSnapshot` and `RestProgress`. Nothing
/// here draws a widget or reloads a timeline; those stay checks for a device.
///
/// Every "today" is one a test picked, through the `calendar:` and `now:`
/// `WidgetPublisher.snapshot` takes, so a run at 00:10 or on a daylight-saving
/// day reads the same as one at noon. How a command from the wrist reaches the
/// widgets with no logger running is in `WatchCommandCenterHeadlessTests`.
@MainActor @Suite(.serialized)
struct WidgetSnapshotTests {

    // MARK: - Fixtures

    private static let calendar = TestClock.calendar
    /// A Wednesday noon, so each session below is plainly this morning's or
    /// last night's.
    private static let now = TestClock.reference
    private static let midnight = calendar.startOfDay(for: now)

    private static func at(hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }

    /// A finished session of one timed set, of `day` or freestyle.
    private static func session(_ day: PlanDay?, from start: Date, lasting seconds: TimeInterval = 3600,
                                in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: day?.name ?? "Freestyle", planDayID: day?.id, startedAt: start)
        session.endedAt = start.addingTimeInterval(seconds)
        context.insert(session)
        let set = SetLog(catalogID: "test-plank", exerciseName: "Plank",
                         exerciseOrder: 0, setIndex: 0, seconds: 60, tracking: .duration)
        set.isCompleted = true
        set.completedAt = session.endedAt
        context.insert(set)
        set.session = session
        return session
    }

    /// An active plan with Legs pinned to today's weekday and Push to tomorrow's.
    private static func plan(in context: ModelContext) -> (plan: Plan, legs: PlanDay, push: PlanDay) {
        let plan = Plan(name: "Test plan", isActive: true)
        context.insert(plan)
        let weekday = calendar.component(.weekday, from: now)
        func day(_ name: String, weekday: Int) -> PlanDay {
            let day = PlanDay(name: name, order: plan.days.count, weekday: weekday)
            context.insert(day)
            day.plan = plan
            let item = PlanItem(catalogID: "test-plank", name: "Plank", order: 0)
            context.insert(item)
            item.day = day
            return day
        }
        return (plan, day("Legs", weekday: weekday), day("Push", weekday: weekday % 7 + 1))
    }

    /// A routine named for its one day, pinned to today's weekday, so the
    /// snapshot's `todayTitle` says which routine it described.
    private static func routine(day name: String, createdAt: Date, isActive: Bool,
                                in context: ModelContext) -> Plan {
        let plan = Plan(name: "\(name) routine", isActive: isActive)
        plan.createdAt = createdAt
        context.insert(plan)
        let day = PlanDay(name: name, order: 0, weekday: calendar.component(.weekday, from: now))
        context.insert(day)
        day.plan = plan
        let item = PlanItem(catalogID: "test-plank", name: "Plank", order: 0)
        context.insert(item)
        item.day = day
        return plan
    }

    private static func snapshot(_ plan: Plan, _ sessions: [WorkoutSession]) -> GymTrackSnapshot {
        WidgetPublisher.snapshot(plans: [plan], sessions: sessions, running: nil, calendar: calendar, now: now)
    }

    /// A planned session with one slot per entry of `sets`, the shape a
    /// routine builds. Its plan is in `context` too.
    static func plannedSession(in context: ModelContext, sets: [Int]) throws -> WorkoutSession {
        let plan = Plan(name: "Widget plan")
        let day = PlanDay(name: "Push", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        for (order, count) in sets.enumerated() {
            let item = PlanItem(catalogID: "test-widget-\(order)", name: "Widget lift \(order)", order: order,
                                targetSets: count, targetRepsLow: 8, targetRepsHigh: 12, targetWeightKg: 40)
            item.day = day
            context.insert(item)
        }
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [])
        try context.save()
        return session
    }

    // MARK: - The done card

    /// STATS-09. The done card used to ask "did anything finish today", which a
    /// freestyle arm pump or the tail of last night's session also answered,
    /// and put a victory card over a Legs day the phone was still offering.
    /// Last night includes the small hours: before 04:00 is still the night
    /// before.
    @Test func theDoneCardShowsOnlyAWorkoutOfThePlanThatStartedToday() throws {
        let context = try TestStore.context()
        let (plan, legs, push) = Self.plan(in: context)

        #expect(Self.snapshot(plan, []).finishedToday == nil)

        let freestyle = Self.session(nil, from: Self.at(hours: 8.1), in: context)
        #expect(Self.snapshot(plan, [freestyle]).finishedToday == nil)

        let lastNight = Self.session(legs, from: Self.at(hours: -0.8), lasting: 90 * 60, in: context)
        #expect(Self.snapshot(plan, [lastNight]).finishedToday == nil)
        let smallHours = Self.session(legs, from: Self.at(hours: 0.5), in: context)
        #expect(Self.snapshot(plan, [smallHours]).finishedToday == nil)

        // A plan day swapped in for Legs is today's workout,
        let swapped = Self.session(push, from: Self.at(hours: 8.2), in: context)
        #expect(Self.snapshot(plan, [swapped]).finishedToday?.title == "Push")

        // and the scheduled day wins when it was trained.
        let trained = Self.session(legs, from: Self.at(hours: 8.3), in: context)
        #expect(Self.snapshot(plan, [freestyle, swapped, trained]).finishedToday?.title == "Legs")
    }

    @Test func theDoneCardKeepsWhatTheWidgetsDrawAndTheRestOfTheSnapshotStands() throws {
        let context = try TestStore.context()
        let (plan, legs, _) = Self.plan(in: context)
        let trained = Self.session(legs, from: Self.at(hours: 8.3), lasting: 45 * 60, in: context)

        let snapshot = Self.snapshot(plan, [trained])

        let finished = try #require(snapshot.finishedToday)
        #expect(finished.sets == trained.effortSets.count)
        #expect(finished.volumeKg == trained.totalVolumeKg)
        #expect(finished.endedAt == trained.endedAt)
        #expect(snapshot.hasPlan)
        // Stamped with the day asked about.
        #expect(snapshot.day == Self.midnight)
        // No logger, so no running session.
        #expect(snapshot.session == nil)
    }

    /// Today picks its plan from a list sorted by `createdAt`: the active one,
    /// else the oldest. The widgets are handed plans in whatever order a caller
    /// fetched them, and have to reach the same plan from any of them.
    @Test(arguments: [false, true])
    func theWidgetsDescribeThePlanTodayShowsInAnyOrder(newerFirst: Bool) throws {
        let context = try TestStore.context()
        let older = Self.routine(day: "Legs", createdAt: Self.at(hours: -48), isActive: false, in: context)
        let newer = Self.routine(day: "Push", createdAt: Self.at(hours: -24), isActive: false, in: context)
        let plans = newerFirst ? [newer, older] : [older, newer]
        @MainActor func todayTitle() -> String? {
            WidgetPublisher.snapshot(plans: plans, sessions: [], running: nil,
                                     calendar: Self.calendar, now: Self.now).todayTitle
        }

        // With none active, the oldest.
        #expect(todayTitle() == "Legs")
        newer.isActive = true
        #expect(todayTitle() == "Push")
    }

    // MARK: - The small hours

    /// The issue's night, as the widgets and the wrist tell it. Legs is pinned
    /// to Wednesday and Push to Thursday. Legs is skipped in the day and
    /// trained at 00:30 on Thursday, which is still Wednesday night.
    @Test func aSessionStartedAfterMidnightIsTheNightBeforesOnTheWidgetsAndTheWatch() throws {
        let context = try TestStore.context()
        let (plan, legs, _) = Self.plan(in: context)
        let thursday = Self.at(hours: 24)
        @MainActor func snapshot(_ sessions: [WorkoutSession], at now: Date) -> GymTrackSnapshot {
            WidgetPublisher.snapshot(plans: [plan], sessions: sessions, running: nil, calendar: Self.calendar, now: now)
        }
        @MainActor func wrist(_ sessions: [WorkoutSession], at now: Date) -> WatchIdleSnapshot {
            WatchMirrorBuilder.idle(plans: [plan], sessions: sessions, calendar: Self.calendar, now: now)
        }
        let tuesday = Self.session(nil, from: Self.at(hours: -6), in: context)

        // At 00:30 on Thursday, Wednesday's Legs is still today's.
        let smallHours = Self.at(hours: 24.5)
        let before = snapshot([tuesday], at: smallHours)
        #expect(before.todayTitle == "Legs" && before.todayIsRotation == false)
        #expect(before.day == Self.midnight && before.finishedToday == nil && before.streak == 1)
        #expect(wrist([tuesday], at: smallHours).todayTitle == "Legs")
        #expect(wrist([tuesday], at: smallHours).day == Self.midnight)

        let lateNight = Self.session(legs, from: smallHours, in: context)
        let sessions = [tuesday, lateNight]
        let afterward = snapshot(sessions, at: Self.at(hours: 25.75))
        #expect(afterward.finishedToday?.title == "Legs", "The night's workout is done")
        #expect(afterward.lastTrainedDay == Self.midnight && afterward.streak == 2)

        // Thursday evening offers Thursday's Push, not a done card.
        let evening = Self.at(hours: 42)
        let next = snapshot(sessions, at: evening)
        #expect(next.todayTitle == "Push" && next.finishedToday == nil)
        #expect(next.day == thursday && next.lastTrainedDay == Self.midnight)
        #expect(next.streak == 2 && next.sessionsThisWeek == 2)
        #expect(wrist(sessions, at: evening).todayTitle == "Push")
        #expect(wrist(sessions, at: evening).streak == 2)

        // A widget left with Wednesday evening's snapshot rolls over at the
        // cutoff, not at midnight.
        let wednesdayEvening = snapshot([tuesday], at: Self.at(hours: 23))
        #expect(wednesdayEvening.asOf(smallHours, calendar: Self.calendar) == wednesdayEvening)
        let rolled = wednesdayEvening.asOf(Self.at(hours: 28.5), calendar: Self.calendar)
        #expect(rolled.todayTitle == "Push" && rolled.day == thursday)
    }

    // MARK: - A snapshot read on a later day

    /// STATS-01. Egypt springs forward at 00:00 on the last Friday of April,
    /// so 2026-04-24 begins at 01:00, and "a day before 01:00" is not the
    /// previous midnight.
    @Test func aStreakSurvivesTheDayCairosClocksSpringForwardAtMidnight() throws {
        let cairo = TestClock.calendar(in: "Africa/Cairo")
        func at(_ day: Int, _ hour: Int) -> Date {
            TestClock.at("2026-04-\(day)T\(hour):00:00", in: "Africa/Cairo")
        }
        let springDay = cairo.startOfDay(for: at(24, 12))
        // Without the change at midnight the checks below prove nothing.
        try #require(cairo.component(.hour, from: springDay) == 1)

        let thursday = cairo.startOfDay(for: at(23, 12))
        let trainedThursday = GymTrackSnapshot(day: thursday, lastTrainedDay: thursday, streak: 5)
        #expect(trainedThursday.asOf(at(24, 10), calendar: cairo).streak == 5)
        #expect(trainedThursday.asOf(at(24, 23), calendar: cairo).streak == 5)
        // Last trained two days ago, it lapses.
        #expect(trainedThursday.asOf(at(25, 10), calendar: cairo).streak == 0)

        // Trained on the short day, it survives the day after.
        let trainedFriday = GymTrackSnapshot(day: springDay, lastTrainedDay: springDay, streak: 6)
        #expect(trainedFriday.asOf(at(25, 10), calendar: cairo).streak == 6)
    }

    /// STATS-03. A weekday with nothing pinned carries the rotation's next day,
    /// which the widgets call "Next up", not "Today".
    @Test func aWeekdayCarryingTheRotationReadsAsNextUpOnceTheWidgetRollsForwardToIt() {
        let calendar = TestClock.calendar
        func day(_ number: Int) -> Date { TestClock.at("2026-09-\(number)T09:00:00") }
        // Monday the 21st. Tuesday is pinned; Wednesday carries the rotation.
        let schedule = [
            GymTrackSnapshot.ScheduledDay(weekday: 3, title: "Pull", exerciseCount: 5, setCount: 15,
                                          muscles: [], isRotation: false),
            GymTrackSnapshot.ScheduledDay(weekday: 4, title: "Legs", exerciseCount: 5, setCount: 15,
                                          muscles: [], isRotation: true),
        ]
        let monday = GymTrackSnapshot(day: calendar.startOfDay(for: day(21)), schedule: schedule,
                                      hasPlan: true, todayTitle: "Push", todayIsRotation: false)

        #expect(monday.asOf(day(22), calendar: calendar).todayIsRotation == false)
        #expect(monday.asOf(day(23), calendar: calendar).todayIsRotation == true)
        // A rest day has no session to call anything.
        #expect(monday.asOf(day(24), calendar: calendar).todayIsRotation == nil)
    }

    // MARK: - Older and newer builds on either end

    /// `WatchIdleSnapshot` exactly as builds before `todayIsRotation` declared it.
    private struct OldWatchIdleSnapshot: Codable {
        var day: Date?
        var todayTitle: String?
        var todayExerciseCount: Int
        var todaySetCount: Int
        var todayMuscles: [String]
        var streak: Int
        var sessionsThisWeek: Int
        var lastSessionTitle: String?
        var lastSessionDate: Date?
        var unit: WeightUnit
    }

    /// The other direction, a newer watch reading an older phone's mirror, is
    /// `WatchLinkWireTests.anOlderSnapshotMissingNewerOptionalFieldsStillDecodes`.
    @Test func anOlderWatchReadsAMirrorCarryingTheRotationFlagAndTheFlagSurvivesTheLink() throws {
        var fresh = WatchIdleSnapshot.empty
        fresh.day = Date(timeIntervalSince1970: 1_790_000_000)
        fresh.todayTitle = "Legs"
        fresh.todayExerciseCount = 5
        fresh.todayIsRotation = true
        let data = try JSONEncoder.watchLink.encode(fresh)

        let onOldWatch = try JSONDecoder.watchLink.decode(OldWatchIdleSnapshot.self, from: data)
        #expect(onOldWatch.todayTitle == "Legs" && onOldWatch.todayExerciseCount == 5)
        #expect(try JSONDecoder.watchLink.decode(WatchIdleSnapshot.self, from: data) == fresh)
    }

    /// The shared store's coders are private to it; these match them.
    private static func wireEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func wireDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    @Test func aSnapshotWithNoRotationFlagCarriesNoKeyAndOlderAndNewerBuildsReadEachOther() throws {
        let unflagged = GymTrackSnapshot(
            day: Date(timeIntervalSince1970: 1_790_000_000),
            schedule: [GymTrackSnapshot.ScheduledDay(weekday: 2, title: "Push", exerciseCount: 4,
                                                     setCount: 12, muscles: [])],
            hasPlan: true, todayTitle: "Push")
        let oldData = try Self.wireEncoder().encode(unflagged)
        let oldJSON = String(decoding: oldData, as: UTF8.self)
        // No flag, no key, exactly as an older build wrote it.
        #expect(!oldJSON.contains("isRotation") && !oldJSON.contains("todayIsRotation"))
        let read = try Self.wireDecoder().decode(GymTrackSnapshot.self, from: oldData)
        #expect(read.todayTitle == "Push" && read.todayIsRotation == nil && read.schedule?.first?.isRotation == nil)

        var flagged = unflagged
        flagged.todayIsRotation = true
        flagged.schedule?[0].isRotation = true
        let back = try Self.wireDecoder().decode(GymTrackSnapshot.self, from: Self.wireEncoder().encode(flagged))
        #expect(back.todayIsRotation == true && back.schedule?.first?.isRotation == true)
    }

    // MARK: - The rest ring

    /// HK-10. The first version measured from the rest's end rather than its
    /// start, so the Dynamic Island's ring sat full whatever the clock said.
    /// Each case is a moment into a 90-second rest and how full the ring is
    /// then; a clock a little behind the phone's reads a moment before it.
    @Test(arguments: [(0.0, 0.0), (45, 0.5), (67.5, 0.75), (90, 1), (690, 1), (-5, 0)])
    func theRestRingFillsFromEmptyToFullAsTheRestIsUsedUp(_ secondsIn: TimeInterval, fraction: Double) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RestProgress.fraction(startedAt: start, endsAt: start.addingTimeInterval(90),
                                      now: start.addingTimeInterval(secondsIn)) == fraction)
    }

    @Test func aRestWithNoLengthIsAlreadyDone() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RestProgress.fraction(startedAt: start, endsAt: start, now: start) == 1)
    }

    // MARK: - What a reload costs

    private nonisolated static let stamp = Date(timeIntervalSince1970: 1_800_000_000)

    private static func midWorkout(completed: Int = 3, streak: Int = 4, restEndsAt: Date? = nil,
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

    /// HK-09. WidgetKit gives an app a small daily budget of reloads, and a
    /// session logged from the wrist spends it a set at a time.
    @Test func aSnapshotReloadsOnlyTheWidgetsWithSomethingNewToDraw() {
        let base = Self.midWorkout()
        let both = GymTrackWidgetKind.all
        let today: Set<String> = [GymTrackWidgetKind.today]

        // Differing only in when it was written, it reloads nothing.
        #expect(Self.midWorkout(updatedAt: Self.stamp.addingTimeInterval(60))
            .widgetKindsToReload(replacing: base).isEmpty)
        // With nothing known to be on screen, both.
        #expect(base.widgetKindsToReload(replacing: nil) == both)
        // A set logged, or a rest starting, is drawn by the Today widget alone.
        #expect(Self.midWorkout(completed: 4).widgetKindsToReload(replacing: base) == today)
        #expect(Self.midWorkout(restEndsAt: Self.stamp.addingTimeInterval(90))
            .widgetKindsToReload(replacing: base) == today)
        // A session ending, or starting, changes the Streak widget's "Session running" too.
        #expect(Self.midWorkout(running: false).widgetKindsToReload(replacing: base) == both)
        #expect(base.widgetKindsToReload(replacing: Self.midWorkout(running: false)) == both)
        // A streak that moved is drawn by both.
        #expect(Self.midWorkout(streak: 5).widgetKindsToReload(replacing: base) == both)
    }

    /// A process woken in the background has no memory of what it wrote, so it
    /// compares against what it reads back from the store.
    @Test func lessThanAMillisecondIsNoChangeEvenThroughTheStore() throws {
        let precise = Self.midWorkout(startedAt: Date(timeIntervalSince1970: 1_799_998_200.000_4))
        let coarse = Self.midWorkout(startedAt: Date(timeIntervalSince1970: 1_799_998_200.000_1))
        #expect(coarse.widgetKindsToReload(replacing: precise).isEmpty)

        let stored = try Self.wireDecoder().decode(GymTrackSnapshot.self, from: Self.wireEncoder().encode(precise))
        #expect(precise.widgetKindsToReload(replacing: stored).isEmpty)
    }

    // MARK: - A session nobody finished

    /// HK-08. Nothing wakes the app when the lifter walks out of the gym, so a
    /// widget has to stop showing the session from the clock alone.
    @Test func aSessionOpenPastTwelveHoursStopsShowingAsRunning() throws {
        let utc = TestClock.calendar
        let morning = utc.startOfDay(for: Self.stamp).addingTimeInterval(9 * 3600)
        let twelve = GymTrackSnapshot.Running.staleAfter

        // No day at all, as a snapshot from an older build reads, which skips
        // every day-based rule.
        let undated = Self.midWorkout(startedAt: morning)
        #expect(undated.asOf(morning.addingTimeInterval(twelve - 60), calendar: utc).session != nil)
        // Exactly twelve hours is not yet stale, as the app counts it.
        #expect(undated.asOf(morning.addingTimeInterval(twelve), calendar: utc).session != nil)
        #expect(undated.asOf(morning.addingTimeInterval(twelve + 60), calendar: utc).session == nil)

        // The same evening, on the day it began: stale by the clock while the
        // day rule has nothing to say, so it goes before midnight, not after.
        var dated = undated
        dated.day = utc.startOfDay(for: morning)
        let evening = morning.addingTimeInterval(14 * 3600)
        try #require(utc.isDate(evening, inSameDayAs: morning))
        #expect(dated.asOf(evening, calendar: utc).session == nil)
        // Retiring the session leaves the rest of the snapshot alone.
        #expect(dated.asOf(evening, calendar: utc).streak == dated.streak)

        let running = try #require(undated.session)
        // The moment the timeline stops at reads stale; the turn itself does
        // not, which is why that entry sits a second after it.
        #expect(running.isStale(at: running.staleAt))
        #expect(!running.isStale(at: running.startedAt.addingTimeInterval(twelve)))
    }

    /// `WorkoutSession.staleAfter` reads the snapshot's number; this fails if
    /// somebody hard-codes a second one again.
    @Test func theWidgetsAndTheAppAgreeHowLongASessionMayStayOpen() {
        #expect(GymTrackSnapshot.Running.staleAfter == WorkoutSession.staleAfter)
    }

    // MARK: - Agreement with the logger

    /// `SessionPosition` describes a session to the widgets from the store
    /// alone, by the rules `ActiveWorkout` uses on screen. A card and a logger
    /// that disagree about which set is up send the lifter to the wrong bar.
    @Test func theCardAndTheLoggerAgreeWhichSetIsUp() throws {
        let context = try TestStore.context()
        let suite = "WidgetSnapshotTests.logger"
        let memory = LoggerMemoryStore(defaults: TestClock.freshDefaults(suite))
        let session = try Self.plannedSession(in: context, sets: [3, 2, 2])
        let workout = ActiveWorkout(session: session, context: context, history: [], memory: memory)
        defer {
            workout.restTimer.stop()
            // The logger told the watch link about its session when it was built.
            WatchBridge.shared.update(session: nil, ended: nil)
            UserDefaults().removePersistentDomain(forName: "GymTrackTests." + suite)
        }
        let ordered = session.sets.sorted(by: SetLog.precedesInSession)
        @MainActor func compare(_ moment: Comment) {
            let position = SessionPosition(session)
            #expect(position.currentGroup?.catalogID == workout.currentGroup?.catalogID, moment)
            #expect(position.nextSet?.id == workout.nextSet?.id, moment)
            #expect(position.nextSetNumber == workout.nextSetNumber, moment)
            #expect(position.currentSetTotal == workout.currentSetTotal, moment)
            #expect(position.nextTargetLabel == workout.nextTargetLabel, moment)
            #expect(position.upNextName == workout.upNextName, moment)
            #expect(position.completedCount == workout.completedCount, moment)
            #expect(position.totalCount == workout.totalCount, moment)
        }
        @MainActor func log(_ sets: some Sequence<SetLog>) {
            for set in sets {
                set.isCompleted = true
                set.completedAt = TestClock.reference
            }
        }

        compare("A fresh session")
        log(ordered.prefix(1))
        compare("After the first set")
        log(ordered.prefix(3))
        compare("After the first exercise")
        session.preferredExerciseID = "test-widget-2"
        compare("With the last exercise picked out of order")
        log(ordered)
        compare("With every set logged")
    }
}
