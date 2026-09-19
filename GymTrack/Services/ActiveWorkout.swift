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
            // Onto the machine's ladder: a target typed while the app was in
            // kilograms shouldn't open as 61.2 lb on a stack marked in fives.
            let startingWeight = item.loadScale.snap(
                kg: last.isEmpty ? item.targetWeightKg : suggestion.weightKg
            )

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

    /// The set logged most recently. Only that one row offers an effort
    /// rating — asking on every completed set at once would turn a column of
    /// finished work into a column of unanswered questions.
    private(set) var lastLoggedSetID: UUID?

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
        return "\(set.weightLabel) × \(reps)"
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
        // Warm-ups are never rated: an effort score on a ramp is noise the
        // progression would then have to learn to ignore.
        lastLoggedSetID = set.isWarmup ? nil : set.id
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
    ///
    /// The warm-up boundary is deliberately one-way: a ramp is lighter than the
    /// work on purpose, so logging 40 kg on the second warm-up must not quietly
    /// rewrite the 100 kg waiting underneath it.
    private func carryLoadForward(from set: SetLog) {
        guard !set.isWarmup else { return }
        for other in session.sets
        where other.catalogID == set.catalogID
            && !other.isCompleted
            && !other.isWarmup
            && other.setIndex > set.setIndex {
            other.weightKg = set.weightKg
            if other.tracking == .duration { other.seconds = set.seconds }
        }
    }

    func uncomplete(_ set: SetLog) {
        set.isCompleted = false
        set.completedAt = nil
        set.rpe = nil
        recentPRs.remove(set.id)
        if lastLoggedSetID == set.id { lastLoggedSetID = nil }
        // The rest belonged to the set being taken back, so it goes with it.
        // `complete` is what started it; this is the other half of that.
        restTimer.stop()
        save()
        Haptics.tick()
    }

    func isPR(_ set: SetLog) -> Bool { recentPRs.contains(set.id) }

    /// How hard that set was, 6–10. Passing the value it already holds clears
    /// it, so the same tap that answers the question takes the answer back.
    func rate(_ set: SetLog, rpe: Double?) {
        set.rpe = set.rpe == rpe ? nil : rpe
        save()
        Haptics.tick()
    }

    // MARK: - Structure edits

    func addSet(to group: SessionExerciseGroup) {
        // Modelled on the last working set, never on a warm-up — an extra set
        // added to an exercise that has only been ramped so far should still
        // open at the weight you intend to work with.
        guard let template = group.workingSets.last ?? group.sets.last else { return }
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

    /// Takes a working set off the end. It won't eat into the warm-ups — those
    /// are removed by demoting them, not by this button, which is the pair of
    /// `addSet` and should undo exactly what that did.
    func removeLastSet(from group: SessionExerciseGroup) {
        guard group.workingSets.count > 1, let last = group.workingSets.last else { return }
        context.delete(last)
        resequence(group.catalogID)
        save()
        Haptics.tick()
    }

    // MARK: Warm-ups

    /// The ramp, as a share of the working weight and the reps to do there.
    /// Light and brief on purpose: this is the part that gets you ready, not
    /// the part that makes you tired.
    private static let warmupRamp: [(fraction: Double, reps: Int)] = [
        (0.4, 8), (0.6, 5), (0.8, 3)
    ]

    /// Builds a ramp up to the first working set — every rung pulled onto the
    /// ladder the machine actually has, which is the whole reason the app can
    /// offer this at all. Rungs that collapse onto each other, or onto the
    /// working weight itself, are dropped rather than logged twice.
    func addWarmupRamp(to group: SessionExerciseGroup) {
        guard let reference = group.workingSets.first ?? group.sets.first else { return }
        var rungs: [(weightKg: Double, reps: Int, seconds: Int)] = []

        if reference.tracking == .duration {
            rungs = [(0, 0, max(5, reference.seconds / 2))]
        } else {
            let scale = reference.loadScale
            let working = reference.weightKg
            var previous = 0.0
            if working > 0 {
                for step in Self.warmupRamp {
                    let rung = scale.snap(kg: working * step.fraction)
                    guard rung > 0, rung < working, rung > previous else { continue }
                    rungs.append((rung, step.reps, reference.seconds))
                    previous = rung
                }
            }
            // Bodyweight work, or a load with no rung beneath it: the warm-up
            // is the movement itself, done easy.
            if rungs.isEmpty {
                rungs = [(working, max(1, min(reference.reps, 10)), reference.seconds)]
            }
        }

        for rung in rungs {
            insertWarmup(into: group, weightKg: rung.weightKg, reps: rung.reps, seconds: rung.seconds)
        }
        resequence(group.catalogID)
        save()
        Haptics.log()
    }

    /// One more warm-up, carrying whatever the last one used.
    func addWarmupSet(to group: SessionExerciseGroup) {
        let template = group.warmupSets.last ?? group.workingSets.first
        insertWarmup(into: group,
                     weightKg: template?.weightKg ?? 0,
                     reps: template?.reps ?? 8,
                     seconds: template?.seconds ?? 30)
        resequence(group.catalogID)
        save()
        Haptics.tick()
    }

    /// Reclassifies a set already on screen. The load is left exactly as it is —
    /// calling something a warm-up says what it counts as, not what it weighs.
    func setWarmup(_ set: SetLog, _ isWarmup: Bool) {
        guard set.isWarmup != isWarmup else { return }
        set.isWarmup = isWarmup
        // A set that was celebrated as a record and has just been demoted to a
        // warm-up isn't one any more.
        if isWarmup { recentPRs.remove(set.id) }
        resequence(set.catalogID)
        save()
        Haptics.tick()
    }

    private func insertWarmup(into group: SessionExerciseGroup,
                              weightKg: Double, reps: Int, seconds: Int) {
        let existing = session.sets.filter { $0.catalogID == group.catalogID && $0.isWarmup }
        let set = SetLog(
            catalogID: group.catalogID,
            exerciseName: group.name,
            exerciseOrder: group.order,
            setIndex: (existing.map(\.setIndex).max() ?? -1) + 1,
            weightKg: weightKg,
            reps: reps,
            seconds: seconds,
            isWarmup: true
        )
        set.session = session
        context.insert(set)
    }

    /// Renumbers one exercise so its warm-ups sit above its working sets.
    /// `setIndex` is what orders a card, and it's also what pairs a set with
    /// last session's numbers, so the two groups are kept contiguous rather
    /// than interleaved by whenever a row happened to be added.
    private func resequence(_ catalogID: String) {
        let sets = session.sets
            .filter { $0.catalogID == catalogID }
            .sorted {
                $0.isWarmup == $1.isWarmup
                    ? $0.setIndex < $1.setIndex
                    : $0.isWarmup && !$1.isWarmup
            }
        for (index, set) in sets.enumerated() { set.setIndex = index }
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
        WidgetPublisher.updateSession(nil)
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
        WidgetPublisher.updateSession(nil)
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
        WidgetPublisher.updateSession(self)
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
            elapsedLabel: session.duration.durationString,
            elapsedShort: session.duration.shortDurationString
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
