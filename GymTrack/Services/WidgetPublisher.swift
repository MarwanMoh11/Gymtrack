import Foundation
import WidgetKit

/// Keeps the Home Screen and Lock Screen widgets in step with the app.
///
/// The widgets run in their own process and can't reach SwiftData, so the app
/// restamps a small snapshot into the shared container whenever the numbers
/// behind it move — the same arrangement the watch already has, and for the
/// same reason: one owner of the data, everything else drawing a mirror.
@MainActor
enum WidgetPublisher {

    /// The last thing written, so a rewrite doesn't have to read the store back
    /// to know what a widget is drawing. Empty in a freshly woken process, which
    /// then asks the store instead; see `write`.
    private static var lastWritten: GymTrackSnapshot?

    /// The logger on screen, held weakly. While there is one it publishes every
    /// change itself, with the rest timer this side has no way to see, so the
    /// headless path stands down rather than overwrite the countdown with none.
    /// Weak so a logger that goes away without saying so can't leave this
    /// believing one is still there.
    private static weak var logger: ActiveWorkout?

    /// True while a logger owns the running session's publishing.
    static var isLoggerRunning: Bool {
        guard let session = logger?.session else { return false }
        return !session.isGoneFromStore && session.isActive
    }

    /// Rebuilds the whole snapshot: today's prescription, the streak, the week,
    /// and whatever session is running.
    static func publish(plans: [Plan], sessions: [WorkoutSession], running: ActiveWorkout?) {
        logger = running
        write(snapshot(plans: plans, sessions: sessions, running: running))
    }

    /// The plan the widgets describe: the active one, else the oldest. The rule
    /// lives in `Plan.displayed(among:)`, shared with Today, the root view and
    /// the headless watch path; this is the name the widget code and its tests
    /// have always asked for it by.
    static func displayedPlan(among plans: [Plan]) -> Plan? {
        Plan.displayed(among: plans)
    }

    /// What the widgets are told, built without touching the shared container
    /// or WidgetKit so a test can ask it questions. `now` and `calendar` are
    /// parameters for the same reason: "today" has to be a day the test picked.
    static func snapshot(plans: [Plan], sessions: [WorkoutSession], running: ActiveWorkout?,
                         calendar: Calendar = .current, now: Date = .now) -> GymTrackSnapshot {
        let finished = sessions.filter { !$0.isActive }
        let plan = displayedPlan(among: plans)
        let today = plan?.nextDay(on: now, after: finished, calendar: calendar)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? .distantPast
        let thisWeek = finished.filter { $0.startedAt >= weekStart && TrainingStats.isTrained($0) }
        let rotation = plan?.nextInRotation(after: finished)

        // The whole week, so a widget can say what tomorrow is without the app
        // having been opened tomorrow. A weekday with nothing pinned carries
        // the rotation's next day: the rotation only moves when a session is
        // finished, and finishing one republishes this, so it is still the
        // right answer on any later day the widget rolls forward to. Leaving
        // those weekdays out had a rotation-only routine read "Rest day" from
        // the first midnight until the app was next opened.
        let schedule: [GymTrackSnapshot.ScheduledDay] = (1...7).compactMap { weekday in
            let pinned = plan?.day(onWeekday: weekday)
            guard let day = pinned ?? rotation else { return nil }
            return GymTrackSnapshot.ScheduledDay(
                weekday: weekday,
                title: day.name,
                exerciseCount: day.items.count,
                setCount: day.totalSets,
                muscles: day.targetedMuscles.prefix(3).map(\.name),
                isRotation: pinned == nil
            )
        }
        // Asked of the plan the way the phone's Today card asks it, so a widget
        // never calls "Today" a day the app calls "Next up".
        let todayIsRotation = today != nil && plan?.day(for: now) == nil

        return GymTrackSnapshot(
            day: calendar.startOfDay(for: now),
            schedule: schedule,
            // Trained sessions only, because that is what the streak it stands
            // next to counts. The latest is found by date first, so only the
            // sessions newer than it have their sets read.
            lastTrainedDay: finished.sorted { $0.startedAt > $1.startedAt }
                .first(where: TrainingStats.isTrained)
                .map { calendar.startOfDay(for: $0.startedAt) },
            weekStart: weekStart,
            // Decided the way the phone's Today card decides it, so the
            // widget never shows a victory card over a scheduled day the app is
            // still offering. `finishedToday` answered "did anything finish
            // today", which a freestyle arm pump or the tail of last night's
            // session also satisfied.
            finishedToday: TrainingStats.completedToday(in: finished, plan: plan, calendar: calendar, now: now).map {
                GymTrackSnapshot.Finished(title: $0.title, sets: $0.effortSets.count,
                                          volumeKg: $0.totalVolumeKg, endedAt: $0.endedAt ?? $0.startedAt)
            },
            hasPlan: plan != nil,
            todayTitle: today?.name,
            todayExerciseCount: today?.items.count ?? 0,
            todaySetCount: today?.totalSets ?? 0,
            todayMuscles: today?.targetedMuscles.prefix(3).map(\.name) ?? [],
            streak: TrainingStats.streak(from: finished).current,
            sessionsThisWeek: thisWeek.count,
            weekVolumeKg: TrainingStats.totalVolume(thisWeek),
            unit: AppSettings.shared.weightUnit,
            session: state(of: running),
            todayIsRotation: todayIsRotation
        )
    }

