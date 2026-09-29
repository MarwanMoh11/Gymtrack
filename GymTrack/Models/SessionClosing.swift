import Foundation
import SwiftData

/// Ending a session, said once.
///
/// A session ends three ways: *Finish* on the phone, *Finish* on the wrist with
/// the phone asleep in a locker, and the phone finding yesterday's session still
/// open — see `closeIfStale`. Only the first used to do the whole job. The wrist's
/// path deleted the sets nobody lifted and stopped there, so a note about an
/// exercise that was never trained outlived it, and a drop row whose set had
/// been taken back went on claiming to continue whichever set now sat above it.
/// The launch path only stamped an end, so a plan's untouched prescription
/// reached the export as a column of sets marked "not completed" rather than as
/// nothing, which is what they were.
///
/// Three paths closing different amounts is how a record ends up half closed,
/// so all three come through here.
extension WorkoutSession {

    /// Incorporates the wrist's unconfirmed actions before `close` removes
    /// untouched rows. A live Finish can overtake queued log and undo messages;
    /// replaying the wrist's latest state here makes either arrival order end
    /// with the same record. The set IDs are looked up only in this session.
    @discardableResult
    func applyWatchFinish(_ batch: WatchFinishBatch) -> Bool {
        guard isActive, batch.sessionID == id else { return false }
        let rows = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        replayWatchActions(batch, on: rows)
        // The batch is the wrist's final word on this session, so a row it
        // leaves unlogged is one the wrist itself does not count. A queued log
        // for it that turns up later was overtaken by an undo, and remembering
        // the row would let that stale log put back a set the lifter took back.
        DroppedSetMemory.shared.settle(id)
        return true
    }

    private func replayWatchActions(_ batch: WatchFinishBatch, on rows: [UUID: SetLog]) {
        for (id, moment) in batch.starts where WatchCommand.isBelievableStart(moment) {
            guard let set = rows[id], set.startedAt == nil else { continue }
            if let completedAt = set.completedAt, moment > completedAt { continue }
            set.startedAt = moment
        }
        for log in batch.logs {
            guard let set = rows[log.setID], !batch.undos.contains(log.setID) else { continue }
            // A log the phone already took is not news, and whatever the row
            // holds now is the phone's word on it: a set the lifter took back
            // on the phone came back with the wrist's Finish, and one they
            // re-logged there was overwritten by the older log. A log the
            // phone never heard has no entry, so a genuinely late one still
            // lands.
            guard !DroppedSetMemory.shared.wasHeardLog(log.setID, loggedAt: log.completedAt) else { continue }
            set.takeWristLog(weightKg: log.weightKg, reps: log.reps, seconds: log.seconds,
                             at: WatchCommand.loggedMoment(log.completedAt))
        }
        for id in batch.undos { rows[id]?.unlog() }
        for id in batch.cancels { rows[id]?.startedAt = nil }
        settleStarts(replayedFrom: batch, on: rows)
        for rating in batch.ratings where rating.sessionID == id && rating.isValid {
            guard let set = rows[rating.setID], set.isCompleted,
                  rating.matches(set.completedAt) else { continue }
            set.rpe = rating.rpe
        }
    }

    /// The starts a batch wrote, held to the rules the live path holds them
    /// to. A start that waited in the wrist's queue is exactly the kind the
    /// rules exist for: one abandoned for another exercise, or announced long
    /// before the log that finally closed it, and replayed unchecked it went
    /// into the record as a time under tension nobody measured.
    private func settleStarts(replayedFrom batch: WatchFinishBatch, on rows: [UUID: SetLog]) {
        let touched = Set(batch.starts.keys).union(batch.logs.map(\.setID))
        for id in touched {
            guard let set = rows[id], !set.isGoneFromStore else { continue }
            if set.isCompleted, let moment = set.completedAt {
                settleStarts(afterLogging: set, at: moment)
            } else if let start = set.startedAt {
                dropOvertakenStarts(besides: set, at: start)
            }
        }
    }

