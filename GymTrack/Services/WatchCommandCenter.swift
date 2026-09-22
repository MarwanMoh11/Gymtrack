import Foundation
import SwiftData

/// Turns what the watch sends into changes on the phone.
///
/// There are two ways in. While the app is on screen, `RootView` owns the
/// running session and handles commands itself — that path has the rest timer,
/// the Live Activity and the logger all in step.
///
/// The other way is this object's own. iOS wakes a terminated app in the
/// background to deliver a watch message, and at that point there is no view
/// hierarchy and no `ActiveWorkout` — only the store. Without the headless path
/// below, a set logged on the wrist with the phone in a locker would be handed
/// to nobody and lost. So the same commands are applied straight to SwiftData,
/// and the watch is sent a fresh mirror so it can see they landed.
@MainActor
final class WatchCommandCenter {

    static let shared = WatchCommandCenter()

    /// Set by `RootView` while the app is running. Returns true when the UI
    /// took the command, in which case nothing here touches the store — and
    /// false for anything the UI isn't holding, which falls through below.
    var uiHandler: ((WatchCommand) -> Bool)?

    private var container: ModelContainer?
    private lazy var context: ModelContext? = container.map { ModelContext($0) }

    private init() {}

    /// Called once at launch, before the first watch message can arrive.
    func configure(container: ModelContainer) {
        self.container = container
        WatchBridge.shared.commandHandler = { [weak self] command in
            self?.handle(command)
        }
        WatchBridge.shared.activate()
    }

    func handle(_ command: WatchCommand) {
        if uiHandler?(command) == true { return }
        applyHeadless(command)
    }

    // MARK: - Headless

    private func applyHeadless(_ command: WatchCommand) {
        guard let context else { return }

        switch command {
        case .requestMirror:
            pushMirror(context: context)
            // Forced, not left to whether anything changed. A watch only asks
            // when it suspects it is behind — it has just launched, just come
            // back into range, or is holding a mirror built on a day that has
            // since ended — and answering "nothing changed" with silence leaves
            // it exactly as wrong as it was.
            WatchBridge.shared.resend()

        case .startToday, .startFreestyle:
            guard activeSession(in: context) == nil else { return }
            let history = finishedSessions(in: context)
            if case .startToday = command,
               let plan = activePlan(in: context),
               let day = plan.day(for: .now) {
                let session = SessionFactory.build(day: day, plan: plan, context: context, history: history)
                session.wasWatchDriven = true
            } else {
                let session = WorkoutSession(title: "Freestyle Session")
                session.wasWatchDriven = true
                context.insert(session)
            }
            save(context)
            pushMirror(context: context)

        case .logSet(let id, let weightKg, let reps, let seconds, let loggedAt):
            guard let set = setLog(id: id, in: context) else { return }
            set.weightKg = weightKg
            set.reps = reps
            if set.tracking == .duration { set.seconds = seconds }
            set.isCompleted = true
            // The wrist's clock rather than this one, and this is the path
            // where the two come apart: it runs with the phone asleep in a
            // locker or out of range entirely, so the moment it was handed the
            // command is the moment the lifter came back, not the moment they
            // racked the bar. No rest is started to go with it — there is no
            // screen here to count one down on, and the wrist has been running
            // the one that matters since the set was logged.
            set.completedAt = WatchCommand.loggedMoment(loggedAt)
            carryLoadForward(from: set)
            save(context)
            pushMirror(context: context)

        case .rateSet(let rating):
            guard rating.isValid,
                  let ratedSession = session(id: rating.sessionID, in: context),
                  let set = ratedSession.sets.first(where: { $0.id == rating.setID }),
                  set.isCompleted, rating.matches(set.completedAt) else { return }
            guard set.rpe != rating.rpe else {
                pushMirror(context: context)
                return
            }
            set.rpe = rating.rpe
            if set.loadNudgeOutcome == .declined { set.clearLoadNudge() }
            save(context)
            pushMirror(context: context)

        case .announceStart(let id, let moment):
            // The same rule `ActiveWorkout.announceStart` applies, and it has
            // to be the same one: this is the path that runs with the phone
            // asleep in a locker, which is exactly where a start that waited in
            // the queue comes from — and waiting is no longer a reason to
            // refuse one. See `WatchCommand.clockSkewTolerance`.
            guard let set = setLog(id: id, in: context), !set.isCompleted, set.startedAt == nil,
                  moment.timeIntervalSinceNow <= WatchCommand.clockSkewTolerance
            else { return }
            set.startedAt = moment
            save(context)
            pushMirror(context: context)

        case .cancelStart(let id):
            guard let set = setLog(id: id, in: context) else { return }
            // Nothing else goes with it. The announcement is the only thing
            // this tap ever wrote, and the rest it cut short is a countdown on
            // a screen — the phone is asleep here, so there is none to restore.
            set.startedAt = nil
            save(context)
            pushMirror(context: context)

        case .undoSet(let id):
            guard let set = setLog(id: id, in: context) else { return }
            // The same erasure the phone's own undo performs, and deliberately
            // the identical call. Clearing the completion alone left the effort
            // answer, the announced start and the heart rate read through it
            // sitting on a set the lifter had taken back — so a mis-tap on the
            // wrist wrote a rating and a time under tension into the record for
            // a set that, as far as the record is concerned, never happened.
            set.unlog()
            save(context)
            pushMirror(context: context)

        case .addSet(let catalogID):
            guard let session = activeSession(in: context) else { return }
            let existing = session.sets.filter { $0.catalogID == catalogID }
            // Modelled on the last set that was a set, exactly as the logger
            // does it — the wrist shouldn't add a different kind of set to the
            // phone just because it was the thing that asked. After a drop the
            // bottom row of an exercise is the lightest thing the lifter did.
            guard let template = existing.filter({ !$0.isContinuation }).max(by: { $0.setIndex < $1.setIndex })
                    ?? existing.max(by: { $0.setIndex < $1.setIndex })
            else { return }
            let set = SetLog(
                catalogID: template.catalogID,
                exerciseName: template.exerciseName,
                exerciseOrder: template.exerciseOrder,
                setIndex: (existing.map(\.setIndex).max() ?? template.setIndex) + 1,
                weightKg: template.weightKg,
                reps: template.reps,
                seconds: template.seconds,
                targetRepsLow: template.targetRepsLow,
                targetRepsHigh: template.targetRepsHigh
            )
            set.session = session
            context.insert(set)
            save(context)
            pushMirror(context: context)

        case .finish(let metrics):
            guard let session = activeSession(in: context) else { return }
            // The whole close, not just the unlogged sets. This path runs with
            // the phone asleep, and it used to stop at deleting those — so the
            // notes and drop rows the phone's own Finish tidies away reached
            // the record from here describing work that didn't happen.
            session.close(in: context)
            apply(metrics, to: session)
            save(context)
            WorkoutLiveActivity.shared.end(with: nil)
            WatchBridge.shared.update(session: nil)
            WatchBridge.shared.clearMetrics()
            publishWidgets(context: context)
            recordToHealth(session, context: context)

        case .discard:
            guard let session = activeSession(in: context) else { return }
            context.delete(session)
            save(context)
            WorkoutLiveActivity.shared.end(with: nil)
            WatchBridge.shared.update(session: nil)
            WatchBridge.shared.clearMetrics()
            publishWidgets(context: context)

        case .metrics(let metrics):
            // Live heart rate while the app is asleep is only worth keeping if
            // it belongs to a session that's already closed — that's the watch
            // handing over the workout it just saved to Health.
            guard let id = metrics.sessionID, let session = session(id: id, in: context) else { return }
            apply(metrics, to: session)
            save(context)

        case .focusExercise(let catalogID):
            guard let session = activeSession(in: context) else { return }
            session.preferredExerciseID = session.sets.contains { $0.catalogID == catalogID } ? catalogID : nil
            save(context)
            pushMirror(context: context)

        case .startRest, .stopRest, .extendRest:
            // The phone's own rest timer, which doesn't exist while the app is
            // asleep — the watch is running the countdown that matters.
            break
        }
    }

