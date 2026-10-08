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

    /// The container's main context, the one `RootView` and the logger read
    /// and write through. It used to be a second context of its own, kept for
    /// the life of the process, and rows saved through one were not always
    /// visible in the other: the summary on screen could not show a late
    /// wrist log until it was reopened. Commands are handled on the main
    /// actor, so sharing costs nothing and there is a single set of rows.
    private var context: ModelContext?

    /// Where the logger keeps what it would lose to a relaunch. Read here for
    /// the undo of a set the phone's logger carried, and cleared for a session
    /// this path ends. Tests hand it a suite of their own.
    var loggerMemory = LoggerMemoryStore.standard

    /// What this path asks of Health, and of the watch about Health, once a
    /// session ends here or a watch workout turns up with no session to own
    /// it. Each is the real call unless a test hands over its own:
    /// `HealthKitService` has a single instance and, in a test host, no Health
    /// store and no container to look a session up in, so a test could not
    /// otherwise see what was asked of it.
    struct HealthCalls {
        var saveWorkout: @MainActor (WorkoutSession) async -> UUID? = {
            await HealthKitService.shared.saveWorkout(for: $0)
        }
        var backfillVitals: @MainActor (WorkoutSession) async -> Void = {
            await HealthKitService.shared.backfillVitals(for: $0)
        }
        var discardOrphanWorkout: @MainActor (_ workoutID: UUID, _ sessionID: UUID) -> Void = {
            _ = HealthKitService.shared.discardOrphanWorkout($0, sessionID: $1)
        }
        var notePhoneWorkout: @MainActor (_ workoutID: UUID, _ sessionID: UUID) -> Void = {
            WatchBridge.shared.notePhoneHealthWorkout($0, for: $1)
        }
    }

    var health = HealthCalls()

    /// The Health write the last session ended here set off, so a test can
    /// wait for it to settle rather than guess how long that takes.
    private(set) var healthFollowUp: Task<Void, Never>?

    private init() {}

    /// Called once at launch, before the first watch message can arrive.
    func configure(container: ModelContainer) {
        context = container.mainContext
        repairStoredStartsOnce(in: container.mainContext)
        WatchBridge.shared.commandHandler = { [weak self] command in
            self?.handle(command)
        }
        WatchBridge.shared.activate()
        // The bridge sends nothing until it has been told what is running, and
        // this is where it is told. Activation finishing is what used to send
        // the first mirror, and in a fresh process that mirror said "no
        // session" — a guess, not the store. A watch mid-workout took it as the
        // end, threw away the Health recording it had kept since the first set
        // and dropped its unconfirmed logs. A background launch has no view to
        // correct it, and a foreground one corrected it too late, so the store
        // is read here, before either can happen.
        if let context { pushMirror(context: context) }
    }

    func handle(_ command: WatchCommand) {
        if uiHandler?(command) == true {
            rememberHeardLog(command)
            return
        }
        applyHeadless(command)
    }

    /// Clears the starts already stored that no set could have filled, and the
    /// ones another set's log overtook, once each. See
    /// `SetLog.dropImplausibleStoredStarts` and `SetLog.dropOvertakenStoredStarts`.
    /// A flag apiece rather than a check on every launch: the rules now hold on
    /// every path that writes a start, so once the old ones are gone nothing
    /// makes new ones. Two flags, not one, because the first pass has already
    /// run on every phone that has been updated before, and a second rule
    /// sharing its flag would never run on them.
    func repairStoredStartsOnce(in context: ModelContext, defaults: UserDefaults = .standard) {
        let implausibleKey = "implausibleStartsRepaired"
        if !defaults.bool(forKey: implausibleKey) {
            SetLog.dropImplausibleStoredStarts(in: context)
            defaults.set(true, forKey: implausibleKey)
        }
        let overtakenKey = "overtakenStartsRepaired"
        if !defaults.bool(forKey: overtakenKey) {
            SetLog.dropOvertakenStoredStarts(in: context)
            defaults.set(true, forKey: overtakenKey)
        }
    }

    /// A wrist log the running logger took, remembered as the headless path
    /// remembers its own; see `DroppedSetMemory.rememberHeardLog`. The logger
    /// reports nothing back, so the store is asked whether the row holds it.
    private func rememberHeardLog(_ command: WatchCommand) {
        guard case .logSet(let id, _, _, _, let loggedAt) = command, loggedAt != nil,
              let context else { return }
        var byID = FetchDescriptor<SetLog>(predicate: #Predicate { $0.id == id })
        byID.fetchLimit = 1
        guard let set = (try? context.fetch(byID))?.first, set.holdsWristLog(at: loggedAt) else { return }
        DroppedSetMemory.shared.rememberHeardLog(id, completedAt: loggedAt)
    }

    // MARK: - Headless

    /// Internal so a test can drive it without a view hierarchy, as a wake in
    /// the background does. Everything else goes through `handle`.
    func applyHeadless(_ command: WatchCommand) {
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
            // Yesterday's session would otherwise count as the one already
            // running, and be handed back to a wrist that will not draw it.
            closeStaleSession(in: context)
            guard activeSession(in: context) == nil else {
                // The first start may have landed while its mirror did not.
                // A retry needs the session back, even though nothing changed.
                pushMirror(context: context)
                WatchBridge.shared.resend()
                return
            }
            let history = finishedSessions(in: context)
            if case .startToday = command,
               let plan = activePlan(in: context),
               let day = plan.nextDay(on: .now, after: history) {
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
            // A log the wrist already took back, whose undo got here first.
            guard !DroppedSetMemory.shared.wasTakenBack(id, loggedAt: loggedAt) else { return }
            // A log this path already applied and the lifter has since undone,
            // sent again because the wrist never heard the answer. The row no
            // longer holds it, so `holdsWristLog` below cannot tell.
            guard !DroppedSetMemory.shared.wasHeardLog(id, loggedAt: loggedAt) else {
                pushMirror(context: context)
                return
            }
            // Finish carries the wrist's final set state. A queued command
            // delivered afterward must not rewrite that closed record — but
            // it may still be owed a row the close deleted before this log
            // could reach it.
            guard let set = setLog(id: id, in: context), set.session?.isActive == true else {
                restoreDroppedSet(id, weightKg: weightKg, reps: reps, seconds: seconds,
                                  loggedAt: loggedAt, in: context)
                return
            }
            // The same log again: see `SetLog.holdsWristLog`. Its load has
            // already been carried, and carrying it a second time would undo
            // whatever the lifter has dialled on the rows since.
            guard !set.holdsWristLog(at: loggedAt) else {
                pushMirror(context: context)
                return
            }
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
            let loggedMoment = WatchCommand.loggedMoment(loggedAt)
            set.completedAt = loggedMoment
            DroppedSetMemory.shared.rememberHeardLog(id, completedAt: loggedAt)
            // Logged inside the count-in: the start was a moment still to come,
            // and it never came. The rule `ActiveWorkout.complete` applies, for
            // the same reason — a set that began after it ended is a moment
            // nobody lived, whichever path wrote it. The same call also drops a
            // start too old for one set to have filled, and the starts this log
            // has overtaken on other sets: with the phone asleep, a start
            // abandoned for another exercise is exactly what the queue delivers
            // minutes before the log that used to close it.
            set.session?.settleStarts(afterLogging: set, at: loggedMoment)
            carryLoadForward(from: set, in: context)
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
            // refuse one. See `WatchCommand.isBelievableStart`. The moment is
            // written as it came: the wrist added the count-in when it was
            // tapped, and adding it again here would start the set late.
            guard let set = setLog(id: id, in: context), set.session?.isActive == true,
                  !set.isCompleted, set.startedAt == nil,
                  WatchCommand.isBelievableStart(moment)
            else { return }
            set.startedAt = moment
            // One set is under way at a time; see `ActiveWorkout.announceStart`.
            set.session?.dropOvertakenStarts(besides: set, at: moment)
            save(context)
            pushMirror(context: context)

        case .cancelStart(let id):
            guard let set = setLog(id: id, in: context), set.session?.isActive == true else { return }
            // Nothing else goes with it. The announcement is the only thing
            // this tap ever wrote, and the rest it cut short is a countdown on
            // a screen — the phone is asleep here, so there is none to restore.
            set.startedAt = nil
            save(context)
            pushMirror(context: context)

        case .undoSet(let id, let completion):
            DroppedSetMemory.shared.rememberTakenBack(id, completedAt: completion)
            guard let set = setLog(id: id, in: context), set.session?.isActive == true else {
                withdrawDroppedSet(id, completedAt: completion, in: context)
                return
            }
            // A stale undo, of a log the lifter has since replaced with
            // another; see `SetLog.admitsWristUndo`.
            guard set.admitsWristUndo(of: completion) else {
                pushMirror(context: context)
                return
            }
            // The same erasure the phone's own undo performs, and deliberately
            // the identical call. Clearing the completion alone left the effort
            // answer, the announced start and the heart rate read through it
            // sitting on a set the lifter had taken back — so a mis-tap on the
            // wrist wrote a rating and a time under tension into the record for
            // a set that, as far as the record is concerned, never happened.
            //
            // The logged drops directly beneath it go too, last one first, as
            // `ActiveWorkout.uncomplete` takes them. Left logged, they went
            // into the record as lifts taken without rest off a set that was
            // never done, whenever the phone was asleep for the undo.
            let carried = set.isCompleted ? (set.session?.loggedContinuations(below: set) ?? []) : []
            for row in carried.reversed() { row.unlog() }
            set.unlog()
            restorePrefill(carriedBy: set)
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
                targetRepsHigh: template.targetRepsHigh,
                tracking: template.tracking
            )
            set.session = session
            context.insert(set)
            save(context)
            pushMirror(context: context)

        case .finishSession(let batch, let metrics):
            guard let session = session(id: batch.sessionID, in: context) else {
                discardOrphanWorkout(of: metrics, sessionID: batch.sessionID)
                return
            }
            guard session.isActive else {
                // Repeated delivery may carry a late Health workout, but it
                // must never close whichever session opened after this one.
                // The phone's Finish may have got here first, too, deleting
                // rows this batch holds the wrist's logs for.
                let changed = session.applyLateWatchFinish(batch, in: context)
                apply(metrics, to: session, final: true, context: context)
                save(context)
                if changed { announceChange(context: context) }
                return
            }
            guard activeSession(in: context)?.id == batch.sessionID else { return }
            session.applyWatchFinish(batch)
            finish(session, metrics: metrics, at: session.wristFinishMoment(batch.endedAt), context: context)

        case .finish(let metrics):
            // Older queued commands only identify a session when the watch
            // sent metrics. A nil-metrics Finish cannot safely choose one.
            guard let metrics, let id = metrics.sessionID else { return }
            guard let session = session(id: id, in: context) else {
                discardOrphanWorkout(of: metrics, sessionID: id)
                return
            }
            if session.isActive {
                guard activeSession(in: context)?.id == id else { return }
                finish(session, metrics: metrics, context: context)
            } else {
                apply(metrics, to: session, final: true, context: context)
                save(context)
            }

        case .discardSession(let id):
            guard let session = activeSession(in: context), session.id == id else { return }
            discard(session, context: context)

        case .discard:
            // Legacy Discard has no session ID, so a delayed copy cannot be
            // distinguished from a request to delete the current workout.
            break

        case .metrics(let metrics):
            // Live heart rate while the app is asleep is written into the
            // session still running, the only record of it if the watch's
            // final report never comes. A closed session takes only the watch
            // handing over the workout it just saved to Health; see
            // `WorkoutSession.takeWatchMetrics`.
            guard let id = metrics.sessionID else { return }
            guard let session = session(id: id, in: context) else {
                discardOrphanWorkout(of: metrics, sessionID: id)
                return
            }
            guard apply(metrics, to: session, final: false, context: context) else { return }
            save(context)

        case .focusExercise(let catalogID):
            guard let session = activeSession(in: context) else { return }
            let known = session.sets.contains { $0.catalogID == catalogID }
            session.preferredExerciseID = known ? catalogID : nil
            // Somebody lifting this is no longer about to lift the set they
            // announced elsewhere; `ActiveWorkout.focus` clears it for the same
            // reason, and this is the path that runs with no logger.
            if known { session.dropStarts(awayFrom: catalogID) }
            save(context)
            pushMirror(context: context)

        case .startRest, .stopRest, .extendRest:
            // The phone's own rest timer, which doesn't exist while the app is
            // asleep — the watch is running the countdown that matters.
            break
        }
    }

    // MARK: - Pieces

    /// The workout the wrist saved to Health for a session that is no longer
    /// here: deleted while the wrist was saving, or before its Finish arrived.
    /// It is in Health with nothing to own it, so it is queued for removal;
    /// Health checks the store again first, and keeps it if a restore has put
    /// the session back.
    private func discardOrphanWorkout(of metrics: WatchWorkoutMetrics?, sessionID: UUID) {
        guard let workoutID = metrics?.healthWorkoutID else { return }
        health.discardOrphanWorkout(workoutID, sessionID)
    }

    /// A set command the running logger has no row for, arriving while the
    /// app is on screen. Such a row can only be one `close` deleted from a
    /// session already finished, so this reaches for that and nothing else:
    /// the running session belongs to the logger, and this context writing
    /// to it behind the logger's back is how two copies of a set disagree.
    func applyToFinishedSession(_ command: WatchCommand) {
        guard let context else { return }
        switch command {
        case .logSet(let id, let weightKg, let reps, let seconds, let loggedAt):
            restoreDroppedSet(id, weightKg: weightKg, reps: reps, seconds: seconds,
                              loggedAt: loggedAt, in: context, loggerRunning: true)
        case .undoSet(let id, let completion):
            DroppedSetMemory.shared.rememberTakenBack(id, completedAt: completion)
            withdrawDroppedSet(id, completedAt: completion, in: context, loggerRunning: true)
        default:
            break
        }
    }

    /// See `WorkoutSession.restoreDroppedSet` for when a row comes back.
    private func restoreDroppedSet(_ id: UUID, weightKg: Double, reps: Int, seconds: Int,
                                   loggedAt: Date?, in context: ModelContext,
                                   loggerRunning: Bool = false) {
        guard let row = DroppedSetMemory.shared.row(for: id),
              let session = session(id: row.sessionID, in: context),
              session.restoreDroppedSet(id, weightKg: weightKg, reps: reps, seconds: seconds,
                                        loggedAt: loggedAt, in: context) != nil
        else { return }
        save(context)
        announceChange(context: context, loggerRunning: loggerRunning)
    }

    private func withdrawDroppedSet(_ id: UUID, completedAt completion: Date? = nil,
                                    in context: ModelContext, loggerRunning: Bool = false) {
        guard let row = DroppedSetMemory.shared.row(for: id) else { return }
        guard let session = session(id: row.sessionID, in: context) else {
            // Discarded since: there is nothing left for a late log to join.
            DroppedSetMemory.shared.forget(id)
            return
        }
        guard session.withdrawDroppedSet(id, completedAt: completion, in: context) else { return }
        save(context)
        announceChange(context: context, loggerRunning: loggerRunning)
    }

    /// A finished session changed after the fact. The Home Screen and the
    /// watch's idle screen both count what it holds — sets, volume, the last
    /// thing trained — and would go on showing it without the set.
    ///
    /// The widgets only while nothing is running: this path has no logger to
    /// describe, and publishing without one would take a workout still in
    /// progress off the Home Screen. Its own Finish publishes this change too.
    /// With the logger on screen, only the idle half of the mirror goes: the
    /// session half is the logger's, and one built here has no rest timer.
    private func announceChange(context: ModelContext, loggerRunning: Bool = false) {
        let sessions = allSessions(in: context)
        if !sessions.contains(where: \.isActive) {
            publishWidgets(context: context, sessions: sessions)
        }
        guard loggerRunning else {
            pushMirror(context: context)
            return
        }
        let plans = allPlans(in: context)
        WatchBridge.shared.update(idle: WatchMirrorBuilder.idle(plans: plans, sessions: sessions))
    }

    /// - Parameter moment: when the session ended: the wrist's tap where it
    ///   sent one, and otherwise now.
    private func finish(_ session: WorkoutSession, metrics: WatchWorkoutMetrics?,
                        at moment: Date = .now, context: ModelContext) {
        // Read after the wrist's batch is applied, so its logs count. A Finish
        // with nothing logged is a Discard, here as in `ActiveWorkout.finish`:
        // kept, the empty session counted toward the streak and the week as a
        // day trained. A Health workout the wrist saved for it is not linked,
        // since there is no session left to own it.
        guard !session.completedSets.isEmpty else {
            discard(session, context: context)
            return
        }
        // The same close as the phone UI, after the wrist's last unconfirmed
        // actions have been applied. Only untouched rows are discarded.
        session.close(at: moment, in: context)
        // The logger's memory of this session goes with it: no logger is left
        // to clear it, and a key that outlived its session would be the one
        // thing in the app still remembering sets nobody holds any more.
        loggerMemory.forget(session.id)
        apply(metrics, to: session, final: true, context: context)
        save(context)
        WorkoutLiveActivity.shared.end(with: nil)
        // With the idle screen that counts it: nothing else restamps the wrist
        // on this path, so a Finish handled with the app asleep left it on the
        // start screen it showed before the workout.
        let sessions = allSessions(in: context)
        WatchBridge.shared.update(session: nil, ended: WatchSessionEnd(sessionID: session.id, reason: .finished),
                                  idle: WatchMirrorBuilder.idle(plans: allPlans(in: context), sessions: sessions))
        WatchBridge.shared.clearMetrics()
        publishWidgets(context: context, sessions: sessions)
        recordToHealth(session, context: context)
        NotificationCenter.default.post(name: .gymTrackWorkoutFinished, object: nil)
    }

    /// Deletes a running session and says so everywhere a Discard is heard.
    private func discard(_ session: WorkoutSession, context: ModelContext) {
        // Read before the delete: a deleted model is not something to read.
        let sessionID = session.id
        context.delete(session)
        loggerMemory.forget(sessionID)
        save(context)
        WorkoutLiveActivity.shared.end(with: nil)
        WatchBridge.shared.update(session: nil, ended: WatchSessionEnd(sessionID: sessionID, reason: .discarded))
        WatchBridge.shared.clearMetrics()
        publishWidgets(context: context)
    }

    /// - Parameter final: true for the metrics a Finish carried.
    /// - Returns: true when the session took them.
    @discardableResult
    private func apply(_ metrics: WatchWorkoutMetrics?, to session: WorkoutSession,
                       final: Bool, context: ModelContext) -> Bool {
        guard let metrics, session.takeWatchMetrics(metrics, final: final) else { return false }
        session.stampWatchVitals(average: metrics.averageHeartRate, max: metrics.maxHeartRate, energy: metrics.activeEnergyKcal)
        if let workoutID = metrics.healthWorkoutID {
            HealthKitService.shared.acceptWatchWorkout(workoutID, for: session, context: context)
        }
        return true
    }

    /// Mirrors the load just used onto the remaining sets, exactly as the
    /// logger does — the watch shouldn't behave differently because the phone
    /// happened to be asleep.
    ///
    /// Only as far as the end of the set's plan slot, as in the logger. A day
    /// that repeats a movement prescribes each slot its own load, and a top
    /// set logged on the wrist used to be carried onto the back-off sets too,
    /// so the phone and the watch disagreed about the same log.
    private func carryLoadForward(from set: SetLog, in context: ModelContext) {
        guard let session = set.session, !set.isContinuation else { return }
        let overwritten = ActiveWorkout.Prefill.carry(
            from: set, onto: SessionFactory.laterRowsInSlot(of: set, in: session, context: context))
        carriedPrefills[set.id] = overwritten.isEmpty ? nil : overwritten
    }

    /// What each set's carry overwrote, by the set that carried, so the wrist's
    /// undo can put the rows back as the phone's own does. In memory only: a
    /// carry this path made and then lost to a relaunch is not remembered. A
    /// carry the phone's logger made is in `loggerMemory` instead, and
    /// `restorePrefill` reads both.
    private var carriedPrefills: [UUID: [UUID: ActiveWorkout.Prefill]] = [:]

    /// The other half of `carryLoadForward`. Without it a mis-tapped wrist log
    /// left the rows below opening at the weight of a set never lifted, which
    /// the phone's undo never did. A row the lifter has typed into since keeps
    /// what they typed.
    ///
    /// A set logged on the phone and undone from the wrist has no record here,
    /// its carry having been made by the logger, which kept it in
    /// `LoggerMemoryStore` for exactly the case of nobody being left to ask.
    /// That record is used the same way, and spent: it is taken out of the
    /// store, so it can't put a weight back a second time.
    private func restorePrefill(carriedBy set: SetLog) {
        guard let session = set.session else { return }
        let memory = carriedPrefills.removeValue(forKey: set.id) ?? storedPrefill(carriedBy: set, in: session)
        guard let memory else { return }
        ActiveWorkout.Prefill.restore(memory, onto: Array(session.sets))
    }

    private func storedPrefill(carriedBy set: SetLog, in session: WorkoutSession) -> [UUID: ActiveWorkout.Prefill]? {
        guard var stored = loggerMemory.load(for: session.id),
              let carried = stored.carries.first(where: { $0.setID == set.id }) else { return nil }
        stored.carries.removeAll { $0.setID == set.id }
        loggerMemory.save(stored, for: session.id)
        return Dictionary(carried.rows.map { row in
            (row.rowID, ActiveWorkout.Prefill(kg: row.kg, seconds: row.seconds,
                                              carriedKg: row.carriedKg, carriedSeconds: row.carriedSeconds))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The headless twin of `ActiveWorkout.recordToHealth`.
    ///
    /// The task holds the session across up to twelve seconds of waiting and
    /// then Health's own calls, and it can be deleted, erased or restored over
    /// meanwhile. So every read after an await checks it is still there
    /// first: a deleted model can trap when read, and anything written for it
    /// is an orphan no later erase can find. The store is asked, not only the
    /// instance, because this context holds the session while the screen
    /// deletes through another, and that leaves this copy looking alive.
    ///
    /// The Health calls are taken when the session ends. Read after up to
    /// twelve seconds of waiting, they could be ones a later test handed over.
    private func recordToHealth(_ session: WorkoutSession, context: ModelContext) {
        let sessionID = session.id
        let health = self.health
        healthFollowUp = Task { @MainActor in
            func isGone() -> Bool {
                session.isGone(fromStore: FetchDescriptor<WorkoutSession>(
                    predicate: #Predicate { $0.id == sessionID }))
            }
            if session.healthWorkoutID == nil {
                for _ in 0..<12 {
                    guard !isGone() else { return }
                    if session.healthWorkoutID != nil { break }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            guard !isGone() else { return }
            let phoneWorkoutID = await health.saveWorkout(session)
            // A workout written for a session that went meanwhile has already
            // been queued for removal by `saveWorkout`.
            guard !isGone() else { return }
            if let phoneWorkoutID {
                health.notePhoneWorkout(phoneWorkoutID, sessionID)
            }
            await health.backfillVitals(session)
            guard !isGone() else { return }
            self.save(context)
        }
    }

    /// Restamps the widgets once a session has ended here. The Live Activity is
    /// taken down on this path and the Home Screen has to follow it, or a
    /// workout finished on the wrist with the phone in a bag goes on showing as
    /// running there until somebody next opens the app.
    private func publishWidgets(context: ModelContext, sessions: [WorkoutSession]? = nil) {
        let plans = allPlans(in: context)
        WidgetPublisher.publish(plans: plans, sessions: sessions ?? allSessions(in: context), running: nil)
    }

    private func pushMirror(context: ModelContext) {
        closeStaleSession(in: context)
        let sessions = allSessions(in: context)
        let plans = allPlans(in: context)
        // The session before the idle screen. Each update can go out on its
        // own, and the idle one sent first carried whatever session the bridge
        // held before — nothing at all in a fresh process, which a watch
        // mid-workout reads as the workout having ended.
        WatchBridge.shared.update(session: sessionSnapshot(from: sessions, in: context))
        WatchBridge.shared.update(idle: WatchMirrorBuilder.idle(plans: plans, sessions: sessions))
        // The Lock Screen card and the Home Screen widget are told from the
        // same read, once per change. Every command that reaches here without
        // a logger used to leave both on whatever the app last published, so
        // sets logged from the wrist with the phone in a bag never moved them.
        WidgetPublisher.publishHeadless(running: sessions.first(where: \.isActive))
    }

    private func sessionSnapshot(from sessions: [WorkoutSession],
                                 in context: ModelContext) -> WatchSessionSnapshot? {
        guard let session = sessions.first(where: \.isActive) else { return nil }
        if session.normalizeExerciseSlots() { save(context) }

        let history = sessions.filter { !$0.isActive }
        let items = planItems(for: session, in: context)
        return WatchSnapshotFactory.snapshot(
            for: session,
            rest: (nil, nil, 0),
            // Blank because there is no timer here, not because there is no
            // rest. See `WatchSessionSnapshot.restUnknown`.
            restUnknown: true,
            restSeconds: { items[$0]?.resolvedRestSeconds ?? AppSettings.shared.defaultRestSeconds },
            lastTimeLabel: { catalogID in
                WatchSnapshotFactory.label(
                    for: TrainingStats.lastPerformance(of: catalogID, in: history, excluding: session.id)
                )
            }
        )
    }

    /// Retires a session left open past the twelve-hour mark — see
    /// `WorkoutSession.closeIfStale` — on the path that runs with no view at
    /// all: a phone woken in the background by the wrist has never been
    /// through the cold launch that used to be the only place this was asked.
    ///
    /// The Live Activity goes because the session it describes has; the
    /// widgets follow for the same reason. The watch is told how the session
    /// ended before whichever mirror the caller sends next.
    @discardableResult
    private func closeStaleSession(in context: ModelContext) -> Bool {
        // Only an open session can be stale, so the history is not fetched to
        // answer this, and this runs on every mirror.
        let stale = unfinishedSessions(in: context).filter { $0.isStale() }.sorted { $0.startedAt < $1.startedAt }
        guard !stale.isEmpty else { return false }
        let ends = stale.compactMap { retire($0, in: context) }
        // A session opened alongside the stale one is still running, and the
        // card, the widgets and the wrist are about that one.
        guard unfinishedSessions(in: context).isEmpty else { return true }
        WorkoutLiveActivity.shared.end(with: nil)
        // The latest is the one a wrist could still be recording.
        WatchBridge.shared.update(session: nil, ended: ends.last)
        publishWidgets(context: context)
        return true
    }

    /// Retires one session left open past the twelve-hour mark, and writes the
    /// Health workout of one that kept sets, ending where the close ended it:
    /// at the last set. Shared with `RootView`, which meets the same session on
    /// a warm resume and a cold launch.
    ///
    /// The Health write is the one a Finish makes, waiting for a watch that is
    /// still recording to hand over its own workout first. A session deleted
    /// for being empty gets none: it is not a workout.
    ///
    /// - Returns: how the wrist should hear the session ended, for the
    ///   caller's next mirror; `nil` when the session was not stale.
    @discardableResult
    func retire(_ session: WorkoutSession, in context: ModelContext) -> WatchSessionEnd? {
        guard let end = session.retireIfStale(in: context) else { return nil }
        // Finished or deleted, either way the logger's memory of it is over.
        loggerMemory.forget(end.sessionID)
        save(context)
        if end.reason == .finished { recordToHealth(session, context: context) }
        return end
    }

    // MARK: - Fetching

    /// Every session, finished or not. Only what reads the whole history asks
    /// for this — the idle screen's streak, the widgets — and each command
    /// asks once; the lookups below are predicated.
    private func allSessions(in context: ModelContext) -> [WorkoutSession] {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return WatchSessionRecovery.discardUntouchedOverlaps(sessions, in: context)
    }

    /// Sessions still open, which is nearly always one. A workout is looked
    /// for here far more often than the history is wanted, and the history
    /// grows for as long as the app is used.
    private func unfinishedSessions(in context: ModelContext) -> [WorkoutSession] {
        let open = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt == nil })
        let sessions = (try? context.fetch(open)) ?? []
        return WatchSessionRecovery.discardUntouchedOverlaps(sessions, in: context)
    }

    /// Finished sessions need no overlap check: only a session still open can
    /// be the duplicate that check removes.
    private func finishedSessions(in context: ModelContext) -> [WorkoutSession] {
        let finished = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil })
        return (try? context.fetch(finished)) ?? []
    }

    private func activeSession(in context: ModelContext) -> WorkoutSession? {
        guard let session = unfinishedSessions(in: context).first else { return nil }
        if session.normalizeExerciseSlots() { save(context) }
        return session
    }

    private func session(id: UUID, in context: ModelContext) -> WorkoutSession? {
        var byID = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        byID.fetchLimit = 1
        guard let found = try? context.fetch(byID).first else { return nil }
        // An open session that is an untouched duplicate is deleted by the
        // check, and a lookup by its ID must not hand it back.
        return WatchSessionRecovery.discardUntouchedOverlaps([found], in: context).first
    }

    private func setLog(id: UUID, in context: ModelContext) -> SetLog? {
        activeSession(in: context)?.sets.first { $0.id == id }
    }

    /// The plan Today is showing; see `Plan.displayed(among:)`. What a Start
    /// from the wrist begins has to be that plan, whichever order the store
    /// hands the plans back in.
    private func activePlan(in context: ModelContext) -> Plan? {
        Plan.displayed(among: allPlans(in: context))
    }

    /// Every plan, oldest first, the order Today's own query reads them in.
    /// The idle mirror takes its plan as the first the rule finds in this list,
    /// so an unsorted fetch here put a different routine on the wrist than the
    /// one on the phone.
    private func allPlans(in context: ModelContext) -> [Plan] {
        (try? context.fetch(FetchDescriptor<Plan>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private func planItems(for session: WorkoutSession, in context: ModelContext) -> [String: PlanItem] {
        guard let dayID = session.planDayID else { return [:] }
        var byID = FetchDescriptor<PlanDay>(predicate: #Predicate { $0.id == dayID })
        byID.fetchLimit = 1
        guard let day = (try? context.fetch(byID))?.first else { return [:] }
        return Dictionary(day.orderedItems.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
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
                         restUnknown: Bool = false,
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
            effortEnabled: AppSettings.shared.trackRPE,
            restUnknown: restUnknown ? true : nil
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

/// What the phone has told the watch link so far, kept apart from
/// WatchConnectivity so the rule that matters most can be checked on its own:
/// no mirror exists until the phone has said what is running.
///
/// A fresh process starts with an empty idle screen and no session, and until
/// something has read the store that is a guess. Sent anyway — activation
/// finishing was enough to send it — it reached a watch mid-workout stamped
/// newer than anything it held, and the watch took "no session" to mean the
/// workout was over: it discarded the Health recording it had kept since the
/// first set, and the logs it had not yet heard back about.
struct WatchMirrorState {
    private(set) var idle: WatchIdleSnapshot = .empty
    private(set) var session: WatchSessionSnapshot?
    private(set) var endedSession: WatchSessionEnd?
    /// Set by the first session update, including one saying none is running.
    /// That answer is as much the truth as a session is; the empty value this
    /// starts with is not.
    private(set) var isEstablished = false
    private var revision = 0

    /// Returns true when the idle screen changed.
    mutating func update(idle snapshot: WatchIdleSnapshot) -> Bool {
        guard idle != snapshot else { return false }
        idle = snapshot
        return true
    }

    /// Returns true when there is something new to send. The first update
    /// always is: it is the moment the watch can be told anything at all.
    mutating func update(session snapshot: WatchSessionSnapshot?, ended end: WatchSessionEnd?) -> Bool {
        let nextEnd = snapshot == nil ? (end ?? endedSession) : nil
        let changed = !isEstablished || session != snapshot || endedSession != nextEnd
        isEstablished = true
        session = snapshot
        endedSession = nextEnd
        return changed
    }

    /// Returns true when the finish the watch was told about now names the
    /// phone's Health workout.
    mutating func notePhoneHealthWorkout(_ workoutID: UUID, for sessionID: UUID) -> Bool {
        guard endedSession?.sessionID == sessionID,
              endedSession?.reason == .finished else { return false }
        endedSession?.phoneHealthWorkoutID = workoutID
        return true
    }

    /// The next mirror to send, or nil while nothing has been established.
    mutating func nextMirror(sentAt: Date = .now, healthEnabled: Bool) -> WatchMirror? {
        guard isEstablished else { return nil }
        revision += 1
        return WatchMirror(
            revision: revision,
            sentAt: sentAt,
            idle: idle,
            session: session,
            healthEnabled: healthEnabled,
            endedSession: endedSession
        )
    }
}

extension SetLog {
    /// Drops the start of every logged set that another set's log falls
    /// strictly inside, and returns how many went.
    ///
    /// The live rule (`WorkoutSession.dropOvertakenStarts`) clears the start of
    /// an unlogged set when another set is logged after it: nobody lifts two
    /// sets at once. Sets stored before it, or logged behind a delivery that
    /// arrived out of order, kept the start, and paired with their own log it
    /// is a time under tension that includes somebody else's whole set,
    /// exported as measured.
    ///
    /// The store cannot say which message arrived first, and that is not
    /// needed. Arrival order only decides whether the live rule met the row
    /// still unlogged; the contradiction itself is in the stamps: a set that
    /// was started at `s` and logged at `c` cannot have had another set logged
    /// at `t` with `s < t < c`, whichever order the phone heard the three in.
    /// Only the start goes, as in the first repair; a start proven false is
    /// dropped, never shortened to fit.
    ///
    /// Strictly inside, so two logs stamped the same instant leave both starts
    /// alone: there it is the arrival order that would decide, and that is the
    /// one thing not stored.
    @discardableResult
    static func dropOvertakenStoredStarts(in context: ModelContext) -> Int {
        let withStart = FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.isCompleted && $0.startedAt != nil })
        var dropped = 0
        for set in (try? context.fetch(withStart)) ?? [] {
            guard let start = set.startedAt, let logged = set.completedAt,
                  let session = set.session else { continue }
            let overtaken = session.sets.contains { other in
                guard other.id != set.id, other.isCompleted, let moment = other.completedAt else { return false }
                return start < moment && moment < logged
            }
            guard overtaken else { continue }
            set.startedAt = nil
            dropped += 1
        }
        if dropped > 0 { try? context.save() }
        return dropped
    }
}