    /// Drops everything that didn't happen and stamps the end.
    ///
    /// - Parameter moment: when the session ended. Now, for a session somebody
    ///   finished; the last logged set, for one the app is closing on the
    ///   lifter's behalf, which otherwise would report a workout that ran all
    ///   night.
    func close(at moment: Date = .now, in context: ModelContext) {
        // A Finish tapped on a session left open overnight is still the
        // lifter's own Finish, but "now" is not when they stopped lifting.
        // Stamped as given, it went into the export and into Health as a
        // twenty-hour workout. The last set is the latest moment anybody saw
        // them train, so that is where it ends.
        let end = isStale(at: moment) ? min(moment, lastLoggedAt) : moment
        // Before the unlogged sets go, because which exercises survive is what
        // decides which notes still have something to be about.
        pruneNotesForClosing(in: context)
        // Taken before the links are cut: whether a row continues the one
        // above is what the row is, and a drop whose parent is also still in
        // flight from the wrist is put back as a drop if both arrive.
        let dropped = sets.filter { !$0.isCompleted }.map { DroppedSetRow($0, in: self) }
        unlinkOrphanedContinuations()
        for set in sets where !set.isCompleted {
            context.delete(set)
        }
        endedAt = end
        DroppedSetMemory.shared.remember(dropped, closing: id)
    }

    /// How long a session may stay open before the app stops believing anybody
    /// is still lifting in it. The watch refuses to draw a session older than
    /// this, so the phone has to stop offering one at the same point.
    ///
    /// Read from the snapshot the widgets are built from, which compiles
    /// without this model: the widget has to stop showing a workout at the same
    /// moment the app closes it, and two copies of the number could drift.
    static let staleAfter: TimeInterval = GymTrackSnapshot.Running.staleAfter

    /// True for a session still open more than `staleAfter` past its start —
    /// one the lifter walked away from without finishing.
    func isStale(at moment: Date = .now) -> Bool {
        isActive && moment.timeIntervalSince(startedAt) > Self.staleAfter
    }

    /// The last moment a set was logged, or the start for a session where
    /// nothing was.
    var lastLoggedAt: Date {
        completedSets.compactMap(\.completedAt).max() ?? startedAt
    }

    /// When a Finish tapped on the wrist ended this session, given the moment
    /// the wrist stamped on it. Read after the batch is applied, so its logs
    /// count as sets.
    ///
    /// No later than now: a stamp from ahead of this clock is the two devices
    /// disagreeing, not a moment anybody lived. And no earlier than the last
    /// set, which wins that argument if it comes to one: a set logged after
    /// the session ended would say the lifter trained after they stopped.
    /// Without a stamp, from a watch that predates it, the session ends when
    /// the Finish lands, as every wrist Finish used to.
    func wristFinishMoment(_ stamp: Date?, now: Date = .now) -> Date {
        guard let stamp else { return now }
        return max(min(stamp, now), lastLoggedAt)
    }

    /// Ends a stale session the way the lifter left it: deleted if nothing was
    /// logged, since an empty workout is not a workout, and otherwise closed at
    /// its last set rather than now.
    ///
    /// Every path that can meet yesterday's session asks this one question.
    /// It used to be asked only on a cold launch in the foreground, so a phone
    /// left resident overnight, or woken in the background by the wrist, kept
    /// the session open: each Start from the watch was answered with a session
    /// the watch will not draw, and a Finish recorded the whole night.
    ///
    /// Leaves saving, Health, the Live Activity and the watch to the caller,
    /// which knows which of them it has; see `retireIfStale`.
    ///
    /// - Returns: true when the session was closed or deleted.
    @discardableResult
    func closeIfStale(in context: ModelContext) -> Bool {
        guard isStale() else { return false }
        if completedSets.isEmpty {
            context.delete(self)
        } else {
            // Closed properly, not just stamped: the sets nobody lifted go,
            // and so does anything written about them.
            close(at: lastLoggedAt, in: context)
        }
        return true
    }

