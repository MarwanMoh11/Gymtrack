import Foundation
import SwiftData
import SwiftUI

/// Builds the sets a planned session starts with: every prescription in the
/// day, loaded with what the double-progression suggestion says to lift today.
///
/// Separate from `ActiveWorkout` because a session can also be started from the
/// watch while the app isn't running, and that path has no logger to drive.
enum SessionFactory {

    @MainActor
    @discardableResult
    static func build(day: PlanDay, plan: Plan?, context: ModelContext, history: [WorkoutSession]) -> WorkoutSession {
        let session = WorkoutSession(title: day.name, planDayID: day.id, planName: plan?.name ?? "")
        context.insert(session)

        for (exerciseIndex, item) in day.orderedItems.enumerated() {
            let last = TrainingStats.lastPerformance(of: item.catalogID, in: history)
            let suggestion = TrainingStats.suggestion(for: item, lastSets: last)
            let startingWeight = last.isEmpty ? item.targetWeightKg : suggestion.weightKg

            for setIndex in 0..<max(1, item.targetSets) {
                let previous = setIndex < last.count ? last[setIndex] : last.last
                let set = SetLog(
                    catalogID: item.catalogID,
                    exerciseName: item.name,
                    exerciseOrder: exerciseIndex,
                    setIndex: setIndex,
                    weightKg: startingWeight,
                    reps: previous?.reps ?? item.targetRepsLow,
                    seconds: item.targetSeconds,
                    targetRepsLow: item.targetRepsLow,
                    targetRepsHigh: item.targetRepsHigh
                )
                set.session = session
                context.insert(set)
            }
        }
        return session
    }
}

/// Drives an in-progress session. The session and its sets are SwiftData
/// objects written as you go, so force-quitting mid-workout loses nothing —
/// the app finds the unfinished session on next launch and offers to resume.
@Observable
@MainActor
final class ActiveWorkout {
    private(set) var session: WorkoutSession
    let restTimer = RestTimer()


    /// Set IDs that just earned a PR, so the UI can celebrate once.
    private(set) var recentPRs: Set<UUID> = []

    private let context: ModelContext
    private var history: [WorkoutSession]

    /// The plan prescriptions behind this session, keyed by exercise. Resolved
    /// once — the logging view asks for these on every card render.
    private var prescriptions: [String: PlanItem] = [:]

    /// Last session's sets per exercise, likewise resolved once.
    private var lastPerformances: [String: [SetLog]] = [:]

