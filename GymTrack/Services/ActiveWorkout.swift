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
        session.recordPlan(of: day)
        context.insert(session)

        for row in openingRows(for: day, history: history) {
            let set = SetLog(
                catalogID: row.item.catalogID,
                exerciseName: row.item.name,
                exerciseOrder: row.exerciseIndex,
                setIndex: row.setIndex,
                weightKg: row.weightKg,
                reps: row.reps,
                seconds: row.seconds,
                targetRepsLow: row.item.targetRepsLow,
                targetRepsHigh: row.item.targetRepsHigh,
                tracking: row.item.tracking
            )
            set.session = session
            context.insert(set)
        }
        // A plan may prescribe the same catalog exercise in several slots.
        // The logger and watch treat it as one exercise, so those rows must
        // follow one another with unique indices before either screen sees it.
        session.normalizeExerciseSlots()
        return session
    }

    /// One row as a day opens: its slot, and the numbers the progression
    /// offers for it.
    struct OpeningRow {
        let item: PlanItem
        let exerciseIndex: Int
        let setIndex: Int
        let weightKg: Double
        let reps: Int
        let seconds: Int
    }

    /// The rows `build` inserts, worked out without inserting anything. The
    /// past-workout sheet offers the same numbers, and a draft held in the
    /// store would be a session a cancel or a force-quit leaves behind.
    @MainActor
    static func openingRows(for day: PlanDay, history: [WorkoutSession]) -> [OpeningRow] {
        let items = day.orderedItems
        let lastTimes = lastPerformances(of: Set(items.map(\.catalogID)), in: history)
        var rows: [OpeningRow] = []
        for (exerciseIndex, item) in items.enumerated() {
            let last = lastPerformance(of: item, among: items, merged: lastTimes[item.catalogID] ?? [])
            let suggestion = TrainingStats.suggestion(for: item, lastSets: last)
            // Onto the machine's ladder: a target typed while the app was in
            // kilograms shouldn't open as 61.2 lb on a stack marked in fives.
            let startingWeight = item.loadScale.snap(
                kg: last.isEmpty ? item.targetWeightKg : suggestion.weightKg
            )

            for setIndex in 0..<max(1, item.targetSets) {
                let previous = setIndex < last.count ? last[setIndex] : last.last
                let startingReps = openingReps(for: suggestion, previous: previous, item: item)
                // Each row carries only the measure it is logged in. Every plan
                // slot holds a hold target, 45 s unless someone changed it, and
                // copied onto a squat it would be exported as a set that lasted
                // 45 seconds — a length nobody timed, read as measured.
                let isTimed = item.tracking == .duration
                rows.append(OpeningRow(
                    item: item,
                    exerciseIndex: exerciseIndex,
                    setIndex: setIndex,
                    weightKg: startingWeight,
                    reps: isTimed ? 0 : startingReps,
                    seconds: isTimed ? item.targetSeconds : 0
                ))
            }
        }
        return rows
    }

    /// Last time's high-end reps belong to last time's load. Whenever the
    /// suggestion moves the load, or holds it because last time didn't earn a
    /// move, every set starts at the count the suggestion names. Reusing last
    /// time's short count would open a rebuild at the reps it is meant to fix.
    private static func openingReps(for suggestion: TrainingStats.OverloadSuggestion,
                                    previous: SetLog?, item: PlanItem) -> Int {
        switch suggestion.action {
        case .increaseWeight, .deload, .repeatLoad:
            return suggestion.reps
        case .addReps, .firstTime:
            return previous?.reps ?? item.targetRepsLow
        }
    }

    /// What this slot of the day did last time.
    ///
    /// A day can prescribe one movement twice, a heavy top set and a lighter
    /// back-off say. Reading the exercise's whole last performance for both
    /// would give them one suggestion and one load, and the back-off would
    /// open at the top set's weight. So a repeated slot reads only its own
    /// share of last time's sets, and progresses from its own numbers.
    private static func lastPerformance(of item: PlanItem, among items: [PlanItem],
                                        merged last: [SetLog]) -> [SetLog] {
        let layout = items.filter { $0.catalogID == item.catalogID }
        guard layout.count > 1, let position = layout.firstIndex(where: { $0.id == item.id })
        else { return last }
        return slotShare(of: last, position: position, layout: layout)
    }

    /// One slot's share of an exercise's merged last performance.
    static func slotShare(of last: [SetLog], position: Int, layout: [PlanItem]) -> [SetLog] {
        zip(last, slotPositions(of: last, layout: layout))
            .filter { $0.1 == position }
            .map(\.0)
    }

    /// `TrainingStats.lastPerformance` for several exercises off one walk of
    /// the history. Asking it once per exercise sorted every finished session
    /// again for each one, so opening a session with ten exercises paid for ten
    /// sorts of a history that only grows. This sorts once, reads newest first,
    /// and stops as soon as every exercise asked about has been found; what it
    /// answers for each is what the one-at-a-time call answers.
    static func lastPerformances(of catalogIDs: Set<String>, in history: [WorkoutSession],
                                 excluding sessionID: UUID? = nil) -> [String: [SetLog]] {
        var wanted: [String: [String]] = [:]
        for id in catalogIDs { wanted[ExerciseCatalog.canonicalID(for: id), default: []].append(id) }
        var found: [String: [SetLog]] = [:]
        let candidates = history
            .filter { $0.id != sessionID && !$0.isActive }
            .sorted { $0.startedAt > $1.startedAt }
        for session in candidates where found.count < wanted.count {
            let efforts = session.effortSets
            for canonical in wanted.keys where found[canonical] == nil {
                let sets = efforts
                    .filter { ExerciseCatalog.canonicalID(for: $0.catalogID) == canonical }
                    .sorted(by: SetLog.precedesInSession)
                if !sets.isEmpty { found[canonical] = sets }
            }
        }
        var result: [String: [SetLog]] = [:]
        for (canonical, ids) in wanted {
            for id in ids { result[id] = found[canonical] ?? [] }
        }
        return result
    }

    /// Which of the day's slots each of one exercise's effort rows came from,
    /// given in session order.
    ///
    /// `normalizeExerciseSlots` folds repeated slots into one run so the
    /// logger and the wrist see a single exercise, and no row names its slot
    /// after that. Two things survive: the rep range each row was built with,
    /// and the day's own layout of how many sets each slot holds. A change of
    /// range starts the next slot, so a set skipped in the first slot can't
    /// pull the second slot's work into it. Where neighbouring slots share a
    /// range, the count decides. A row that fits no slot, added on the day or
    /// logged before ranges were kept, stays with the slot it follows.
    static func slotPositions(of rows: [SetLog], layout: [PlanItem]) -> [Int] {
        var slot = 0
        var used = 0
        return rows.map { row in
            while slot + 1 < layout.count {
                let fitsThis = hasRange(of: layout[slot], row)
                let fitsNext = hasRange(of: layout[slot + 1], row)
                let isFull = used >= max(1, layout[slot].targetSets)
                guard fitsNext && (!fitsThis || isFull) else { break }
                slot += 1
                used = 0
            }
            used += 1
            return slot
        }
    }

    private static func hasRange(of item: PlanItem, _ row: SetLog) -> Bool {
        row.targetRepsLow == item.targetRepsLow && row.targetRepsHigh == item.targetRepsHigh
    }

    /// The rows after `set` that belong to the same plan slot, in order.
    ///
    /// A session with no plan behind it, or whose day no longer exists, has
    /// one slot per exercise, which is what logging has always assumed.
    static func laterRowsInSlot(of set: SetLog, in session: WorkoutSession,
                                context: ModelContext) -> [SetLog] {
        laterRowsInSlot(of: set, in: session,
                        layout: slotLayout(of: set.catalogID, in: session, context: context))
    }

    /// The same, for a caller that already holds the day's slots.
    static func laterRowsInSlot(of set: SetLog, in session: WorkoutSession,
                                layout: [PlanItem]) -> [SetLog] {
        guard let place = slotPlace(of: set, in: session, layout: layout) else { return [] }
        return place.rows.indices
            .filter { $0 > place.index && place.slots[$0] == place.slots[place.index] }
            .map { place.rows[$0] }
    }

    /// Where a row sits among its exercise's working rows and their slots.
    /// Nil for a row that isn't one of them, such as a drop underneath.
    static func slotPlace(of set: SetLog, in session: WorkoutSession, layout: [PlanItem])
        -> (rows: [SetLog], slots: [Int], index: Int)? {
        let rows = session.sets
            .filter { $0.catalogID == set.catalogID && !$0.isContinuation }
            .sorted(by: SetLog.precedesInSession)
        guard let index = rows.firstIndex(where: { $0.id == set.id }) else { return nil }
        return (rows, slotPositions(of: rows, layout: layout), index)
    }

    /// The day's slots for one exercise, in the order the session was built.
    private static func slotLayout(of catalogID: String, in session: WorkoutSession,
                                   context: ModelContext) -> [PlanItem] {
        guard let dayID = session.planDayID,
              let day = try? context.fetch(FetchDescriptor<PlanDay>(
                predicate: #Predicate { $0.id == dayID })).first
        else { return [] }
        return day.orderedItems.filter { $0.catalogID == catalogID }
    }
}

extension Notification.Name {
    /// Posted on the main thread once a workout has been finished and saved,
    /// from the phone's Finish and from the wrist's alike. Anything that wants
    /// to react to a finished session listens for this instead of being called
    /// from two places that would each have to remember it.
    static let gymTrackWorkoutFinished = Notification.Name("GymTrack.workoutFinished")
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

    /// The finished sessions this one is read against, as they were when it
    /// began. A session deleted since stays in the array as a model with no
    /// context, so nothing reads it directly: `pruneDeletedHistory` runs first.
    @ObservationIgnored private var history: [WorkoutSession]

    /// The plan prescriptions behind this session, keyed by exercise. Resolved
    /// once — the logging view asks for these on every card render.
    private var prescriptions: [String: PlanItem] = [:]

    /// Every slot the day gives each exercise, in day order. `prescriptions`
    /// keeps only the first of them, which is all a card needs for an exercise
    /// that appears once; a movement repeated for a top set and a back-off has
    /// a prescription, a history and an offer per slot.
    private var slotLayouts: [String: [PlanItem]] = [:]

    /// Last session's sets per exercise, likewise resolved once. Filled on
    /// first ask rather than observed: `lastPerformance(for:)` refills it from
    /// inside a view body when a session has been deleted, and a write to
    /// something the body is watching from there is the loop SwiftUI warns of.
    @ObservationIgnored private var lastPerformances: [String: [SetLog]] = [:]

    /// Where this logger keeps what it would otherwise lose to a relaunch; see
    /// `LoggerMemoryStore`. Tests hand it a suite of their own.
    private let memory: LoggerMemoryStore

    /// What was last written to `memory`, so a save that changed none of it
    /// costs no write.
    @ObservationIgnored private var storedMemory: LoggerMemory?

    /// Set once the session is finished or discarded. A save that lands after
    /// that must not write the memory back, or the key outlives its session.
    @ObservationIgnored private var isClosed = false

    init(session: WorkoutSession, context: ModelContext, history: [WorkoutSession],
         memory: LoggerMemoryStore = .standard) {
        self.session = session
        self.context = context
        self.memory = memory
        self.history = history.filter { $0.id != session.id }

        if session.isActive && session.normalizeExerciseSlots() {
            try? context.save()
        }

        if let dayID = session.planDayID,
           let day = (try? context.fetch(FetchDescriptor<PlanDay>(
               predicate: #Predicate { $0.id == dayID })))?.first {
            prescriptions = Dictionary(day.orderedItems.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
            slotLayouts = Dictionary(grouping: day.orderedItems, by: \.catalogID)
        }
        lastPerformances = SessionFactory.lastPerformances(
            of: Set(session.sets.map(\.catalogID)), in: self.history, excluding: session.id
        )
        restoreLoggerMemory()

        // A rest starting, being extended or running out changes what the Lock
        // Screen should say, and none of those go through `save()`.
        //
        // The widgets too. They used to be left out, and `complete` writes the
        // widget snapshot a moment *before* it starts the rest — so the Today
        // widget never once showed a rest, and a rest skipped from the Lock
        // Screen or the wrist went on counting down on the Home Screen.
        restTimer.onChange = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.pushLiveActivity()
                self.pushToWatch()
                WidgetPublisher.updateSession(self)
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

    /// Sets done and sets planned, counted as efforts; see
    /// `WorkoutSession.effortCount`.
    var completedCount: Int { session.effortSets.count }
    var totalCount: Int { session.effortCount }

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var volumeKg: Double { session.totalVolumeKg }

    /// The exercise holding the next unlogged set — what the session is "on".
    /// Normally the first one that isn't finished, unless the lifter has picked
    /// a different one to work on.
    var currentGroup: SessionExerciseGroup? { currentGroup(in: groups) }

    /// `currentGroup` over groups the caller already has.
    ///
    /// `groups` is worked out from the session's sets on every read (group by
    /// exercise, sort each, sort the lot), and the logger asks "which exercise
    /// is current?" once per queue row as well as for the card and the scroll.
    /// A view takes `groups` once per pass and asks here, so a stepper step or
    /// a heart-rate merge costs one build rather than two dozen. Nothing is
    /// cached between passes, so no write path has to remember to invalidate
    /// anything and a log, undo, add, remove or reorder can never be answered
    /// from the sets as they were.
    func currentGroup(in groups: [SessionExerciseGroup]) -> SessionExerciseGroup? {
        SessionPosition(session, groups: groups).currentGroup
    }

    /// Moves the session onto a different exercise — a superset, or a machine
    /// that was taken when its turn came round. This is "I am lifting this
    /// now": the wrist, the Lock Screen and the dock all follow it.
    func focus(on catalogID: String) {
        let known = groups.contains { $0.catalogID == catalogID }
        session.preferredExerciseID = known ? catalogID : nil
        // Somebody who says they are lifting this is no longer about to lift
        // the set they announced on another exercise, whether the machine was
        // taken or they simply changed their mind. Left standing, that start
        // paired with whatever log finally closed the set, minutes later, and
        // the record said the set took as long as the detour.
        if known { forget(startsOf: session.dropStarts(awayFrom: catalogID)) }
        save()
    }

    /// A tap on an exercise in the phone's queue, which means one of two
    /// different things. An unfinished exercise is the lifter choosing what to
    /// lift next, so the session moves onto it. A finished one is only being
    /// looked at — to rate a set, change a note, fix a number — and moves
    /// nothing.
    ///
    /// Both used to go through `focus`. `currentGroup` passes over a finished
    /// pick, so looking back at the first exercise threw away the one picked
    /// out of order and fell back to plan order: the wrist, the Lock Screen and
    /// the dock jumped to an exercise nobody was doing, and a set logged from
    /// the wrist without looking went onto it.
    ///
    /// Returns true when the tap is a review, which the logger shows beside the
    /// working position rather than in place of it.
    @discardableResult
    func openFromQueue(_ catalogID: String) -> Bool {
        guard let group = groups.first(where: { $0.catalogID == catalogID }) else { return false }
        if group.isComplete { return true }
        focus(on: catalogID)
        return false
    }

    /// The set the logger has expanded, i.e. the one about to be performed.
    var nextSet: SetLog? { SessionPosition(session, groups: groups).nextSet }

    /// What `nextSet` is called on its card — efforts, not rows; see
    /// `SessionExerciseGroup.number(of:)`.
    var nextSetNumber: Int { SessionPosition(session, groups: groups).nextSetNumber }

    /// `nextSetNumber` for the group the caller already holds, so a caller
    /// that needs the group as well does not build the groups a second time.
    func nextSetNumber(in group: SessionExerciseGroup) -> Int {
        guard let next = group.sets.first(where: { !$0.isCompleted }) else { return group.effortCount }
        return group.number(of: next)
    }

    /// How many sets the exercise that's up holds, counted the same way.
    var currentSetTotal: Int { SessionPosition(session, groups: groups).currentSetTotal }

    /// "60 kg × 8–12" — the prescription for the set that's up.
    var nextTargetLabel: String { SessionPosition(session, groups: groups).nextTargetLabel }

    /// The exercise queued behind the current one.
    var upNextName: String { SessionPosition(session, groups: groups).upNextName }

    /// What the same exercise looked like last time, for the "last: …" hints.
    ///
    /// The sets are read from a session that can be deleted while this one runs,
    /// from the history screen behind a minimised logger. A hint naming a lift
    /// that no longer exists is worse than no hint, so a remembered answer whose
    /// sets have gone is worked out again from what is left.
    func lastPerformance(for catalogID: String) -> [SetLog] {
        if let cached = lastPerformances[catalogID], !cached.contains(where: \.isGoneFromStore) {
            return cached
        }
        pruneDeletedHistory()
        let found = TrainingStats.lastPerformance(of: catalogID, in: history, excluding: session.id)
        lastPerformances[catalogID] = found
        return found
    }

    /// Lets go of every past session that has been deleted since this one began.
    ///
    /// The array holds the models the store handed over, and a delete leaves
    /// them behind still answering with their old values, so a mistyped 500 kg
    /// bench survived its own deletion as a "last time" hint and as the record
    /// the next bench had to beat. What was worked out from them goes too:
    /// the record baseline, and the remembered hints, which are asked for again.
    private func pruneDeletedHistory() {
        guard history.contains(where: \.isGoneFromStore) else { return }
        history.removeAll { $0.isGoneFromStore }
        recordBaseline = nil
        lastPerformances = [:]
    }

    /// The prescription behind an exercise, while the plan still has it.
    ///
    /// The cache is filled once, so an exercise taken out of the day mid-session
    /// stays in it as a deleted model — and the logger went on reading its rest
    /// and rep range, which SwiftData is free to trap on. Once it's gone from the
    /// plan the session treats it like an exercise added on the day.
    func planItem(for catalogID: String) -> PlanItem? {
        guard let item = prescriptions[catalogID], !item.isDeleted, item.modelContext != nil else { return nil }
        return item
    }

    // MARK: - Slots

    /// The plan slots behind an exercise, or none once any of them has left the
    /// plan. A layout with a hole in it would put every later row in the wrong
    /// slot, so the session treats the exercise as a single slot, the way it
    /// treats one added on the day.
    private func slotLayout(of catalogID: String) -> [PlanItem] {
        guard let layout = slotLayouts[catalogID],
              layout.allSatisfy({ !$0.isDeleted && $0.modelContext != nil }) else { return [] }
        return layout
    }

    /// Which slot of its exercise a working row belongs to. A row that isn't
    /// one, a drop underneath, answers with the slot of the set it continues.
    private func slot(of set: SetLog) -> Int {
        let layout = slotLayout(of: set.catalogID)
        var anchor = set
        if set.isContinuation,
           let parent = session.sets
               .filter({ $0.catalogID == set.catalogID && !$0.isContinuation && SetLog.precedesInSession($0, set) })
               .max(by: SetLog.precedesInSession) {
            anchor = parent
        }
        guard let place = SessionFactory.slotPlace(of: anchor, in: session, layout: layout) else { return 0 }
        return place.slots[place.index]
    }

    /// The prescription behind this set's own slot. `planItem(for:)` by
    /// exercise gives the first slot's, which for the back-off of a repeated
    /// movement is the top set's rest and the top set's rep range.
    func planItem(for set: SetLog) -> PlanItem? {
        let layout = slotLayout(of: set.catalogID)
        guard layout.count > 1 else { return planItem(for: set.catalogID) }
        let position = slot(of: set)
        return layout.indices.contains(position) ? layout[position] : nil
    }

    /// What this set's slot did last time, so a back-off is read against last
    /// time's back-off rather than against the exercise's sets pooled.
    func lastPerformance(for set: SetLog) -> [SetLog] {
        let merged = lastPerformance(for: set.catalogID)
        let layout = slotLayout(of: set.catalogID)
        guard layout.count > 1 else { return merged }
        return SessionFactory.slotShare(of: merged, position: slot(of: set), layout: layout)
    }

    /// Last time's set opposite this one, paired by position within its slot,
    /// and nothing for a row that continued another.
    func previousSet(for set: SetLog) -> SetLog? {
        guard !set.isContinuation,
              let place = SessionFactory.slotPlace(of: set, in: session, layout: slotLayout(of: set.catalogID))
        else { return nil }
        let position = place.rows[..<place.index].indices.filter { place.slots[$0] == place.slots[place.index] }.count
        let last = lastPerformance(for: set)
        return position < last.count ? last[position] : nil
    }

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
        // Logged inside the count-in, so the start it was counting towards
        // never came — whatever happened under the bar, it didn't begin at the
        // moment on the set. Kept, it would be a set that began after it ended:
        // a moment nobody lived, and a negative length for anything reading
        // the pair. The rest that tap stopped isn't put back either. It was the
        // rest before this set, and this set is now logged; whatever follows
        // is the next rest, which is why `restCancelledByStart` goes below.
        //
        // And a start that has waited too long for its log, or that another
        // set's log has overtaken, is not this set's start any more: see
        // `SetLog.startStillDescribes` and `WorkoutSession.dropOvertakenStarts`.
        session.settleStarts(afterLogging: set, at: moment)
        lastLoggedSetID = set.id
        settleOffer(answeredBy: set)
        // The rest this set's announcement cut short can no longer be put
        // back: the set it would have been counting down to has been done.
        // The same for the rest a continuation cut short, which was the rest
        // before a set that has since been logged over it.
        restCancelledByStart = nil
        restCancelledByContinuation = nil
        carryLoadForward(from: set)
        save()

        if isPersonalRecord(set) {
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

    /// Logging the next working set of the exercise an offer was made on is an
    /// answer to it whether or not anybody touched the offer: you took the
    /// weight you took. Lifted at the offered rung it was taken, by hand rather
    /// than by the button; at any other weight it was not.
    ///
    /// Nothing else answers it. A superset partner's set, or a drop row of the
    /// exercise itself, says nothing about what its next working set should
    /// weigh, and filing a decline for one would put a refusal on the record
    /// before a single set the offer was about had been lifted. The offer keeps
    /// standing over its own card until one of those sets is logged.
    ///
    /// What the answer replaced is kept, so that undoing the set puts the offer
    /// and the record back exactly as they were — see `takeBackAnswer`.
    private func settleOffer(answeredBy set: SetLog) {
        let standing = pendingNudge(for: set.catalogID).flatMap { offer($0, covers: set) ? $0 : nil }
        let taken = takenNudge(for: set.catalogID).flatMap { offer($0.nudge, covers: set) ? $0 : nil }
        guard standing != nil || taken != nil else { return }

        var answer = SettledOffer(loggedSetID: set.id, standing: standing, taken: taken)
        if let standing, let subject = subject(of: standing) {
            answer.priorOutcome = subject.loadNudgeOutcome
            answer.priorToKg = subject.loadNudgeToKg
            let outcome: LoadNudgeOutcome = isOfferedRung(set.weightKg, of: standing, on: set)
                ? .taken : .declined
            subject.recordLoadNudge(outcome, toKg: standing.toKg)
            answer.recorded = outcome
            standingOffers.removeAll { $0.setID == standing.setID }
        }
        // The chance to undo a take ends where the sets it moved start being
        // lifted: undoing it after that would move a weight off a finished set.
        if let taken { openTakes.removeAll { $0.nudge.setID == taken.nudge.setID } }

        let subjectID = (standing ?? taken?.nudge)?.setID
        settledOffers.removeAll { ($0.standing ?? $0.taken?.nudge)?.setID == subjectID }
        settledOffers.append(answer)
    }

    /// Whether a logged weight is the rung an offer named. Compared on the
    /// equipment's own scale, so a load typed in pounds and one stepped to by
    /// the offer are the same rung even where the kilogram conversions differ
    /// in the last bit.
    private func isOfferedRung(_ kg: Double, of nudge: LoadNudge, on set: SetLog) -> Bool {
        let scale = set.loadScale
        return abs(scale.display(kg) - scale.display(nudge.toKg)) < 0.001
    }

    /// The other half of `settleOffer`: the set that answered an offer is being
    /// taken back, so the answer goes with it. The record returns to what it
    /// said before, and the offer — or the undo of having taken it — stands
    /// again, recomputed so it counts the sets actually left.
    ///
    /// Only where nothing newer has spoken since. A subject re-rated in the
    /// meantime has a newer offer or none, and restoring the old one would
    /// overwrite a decision the lifter made after this one.
    private func takeBackAnswer(of set: SetLog) {
        guard let index = settledOffers.firstIndex(where: { $0.loggedSetID == set.id }) else { return }
        let answer = settledOffers.remove(at: index)

        if let standing = answer.standing, let recorded = answer.recorded,
           let subject = subject(of: standing), subject.isCompleted,
           subject.loadNudgeOutcome == recorded, subject.loadNudgeToKg == standing.toKg {
            if let prior = answer.priorOutcome, let priorToKg = answer.priorToKg {
                subject.recordLoadNudge(prior, toKg: priorToKg)
            } else {
                subject.clearLoadNudge()
            }
            if pendingNudge(for: standing.catalogID) == nil, let again = nudge(after: subject),
               again.feel == standing.feel, again.toKg == standing.toKg {
                standingOffers.append(again)
            }
        }
        if let taken = answer.taken, takenNudge(for: taken.nudge.catalogID) == nil,
           let subject = subject(of: taken.nudge), subject.isCompleted {
            openTakes.append(taken)
        }
    }

    /// An offer the logger settled without a tap, and what it overwrote.
    private struct SettledOffer {
        /// The set whose logging answered it.
        let loggedSetID: UUID
        /// The offer that was standing, if one was.
        let standing: LoadNudge?
        /// The undo of a take that was still open, if one was.
        let taken: TakenNudge?
        /// What the log filed on the subject, so a later decision is told apart.
        var recorded: LoadNudgeOutcome?
        /// The subject's record before the log, put back verbatim on undo.
        var priorOutcome: LoadNudgeOutcome?
        var priorToKg: Double?
    }

    /// One per subject at most: a newer answer about the same set supersedes
    /// the older one, which has nothing left on the record to take back.
    @ObservationIgnored private var settledOffers: [SettledOffer] = []

    /// Mirrors the load just used onto the remaining sets of the same exercise.
    /// Without this you re-dial the weight for every set of every exercise.
    ///
    /// A row that continued the set above it carries nothing forward: its
    /// weight was chosen to be lower, for that row, and pushing it down the
    /// card would leave the working sets still to come sitting at the drop
    /// weight — the lifter would take one drop and find the rest of the
    /// exercise quietly deloaded.
    ///
    /// The load stops at the end of the set's plan slot. A day that repeats a
    /// movement prescribes each slot its own load, and the first set of a top
    /// set carried onto the back-off would erase what the plan asked for.
    ///
    /// What each row held before is kept, so that taking the set back can put
    /// it there again — see `restorePrefill`.
    private func carryLoadForward(from set: SetLog) {
        guard !set.isContinuation else { return }
        let overwritten = Prefill.carry(from: set,
                                        onto: SessionFactory.laterRowsInSlot(of: set, in: session,
                                                                             layout: slotLayout(of: set.catalogID)))
        carriedPrefills[set.id] = overwritten.isEmpty ? nil : overwritten
    }

    /// A row's numbers before a logged set carried its own onto it, and what
    /// it carried. Shared with the wrist's headless path, which carries and
    /// takes back a load on its own without a logger: two copies of the rule
    /// would let the phone and the watch disagree about the same undo.
    struct Prefill {
        let kg: Double
        let seconds: Int
        let carriedKg: Double
        let carriedSeconds: Int

        /// Copies the set's load onto each unlogged row and returns what those
        /// rows held, for the rows it actually changed.
        static func carry(from set: SetLog, onto rows: [SetLog]) -> [UUID: Prefill] {
            var overwritten: [UUID: Prefill] = [:]
            for other in rows where !other.isCompleted {
                let before = Prefill(kg: other.weightKg, seconds: other.seconds,
                                     carriedKg: set.weightKg, carriedSeconds: set.seconds)
                other.weightKg = set.weightKg
                if other.tracking == .duration { other.seconds = set.seconds }
                if before.kg != other.weightKg || (other.tracking == .duration && before.seconds != other.seconds) {
                    overwritten[other.id] = before
                }
            }
            return overwritten
        }

        /// Puts the rows a carry changed back to what they held. A row whose
        /// numbers have been touched since is the lifter's own now and stays as
        /// typed, so only a row still holding exactly what was carried moves.
        static func restore(_ memory: [UUID: Prefill], onto rows: [SetLog]) {
            for row in rows where !row.isCompleted {
                guard let before = memory[row.id], row.weightKg == before.carriedKg else { continue }
                row.weightKg = before.kg
                if row.tracking == .duration, row.seconds == before.carriedSeconds { row.seconds = before.seconds }
            }
        }
    }

    /// What each logged set's carry overwrote, by the set that carried.
    /// Kept across a relaunch by `LoggerMemoryStore`, or a set taken back after
    /// one would leave the rows below it holding a weight nobody lifted.
    /// Nothing here is exported, since unlogged rows are dropped when the
    /// session closes and the store goes with them.
    @ObservationIgnored private var carriedPrefills: [UUID: [UUID: Prefill]] = [:]

    /// The other half of `carryLoadForward`: the set is being taken back, so
    /// the rows it prefilled go back to what they held. Otherwise the next row
    /// of a set that never happened opens at its weight, as though it had been
    /// lifted. A row whose numbers have been touched since is the lifter's own
    /// now and stays as typed.
    private func restorePrefill(carriedBy set: SetLog) {
        guard let memory = carriedPrefills.removeValue(forKey: set.id) else { return }
        Prefill.restore(memory, onto: Array(session.sets))
    }

    func uncomplete(_ set: SetLog) {
        // A logged drop or cluster underneath goes too, last one first. Left
        // logged, it went into the record as a lift taken without rest off a set
        // that was never done, and a re-log of the set above stamped the parent
        // after the row claiming to continue it. Blocking the undo instead would
        // leave a button that does nothing mid-set. The rows keep their numbers,
        // so logging both again is two taps. Only while this set is logged: a
        // repeated undo must not take back a lift logged since.
        let carried = set.isCompleted ? session.loggedContinuations(below: set) : []
        // Read before `takeBack` clears it. The rest is the last logged set's,
        // and only a rest that belonged to one of the sets going is taken away
        // with them. Undoing an old set through the review path while another
        // exercise's countdown ran used to stop that one too, on the phone, on
        // the Lock Screen and on the wrist, and cancel its "Rest over".
        let goingSetIDs = ([set] + carried).map(\.id)
        let restBelongedToUndone = lastLoggedSetID.map { goingSetIDs.contains($0) } ?? false
        for row in carried.reversed() { takeBack(row) }
        takeBack(set)
        // `complete` is what started that rest; this is the other half of it.
        if restBelongedToUndone { restTimer.stop() }
        // A rest a continuation cut short belonged to the set it was
        // continuing; with that set taken back it isn't worth putting back.
        if let cut = restCancelledByContinuation, let owner = cut.ownerID, goingSetIDs.contains(owner) {
            restCancelledByContinuation = nil
        }
        save()
        Haptics.tick()
    }

    /// Everything one set gained by being logged, for `uncomplete`, which runs
    /// it on the set and on every logged row carrying on from it.
    private func takeBack(_ set: SetLog) {
        // Everything the set itself gained by being logged — see `SetLog.unlog`,
        // which is also what the wrist's own undo runs so the two can't drift.
        set.unlog()
        recentPRs.remove(set.id)
        if lastLoggedSetID == set.id { lastLoggedSetID = nil }
        standingOffers.removeAll { $0.setID == set.id }
        // Taking the set back takes back everything answering for it did,
        // including a weight change its answer put on the sets underneath.
        if let taken = openTakes.first(where: { $0.nudge.setID == set.id }) { restoreWeights(of: taken) }
        // An offer this set answered by being logged is unanswered again. And
        // an answer about this set's own offer has nothing left to restore:
        // `unlog` has just cleared the record it was kept to put back.
        takeBackAnswer(of: set)
        settledOffers.removeAll { ($0.standing ?? $0.taken?.nudge)?.setID == set.id }
        restorePrefill(carriedBy: set)
    }

    func isPR(_ set: SetLog) -> Bool { recentPRs.contains(set.id) }

    /// Everything a set logged today has to beat from earlier sessions, per
    /// exercise. Those sessions are finished and don't change while this one
    /// runs, so the history is walked once, on the first set logged, instead
    /// of in full on every tap of *Log set*.
    @ObservationIgnored private var recordBaseline: [String: [SetLog]]?

    private func isPersonalRecord(_ set: SetLog) -> Bool {
        // The baseline is the past as it was when it was built. A session
        // deleted since, a mistyped 500 kg bench, would otherwise still be the
        // record no lift today could beat.
        pruneDeletedHistory()
        let baseline = recordBaseline ?? TrainingStats.recordCandidates(in: history)
        recordBaseline = baseline
        let catalogID = ExerciseCatalog.canonicalID(for: set.catalogID)
        let today = session.sets.filter { ExerciseCatalog.canonicalID(for: $0.catalogID) == catalogID }
        return TrainingStats.isPersonalRecord(set, among: (baseline[catalogID] ?? []) + today)
    }

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
    ///
    /// Settled rather than sent per step. Each save re-encodes the whole
    /// session for the watch, updates the Live Activity and restamps the
    /// widgets, and a weight is dialled in runs — a key held down steps it
    /// several times a second. The screen is already right, since the row wrote
    /// the number itself; everything else only needs the one it settles on, a
    /// beat after the thumb stops. Any other save lands first and takes this
    /// one with it, so a set logged mid-run still goes out with its numbers.
    /// The most a force-quit inside that beat can cost is the last step dialled
    /// onto a set nobody has logged yet — or, for a logged set being corrected
    /// through `correct`, the run of steps since the thumb last rested, which
    /// leaves that set holding the number it held before them.
    func numbersChanged() {
        pendingEdit?.cancel()
        pendingEdit = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Fixes the numbers on a set already logged: the 80 typed for the 100
    /// that was lifted, the 8 for the 10.
    ///
    /// Only the numbers move. When the set was logged, when it began, how it
    /// felt and the heart rate read through it are facts about the moment, and
    /// a typo is a fact about the numbers. Undo then Log used to be the only
    /// way to fix one, and it rewrote all of them: the lift stamped at the
    /// moment of the correction and sorted after whatever had been logged
    /// since, so the rests either side of it described gaps nobody took; its
    /// start, rating and heart rate gone; and a rest counting down that nobody
    /// was taking.
    ///
    /// Seconds are written only for a timed set, as logging does. The record
    /// question is asked again of the whole exercise, because a corrected
    /// number can make or unmake a record on this set and moves the bar every
    /// set logged after it had to clear. An offer still standing on this set is
    /// withdrawn without being recorded: it was read off numbers that weren't
    /// the lift, so nobody turned down anything real.
    func correct(_ set: SetLog, weightKg: Double, reps: Int, seconds: Int) {
        guard set.isCompleted, weightKg.isFinite else { return }
        set.weightKg = max(0, weightKg)
        set.reps = max(0, reps)
        if set.tracking == .duration { set.seconds = max(0, seconds) }
        reassessRecords(for: set.catalogID)
        standingOffers.removeAll { $0.setID == set.id }
        // Not left to the settle a beat from now: a relaunch inside it would
        // stand back up an offer that was read off the number just corrected.
        persistLoggerMemory()
        numbersChanged()
    }

    /// Asks the record question again of every set of one exercise logged
    /// today, after one of them changed underneath the answers already given.
    private func reassessRecords(for catalogID: String) {
        let exercise = ExerciseCatalog.canonicalID(for: catalogID)
        for logged in session.sets
        where logged.isCompleted && ExerciseCatalog.canonicalID(for: logged.catalogID) == exercise {
            if isPersonalRecord(logged) {
                recentPRs.insert(logged.id)
            } else {
                recentPRs.remove(logged.id)
            }
        }
    }

    @ObservationIgnored private var pendingEdit: Task<Void, Never>?

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

        // Only the measure this exercise is logged in: a row taken on from a
        // set made before sessions stopped seeding a hold time onto every row
        // would otherwise copy that unmeasured 45 s forward.
        let isTimed = set.tracking == .duration
        let next = SetLog(
            catalogID: set.catalogID,
            exerciseName: set.exerciseName,
            exerciseOrder: set.exerciseOrder,
            setIndex: set.setIndex + 1,
            weightKg: set.weightKg,
            reps: isTimed ? 0 : set.reps,
            seconds: isTimed ? set.seconds : 0,
            // No rep range, because nobody prescribed one. The plan asks for
            // three sets of 6–10; it has nothing to say about what a lifter
            // does after the third one on the way back down, and a range copied
            // off the set above would have the card demand 6 reps of a drop and
            // the progression read it as a working set that fell short.
            targetRepsLow: 0,
            targetRepsHigh: 0,
            tracking: set.tracking
        )
        next.continuesPreviousSet = true
        next.session = session
        context.insert(next)

        // Kept for `removeContinuation`, on the same principle as
        // `restCancelledByStart`: a mis-tap costs nothing, including the
        // countdown that was on screen.
        if restTimer.isRunning, let endsAt = restTimer.endsAt {
            restCancelledByContinuation = (next.id, lastLoggedSetID, endsAt, restTimer.totalSeconds)
        }
        restTimer.stop()
        save()
        Haptics.log()
    }

    /// The rest that `continueSet` stopped, kept only long enough for the row to
    /// be taken back off. `rowID` is the continuation it belongs to and
    /// `ownerID` the set whose log started the rest. Not persisted, for the
    /// reason `restCancelledByStart` isn't.
    private var restCancelledByContinuation: (rowID: UUID, ownerID: UUID?, endsAt: Date, totalSeconds: Int)?

    /// Takes the row back off, the exact pair of `continueSet` — for a mis-tap,
    /// or an effort the lifter decided not to take further after all. Only
    /// while it holds nothing: once there are reps in it, removing it would
    /// delete a lift, and `separate` is the way out of that instead.
    func removeContinuation(_ set: SetLog) {
        guard set.isContinuation, !set.isCompleted else { return }
        // The countdown comes back where it was, as after `cancelStart`. Not
        // over a rest that is running now: something has started a newer one
        // since, and the old end would replace it. A rest that has run out in
        // the meantime is simply over, and `restore` puts nothing back for it.
        if let cut = restCancelledByContinuation, cut.rowID == set.id {
            restCancelledByContinuation = nil
            if !restTimer.isRunning {
                restTimer.restore(endingAt: cut.endsAt, totalSeconds: cut.totalSeconds)
            }
        }
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

    /// A tap on this phone's *Start set*. The set begins when the count-in
    /// runs out rather than under the thumb — see `SetLeadIn`.
    func announceStart(_ set: SetLog) {
        announceStart(set, at: SetLeadIn.start(forTapAt: .now))
    }

    /// Marks the moment the set begins. Everything the record gains comes from
    /// this one stamp: the rest before it stops being a guess with a set hidden
    /// inside it, and the set itself gets a length.
    ///
    /// Optional in the strongest sense — nothing here is required for a set to
    /// be logged, and a session where it's never touched behaves exactly as it
    /// did before this existed.
    ///
    /// - Parameter moment: when the set begins, with the count-in already in
    ///   it. Nothing here adds one: the phone's own tap goes through the
    ///   overload above, and the wrist passes the moment it stamped, because a
    ///   command sent out of range waits in a queue until the phone is nearby
    ///   again and stamping it on arrival would report a set that started in
    ///   the locker room.
    func announceStart(_ set: SetLog, at moment: Date) {
        guard !set.isCompleted, set.startedAt == nil else { return }
        // A start that has been sitting in the watch's delivery queue is kept:
        // the log that closes the set carries the wrist's clock too, so the
        // pair is true however long the two of them waited together. Only a
        // start from further ahead of this clock than the count-in explains is
        // refused, and that one is the two devices disagreeing about the time
        // rather than a moment — see `WatchCommand.isBelievableStart`.
        guard WatchCommand.isBelievableStart(moment) else { return }
        set.startedAt = moment
        // One set is under way at a time. A start announced on another set that
        // this one comes after was abandoned; see `dropOvertakenStarts`.
        forget(startsOf: session.dropOvertakenStarts(besides: set, at: moment))

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

    /// Un-says it, all the way back to never having tapped — during the
    /// count-in exactly as after it. The stamp goes, and the rest the tap cut
    /// short comes back exactly where it was — a mis-tap on a small control
    /// mid-workout has to cost nothing at all, including the countdown you were
    /// watching.
    func cancelStart(_ set: SetLog) {
        set.startedAt = nil
        if let cancelled = restCancelledByStart, cancelled.setID == set.id {
            restTimer.restore(endingAt: cancelled.endsAt, totalSeconds: cancelled.totalSeconds)
            restCancelledByStart = nil
        }
        save()
        Haptics.tick()
    }

    /// Lets go of the rest a dropped start had cut short. The set it would have
    /// counted down to is no longer being started, and a late cancel from the
    /// wrist would otherwise put that old countdown back over whatever the
    /// lifter is doing now.
    private func forget(startsOf setIDs: [UUID]) {
        if let cancelled = restCancelledByStart, setIDs.contains(cancelled.setID) {
            restCancelledByStart = nil
        }
    }

    /// How the set felt. The answer is acted on immediately rather than filed
    /// away for next week: that's the whole difference between a question with
    /// a point and a quiz.
    func rate(_ set: SetLog, feel: SetFeel) {
        // Only a lift can be rated. The effort strip and the wrist ask only
        // after a log, but an answer taken on a row nobody has lifted would be
        // exported with whatever set the row later became, and the offer it
        // made would move the sets to come on the strength of nothing.
        guard set.isCompleted else { return }
        // Tapping the answer it already holds takes it back, so the gesture
        // that answers the question also un-answers it.
        guard set.rpe != feel.rawValue else { return clearRating(set) }
        set.rpe = feel.rawValue
        forgetUntakenNudge(on: set)
        // Replaces only this exercise's own offer. In a superset the partner's
        // rating used to overwrite whatever was standing, and the offer on
        // the other card vanished without its answer ever being asked for.
        standingOffers.removeAll { $0.catalogID == set.catalogID }
        if let offered = nudge(after: set) { standingOffers.append(offered) }
        save()
        Haptics.tick()
    }

    /// Un-answers the question, all the way back to never having been asked.
    /// An offer the answer produced goes with it; a change already taken has
    /// its own undo, because that one moved real numbers.
    func clearRating(_ set: SetLog) {
        set.rpe = nil
        standingOffers.removeAll { $0.setID == set.id }
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

    /// The rows an offer is about: the working sets of its exercise after the
    /// one that was rated. The same rows are the ones taking it moves and the
    /// only ones whose logging answers it, so the two can't disagree about
    /// which sets the offer was for.
    ///
    /// A pending drop row is at the weight the lifter dialled it to, and says
    /// nothing about the working sets, so it is neither moved nor an answer.
    ///
    /// Only within the slot it was made in. A day that repeats a movement gives
    /// each slot its own load, and an offer read off the top set's answer must
    /// not move the back-off's sets, nor be answered by lifting one.
    private func offer(_ nudge: LoadNudge, covers row: SetLog) -> Bool {
        guard row.catalogID == nudge.catalogID, !row.isContinuation, row.setIndex > nudge.fromIndex,
              let subject = subject(of: nudge) else { return false }
        return SessionFactory.laterRowsInSlot(of: subject, in: session,
                                              layout: slotLayout(of: nudge.catalogID))
            .contains { $0.id == row.id }
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

    /// Every offer standing, at most one per exercise, oldest first. Kept per
    /// exercise so that rating one half of a superset leaves the other half's
    /// offer where it was.
    private var standingOffers: [LoadNudge] = []

    /// The offer standing on an exercise's card.
    func pendingNudge(for catalogID: String) -> LoadNudge? {
        standingOffers.first { $0.catalogID == catalogID }
    }

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

        // The slot's own sets: what the offer would move is what it counts.
        let remaining = SessionFactory.laterRowsInSlot(of: set, in: session,
                                                       layout: slotLayout(of: set.catalogID))
            .filter { !$0.isCompleted }
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

    /// Every take still open to undo, at most one per exercise. As with the
    /// standing offers, one exercise's take must not cost another its undo.
    private var openTakes: [TakenNudge] = []

    func takenNudge(for catalogID: String) -> TakenNudge? {
        openTakes.first { $0.nudge.catalogID == catalogID }
    }

    /// Takes the offer: every set of that exercise still to come moves onto the
    /// new rung.
    func apply(_ nudge: LoadNudge) {
        // A changed answer can offer another rung before the first take is
        // settled. Both taps are one undoable choice: keep the weight each row
        // had before either tap, or Undo would stop at the intermediate rung.
        var previous: [UUID: Double] = [:]
        if let taken = openTakes.first(where: { $0.nudge.setID == nudge.setID }) {
            previous = taken.previousKg
        }
        for set in session.sets where !set.isCompleted && offer(nudge, covers: set) {
            if previous[set.id] == nil { previous[set.id] = set.weightKg }
            set.weightKg = nudge.toKg
        }
        standingOffers.removeAll { $0.setID == nudge.setID }
        openTakes.removeAll { $0.nudge.catalogID == nudge.catalogID }
        let taken = previous.isEmpty ? nil : TakenNudge(nudge: nudge, previousKg: previous)
        if let taken { openTakes.append(taken) }
        // Only where something actually moved. An offer that found no sets left
        // to change was not taken — nothing happened — and saying it was would
        // put a rung on the record that nobody ever lifted.
        if taken != nil { subject(of: nudge)?.recordLoadNudge(.taken, toKg: nudge.toKg) }
        save()
        Haptics.log()
    }

    /// Puts every weight back where it was and stands the offer back up, so the
    /// screen reads exactly as it did before the button was pressed. One
    /// exercise's take, whichever card it is drawn on.
    func undoTakenNudge(_ taken: TakenNudge) {
        guard openTakes.contains(where: { $0.nudge.setID == taken.nudge.setID }) else { return }
        restoreWeights(of: taken)
        standingOffers.removeAll { $0.catalogID == taken.nudge.catalogID }
        standingOffers.append(taken.nudge)
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
    private func restoreWeights(of taken: TakenNudge) {
        for set in session.sets {
            guard let weight = taken.previousKg[set.id], !set.isCompleted else { continue }
            set.weightKg = weight
        }
        openTakes.removeAll { $0.nudge.setID == taken.nudge.setID }
    }

    /// Turns down one exercise's offer, whichever card it is drawn on.
    func dismissNudge(_ nudge: LoadNudge) {
        guard standingOffers.contains(where: { $0.setID == nudge.setID }) else { return }
        subject(of: nudge)?.recordLoadNudge(.declined, toKg: nudge.toKg)
        standingOffers.removeAll { $0.setID == nudge.setID }
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
            targetRepsHigh: template.targetRepsHigh,
            tracking: template.tracking
        )
        set.session = session
        context.insert(set)
        save()
        Haptics.tick()
    }

    /// Takes a set nobody has lifted off the card — the pair of `addSet`,
    /// undoing exactly what that did. See `removableSet(in:)` for which one.
    func removeLastSet(from group: SessionExerciseGroup) {
        guard let row = removableSet(in: group) else { return }
        context.delete(row)
        resequence(group.catalogID)
        save()
        Haptics.tick()
    }

    /// The row *Remove* would take, or nothing when there isn't one — which is
    /// also when the logger hides the button.
    ///
    /// Only a row nobody logged. This used to be whatever row was last, logged
    /// or not, so a slip reaching for *Add set* on a finished exercise opened
    /// for review erased the last set with its reps, rating, start and heart
    /// rate, one tap, no way back; and with set 2 taken back to fix it, Remove
    /// deleted the logged set 3 and left the empty set 2 in place. Erasing a
    /// lift goes through its undo first, where it is one deliberate step.
    ///
    /// A working set is preferred over a continuation row: *Add set* only ever
    /// adds working sets. A row with a continuation directly beneath it is
    /// passed over, because the continuation would then claim to carry on from
    /// whatever row was above the one removed — a drop off a set it was never
    /// taken from. The last row of an exercise stays, or the card would be left
    /// with nothing on it.
    func removableSet(in group: SessionExerciseGroup) -> SetLog? {
        let rows = group.sets
        guard rows.count > 1 else { return nil }
        let candidates = rows.indices.filter { index in
            let holdsUpContinuation = index + 1 < rows.count && rows[index + 1].isContinuation
            return !rows[index].isCompleted && !holdsUpContinuation
        }
        let pick = candidates.last { !rows[$0].isContinuation } ?? candidates.last
        return pick.map { rows[$0] }
    }

    /// Renumbers one exercise so its sets run 0, 1, 2 with no gaps. `setIndex`
    /// is what orders a card, and it's also what pairs a set with the same set
    /// last session, so a deletion in the middle can't be left as a hole.
    private func resequence(_ catalogID: String) {
        let sets = session.sets
            .filter { $0.catalogID == catalogID && !$0.isDeleted }
            .sorted { $0.setIndex < $1.setIndex }
        for (index, set) in sets.enumerated() { set.setIndex = index }
    }

    func addExercise(_ exercise: CatalogExercise, sets: Int = 3) {
        // Matched by movement, not spelling: a session started from a plan
        // slot made before a merge holds the losing ID, while the picker only
        // offers the survivor. Compared raw, adding the survivor opened a
        // second card for the same lift. The new rows take the card's own ID,
        // because the session groups its rows by the ID they carry.
        let canonical = ExerciseCatalog.canonicalID(for: exercise.id)
        let existing = groups.first { ExerciseCatalog.canonicalID(for: $0.catalogID) == canonical }
        let catalogID = existing?.catalogID ?? exercise.id
        let order = existing?.order ?? (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        let firstIndex = (existing?.sets.map(\.setIndex).max() ?? -1) + 1
        let template = existing?.sets.last(where: { !$0.isContinuation })
        let last = lastPerformance(for: catalogID)
        let tracking = template?.tracking ?? exercise.tracking
        let isTimed = tracking == .duration
        for index in 0..<sets {
            let previous = template ?? (index < last.count ? last[index] : last.last)
            // The 10 reps and 45 s are where the stepper opens, not a claim about
            // the set; each row carries only the one its exercise is logged in,
            // or a squat would export a hold time nobody took.
            //
            // And no rep range, unless the plan already set one for this
            // exercise. Nobody prescribed anything for a movement added on the
            // floor, and an 8–12 filled in here would be exported as a target
            // and read back as a heavy triple that "fell short" of it. With no
            // range the card reads the reps being dialled, as a drop row does,
            // and an Easy answer can still offer the next rung.
            let set = SetLog(
                catalogID: catalogID,
                exerciseName: existing?.name ?? exercise.name,
                exerciseOrder: order,
                setIndex: firstIndex + index,
                weightKg: previous?.weightKg ?? 0,
                reps: isTimed ? 0 : previous?.reps ?? 10,
                seconds: isTimed ? previous?.seconds ?? 45 : 0,
                targetRepsLow: template?.targetRepsLow ?? 0,
                targetRepsHigh: template?.targetRepsHigh ?? 0,
                tracking: tracking
            )
            set.session = session
            context.insert(set)
        }
        save()
        Haptics.log()
    }

    /// Whether an exercise can be taken back out of the session, which is the
    /// only time the logger offers it.
    ///
    /// Only an exercise added on the day, and only while nothing on it is
    /// logged. A logged set is data, and undoing it first is what says the
    /// lifter means it. A planned exercise is not offered either: leaving it
    /// unlogged already says it was skipped, and removing it would erase that
    /// the plan asked for it. Freestyle sessions have no plan, so everything in
    /// them counts as added on the day.
    ///
    /// Read from the session's rows rather than from `group`, which is a copy
    /// taken when the card was drawn; a set logged from the wrist since then
    /// must still stop the removal.
    func canRemove(_ group: SessionExerciseGroup) -> Bool {
        let held = rows(of: group)
        return planItem(for: group.catalogID) == nil
            && !held.isEmpty
            && !held.contains(where: \.isCompleted)
    }

    /// Takes an exercise added by mistake out of the session, leaving no trace
    /// of it: its unlogged rows, its note and any claim it had on the working
    /// position go, and nothing else is touched.
    func removeExercise(_ group: SessionExerciseGroup) {
        guard canRemove(group) else { return }
        for set in rows(of: group) {
            // A start announced on a row that is going was a mis-tap on the
            // wrong exercise, and it may have cut a rest short. Same as
            // `cancelStart`: the countdown comes back with the row's stamp
            // gone, rather than staying stopped for a set that no longer exists.
            if let cancelled = restCancelledByStart, cancelled.setID == set.id {
                restTimer.restore(endingAt: cancelled.endsAt, totalSeconds: cancelled.totalSeconds)
                restCancelledByStart = nil
            }
            context.delete(set)
        }
        // A pick that names an exercise which is gone would come back to life
        // the moment the same lift was added again, and the session would open
        // on it as if it had been chosen twice.
        if session.preferredExerciseID == group.catalogID { session.preferredExerciseID = nil }
        // The note was about an exercise that is no longer in this session.
        // Left behind it would describe work the record says never happened.
        session.dropNote(about: group.catalogID, in: context)
        // `save` is what moves the wrist, the Lock Screen and the widgets off the
        // exercise, the same door `addExercise` goes through to put it there.
        save()
    }

    private func rows(of group: SessionExerciseGroup) -> [SetLog] {
        session.sets.filter { $0.catalogID == group.catalogID && !$0.isDeleted }
    }

    /// How many of one exercise's efforts are logged, against
    /// `SessionExerciseGroup.effortCount` for the total.
    func loggedEffortCount(in group: SessionExerciseGroup) -> Int {
        group.sets.filter { $0.isCompleted && !$0.isContinuation }.count
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

    /// Drops any sets left unlogged and stamps the session finished — see
    /// `WorkoutSession.close`, which the wrist's headless finish runs too.
    ///
    /// With nothing logged there is nothing to keep, and the session is
    /// discarded instead. Closed, it was a finished workout with no sets: the
    /// streak, the week strip and "This week" counted a mis-tap as a day
    /// trained, while the calendar and Today called it rest. Going through
    /// `discard` means the Lock Screen, the wrist and Health hear exactly what
    /// a Discard tells them.
    ///
    /// - Parameter moment: when the session ended. Now, for the phone's own
    ///   Finish; the wrist's tap, for one that waited in the queue while the
    ///   lifter walked back — see `WorkoutSession.wristFinishMoment`.
    /// - Returns: false when the session was discarded for being empty, so
    ///   there is no summary to show.
    @discardableResult
    func finish(at moment: Date = .now) -> Bool {
        guard !session.completedSets.isEmpty else {
            discard()
            return false
        }
        // A settle still waiting would otherwise go out after the end, about a
        // session that has already been closed — or, after `discard`, one that
        // no longer exists.
        pendingEdit?.cancel()
        session.close(at: moment, in: context)
        forgetLoggerMemory(of: session.id)
        adoptWatchMetrics()
        restTimer.onChange = nil
        restTimer.stop()
        writeThrough()
        WorkoutLiveActivity.shared.end(with: activityState)
        WatchBridge.shared.update(session: nil, ended: WatchSessionEnd(sessionID: session.id, reason: .finished))
        WatchBridge.shared.clearMetrics()
        WidgetPublisher.updateSession(nil)
        recordToHealth()
        NotificationCenter.default.post(name: .gymTrackWorkoutFinished, object: nil)
        Haptics.success()
        return true
    }

    func discard() {
        pendingEdit?.cancel()
        restTimer.onChange = nil
        restTimer.stop()
        // Read before the delete. A deleted model can trap when read, and an
        // empty Finish now comes through here as well as Discard.
        let sessionID = session.id
        context.delete(session)
        forgetLoggerMemory(of: sessionID)
        writeThrough()
        WorkoutLiveActivity.shared.end(with: nil)
        WatchBridge.shared.update(session: nil, ended: WatchSessionEnd(sessionID: sessionID, reason: .discarded))
        WatchBridge.shared.clearMetrics()
        WidgetPublisher.updateSession(nil)
    }

    // MARK: - Health

    /// Takes whatever the watch measured while the session ran. The watch is
    /// the only thing here that can read a heart rate, so its numbers win.
    private func adoptWatchMetrics() {
        guard let metrics = WatchBridge.shared.liveMetrics, metrics.sessionID == session.id else { return }
        // Each field is written only when it differs. A model property that is
        // set to the value it already holds still tells every observer it
        // changed, and anything on screen that reads it draws again for nothing.
        if !session.wasWatchDriven { session.wasWatchDriven = true }
        // A zero is a watch that had nothing to report yet, not a heart that
        // never beat. Filed, it would read as a measurement, and it would stop
        // the Health backfill filling the real number in later.
        if let average = metrics.averageHeartRate, average > 0, session.averageHeartRate != average {
            session.averageHeartRate = average
        }
        if let max = metrics.maxHeartRate, max > 0, session.maxHeartRate != max { session.maxHeartRate = max }
        if let energy = metrics.activeEnergyKcal, energy > 0, session.activeEnergyKcal != energy {
            session.activeEnergyKcal = energy
        }
        session.stampWatchVitals(average: metrics.averageHeartRate, max: metrics.maxHeartRate,
                                 energy: metrics.activeEnergyKcal)
        // The watch saves its own workout — with the full beat-by-beat record —
        // so the phone must not write a second copy of the same session.
        if let workoutID = metrics.healthWorkoutID, session.healthWorkoutID != workoutID {
            session.healthWorkoutID = workoutID
        }
    }

    /// Writes the session to Health and picks up the heart rate and energy an
    /// Apple Watch recorded during it, whether or not our watch app was running.
    /// Deliberately detached: a slow or refused Health call must never hold up
    /// the summary screen.
    private func recordToHealth() {
        let session = session
        let sessionID = session.id
        let context = context
        let watchIsRecording = session.wasWatchDriven || WatchBridge.shared.liveMetrics != nil
        // The task holds the session across up to twelve seconds of waiting
        // and then Health's own calls, and it can be deleted, erased or
        // restored over in that time. So every read after an await checks it
        // is still there first: a deleted model can trap when read, and
        // anything written for it is an orphan no later erase can find.
        Task { @MainActor in
            // When the watch drove the session it saves the workout itself —
            // with the beat-by-beat heart rate the phone can't reproduce — and
            // tells us the ID a moment later. Give it that moment rather than
            // racing it to a duplicate workout in Health.
            if watchIsRecording {
                for _ in 0..<12 {
                    guard !session.isGoneFromStore else { return }
                    if session.healthWorkoutID != nil { break }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            guard !session.isGoneFromStore else { return }
            let phoneWorkoutID = await HealthKitService.shared.saveWorkout(for: session)
            // A workout written for a session that went meanwhile has already
            // been queued for removal by `saveWorkout`.
            guard !session.isGoneFromStore else { return }
            if let phoneWorkoutID {
                WatchBridge.shared.notePhoneHealthWorkout(phoneWorkoutID, for: sessionID)
            }
            await HealthKitService.shared.backfillVitals(for: session)
            guard !session.isGoneFromStore else { return }
            try? context.save()
        }
    }

    private func save() {
        pendingEdit?.cancel()
        pendingEdit = nil
        writeThrough()
        persistLoggerMemory()
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
                (nextRow(of: catalogID).flatMap(planItem(for:)) ?? planItem(for: catalogID))?
                    .resolvedRestSeconds ?? AppSettings.shared.defaultRestSeconds
            },
            lastTimeLabel: { [self] catalogID in lastTimeLabel(for: catalogID) }
        )
    }

    private func lastTimeLabel(for catalogID: String) -> String? {
        WatchSnapshotFactory.label(for: nextRow(of: catalogID).map(lastPerformance(for:))
                                        ?? lastPerformance(for: catalogID))
    }

    /// The working row an exercise is up to, so the wrist reads the rest and
    /// the "last time" of the slot that row is in rather than of the first.
    private func nextRow(of catalogID: String) -> SetLog? {
        session.sets
            .filter { $0.catalogID == catalogID && !$0.isCompleted && !$0.isContinuation }
            .min(by: SetLog.precedesInSession)
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
    /// them without this object having to know about navigation. Also for a
    /// set this session has no row for, which is not this object's to drop.
    @discardableResult
    func apply(_ command: WatchCommand) -> Bool {
        switch command {
        case .logSet(let id, let weightKg, let reps, let seconds, let loggedAt):
            // Not a row of this session, so possibly one the last Finish
            // deleted before the wrist's log of it could arrive. Swallowed
            // here, that lift was lost from the record; `RootView` passes it
            // on to the one path allowed to put it back.
            // A log the wrist already took back, whose undo got here first.
            // Nobody is owed it, here or in a finished session.
            guard !DroppedSetMemory.shared.wasTakenBack(id, loggedAt: loggedAt) else { return true }
            // A log this logger already applied and the phone has since undone:
            // the wrist re-sent it because it never heard the answer. The set
            // no longer holds it, so `holdsWristLog` below cannot tell, and
            // applying it again re-completed a lift the lifter had taken back.
            // The wrist is told where things stand instead.
            guard !DroppedSetMemory.shared.wasHeardLog(id, loggedAt: loggedAt) else {
                pushToWatch()
                return true
            }
            guard let set = session.sets.first(where: { $0.id == id }) else { return false }
            // The same log again. See `SetLog.holdsWristLog`: run twice,
            // `complete` files a decline nobody made and re-dials rows the
            // lifter has moved on from.
            guard !set.holdsWristLog(at: loggedAt) else {
                pushToWatch()
                return true
            }
            set.weightKg = weightKg
            set.reps = reps
            if set.tracking == .duration { set.seconds = seconds }
            complete(set,
                     restSeconds: planItem(for: set)?.resolvedRestSeconds,
                     at: WatchCommand.loggedMoment(loggedAt))
            return true

        case .rateSet(let rating):
            guard rating.sessionID == session.id else { return false }
            guard rating.isValid,
                  let set = session.sets.first(where: { $0.id == rating.setID }),
                  set.isCompleted, rating.matches(set.completedAt) else { return true }
            // Delivery may repeat. The phone's tap gesture toggles an answer,
            // but a repeated message must leave the explicit answer intact.
            guard set.rpe != rating.rpe else {
                pushToWatch()
                return true
            }
            if let rpe = rating.rpe, let feel = SetFeel(rawValue: rpe) {
                rate(set, feel: feel)
            } else {
                clearRating(set)
            }
            return true

        case .undoSet(let id, let completion):
            // The same, for taking back a set that was put back that way.
            DroppedSetMemory.shared.rememberTakenBack(id, completedAt: completion)
            guard let set = session.sets.first(where: { $0.id == id }) else { return false }
            // An undo of a log this row no longer holds; see
            // `SetLog.admitsWristUndo`. The wrist is shown the set as kept.
            guard set.admitsWristUndo(of: completion) else {
                pushToWatch()
                return true
            }
            uncomplete(set)
            return true

        case .announceStart(let id, let moment):
            guard let set = session.sets.first(where: { $0.id == id }) else { return true }
            // The wrist's moment as it came, count-in included. Through the
            // phone's own tap it would be restamped as its arrival plus a
            // second count-in — late twice over, and later still out of range.
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

        case .metrics(let metrics):
            // A late update for the previous session belongs to RootView's
            // finished-session path, even while a new logger is open.
            guard metrics.sessionID == session.id else { return false }
            // Already folded into `WatchBridge.liveMetrics`; the logger reads it
            // from there. Nothing to write until this session ends.
            return true

        case .requestMirror:
            WatchBridge.shared.resend()
            return true

        case .startToday, .startFreestyle, .finish, .finishSession, .discard, .discardSession:
            return false
        }
    }

    // MARK: - Live Activity

    /// The whole of what the Lock Screen and Dynamic Island draw. Unit-bearing
    /// values are formatted here because the widget can't read the user's
    /// kg/lb preference.
    var activityState: WorkoutActivity.ContentState {
        WorkoutLiveActivity.state(for: session, restEndsAt: restTimer.endsAt,
                                  restStartedAt: restTimer.startedAt)
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

// MARK: - Rows that lean on a set

extension WorkoutSession {
    /// The logged rows whose claim to have been taken without rest leans on
    /// `set`: the unbroken run of logged continuations directly beneath it,
    /// top to bottom. The run stops at the first row that is not one, because
    /// a drop below an unlogged row was already leaning on nothing and this
    /// undo changes nothing about it.
    ///
    /// Here rather than in the logger because the wrist's undo, applied with
    /// no logger running, has to take the same rows back as the phone's.
    func loggedContinuations(below set: SetLog) -> [SetLog] {
        let below = sets
            .filter { $0.catalogID == set.catalogID && !$0.isDeleted && $0.setIndex > set.setIndex }
            .sorted { $0.setIndex < $1.setIndex }
        return Array(below.prefix { $0.isContinuation && $0.isCompleted })
    }
}

// MARK: - Surviving a relaunch

/// What the logger keeps only in memory and would lose when iOS reclaims the
/// app in the middle of a workout: the load offers standing over each card, the
/// takes still open to undo, and what logging and undoing a set overwrote.
///
/// Without it a lifter who put the phone down between sets came back to a
/// logger that had forgotten every offer, and undoing a set taken before the
/// relaunch left the rows below it at a weight nobody lifted — the record
/// disagreeing with the screen in exactly the direction the undo rules exist
/// to prevent.
///
/// Numbers and IDs only, never model objects: a stored ID that no longer names
/// a row is dropped on the way back in, and nothing here can keep a deleted
/// `SetLog` alive. It is not the export's business either. It lives in
/// `UserDefaults`, not the store, so an undone action is never on the record,
/// and `LoggerMemoryStore` removes it the moment its session closes.
struct LoggerMemory: Codable, Equatable {
    /// One `ActiveWorkout.LoadNudge`.
    struct Offer: Codable, Equatable {
        var setID: UUID
        var fromIndex: Int
        var catalogID: String
        var fromKg: Double
        var toKg: Double
        var setCount: Int
        /// `SetFeel.rawValue`.
        var feel: Double
    }

    /// A row's weight before a take moved it.
    struct Weight: Codable, Equatable {
        var rowID: UUID
        var kg: Double
    }

    /// One `ActiveWorkout.TakenNudge`.
    struct Take: Codable, Equatable {
        var offer: Offer
        var previous: [Weight]
    }

    /// One settled offer, as `ActiveWorkout` keeps it to take back the answer
    /// a logged set gave.
    struct Answer: Codable, Equatable {
        var loggedSetID: UUID
        var standing: Offer?
        var taken: Take?
        /// `LoadNudgeOutcome.rawValue`, for the outcome the log filed.
        var recorded: String?
        var priorOutcome: String?
        var priorToKg: Double?
    }

    /// One row a logged set's load was carried onto, and what it held before.
    struct Carry: Codable, Equatable {
        var rowID: UUID
        var kg: Double
        var seconds: Int
        var carriedKg: Double
        var carriedSeconds: Int
    }

    /// Everything one logged set carried forward.
    struct Carried: Codable, Equatable {
        var setID: UUID
        var rows: [Carry]
    }

    var offers: [Offer] = []
    var takes: [Take] = []
    var answers: [Answer] = []
    var carries: [Carried] = []

    /// Nothing to remember, which is what a session nobody used the offers or
    /// the undo in looks like. That stores no key at all.
    var isEmpty: Bool { offers.isEmpty && takes.isEmpty && answers.isEmpty && carries.isEmpty }
}

/// Where `LoggerMemory` is kept between launches: one key per session, so it
/// can be dropped the moment that session closes.
///
/// A key that outlived its session would be the one thing in the app still
/// remembering a set nobody was left holding, so a closed or discarded session
/// removes its own, and `prune` sweeps the ones a path with no logger left
/// behind — the wrist finishing a session while the app was suspended.
struct LoggerMemoryStore {
    static let standard = LoggerMemoryStore(defaults: .standard)
    static let keyPrefix = "activeWorkout.loggerMemory."

    let defaults: UserDefaults

    func key(for sessionID: UUID) -> String { Self.keyPrefix + sessionID.uuidString }

    /// What was stored for the session. A value that will not decode is removed
    /// rather than tried again on every launch.
    func load(for sessionID: UUID) -> LoggerMemory? {
        guard let data = defaults.data(forKey: key(for: sessionID)) else { return nil }
        guard let memory = try? JSONDecoder().decode(LoggerMemory.self, from: data) else {
            forget(sessionID)
            return nil
        }
        return memory
    }

    /// Stores it, or removes the key when there is nothing to keep.
    func save(_ memory: LoggerMemory, for sessionID: UUID) {
        guard !memory.isEmpty, let data = try? JSONEncoder().encode(memory) else {
            forget(sessionID)
            return
        }
        defaults.set(data, forKey: key(for: sessionID))
    }

    func forget(_ sessionID: UUID) {
        defaults.removeObject(forKey: key(for: sessionID))
    }

    /// Every session that has a key.
    var storedSessionIDs: Set<UUID> {
        Set(defaults.dictionaryRepresentation().keys.compactMap { key in
            key.hasPrefix(Self.keyPrefix) ? UUID(uuidString: String(key.dropFirst(Self.keyPrefix.count))) : nil
        })
    }

    /// Drops the memory of every session not in `live`, and any key under the
    /// prefix that names no session at all.
    func prune(keeping live: Set<UUID>) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            if let id = UUID(uuidString: String(key.dropFirst(Self.keyPrefix.count))), live.contains(id) { continue }
            defaults.removeObject(forKey: key)
        }
    }
}

extension LoggerMemory.Offer {
    init(_ nudge: ActiveWorkout.LoadNudge) {
        self.init(setID: nudge.setID, fromIndex: nudge.fromIndex, catalogID: nudge.catalogID,
                  fromKg: nudge.fromKg, toKg: nudge.toKg, setCount: nudge.setCount, feel: nudge.feel.rawValue)
    }
}

extension LoggerMemory.Take {
    init(_ taken: ActiveWorkout.TakenNudge) {
        self.init(offer: .init(taken.nudge),
                  previous: taken.previousKg.map { LoggerMemory.Weight(rowID: $0.key, kg: $0.value) }
                      .sorted { $0.rowID.uuidString < $1.rowID.uuidString })
    }
}

extension ActiveWorkout.LoadNudge {
    /// Nil for a feel this build does not know.
    init?(_ stored: LoggerMemory.Offer) {
        guard let feel = SetFeel(rawValue: stored.feel) else { return nil }
        self.init(setID: stored.setID, fromIndex: stored.fromIndex, catalogID: stored.catalogID,
                  fromKg: stored.fromKg, toKg: stored.toKg, setCount: stored.setCount, feel: feel)
    }
}

extension ActiveWorkout {
    /// The memory as it stands. Sorted wherever the source is a dictionary, so
    /// that a save which changed nothing compares equal and writes nothing.
    fileprivate var loggerMemory: LoggerMemory {
        LoggerMemory(
            offers: standingOffers.map(LoggerMemory.Offer.init),
            takes: openTakes.map(LoggerMemory.Take.init),
            answers: settledOffers.map { answer in
                LoggerMemory.Answer(loggedSetID: answer.loggedSetID,
                                    standing: answer.standing.map(LoggerMemory.Offer.init),
                                    taken: answer.taken.map(LoggerMemory.Take.init),
                                    recorded: answer.recorded?.rawValue,
                                    priorOutcome: answer.priorOutcome?.rawValue,
                                    priorToKg: answer.priorToKg)
            },
            carries: carriedPrefills.map { setID, rows in
                LoggerMemory.Carried(setID: setID, rows: rows.map { rowID, before in
                    LoggerMemory.Carry(rowID: rowID, kg: before.kg, seconds: before.seconds,
                                       carriedKg: before.carriedKg, carriedSeconds: before.carriedSeconds)
                }.sorted { $0.rowID.uuidString < $1.rowID.uuidString })
            }.sorted { $0.setID.uuidString < $1.setID.uuidString }
        )
    }

    /// Writes the memory after a change, and only then. Called wherever the
    /// logger saves, so the store never runs further behind the record than the
    /// one save a force-quit can interrupt.
    fileprivate func persistLoggerMemory() {
        guard !isClosed else { return }
        let now = loggerMemory
        guard now != storedMemory else { return }
        memory.save(now, for: session.id)
        storedMemory = now
    }

    /// The session is over: nothing about it is worth keeping, and a save that
    /// lands afterwards must not write it back.
    fileprivate func forgetLoggerMemory(of sessionID: UUID) {
        isClosed = true
        storedMemory = LoggerMemory()
        memory.forget(sessionID)
    }

    /// Brings back what the last launch was holding, checked against the record
    /// it is read against. Each piece is kept only while the sets it names are
    /// still what it was made about: an offer whose set has since been taken
    /// back, a take whose rows are gone, an answer whose logged set no longer
    /// is. A piece that fails that is dropped rather than repaired, because the
    /// worst a dropped one costs is an offer or an undo the lifter didn't need.
    fileprivate func restoreLoggerMemory() {
        guard session.isActive else {
            memory.forget(session.id)
            return
        }
        // Another session's memory is stale by construction — only sessions
        // still open can be resumed, and one closed with no logger to say so
        // (the wrist's Finish while the app slept) never cleared its own.
        let open = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil }))) ?? []
        memory.prune(keeping: Set(open.map(\.id)).union([session.id]))
        guard let stored = memory.load(for: session.id) else { return }
        storedMemory = stored

        let rows = Dictionary(session.sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func weights(_ kept: [LoggerMemory.Weight]) -> [UUID: Double] {
            Dictionary(kept.filter { rows[$0.rowID] != nil }.map { ($0.rowID, $0.kg) }, uniquingKeysWith: { first, _ in first })
        }
        func taken(_ stored: LoggerMemory.Take) -> TakenNudge? {
            guard let nudge = LoadNudge(stored.offer) else { return nil }
            let previous = weights(stored.previous)
            return previous.isEmpty ? nil : TakenNudge(nudge: nudge, previousKg: previous)
        }

        for offer in stored.offers {
            // Read again rather than trusted: the count of sets it would move,
            // and whether it would still be made, are the record's to say.
            guard let old = LoadNudge(offer), let subject = rows[old.setID], subject.isCompleted,
                  subject.loadNudgeOutcome == nil, pendingNudge(for: old.catalogID) == nil,
                  let fresh = nudge(after: subject), fresh.toKg == old.toKg, fresh.feel == old.feel
            else { continue }
            standingOffers.append(fresh)
        }
        for take in stored.takes {
            guard let kept = taken(take), let subject = rows[kept.nudge.setID], subject.isCompleted,
                  subject.loadNudgeOutcome == .taken, subject.loadNudgeToKg == kept.nudge.toKg,
                  kept.previousKg.keys.contains(where: { rows[$0]?.isCompleted == false }),
                  takenNudge(for: kept.nudge.catalogID) == nil
            else { continue }
            openTakes.append(kept)
        }
        for entry in stored.answers {
            guard rows[entry.loggedSetID]?.isCompleted == true else { continue }
            let standing = entry.standing.flatMap(LoadNudge.init)
            let take = entry.taken.flatMap(taken)
            guard standing != nil || take != nil else { continue }
            var answer = SettledOffer(loggedSetID: entry.loggedSetID, standing: standing, taken: take)
            answer.recorded = entry.recorded.flatMap(LoadNudgeOutcome.init(rawValue:))
            answer.priorOutcome = entry.priorOutcome.flatMap(LoadNudgeOutcome.init(rawValue:))
            answer.priorToKg = entry.priorToKg
            settledOffers.append(answer)
        }
        for carried in stored.carries {
            guard rows[carried.setID]?.isCompleted == true else { continue }
            let kept = carried.rows.filter { rows[$0.rowID] != nil }.map {
                ($0.rowID, Prefill(kg: $0.kg, seconds: $0.seconds,
                                   carriedKg: $0.carriedKg, carriedSeconds: $0.carriedSeconds))
            }
            if !kept.isEmpty { carriedPrefills[carried.setID] = Dictionary(kept, uniquingKeysWith: { first, _ in first }) }
        }
        persistLoggerMemory()
    }
}