    /// `closeIfStale`, answering how the wrist should hear the session ended:
    /// finished when it kept sets, discarded when it was deleted empty.
    ///
    /// A session closed with sets is a workout, and is told to the watch and
    /// written to Health the way a Finish is. Retired with a bare "no session",
    /// it reached neither: the wrist threw away a recording it had kept since
    /// the first set, and Health never heard of the workout at all.
    ///
    /// - Returns: `nil` when the session was not stale.
    @discardableResult
    func retireIfStale(in context: ModelContext) -> WatchSessionEnd? {
        let sessionID = id
        let keepsSets = !completedSets.isEmpty
        guard closeIfStale(in: context) else { return nil }
        return WatchSessionEnd(sessionID: sessionID, reason: keepsSets ? .finished : .discarded)
    }

    /// What survives the end of the session: a note that says something, about
    /// an exercise that ended up in the record.
    ///
    /// An exercise you logged nothing for is dropped from the session entirely
    /// — that's what `close` does with its sets — so a note left on it would be
    /// the only trace of an exercise the record says you didn't do, and it would
    /// have nowhere to be read back. It goes with the sets.
    private func pruneNotesForClosing(in context: ModelContext) {
        let trained = Set(sets.filter(\.isCompleted).map(\.catalogID))
        for note in exerciseNotes where note.isEmpty || !trained.contains(note.catalogID) {
            context.delete(note)
        }
    }

    /// Cuts the link on any row left continuing a set that won't be in the
    /// record.
    ///
    /// A continuation is always built on top of a set that has already been
    /// logged, so this only comes up one way: the lifter takes that set back
    /// and leaves it taken back. `close` then deletes it as an unlogged set,
    /// and the row underneath would survive as the exercise's first set still
    /// claiming it was taken on without rest from something that, as far as
    /// the record goes, never happened. It is a set on its own now, and the
    /// only honest thing left to say about it is nothing.
    ///
    /// The set it has to keep is the row directly above it — the one
    /// `SetLog.continuedSet` names — not any logged set further up. Asked the
    /// looser question, a drop taken off set 2 survived set 2 being taken back
    /// as long as set 1 was still there, and went into the record as a drop
    /// off set 1: a lift the lifter did, attached to a set it had nothing to
    /// do with.
    private func unlinkOrphanedContinuations() {
        for set in sets where set.isContinuation && set.continuedSet?.isCompleted != true {
            set.continuesPreviousSet = nil
        }
    }
}

// MARK: - Sets the wrist logged before the end and the link delivered after it

/// A Finish on the phone deletes every row nobody logged, and a set the wrist
/// logged out of range is exactly such a row until its message lands. The
/// transfer is never cancelled, so it does land, after the close, and used to
/// find nothing to write to: a real lift gone from the record while the watch,
/// seeing the session ended, threw away its own copy. These put it back.
extension WorkoutSession {

    /// Puts back a row `close` removed, logged with the wrist's values.
    ///
    /// Only into a session that has ended and is still here, only where no
    /// row with that ID exists, and only for a lift logged at or before the
    /// end. A log stamped after the end is not a late copy of anything this
    /// session held — it is the wrist's clock running ahead, or a message
    /// with no stamp, which reads as the moment it arrived — and writing it
    /// in would record a set after the lifter had stopped.
    ///
    /// - Returns: the row, now logged, or nil when nothing was put back.
    @discardableResult
    func restoreDroppedSet(_ setID: UUID, weightKg: Double, reps: Int, seconds: Int,
                           loggedAt: Date?, in context: ModelContext) -> SetLog? {
        let memory = DroppedSetMemory.shared
        guard let end = endedAt,
              let row = memory.row(for: setID), row.sessionID == id, row.restoredAt == nil,
              !sets.contains(where: { $0.id == setID })
        else { return nil }
        // The two ways a log stops being owed a row, checked here so every
        // path that restores one agrees. Taken back: the wrist's own undo got
        // here first. Heard: the phone had this very log while the session was
        // running and the lifter took it back on the phone, so its row was
        // dropped at the close for being unlogged, and a copy still in the
        // wrist's queue is not a lift the phone missed. A log the phone never
        // heard is the one this exists for, and is told apart by exactly that.
        guard !memory.wasTakenBack(setID, loggedAt: loggedAt),
              !memory.wasHeardLog(setID, loggedAt: loggedAt) else { return nil }
        let moment = WatchCommand.loggedMoment(loggedAt)
        guard moment <= end else { return nil }

        let set = row.rebuilt()
        set.session = self
        context.insert(set)
        set.takeWristLog(weightKg: weightKg, reps: reps, seconds: seconds, at: moment)
        // The start the phone heard is held to the rules a live one is: a start
        // remembered from before the close can be as old as any abandoned one.
        settleStarts(afterLogging: set, at: moment)
        // `close` cut this link if the row above didn't make the record, and
        // it still may not have: its own log can be later in the queue, or
        // never have been made.
        if set.isContinuation && set.continuedSet?.isCompleted != true {
            set.continuesPreviousSet = nil
        }
        memory.markRestored(setID)
        return set
    }