    // MARK: - Pieces

    private func apply(_ metrics: WatchWorkoutMetrics?, to session: WorkoutSession) {
        guard let metrics else { return }
        session.wasWatchDriven = true
        if let average = metrics.averageHeartRate { session.averageHeartRate = average }
        if let max = metrics.maxHeartRate { session.maxHeartRate = max }
        if let energy = metrics.activeEnergyKcal, energy > 0 { session.activeEnergyKcal = energy }
        if let workoutID = metrics.healthWorkoutID { session.healthWorkoutID = workoutID }
    }

    /// Mirrors the load just used onto the remaining sets, exactly as the
    /// logger does — the watch shouldn't behave differently because the phone
    /// happened to be asleep.
    private func carryLoadForward(from set: SetLog) {
        guard let session = set.session, !set.isContinuation else { return }
        for other in session.sets
        where other.catalogID == set.catalogID
            && !other.isCompleted
            && !other.isContinuation
            && other.setIndex > set.setIndex {
            other.weightKg = set.weightKg
            if other.tracking == .duration { other.seconds = set.seconds }
        }
    }

    private func recordToHealth(_ session: WorkoutSession, context: ModelContext) {
        Task { @MainActor in
            if session.healthWorkoutID == nil {
                for _ in 0..<12 where session.healthWorkoutID == nil {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            await HealthKitService.shared.saveWorkout(for: session)
            await HealthKitService.shared.backfillVitals(for: session)
            self.save(context)
        }
    }

    /// Restamps the widgets once a session has ended here. The Live Activity is
    /// taken down on this path and the Home Screen has to follow it, or a
    /// workout finished on the wrist with the phone in a bag goes on showing as
    /// running there until somebody next opens the app.
    private func publishWidgets(context: ModelContext) {
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        WidgetPublisher.publish(plans: plans, sessions: allSessions(in: context), running: nil)
    }

    private func pushMirror(context: ModelContext) {
        let sessions = allSessions(in: context)
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        WatchBridge.shared.update(idle: WatchMirrorBuilder.idle(plans: plans, sessions: sessions))

        guard let session = sessions.first(where: \.isActive) else {
            WatchBridge.shared.update(session: nil)
            return
        }

        let history = sessions.filter { !$0.isActive }
        let items = planItems(for: session, in: context)
        WatchBridge.shared.update(session: WatchSnapshotFactory.snapshot(
            for: session,
            rest: (nil, nil, 0),
            restSeconds: { items[$0]?.resolvedRestSeconds ?? AppSettings.shared.defaultRestSeconds },
            lastTimeLabel: { catalogID in
                WatchSnapshotFactory.label(
                    for: TrainingStats.lastPerformance(of: catalogID, in: history, excluding: session.id)
                )
            }
        ))
    }

    // MARK: - Fetching

    private func allSessions(in context: ModelContext) -> [WorkoutSession] {
        (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
    }

    private func finishedSessions(in context: ModelContext) -> [WorkoutSession] {
        allSessions(in: context).filter { !$0.isActive }
    }

    private func activeSession(in context: ModelContext) -> WorkoutSession? {
        allSessions(in: context).first(where: \.isActive)
    }

    private func session(id: UUID, in context: ModelContext) -> WorkoutSession? {
        allSessions(in: context).first { $0.id == id }
    }

    private func setLog(id: UUID, in context: ModelContext) -> SetLog? {
        activeSession(in: context)?.sets.first { $0.id == id }
    }

    private func activePlan(in context: ModelContext) -> Plan? {
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        return plans.first(where: \.isActive) ?? plans.first
    }

    private func planItems(for session: WorkoutSession, in context: ModelContext) -> [String: PlanItem] {
        guard let dayID = session.planDayID,
              let day = (try? context.fetch(FetchDescriptor<PlanDay>()))?.first(where: { $0.id == dayID })
        else { return [:] }
        return Dictionary(day.items.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func save(_ context: ModelContext) {
        do { try context.save() } catch {
            assertionFailure("Watch command couldn't be saved: \(error)")
        }
    }
}

// MARK: - Building the mirror

/// Shapes a session into what the watch draws. Both callers hand it their own
/// way of answering "how long is the rest here" and "what did this look like
/// last time" — the logger has both cached, the headless path looks them up.
enum WatchSnapshotFactory {

    @MainActor
    static func snapshot(for session: WorkoutSession,
                         currentSetID: UUID? = nil,
                         rest: (endsAt: Date?, startedAt: Date?, total: Int),
                         restSeconds: (String) -> Int,
                         lastTimeLabel: (String) -> String?) -> WatchSessionSnapshot {
        let groups = session.exerciseGroups

        var snapshot = WatchSessionSnapshot(
            sessionID: session.id,
            title: session.title,
            planName: session.planName,
            startedAt: session.startedAt,
            exercises: groups.map { group in
                WatchExerciseSnapshot(
                    id: group.catalogID,
                    name: group.name,
                    order: group.order,
                    tracking: WatchTracking(group.sets.first?.tracking ?? .weightReps),
                    restSeconds: restSeconds(group.catalogID),
                    sets: group.sets.map { set in
                        WatchSetSnapshot(
                            id: set.id,
                            index: set.setIndex,
                            weightKg: set.weightKg,
                            reps: set.reps,
                            seconds: set.seconds,
                            targetRepsLow: set.targetRepsLow,
                            targetRepsHigh: set.targetRepsHigh,
                            isCompleted: set.isCompleted,
                            continuation: set.isContinuation,
                            startedAt: set.startedAt,
                            completedAt: set.completedAt,
                            rpe: set.rpe
                        )
                    },
                    lastTimeLabel: lastTimeLabel(group.catalogID),
                    scale: LoadScaleBook.shared.scale(for: group.catalogID)
                )
            },
            preferredExerciseID: session.preferredExerciseID,
            currentSetID: currentSetID,
            restEndsAt: rest.endsAt,
            restStartedAt: rest.startedAt,
            restTotalSeconds: rest.total,
            restAutoStart: AppSettings.shared.restTimerAutoStart,
            volumeKg: session.totalVolumeKg,
            unit: AppSettings.shared.weightUnit,
            effortEnabled: AppSettings.shared.trackRPE
        )
        // Asked of the snapshot rather than of the session, so this answer and
        // the watch's own — made while a log of its own is still unconfirmed —
        // come out of the same lines. The two of them saying it separately is
        // what dragged the logger off the exercise the lifter had picked.
        if snapshot.currentSetID == nil {
            snapshot.currentSetID = snapshot.focusedExercise?.sets.first { !$0.isCompleted }?.id
        }
        return snapshot
    }

    /// "60 × 8" — last time's best set, for the hint under the exercise name.
    @MainActor
    static func label(for sets: [SetLog]) -> String? {
        guard let best = sets.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) ?? sets.first
        else { return nil }
        if best.tracking == .duration { return "\(best.seconds)s" }
        if best.weightKg == 0 { return "\(best.reps) reps" }
        return "\(best.loadScale.format(best.weightKg, showUnit: false)) × \(best.reps)"
    }
}