    init(session: WorkoutSession, context: ModelContext, history: [WorkoutSession]) {
        self.session = session
        self.context = context
        self.history = history.filter { $0.id != session.id }

        if let dayID = session.planDayID,
           let day = (try? context.fetch(FetchDescriptor<PlanDay>()))?.first(where: { $0.id == dayID }) {
            prescriptions = Dictionary(day.items.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        for catalogID in Set(session.sets.map(\.catalogID)) {
            lastPerformances[catalogID] = TrainingStats.lastPerformance(
                of: catalogID, in: self.history, excluding: session.id
            )
        }

        // A rest starting, being extended or running out changes what the Lock
        // Screen should say, and none of those go through `save()`.
        restTimer.onChange = { [weak self] in
            Task { @MainActor in
                self?.pushLiveActivity()
                self?.pushToWatch()
            }
        }
        pushLiveActivity()
        pushToWatch()
        launchWatchAppIfWanted()
    }

    // MARK: - Creating a session

    /// Starts a session from a plan day, pre-building every prescribed set with
    /// the load carried over from last time.
    static func start(day: PlanDay, plan: Plan?, context: ModelContext, history: [WorkoutSession]) -> ActiveWorkout {
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: history)
        try? context.save()
        return ActiveWorkout(session: session, context: context, history: history)
    }

    /// Starts an empty session the user fills in as they go.
    static func startFreestyle(context: ModelContext, history: [WorkoutSession]) -> ActiveWorkout {
        let session = WorkoutSession(title: "Freestyle Session")
        context.insert(session)
        try? context.save()
        return ActiveWorkout(session: session, context: context, history: history)
    }

    // MARK: - Derived state

    var groups: [SessionExerciseGroup] { session.exerciseGroups }

    var completedCount: Int { session.sets.filter(\.isCompleted).count }
    var totalCount: Int { session.sets.count }

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var volumeKg: Double { session.totalVolumeKg }

    /// The exercise holding the next unlogged set — what the session is "on".
    /// Normally the first one that isn't finished, unless the lifter has picked
    /// a different one to work on.
    var currentGroup: SessionExerciseGroup? {
        if let preferred = session.preferredExerciseID,
           let group = groups.first(where: { $0.catalogID == preferred && !$0.isComplete }) {
            return group
        }
        return groups.first { !$0.isComplete } ?? groups.last
    }

    /// Moves the session onto a different exercise — a superset, or a machine
    /// that was taken when its turn came round.
    func focus(on catalogID: String) {
        session.preferredExerciseID = groups.contains { $0.catalogID == catalogID } ? catalogID : nil
        save()
    }

    /// The set the logger has expanded, i.e. the one about to be performed.
    var nextSet: SetLog? {
        currentGroup?.sets.first { !$0.isCompleted }
    }

    /// 1-based position of `nextSet` within its exercise.
    var nextSetNumber: Int {
        guard let group = currentGroup, let next = nextSet,
              let index = group.sets.firstIndex(where: { $0.id == next.id })
        else { return currentGroup?.sets.count ?? 0 }
        return index + 1
    }

    /// "60 kg × 8–12" — the prescription for the set that's up.
    var nextTargetLabel: String {
        guard let set = nextSet else { return "" }
        if set.tracking == .duration { return "\(set.seconds)s" }
        let reps = set.targetRepsHigh > 0
            ? (set.targetRepsLow == set.targetRepsHigh
               ? "\(set.targetRepsLow)"
               : "\(set.targetRepsLow)–\(set.targetRepsHigh)")
            : "\(set.reps)"
        if set.weightKg == 0 { return "\(reps) reps" }
        return "\(AppSettings.shared.weight(set.weightKg)) × \(reps)"
    }

    /// The exercise queued behind the current one.
    var upNextName: String {
        guard let current = currentGroup else { return "" }
        return groups.first { $0.order > current.order && !$0.isComplete }?.name ?? ""
    }

    /// What the same exercise looked like last time, for the "last: …" hints.
    func lastPerformance(for catalogID: String) -> [SetLog] {
        lastPerformances[catalogID] ?? []
    }

    func planItem(for catalogID: String) -> PlanItem? { prescriptions[catalogID] }

    // MARK: - Logging

    /// Marks a set done, checks for a PR, and kicks off the rest timer.
    func complete(_ set: SetLog, restSeconds: Int?) {
        set.isCompleted = true
        set.completedAt = .now
        carryLoadForward(from: set)
        save()

        if TrainingStats.isPersonalRecord(set, in: history + [session]) {
            recentPRs.insert(set.id)
            Haptics.celebrate()
        } else {
            Haptics.log()
        }

        if AppSettings.shared.restTimerAutoStart {
            let seconds = restSeconds ?? AppSettings.shared.defaultRestSeconds
            restTimer.start(seconds: seconds)
        }
    }

    /// Mirrors the load just used onto the remaining sets of the same exercise.
    /// Without this you re-dial the weight for every set of every exercise.
    private func carryLoadForward(from set: SetLog) {
        for other in session.sets
        where other.catalogID == set.catalogID
            && !other.isCompleted
            && other.setIndex > set.setIndex {
            other.weightKg = set.weightKg
            if other.tracking == .duration { other.seconds = set.seconds }
        }
    }

    func uncomplete(_ set: SetLog) {
        set.isCompleted = false
        set.completedAt = nil
        recentPRs.remove(set.id)
        save()
        Haptics.tick()
    }

    func isPR(_ set: SetLog) -> Bool { recentPRs.contains(set.id) }

    // MARK: - Structure edits

    func addSet(to group: SessionExerciseGroup) {
        guard let template = group.sets.last else { return }
        let set = SetLog(
            catalogID: group.catalogID,
            exerciseName: group.name,
            exerciseOrder: group.order,
            setIndex: (group.sets.map(\.setIndex).max() ?? -1) + 1,
            weightKg: template.weightKg,
            reps: template.reps,
            seconds: template.seconds,
            targetRepsLow: template.targetRepsLow,
            targetRepsHigh: template.targetRepsHigh
        )
        set.session = session
        context.insert(set)
        save()
        Haptics.tick()
    }

    func removeLastSet(from group: SessionExerciseGroup) {
        guard group.sets.count > 1, let last = group.sets.last else { return }
        context.delete(last)
        save()
        Haptics.tick()
    }

    func addExercise(_ exercise: CatalogExercise, sets: Int = 3) {
        let order = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        if lastPerformances[exercise.id] == nil {
            lastPerformances[exercise.id] = TrainingStats.lastPerformance(
                of: exercise.id, in: history, excluding: session.id
            )
        }
        let last = lastPerformance(for: exercise.id)
        for index in 0..<sets {
            let previous = index < last.count ? last[index] : last.last
            let set = SetLog(
                catalogID: exercise.id,
                exerciseName: exercise.name,
                exerciseOrder: order,
                setIndex: index,
                weightKg: previous?.weightKg ?? 0,
                reps: previous?.reps ?? 10,
                seconds: previous?.seconds ?? 45,
                targetRepsLow: 8,
                targetRepsHigh: 12
            )
            set.session = session
            context.insert(set)
        }
        save()
        Haptics.log()
    }

    func removeExercise(_ group: SessionExerciseGroup) {
        for set in group.sets { context.delete(set) }
        save()
    }

    // MARK: - Ending

    /// Drops any sets left unlogged and stamps the session finished.
    func finish() {
        for set in session.sets where !set.isCompleted {
            context.delete(set)
        }
        session.endedAt = .now
        adoptWatchMetrics()
        restTimer.onChange = nil
        restTimer.stop()
        writeThrough()
        WorkoutLiveActivity.shared.end(with: activityState)
        WatchBridge.shared.update(session: nil)
        WatchBridge.shared.clearMetrics()
        recordToHealth()
        Haptics.success()
    }

    func discard() {
        restTimer.onChange = nil
        restTimer.stop()
        context.delete(session)
        writeThrough()
        WorkoutLiveActivity.shared.end(with: nil)
        WatchBridge.shared.update(session: nil)
        WatchBridge.shared.clearMetrics()
    }

    // MARK: - Health

    /// Takes whatever the watch measured while the session ran. The watch is
    /// the only thing here that can read a heart rate, so its numbers win.
    private func adoptWatchMetrics() {
        guard let metrics = WatchBridge.shared.liveMetrics else { return }
        session.wasWatchDriven = true
        if let average = metrics.averageHeartRate { session.averageHeartRate = average }
        if let max = metrics.maxHeartRate { session.maxHeartRate = max }
        if let energy = metrics.activeEnergyKcal, energy > 0 { session.activeEnergyKcal = energy }
        // The watch saves its own workout — with the full beat-by-beat record —
        // so the phone must not write a second copy of the same session.
        if let workoutID = metrics.healthWorkoutID { session.healthWorkoutID = workoutID }
    }

    /// Writes the session to Health and picks up the heart rate and energy an
    /// Apple Watch recorded during it, whether or not our watch app was running.
    /// Deliberately detached: a slow or refused Health call must never hold up
    /// the summary screen.
    private func recordToHealth() {
        let session = session
        let context = context
        let watchIsRecording = session.wasWatchDriven || WatchBridge.shared.liveMetrics != nil
        Task { @MainActor in
            // When the watch drove the session it saves the workout itself —
            // with the beat-by-beat heart rate the phone can't reproduce — and
            // tells us the ID a moment later. Give it that moment rather than
            // racing it to a duplicate workout in Health.
            if watchIsRecording {
                for _ in 0..<12 where session.healthWorkoutID == nil {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            await HealthKitService.shared.saveWorkout(for: session)
            await HealthKitService.shared.backfillVitals(for: session)
            try? context.save()
        }
    }

    private func save() {
        writeThrough()
        pushLiveActivity()
        pushToWatch()
    }

    private func writeThrough() {
        do { try context.save() } catch {
            assertionFailure("Failed to save workout: \(error)")
        }
    }

    // MARK: - Apple Watch

    /// The session as the watch draws it. Built from the same objects the
    /// logger shows, so the wrist and the phone can't disagree.
    var watchSnapshot: WatchSessionSnapshot {
        WatchSnapshotFactory.snapshot(
            for: session,
            currentSetID: nextSet?.id,
            rest: (restTimer.endsAt, restTimer.startedAt, restTimer.totalSeconds),
            restSeconds: { [self] catalogID in
                planItem(for: catalogID)?.resolvedRestSeconds ?? AppSettings.shared.defaultRestSeconds
            },
            lastTimeLabel: { [self] catalogID in lastTimeLabel(for: catalogID) }
        )
    }

    private func lastTimeLabel(for catalogID: String) -> String? {
        WatchSnapshotFactory.label(for: lastPerformance(for: catalogID))
    }

    func pushToWatch() {
        WatchBridge.shared.update(session: session.isActive ? watchSnapshot : nil)
    }

    /// Wakes the watch app when a session starts on the phone, so heart rate is
    /// being recorded from the first set rather than from whenever the user
    /// remembers to raise their wrist.
    private func launchWatchAppIfWanted() {
        guard AppSettings.shared.watchAutoLaunch, session.isActive else { return }
        // Only for a session that has just started. Resuming one the app picked
        // back up at launch shouldn't pull the watch app onto the wrist again.
        guard session.startedAt.timeIntervalSinceNow > -120 else { return }
        HealthKitService.shared.startWatchApp()
    }

    // MARK: Commands from the wrist

    /// Applies something the user did on the watch. Everything routes through
    /// the same methods the phone's own UI calls, so a set logged on the wrist
    /// gets the identical PR check, load carry-forward and rest timer.
    ///
    /// Returns false for the commands that belong to whoever owns session
    /// lifecycle — starting, finishing and discarding — so `RootView` can take
    /// them without this object having to know about navigation.
    @discardableResult
    func apply(_ command: WatchCommand) -> Bool {
        switch command {
        case .logSet(let id, let weightKg, let reps, let seconds):
            guard let set = session.sets.first(where: { $0.id == id }) else { return true }
            set.weightKg = weightKg
            set.reps = reps
            if set.tracking == .duration { set.seconds = seconds }
            complete(set, restSeconds: planItem(for: set.catalogID)?.resolvedRestSeconds)
            return true

        case .undoSet(let id):
            guard let set = session.sets.first(where: { $0.id == id }) else { return true }
            uncomplete(set)
            return true

        case .focusExercise(let catalogID):
            focus(on: catalogID)
            return true

        case .addSet(let catalogID):
            if let group = groups.first(where: { $0.catalogID == catalogID }) {
                addSet(to: group)
            }
            return true

        case .startRest(let seconds):
            restTimer.start(seconds: seconds)
            return true

        case .stopRest:
            restTimer.stop()
            return true

        case .extendRest(let seconds):
            restTimer.add(seconds: seconds)
            return true

        case .metrics:
            // Already folded into `WatchBridge.liveMetrics`; the logger reads it
            // from there. Nothing to write until the session ends.
            return true

        case .requestMirror:
            WatchBridge.shared.resend()
            return true

        case .startToday, .startFreestyle, .finish, .discard:
            return false
        }
    }

    // MARK: - Live Activity

    /// The whole of what the Lock Screen and Dynamic Island draw. Unit-bearing
    /// values are formatted here because the widget can't read the user's
    /// kg/lb preference.
    var activityState: WorkoutActivity.ContentState {
        let unit = AppSettings.shared.weightUnit
        return WorkoutActivity.ContentState(
            startedAt: session.startedAt,
            completedSets: completedCount,
            totalSets: totalCount,
            currentExercise: currentGroup?.name ?? "Freestyle",
            currentSetNumber: nextSetNumber,
            currentSetTotal: currentGroup?.sets.count ?? 0,
            currentTarget: nextTargetLabel,
            upNext: upNextName,
            restEndsAt: restTimer.endsAt,
            restStartedAt: restTimer.startedAt,
            volumeLabel: "\(unit.fromKg(volumeKg).compactVolume) \(unit.short)",
            elapsedLabel: session.duration.durationString
        )
    }

    /// Called after every change, and again whenever the app comes back to the
    /// foreground — `WorkoutLiveActivity` treats it as "make the Lock Screen
    /// match this", which also covers a card that failed to start at launch.
    func pushLiveActivity() {
        guard session.isActive else { return }
        WorkoutLiveActivity.shared.sync(
            sessionID: session.id,
            title: session.title,
            planName: session.planName,
            state: activityState
        )
    }
}