    /// Takes back a set the wrist un-logged after the session ended.
    ///
    /// For a row still only remembered, the memory goes: the two channels the
    /// wrist sends on are not ordered, so a log that was already taken back
    /// can arrive after its undo and must find nothing to put back. For a row
    /// already put back, it goes through `SetLog.unlog()`, the one place a
    /// set is erased, and is then deleted, because an unlogged row in a closed
    /// session is exactly what `close` would have removed.
    ///
    /// An undo that names a different completion than the row put back
    /// holds is left alone, for the reason `SetLog.admitsWristUndo` gives.
    ///
    /// - Returns: true when a row was taken out of the store.
    @discardableResult
    func withdrawDroppedSet(_ setID: UUID, completedAt completion: Date? = nil,
                            in context: ModelContext) -> Bool {
        let memory = DroppedSetMemory.shared
        guard let row = memory.row(for: setID), row.sessionID == id else { return false }
        let restored = sets.first(where: { $0.id == setID })
        if let restored, !restored.admitsWristUndo(of: completion) { return false }
        // A stamped undo names the one log it takes back, and `wasTakenBack`
        // now refuses exactly that log wherever it turns up, so the row can
        // stay for a re-log to find. Forgotten here, a log, an undo and a
        // re-log that all arrived late lost the re-log. An undo with no stamp
        // cannot say which log it answers, and so takes the row with it. That
        // loses a re-log that followed it; keeping the row instead would let
        // the log the undo answered put back a set the lifter took back, which
        // is false detail where the other is missing detail. Only a watch
        // older than stamped undos sends one, and the watch ships inside the
        // phone app, so the choice is left on the side the record can afford.
        if completion != nil {
            memory.markUnrestored(setID)
        } else {
            memory.forget(setID)
        }
        guard row.restoredAt != nil, !isActive, let set = restored else { return false }
        set.unlog()
        // While it is still here and unlogged, so a drop taken off it loses
        // its link to this row rather than to whatever sits above.
        unlinkOrphanedContinuations()
        context.delete(set)
        return true
    }

    /// A wrist Finish that reaches a session the phone has already closed.
    ///
    /// Undos go first. The batch is the wrist's final state, so a set it took
    /// back must not be put back by a log earlier in the same batch or later
    /// in the queue. Everything else in the batch then applies to the rows
    /// put back and to nothing else: the rest of this record was closed by
    /// the phone, and a queued command does not get to rewrite it.
    ///
    /// - Returns: true when a row was put back or taken out.
    @discardableResult
    func applyLateWatchFinish(_ batch: WatchFinishBatch, in context: ModelContext) -> Bool {
        guard !isActive, batch.sessionID == id else { return false }
        var withdrew = false
        for setID in batch.undos where withdrawDroppedSet(setID, in: context) { withdrew = true }
        var restored: [UUID: SetLog] = [:]
        for log in batch.logs where !batch.undos.contains(log.setID) {
            guard let set = restoreDroppedSet(log.setID, weightKg: log.weightKg, reps: log.reps,
                                              seconds: log.seconds, loggedAt: log.completedAt,
                                              in: context) else { continue }
            restored[set.id] = set
        }
        replayWatchActions(batch, on: restored)
        return withdrew || !restored.isEmpty
    }
}

extension WorkoutSession {