    /// Rewrites only the running-session part, for the many small changes
    /// inside a workout. Rebuilding the streak and the week on every logged set
    /// would mean walking the whole history from the logger.
    static func updateSession(_ running: ActiveWorkout?) {
        logger = running
        stamp(session: state(of: running))
    }

    /// The same two things `ActiveWorkout` publishes after every change — the
    /// Home Screen snapshot and the Lock Screen card — for a change made with
    /// no logger to publish it: a watch message that woke the app in the
    /// background. Without this, sets logged from the wrist with the phone
    /// locked left the card on "Set 3 of 4" and the widget on "3/20 sets" until
    /// somebody opened the app.
    ///
    /// Only the running session is restamped, and nothing is said when there
    /// isn't one: a Finish or Discard restamps the whole snapshot and takes the
    /// card down itself. The rest is left blank because the phone runs no rest
    /// timer here; the wrist is running the one that matters.
    static func publishHeadless(running: WorkoutSession?) {
        guard !isLoggerRunning else { return }
        stamp(session: running.map(state(ofSession:)))
        guard let running else { return }
        WorkoutLiveActivity.shared.sync(
            sessionID: running.id,
            title: running.title,
            planName: running.planName,
            state: WorkoutLiveActivity.state(for: running)
        )
    }

    private static func stamp(session: GymTrackSnapshot.Running?) {
        guard var snapshot = lastWritten ?? SharedStore.readSnapshot() else { return }
        snapshot.session = session
        write(snapshot)
    }

    private static func state(of running: ActiveWorkout?) -> GymTrackSnapshot.Running? {
        guard let running, running.session.isActive else { return nil }
        return GymTrackSnapshot.Running(
            title: running.session.title,
            startedAt: running.session.startedAt,
            completedSets: running.completedCount,
            totalSets: running.totalCount,
            exercise: running.currentGroup?.name ?? "Freestyle",
            target: running.nextTargetLabel,
            restEndsAt: running.restTimer.endsAt
        )
    }

    /// Describes a session as the widgets do, from the store alone.
    private static func state(ofSession session: WorkoutSession) -> GymTrackSnapshot.Running {
        let position = SessionPosition(session)
        return GymTrackSnapshot.Running(
            title: session.title,
            startedAt: session.startedAt,
            completedSets: position.completedCount,
            totalSets: position.totalCount,
            exercise: position.currentGroup?.name ?? "Freestyle",
            target: position.nextTargetLabel,
            restEndsAt: nil
        )
    }

    /// Stores the snapshot and reloads exactly the widget kinds that now have
    /// something different to draw — see `widgetKindsToReload`. A save that
    /// changed nothing a widget draws writes nothing and reloads nothing:
    /// WidgetKit gives an app a budget of reloads per day, and a long session
    /// logs a lot of sets.
    ///
    /// Compared against what the store holds when this process hasn't written
    /// yet. A background wake is a fresh process every time, and comparing
    /// against nothing made each one look like a first write and reload
    /// everything.
    private static func write(_ snapshot: GymTrackSnapshot) {
        let kinds = snapshot.widgetKindsToReload(replacing: lastWritten ?? SharedStore.readSnapshot())
        guard !kinds.isEmpty else { return }
        var candidate = snapshot
        candidate.updatedAt = .now
        lastWritten = candidate
        SharedStore.write(candidate)
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
