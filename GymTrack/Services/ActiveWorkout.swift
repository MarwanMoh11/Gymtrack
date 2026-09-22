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

    /// The set logged most recently — the one the effort question is about
    /// while it's still unanswered. Asking on every completed set at once would
    /// turn a column of finished work into a column of open questions; older
    /// sets can still be answered, they just have to be asked for.
    private(set) var lastLoggedSetID: UUID?

    /// The set the rest bar is asking about — the one just logged, whether or
    /// not it has been answered for. It stays after an answer so the answer can
    /// be seen, changed, or cleared outright from the same place it was given.
    var ratingSubject: SetLog? {
        guard AppSettings.shared.trackRPE, let id = lastLoggedSetID else { return nil }
        return session.sets.first { $0.id == id && $0.isCompleted }
    }

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
    ///
    /// - Parameter moment: when the set was logged. Defaults to now, which is
    ///   right for a tap on the phone. The wrist passes its own timestamp,
    ///   because a log sent out of range waits in a queue until the phone is
    ///   nearby again and stamping it on arrival would report a set that
    ///   finished on the walk back rather than under the bar.
    func complete(_ set: SetLog, restSeconds: Int?, at moment: Date = .now) {
        set.isCompleted = true
        set.completedAt = moment
        lastLoggedSetID = set.id
        // Whatever the last answer offered belonged to the set before this one.
        // Logging another set is an answer of its own — you took the weight you
        // took — so the offer, and the chance to undo having taken it, both go
        // rather than hanging over the new row.
        //
        // And that answer is the one that goes on the record: lifting the next
        // set at the old weight is a decline whether or not anybody tapped the
        // cross, and the two are indistinguishable from here.
        if let standing = pendingNudge { subject(of: standing)?.recordLoadNudge(.declined, toKg: standing.toKg) }
        pendingNudge = nil
        takenNudge = nil
        // The rest this set's announcement cut short can no longer be put
        // back: the set it would have been counting down to has been done.
        restCancelledByStart = nil
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
            // The rest began when the set was logged, and for a set logged on
            // the wrist out of range that is not this moment. Starting a fresh
            // countdown for one of those would put the whole app back into
            // resting — amber header, amber Lock Screen, a "Rest over"
            // notification — for a set the lifter finished in another room and
            // has long since rested through. So the rest is picked up where it
            // actually is: still running, and the two screens agree on how much
            // of it is left; already over, and there is nothing to start.
            restTimer.restore(endingAt: moment.addingTimeInterval(TimeInterval(seconds)),
                              totalSeconds: seconds)
        }
    }

    /// Mirrors the load just used onto the remaining sets of the same exercise.
    /// Without this you re-dial the weight for every set of every exercise.
    ///
    /// A row that continued the set above it carries nothing forward: its
    /// weight was chosen to be lower, for that row, and pushing it down the
    /// card would leave the working sets still to come sitting at the drop
    /// weight — the lifter would take one drop and find the rest of the
    /// exercise quietly deloaded.
    private func carryLoadForward(from set: SetLog) {
        guard !set.isContinuation else { return }
        for other in session.sets
        where other.catalogID == set.catalogID
            && !other.isCompleted
            && !other.isContinuation
            && other.setIndex > set.setIndex {
            other.weightKg = set.weightKg
            if other.tracking == .duration { other.seconds = set.seconds }
        }
    }

    func uncomplete(_ set: SetLog) {
        // Everything the set itself gained by being logged — see `SetLog.unlog`,
        // which is also what the wrist's own undo runs so the two can't drift.
        set.unlog()
        recentPRs.remove(set.id)
        if lastLoggedSetID == set.id { lastLoggedSetID = nil }
        if pendingNudge?.setID == set.id { pendingNudge = nil }
        // Taking the set back takes back everything answering for it did,
        // including a weight change its answer put on the sets underneath.
        if takenNudge?.nudge.setID == set.id { restoreWeights() }
        // The rest belonged to the set being taken back, so it goes with it.
        // `complete` is what started it; this is the other half of that.
        restTimer.stop()
        save()
        Haptics.tick()
    }

    func isPR(_ set: SetLog) -> Bool { recentPRs.contains(set.id) }

    /// A weight or a rep count changed by hand on a set that hasn't been logged
    /// yet. The logger writes those straight onto the `SetLog` through a
    /// binding, so the number on screen is already right and nothing here has
    /// to touch it — but everything drawing the same set from a copy is still
    /// holding the old one.
    ///
    /// The wrist is the one that bites. It went on showing the weight from
    /// before the edit and then wrote that stale weight back over this one the
    /// moment the set was logged from the watch, so an adjustment made on the
    /// phone was undone by the next tap on the wrist.
    func numbersChanged() { save() }

    // MARK: - Taking a set further

    /// Adds a row that carries on from `set` without the effort being put down
    /// — the second half of a drop set, the next cluster of a myo-rep run.
    ///
    /// The row goes directly under the set it continues, not on the end, and
    /// the sets after it move down one. Position is the whole of what the link
    /// means: an effort is a run of adjacent rows, so a continuation parked at
    /// the bottom of the card would claim to continue whatever happened to
    /// precede it there.
    ///
    /// It opens at the weight and reps just lifted, so the lifter's only job is
    /// to dial one of them — and which way they dial the weight is what makes
    /// this a drop or a cluster. Nothing about the effort is asked; see
    /// `SetContinuation`.
    ///
    /// The rest stops, because this is the definition of the thing: a
    /// continuation is taken without one. Leaving the countdown running would
    /// have the app read as resting through the seconds that make this a drop
    /// rather than two sets — amber header, amber Lock Screen, amber wrist —
    /// and then fire "Rest over" halfway through the reps.
    func continueSet(_ set: SetLog) {
        guard set.isCompleted else { return }

        for other in session.sets
        where other.catalogID == set.catalogID && other.setIndex > set.setIndex {
            other.setIndex += 1
        }

        let next = SetLog(
            catalogID: set.catalogID,
            exerciseName: set.exerciseName,
            exerciseOrder: set.exerciseOrder,
            setIndex: set.setIndex + 1,
            weightKg: set.weightKg,
            reps: set.reps,
            seconds: set.seconds,
            // No rep range, because nobody prescribed one. The plan asks for
            // three sets of 6–10; it has nothing to say about what a lifter
            // does after the third one on the way back down, and a range copied
            // off the set above would have the card demand 6 reps of a drop and
            // the progression read it as a working set that fell short.
            targetRepsLow: 0,
            targetRepsHigh: 0
        )
        next.continuesPreviousSet = true
        next.session = session
        context.insert(next)

        restTimer.stop()
        save()
        Haptics.log()
    }

    /// Takes the row back off, the exact pair of `continueSet` — for a mis-tap,
    /// or an effort the lifter decided not to take further after all. Only
    /// while it holds nothing: once there are reps in it, removing it would
    /// delete a lift, and `separate` is the way out of that instead.
    func removeContinuation(_ set: SetLog) {
        guard set.isContinuation, !set.isCompleted else { return }
        context.delete(set)
        resequence(set.catalogID)
        save()
        Haptics.tick()
    }

    /// Cuts the link and keeps the reps: the row becomes an ordinary set of its
    /// own, which is what it would have been had nobody said otherwise.
    ///
    /// For the lift that was logged as a continuation and wasn't one. The reps
    /// happened and the weight moved, so deleting them would be erasing work to
    /// correct a label — the only thing wrong here is the claim that no rest
    /// was taken, and that is the only thing that goes.
    func separate(_ set: SetLog) {
        guard set.isContinuation else { return }
        set.continuesPreviousSet = nil
        save()
        Haptics.tick()
    }

    // MARK: - Saying you're starting

    /// The rest that announcing a start stopped, kept only long enough for the
    /// announcement to be taken back. Not persisted: it describes a countdown
    /// on screen, and a countdown doesn't survive the session either.
    private var restCancelledByStart: (setID: UUID, endsAt: Date, totalSeconds: Int)?

    /// Marks the moment the lifter says they're going. Everything the record
    /// gains comes from this one stamp: the rest before it stops being a guess
    /// with a set hidden inside it, and the set itself gets a length.
    ///
    /// Optional in the strongest sense — nothing here is required for a set to
    /// be logged, and a session where it's never touched behaves exactly as it
    /// did before this existed.
    ///
    /// - Parameter moment: when the set began. Defaults to now, which is right
    ///   for a tap on the phone. The wrist passes its own timestamp, because a
    ///   command sent out of range waits in a queue until the phone is nearby
    ///   again and stamping it on arrival would report a set that started in
    ///   the locker room.
    func announceStart(_ set: SetLog, at moment: Date = .now) {
        guard !set.isCompleted, set.startedAt == nil else { return }
        // A start that has been sitting in the watch's delivery queue is kept:
        // the log that closes the set carries the wrist's clock too, so the
        // pair is true however long the two of them waited together. Only a
        // start from ahead of this clock is refused, and that one is the two
        // devices disagreeing about the time rather than a moment — see
        // `WatchCommand.clockSkewTolerance`.
        guard moment.timeIntervalSinceNow <= WatchCommand.clockSkewTolerance else { return }
        set.startedAt = moment

        // The rest is over the moment you say you're starting — that is the
        // thing the countdown was counting down to. Left running it would tick
        // on through the set and fire "Rest over" with the bar on your back,
        // and the whole app would read as resting while you work: amber header,
        // amber Lock Screen, amber wrist. `complete` is what starts a rest;
        // this is the other thing that ends one, and the only one that knows
        // the rest ended early.
        if restTimer.isRunning, let endsAt = restTimer.endsAt {
            restCancelledByStart = (set.id, endsAt, restTimer.totalSeconds)
            restTimer.stop()
        }

        save()
        // Its own feel, not the stepper's tick and not `log()`: the heavier
        // thud means "that's in the record" and stays unique to a set being
        // logged, while the tick was too faint to confirm anything to somebody
        // who is looking at a bar rather than at the screen.
        Haptics.start()
    }

    /// Un-says it, all the way back to never having tapped. The stamp goes, and
    /// the rest the tap cut short comes back exactly where it was — a mis-tap
    /// on a small control mid-workout has to cost nothing at all, including the
    /// countdown you were watching.
    func cancelStart(_ set: SetLog) {
        set.startedAt = nil
        if let cancelled = restCancelledByStart, cancelled.setID == set.id {
            restTimer.restore(endingAt: cancelled.endsAt, totalSeconds: cancelled.totalSeconds)
            restCancelledByStart = nil
        }
        save()
        Haptics.tick()
    }

    /// How the set felt. The answer is acted on immediately rather than filed
    /// away for next week: that's the whole difference between a question with
    /// a point and a quiz.
    func rate(_ set: SetLog, feel: SetFeel) {
        // Tapping the answer it already holds takes it back, so the gesture
        // that answers the question also un-answers it.
        guard set.rpe != feel.rawValue else { return clearRating(set) }
        set.rpe = feel.rawValue
        forgetUntakenNudge(on: set)
        pendingNudge = nudge(after: set)
        save()
        Haptics.tick()
    }

    /// Un-answers the question, all the way back to never having been asked.
    /// An offer the answer produced goes with it; a change already taken has
    /// its own undo, because that one moved real numbers.
    func clearRating(_ set: SetLog) {
        set.rpe = nil
        if pendingNudge?.setID == set.id { pendingNudge = nil }
        forgetUntakenNudge(on: set)
        save()
        Haptics.tick()
    }

    /// Takes an offer the lifter turned down off the record along with the
    /// answer that produced it. The question is being un-asked back to never
    /// having been put, and an offer nobody acted on leaves nothing behind it.
    ///
    /// A taken one stays. It moved real weights and withdrawing the answer
    /// doesn't move them back — that is the line `clearRating` already draws,
    /// and the record follows the weights rather than the fiction.
    private func forgetUntakenNudge(on set: SetLog) {
        guard set.loadNudgeOutcome == .declined else { return }
        set.clearLoadNudge()
    }

    /// The set whose answer produced an offer — where the outcome is filed.
    private func subject(of nudge: LoadNudge) -> SetLog? {
        session.sets.first { $0.id == nudge.setID }
    }

    // MARK: - Acting on the answer

    /// A change to the sets still to come, offered the moment you say how the
    /// last one felt. Never applied on its own — the lifter takes it or ignores
    /// it, and ignoring it is one of the two normal outcomes.
    struct LoadNudge: Identifiable, Equatable {
        /// The set whose answer produced this.
        let setID: UUID
        /// Its position in the exercise — only the sets after it are moved.
        let fromIndex: Int
        let catalogID: String
        let fromKg: Double
        let toKg: Double
        /// How many sets of this exercise it would move.
        let setCount: Int
        let feel: SetFeel

        var id: UUID { setID }

        /// True when the offer is to take weight off rather than put it on.
        var isBackOff: Bool { toKg < fromKg }
    }

    private(set) var pendingNudge: LoadNudge?

    /// Reads the set just rated the way the progression would read it next
    /// week, and applies that reading to the sets still in front of you.
    ///
    /// Only the two unambiguous cases: cleared the range with three reps in the
    /// tank (the load is too light to be teaching anything), or buried yourself
    /// and still came up short (the load is why). Everything in between is left
    /// alone — a suggestion after every single set would be noise, and noise is
    /// what people learn to tap past.
    private func nudge(after set: SetLog) -> LoadNudge? {
        // Nothing is read off a row that continued the set above it. Its load
        // was picked to be survivable rather than to be the right load, so
        // "that felt hard at 40 kg after eight at 62.5" says nothing about what
        // the next working set should weigh — and the offer would move that
        // working set on the strength of it.
        guard !set.isContinuation else { return nil }
        guard let feel = set.feel, set.tracking != .duration, set.weightKg > 0 else { return nil }

        let remaining = session.sets.filter {
            $0.catalogID == set.catalogID && !$0.isCompleted
                && !$0.isContinuation && $0.setIndex > set.setIndex
        }
        guard !remaining.isEmpty else { return nil }

        let scale = set.loadScale
        let target: Double
        switch feel {
        case .easy where set.hitTopOfRange || set.targetRepsHigh <= 0:
            target = scale.step(kg: set.weightKg, by: 1)
        case .allOut where set.fellShortOfRange:
            target = scale.step(kg: set.weightKg, by: -1)
        default:
            return nil
        }

        // A ladder with nowhere left to go — the bottom rung, or an exercise
        // whose scale has no step at this weight — has nothing to offer.
        guard target > 0, target != set.weightKg else { return nil }

        return LoadNudge(setID: set.id, fromIndex: set.setIndex, catalogID: set.catalogID,
                         fromKg: set.weightKg, toKg: target,
                         setCount: remaining.count, feel: feel)
    }

    /// A change that was taken, and every weight it overwrote. Kept so that
    /// taking one by mistake costs exactly nothing: a misfire on a small button
    /// mid-workout has to be undoable back to the state before the tap, not
    /// merely adjustable afterwards.
    struct TakenNudge: Identifiable, Equatable {
        let nudge: LoadNudge
        /// What each set weighed before — restored verbatim, not recomputed.
        let previousKg: [UUID: Double]
        var id: UUID { nudge.setID }
    }

    private(set) var takenNudge: TakenNudge?

    /// Takes the offer: every set of that exercise still to come moves onto the
    /// new rung.
    func apply(_ nudge: LoadNudge) {
        var previous: [UUID: Double] = [:]
        for set in session.sets
        where set.catalogID == nudge.catalogID
            && !set.isCompleted
            // A pending drop row is at the weight the lifter dialled it to. The
            // offer is about the working sets, and it counted only those.
            && !set.isContinuation
            && set.setIndex > nudge.fromIndex {
            previous[set.id] = set.weightKg
            set.weightKg = nudge.toKg
        }
        pendingNudge = nil
        takenNudge = previous.isEmpty ? nil : TakenNudge(nudge: nudge, previousKg: previous)
        // Only where something actually moved. An offer that found no sets left
        // to change was not taken — nothing happened — and saying it was would
        // put a rung on the record that nobody ever lifted.
        if takenNudge != nil { subject(of: nudge)?.recordLoadNudge(.taken, toKg: nudge.toKg) }
        save()
        Haptics.log()
    }

    /// Puts every weight back where it was and stands the offer back up, so the
    /// screen reads exactly as it did before the button was pressed.
    func undoTakenNudge() {
        guard let taken = takenNudge else { return }
        restoreWeights()
        pendingNudge = taken.nudge
        // Off the record entirely, not filed as a decline. The weights are back
        // where they were and the offer is standing again, so the screen reads
        // as though the button was never pressed, and the record has to say the
        // same thing — the lifter has made no decision yet.
        subject(of: taken.nudge)?.clearLoadNudge()
        save()
        Haptics.tick()
    }

    /// The weights half of that, without restoring the offer — for when the set
    /// that produced it is being un-logged and the offer is going too.
    private func restoreWeights() {
        guard let taken = takenNudge else { return }
        for set in session.sets {
            guard let weight = taken.previousKg[set.id], !set.isCompleted else { continue }
            set.weightKg = weight
        }
        takenNudge = nil
    }

    func dismissNudge() {
        guard let nudge = pendingNudge else { return }
        subject(of: nudge)?.recordLoadNudge(.declined, toKg: nudge.toKg)
        pendingNudge = nil
        // This used to change nothing on disk, so there was nothing to write.
        // Now the cross puts something in the record, and the record has to
        // survive the phone dying mid-session like everything else here.
        save()
        Haptics.tick()
    }

    // MARK: - Structure edits

    func addSet(to group: SessionExerciseGroup) {
        // Modelled on the last set that was a set. Copying a drop row instead
        // would open the new one at the back-off weight with no rep range —
        // "Add set" means another working set, and after a drop the last row on
        // the card is the lightest thing the lifter did all exercise.
        guard let template = group.sets.last(where: { !$0.isContinuation }) ?? group.sets.last
        else { return }
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

    /// Takes a set off the end — the pair of `addSet`, undoing exactly what
    /// that did. The last set of an exercise stays: removing it would leave a
    /// card with nothing on it.
    func removeLastSet(from group: SessionExerciseGroup) {
        guard group.sets.count > 1, let last = group.sets.last else { return }
        context.delete(last)
        resequence(group.catalogID)
        save()
        Haptics.tick()
    }

    /// Renumbers one exercise so its sets run 0, 1, 2 with no gaps. `setIndex`
    /// is what orders a card, and it's also what pairs a set with the same set
    /// last session, so a deletion in the middle can't be left as a hole.
    private func resequence(_ catalogID: String) {
        let sets = session.sets
            .filter { $0.catalogID == catalogID }
            .sorted { $0.setIndex < $1.setIndex }
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
        // The note was about an exercise that is no longer in this session.
        // Left behind it would describe work the record says never happened.
        session.dropNote(about: group.catalogID, in: context)
        save()
    }

    // MARK: - Notes

    /// What's been written about one exercise so far, if anything.
    func note(for catalogID: String) -> ExerciseNote? { session.note(for: catalogID) }

    func writeNote(_ text: String, about group: SessionExerciseGroup) {
        session.writeNote(text, about: group.catalogID, named: group.name, in: context)
        persistNote()
    }

    func toggleNoteTag(_ tag: NoteTag, about group: SessionExerciseGroup) {
        session.toggleNoteTag(tag, about: group.catalogID, named: group.name, in: context)
        persistNote()
        Haptics.tick()
    }

    /// Called when a note's field closes, which is the point at which "I typed
    /// something and took it back" becomes final.
    func pruneEmptyNotes() {
        session.pruneEmptyNotes(in: context)
        persistNote()
    }

    /// A note changes nothing the Lock Screen, the widgets or the wrist draw,
    /// and this runs on every keystroke — the full `save()` would put a
    /// watch message and a widget reload behind each character typed.
    private func persistNote() {
        writeThrough()
    }

    // MARK: - Ending

    /// Drops any sets left unlogged and stamps the session finished.
    func finish() {
        // Before the unlogged sets go, because which exercises survive is what
        // decides which notes still have something to be about.
        pruneNotes()
        unlinkOrphanedContinuations()
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

    /// What survives the end of the session: a note that says something, about
    /// an exercise that ended up in the record.
    ///
    /// An exercise you logged nothing for is dropped from the session entirely
    /// — that's what `finish` does with its sets — so a note left on it would
    /// be the only trace of an exercise the record says you didn't do, and it
    /// would have nowhere to be read back. It goes with the sets.
    private func pruneNotes() {
        let trained = Set(session.sets.filter(\.isCompleted).map(\.catalogID))
        for note in session.exerciseNotes where note.isEmpty || !trained.contains(note.catalogID) {
            context.delete(note)
        }
    }

    /// Cuts the link on any row left continuing a set that won't be in the
    /// record.
    ///
    /// A continuation is always built on top of a set that has already been
    /// logged, so this only comes up one way: the lifter takes that set back
    /// and leaves it taken back. `finish` then deletes it as an unlogged set,
    /// and the row underneath would survive as the exercise's first set still
    /// claiming it was taken on without rest from something that, as far as
    /// the record goes, never happened. It is a set on its own now, and the
    /// only honest thing left to say about it is nothing.
    private func unlinkOrphanedContinuations() {
        for set in session.sets where set.isContinuation {
            let keepsItsSet = session.sets.contains {
                $0.catalogID == set.catalogID && $0.setIndex < set.setIndex && $0.isCompleted
            }
            if !keepsItsSet { set.continuesPreviousSet = nil }
        }
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
        case .logSet(let id, let weightKg, let reps, let seconds, let loggedAt):
            guard let set = session.sets.first(where: { $0.id == id }) else { return true }
            set.weightKg = weightKg
            set.reps = reps
            if set.tracking == .duration { set.seconds = seconds }
            complete(set,
                     restSeconds: planItem(for: set.catalogID)?.resolvedRestSeconds,
                     at: WatchCommand.loggedMoment(loggedAt))
            return true

        case .undoSet(let id):
            guard let set = session.sets.first(where: { $0.id == id }) else { return true }
            uncomplete(set)
            return true

        case .announceStart(let id, let moment):
            guard let set = session.sets.first(where: { $0.id == id }) else { return true }
            announceStart(set, at: moment)
            return true

        case .cancelStart(let id):
            guard let set = session.sets.first(where: { $0.id == id }) else { return true }
            cancelStart(set)
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

// MARK: - What became of an offer

/// What the lifter did with a load offer.
///
/// It is an autoregulation signal, and the reason the effort question is worth
/// asking at all. Told there is a rung above this one, some lifters take it
/// every time and some never do, and those two need coaching in opposite
/// directions. Nothing else in this record says which is which: the weights
/// alone can't, because a lifter who was never offered anything and a lifter
/// who turned every offer down both just look like somebody who stayed put.
///
/// Two words, because the app can honestly tell two things apart. Tapping the
/// cross and simply logging the next set both mean the offer was made and the
/// weight stayed where it was; what separates them is how deliberate the
/// refusal felt, and a phone on a bench cannot see that. Splitting them would
/// hand a reader a distinction between a considered no and not having noticed
/// which the data does not support — and they would believe it, because it
/// would be sitting in the file looking like a measurement.
///
/// Two outcomes deliberately record nothing at all. An offer taken and then
/// undone leaves no trace: `undoTakenNudge` puts every weight back verbatim and
/// stands the offer back up, and a record that outlived that would be the only
/// thing in the app still claiming the button was pressed. And an offer still
/// standing when the session ends is not a decline — `finish` deletes the sets
/// it would have moved, so nobody lifted anything at either weight and there is
/// no decision to report. Both leave the set with no key at all, exactly like
/// the sets that were never offered anything, which is what they are.
enum LoadNudgeOutcome: String, Sendable {
    /// Taken: every set of that exercise still to come moved onto the new rung.
    case taken
    /// Not taken: the cross, or the next set logged at the weight that stood.
    case declined
}