    /// Writes the heart rate and energy the watch measured, when this report
    /// is this session's to take.
    ///
    /// A running session takes every reading. A closed one takes what a
    /// Finish carried, and the watch's hand-over of the workout it saved to
    /// Health, and nothing else: a live reading that lands after the close was
    /// taken partway through, and it overwrote the totals the finish had just
    /// written — the export then reported half a workout's heart rate and
    /// energy as the whole one's. See `WatchWorkoutMetrics.isHandover`.
    ///
    /// - Parameter final: true for the metrics a Finish carried.
    /// - Returns: true when the numbers were written; the caller then accepts
    ///   the Health workout, if one came with them.
    @discardableResult
    func takeWatchMetrics(_ metrics: WatchWorkoutMetrics, final: Bool) -> Bool {
        guard metrics.sessionID == id, final || isActive || metrics.isHandover else { return false }
        wasWatchDriven = true
        if let average = metrics.averageHeartRate { averageHeartRate = average }
        if let max = metrics.maxHeartRate { maxHeartRate = max }
        if let energy = metrics.activeEnergyKcal, energy > 0 { activeEnergyKcal = energy }
        return true
    }
}

extension SetLog {

    /// Whether this row already holds the wrist log stamped at this moment.
    ///
    /// A log can reach the phone twice: a live message the watch was told had
    /// failed is queued again, and may have arrived all the same. Run a second
    /// time, logging files the standing load nudge as declined, moves the
    /// effort question back to this set, carries its load over rows the lifter
    /// has since re-dialled and can start a rest mid-set. The second copy is
    /// the same tap, so it changes nothing.
    func holdsWristLog(at stamp: Date?) -> Bool {
        isCompleted && WatchCommand.isSameCompletion(stamp, as: completedAt)
    }

    /// Whether a wrist undo naming this completion may take this row back.
    ///
    /// An undo that names a different completion answers a log this row no
    /// longer holds: the lifter took a set back and logged it again, and the
    /// undo came second. Honouring it erased the lift they corrected. A row
    /// not yet logged is still taken back — the undo overtook its log, and
    /// what the phone knows of the set's start goes as it would have — and an
    /// undo with no stamp, from an older watch, takes back whatever is there.
    func admitsWristUndo(of completion: Date?) -> Bool {
        guard let completion, isCompleted else { return true }
        return WatchCommand.isSameCompletion(completion, as: completedAt)
    }
}

// MARK: - The rules an announced start is held to

// The one statement of them. `ActiveWorkout` (the logger) and the wrist's log
// applied with no logger running both call these, and so does the replay of a
// wrist Finish below, so there is a single copy to change. It lives in this
// file, not the logger's, because some harnesses compile this file without the
// logger, and a rule that only the logger could see would have to be restated
// for them: that restatement existed, and had to be pinned equal to the
// original by a test.
extension SetLog {
    /// The longest an announced start can sit ahead of the log that closes the
    /// set and still be believed as this set's start.
    ///
    /// A start nobody closed is not a slow set. The lifter tapped Start, found
    /// the bench taken, lifted something else and logged this one after the
    /// detour, and the pair then reported a time under tension of however long
    /// the detour took, exported as something measured. So the gap has to be one
    /// a set could fill, and the bound is set by what the set was: ten seconds a
    /// rep, slower than any tempo anybody lifts a working set at, for a
    /// counted set; twice the hold for a timed one; and a minute either way for
    /// the unracking and settling the count-in doesn't cover. Never under three
    /// minutes, because the lifter dials the numbers after the set and before
    /// the tap on Log, and a short set is not a reason to disbelieve a slow tap.
    ///
    /// Over the bound the start is dropped, not shortened. A shortened one
    /// would be a moment made up to fit, and the record would say the set
    /// began then.
    var longestPlausibleLength: TimeInterval {
        let working = tracking == .duration ? TimeInterval(seconds) * 2 : TimeInterval(reps) * 10
        return max(180, working + 60)
    }

    /// Whether the start on this set still describes it once it is logged at
    /// `moment`: it exists, it isn't in the future of the log (logged inside
    /// the count-in, the start it counted towards never came), and the two are
    /// close enough for one set to have filled.
    func startStillDescribes(loggedAt moment: Date) -> Bool {
        guard let startedAt else { return false }
        let length = moment.timeIntervalSince(startedAt)
        return length >= 0 && length <= longestPlausibleLength
    }
}

extension WorkoutSession {
    /// What logging `set` at `moment` does to the starts announced on it and on
    /// the sets around it. Shared by the logger and by the wrist's log applied
    /// with no logger running, so the two can't disagree about a start.
    func settleStarts(afterLogging set: SetLog, at moment: Date) {
        if !set.startStillDescribes(loggedAt: moment) { set.startedAt = nil }
        dropOvertakenStarts(besides: set, at: moment)
    }

    /// Clears the announced start of every unlogged set other than `set` that
    /// began before `moment`, and returns which sets they were.
    ///
    /// A start that a later log, or a later start, has overtaken cannot still
    /// be under way: nobody lifts two sets at once. The rest gap and the heart
    /// rate window already refuse a start that another set's log has passed;
    /// the set's own length and the exported stamp did not, and an abandoned
    /// start paired with a log twenty minutes on.
    @discardableResult
    func dropOvertakenStarts(besides set: SetLog, at moment: Date) -> [UUID] {
        dropStarts { $0.id != set.id && ($0.startedAt ?? .distantFuture) < moment }
    }

    /// Clears the announced start of every unlogged set of another exercise
    /// than `catalogID`, for a lifter who has moved onto it.
    @discardableResult
    func dropStarts(awayFrom catalogID: String) -> [UUID] {
        dropStarts { $0.catalogID != catalogID }
    }

    private func dropStarts(where abandoned: (SetLog) -> Bool) -> [UUID] {
        var dropped: [UUID] = []
        for other in sets where !other.isCompleted && other.startedAt != nil
            && !other.isGoneFromStore && abandoned(other) {
            other.startedAt = nil
            dropped.append(other.id)
        }
        return dropped
    }
}

extension SetLog {

    /// Clears the start on every logged set whose start no set could have
    /// filled, and returns how many there were.
    ///
    /// The rule that drops such a start as it is logged (`startStillDescribes`)
    /// came late, and every set logged before it, or replayed from a queue
    /// without it, kept whatever start it was given. Paired with the log, that
    /// start is a time under tension of however long the detour took, exported
    /// as measured. The check needs nothing but what the row stores, so it can
    /// be run over the history and give the same answer every time. Only the
    /// start goes: a start proven false is dropped, never shortened to fit.
    ///
    /// The overtaken rule is not applied here. `WatchCommandCenter` runs it as
    /// its own one-time repair (`overtakenStartsRepaired`), and only where the
    /// stored stamps prove it: another set logged strictly between this one's
    /// start and its log. A tie would need the order the messages arrived in,
    /// which the store never kept, so a tied start is left alone.
    @discardableResult
    static func dropImplausibleStoredStarts(in context: ModelContext) -> Int {
        let withStart = FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.isCompleted && $0.startedAt != nil })
        var dropped = 0
        for set in (try? context.fetch(withStart)) ?? [] {
            guard let completedAt = set.completedAt,
                  !set.startStillDescribes(loggedAt: completedAt) else { continue }
            set.startedAt = nil
            dropped += 1
        }
        if dropped > 0 { try? context.save() }
        return dropped
    }
}

private extension SetLog {
    /// The wrist's log, written the one way every path writes it. Its
    /// seconds only count on a set measured in time; on a rep set they are a
    /// field the message has to carry, not something anybody timed.
    func takeWristLog(weightKg: Double, reps: Int, seconds: Int, at moment: Date) {
        self.weightKg = weightKg
        self.reps = reps
        if tracking == .duration { self.seconds = seconds }
        isCompleted = true
        completedAt = moment
        // A start after the log is a count-in that never finished.
        if let start = startedAt, start > moment { startedAt = nil }
    }
}

/// Everything needed to rebuild a row `close` deleted, and nothing it gained
/// by being logged, since it never was.
struct DroppedSetRow: Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var catalogID: String
    var exerciseName: String
    var exerciseOrder: Int
    var setIndex: Int
    var seconds: Int
    var trackingRaw: String?
    var targetRepsLow: Int
    var targetRepsHigh: Int
    var continuesPreviousSet: Bool?
    /// An announced start the phone had already heard; the log that follows
    /// it is what makes it part of a set.
    var startedAt: Date?
    var droppedAt: Date
    /// When a late log put the row back. Kept rather than forgotten so a late
    /// undo can tell a row this put back from one the phone closed as logged,
    /// which no queued command may rewrite.
    var restoredAt: Date?

    init(_ set: SetLog, in session: WorkoutSession, at moment: Date = .now) {
        id = set.id
        sessionID = session.id
        catalogID = set.catalogID
        exerciseName = set.exerciseName
        exerciseOrder = set.exerciseOrder
        setIndex = set.setIndex
        seconds = set.seconds
        trackingRaw = set.trackingRaw
        targetRepsLow = set.targetRepsLow
        targetRepsHigh = set.targetRepsHigh
        continuesPreviousSet = set.continuesPreviousSet
        startedAt = set.startedAt
        droppedAt = moment
    }

    func rebuilt() -> SetLog {
        let set = SetLog(catalogID: catalogID, exerciseName: exerciseName,
                         exerciseOrder: exerciseOrder, setIndex: setIndex,
                         seconds: seconds, targetRepsLow: targetRepsLow,
                         targetRepsHigh: targetRepsHigh)
        set.id = id
        set.trackingRaw = trackingRaw
        set.continuesPreviousSet = continuesPreviousSet
        set.startedAt = startedAt
        return set
    }
}

/// Where each row `close` deleted was, kept for a week so a wrist log that
/// arrives after the Finish can be put back into the session it belonged to.
///
/// Operational memory, never data. It lives outside the store and never
/// reaches the export, so a row nobody lifted still leaves no trace in the
/// record; this only says where such a row sat, in case the wrist later
/// proves there was a lift in it. A week, because a watch can stay out of
/// range for days and `transferUserInfo` still delivers when it comes back;
/// capped, because a stream of abandoned plans should not grow it forever.
///
/// It also keeps the other thing a late wrist log is checked against: the
/// undos that named it. See `rememberTakenBack`.
///
/// Locked, because the model methods that reach it (`close`, the late-log
/// restore) are not main-actor isolated and nothing but convention keeps them
/// there. It keeps in-memory state (`settledByWrist`) beside a
/// read-modify-write over `UserDefaults`, which two threads could interleave
/// into a lost entry; every public method holds the lock for the whole of its
/// read and write, and none calls another. `shared` is a constant: it used to
/// be a `var` so tests could swap it, which let any code replace the object
/// other code was holding.
final class DroppedSetMemory: @unchecked Sendable {

    static let shared = DroppedSetMemory(defaults: .standard)

    static let lifetime: TimeInterval = 7 * 24 * 3600
    static let capacity = 200
    private static let key = "droppedSetRows"

    private let lock = NSLock()
    private var defaults: UserDefaults
    /// Sessions whose closing follows the wrist's own Finish batch, which
    /// already settled every row the wrist logged. In memory only: the close
    /// comes straight after, in the same process.
    private var settledByWrist: Set<UUID> = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Points the memory at another store and drops what it held in memory,
    /// which is what a test that used to swap `shared` needs now that it is a
    /// constant.
    func replaceStore(with defaults: UserDefaults) {
        lock.withLock {
            self.defaults = defaults
            settledByWrist = []
        }
    }

    func row(for setID: UUID, now: Date = .now) -> DroppedSetRow? {
        lock.withLock { load(now: now).first { $0.id == setID } }
    }

    func remember(_ rows: [DroppedSetRow], closing sessionID: UUID, now: Date = .now) {
        lock.withLock {
            guard settledByWrist.remove(sessionID) == nil, !rows.isEmpty else { return }
            let incoming = Set(rows.map(\.id))
            store(load(now: now).filter { !incoming.contains($0.id) } + rows)
        }
    }

    func settle(_ sessionID: UUID) {
        lock.withLock { _ = settledByWrist.insert(sessionID) }
    }

    func markRestored(_ setID: UUID, at moment: Date = .now) {
        lock.withLock {
            store(load(now: moment).map { row in
                guard row.id == setID else { return row }
                var restored = row
                restored.restoredAt = moment
                return restored
            })
        }
    }

    func forget(_ setID: UUID) {
        lock.withLock { store(load(now: .now).filter { $0.id != setID }) }
    }

    /// Puts a row back to being only remembered, after the row it restored was
    /// taken out again. The next log for the set is owed a row as much as the
    /// first was.
    func markUnrestored(_ setID: UUID) {
        lock.withLock {
            store(load(now: .now).map { row in
                guard row.id == setID, row.restoredAt != nil else { return row }
                var remembered = row
                remembered.restoredAt = nil
                return remembered
            })
        }
    }

    // MARK: Logs the wrist took back

    /// A wrist undo, by the completion it named. The log it answers can land
    /// after it — the undo was sent live while the log waited in the queue,
    /// or the log was queued a second time after a send reported failing —
    /// and landing second, it put a set the lifter took back into the record.
    ///
    /// Kept as long as a dropped row, and here for the same reason: the log
    /// can wait in the queue for as long as the watch is out of range, and a
    /// row `close` removed in the meantime is one it could otherwise restore.
    /// The stamp is exact, so no other log is ever refused by it.
    private struct TakenBackLog: Codable {
        var setID: UUID
        var completedAt: Date
        var heardAt: Date
    }

    private static let takenBackKey = "takenBackWristLogs"
    private static let heardKey = "heardWristLogs"

    func rememberTakenBack(_ setID: UUID, completedAt: Date?, now: Date = .now) {
        lock.withLock { remember(setID, completedAt: completedAt, key: Self.takenBackKey, now: now) }
    }

    /// Whether a wrist log stamped at this moment was already taken back.
    func wasTakenBack(_ setID: UUID, loggedAt: Date?, now: Date = .now) -> Bool {
        lock.withLock { holds(setID, loggedAt: loggedAt, key: Self.takenBackKey, now: now) }
    }

    /// A wrist log the phone applied, by the stamp it carried. The phone has no
    /// hook on its own undo, so this is how a log the phone already took is
    /// told from one it never heard: a copy of it turning up in a Finish batch
    /// after the lifter took the set back on the phone must not put it back,
    /// and a log with no entry here is the late one the row was kept for.
    /// Kept as long as a dropped row, for the same reason.
    func rememberHeardLog(_ setID: UUID, completedAt: Date?, now: Date = .now) {
        lock.withLock { remember(setID, completedAt: completedAt, key: Self.heardKey, now: now) }
    }

    /// Whether the phone already applied a wrist log stamped at this moment.
    func wasHeardLog(_ setID: UUID, loggedAt: Date?, now: Date = .now) -> Bool {
        lock.withLock { holds(setID, loggedAt: loggedAt, key: Self.heardKey, now: now) }
    }

    private func remember(_ setID: UUID, completedAt: Date?, key: String, now: Date) {
        guard let completedAt else { return }
        let entry = TakenBackLog(setID: setID, completedAt: completedAt, heardAt: now)
        let kept = loadStamped(key: key, now: now).filter {
            $0.setID != setID || $0.completedAt != completedAt
        } + [entry]
        guard let data = try? JSONEncoder().encode(Array(kept.suffix(Self.capacity))) else { return }
        defaults.set(data, forKey: key)
    }

    private func holds(_ setID: UUID, loggedAt: Date?, key: String, now: Date) -> Bool {
        guard let loggedAt else { return false }
        return loadStamped(key: key, now: now).contains {
            $0.setID == setID && WatchCommand.isSameCompletion(loggedAt, as: $0.completedAt)
        }
    }

    private func loadStamped(key: String, now: Date) -> [TakenBackLog] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([TakenBackLog].self, from: data)
        else { return [] }
        return entries.filter { now.timeIntervalSince($0.heardAt) < Self.lifetime }
    }

    private func load(now: Date) -> [DroppedSetRow] {
        guard let data = defaults.data(forKey: Self.key),
              let rows = try? JSONDecoder().decode([DroppedSetRow].self, from: data)
        else { return [] }
        return rows.filter { now.timeIntervalSince($0.droppedAt) < Self.lifetime }
    }

    private func store(_ rows: [DroppedSetRow]) {
        let kept = Array(rows.suffix(Self.capacity))
        guard !kept.isEmpty, let data = try? JSONEncoder().encode(kept) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
