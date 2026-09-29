import Foundation
import SwiftData

/// Run with scripts/test-logger-corrections.sh; no simulator is needed.
///
/// The three ways the logger used to rewrite the lifter's record while they
/// were only trying to look at it or tidy it: fixing a typo re-logged the set
/// at a false moment (LOG-03), *Remove* could delete a logged set (LOG-02), and
/// looking back at a finished exercise moved the working position (LOG-01).
@main
struct LoggerCorrectionTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        try correctionKeepsTheMoment(context)
        try correctionOfATimedSet(context)
        try correctionWithdrawsAnOfferReadOffTheTypo(context)
        try removeNeverTakesALoggedRow(context)
        try removePrefersAWorkingSet(context)
        try reviewLeavesTheWorkingPosition(context)
        print("Logger correction tests passed")
    }

    /// One row of a hand-built session. The state is written straight onto the
    /// models, so these tests don't lean on how logging or undo get there.
    @MainActor @discardableResult
    static func row(_ id: String, order: Int, index: Int, in session: WorkoutSession,
                    context: ModelContext, kg: Double = 80, reps: Int = 8, seconds: Int = 0,
                    tracking: TrackingMode = .weightReps, loggedAt: Date? = nil,
                    continuation: Bool = false) -> SetLog {
        let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: order, setIndex: index,
                         weightKg: kg, reps: reps, seconds: seconds,
                         targetRepsLow: continuation ? 0 : 8, targetRepsHigh: continuation ? 0 : 12,
                         tracking: tracking)
        if let loggedAt {
            set.isCompleted = true
            set.completedAt = loggedAt
        }
        if continuation { set.continuesPreviousSet = true }
        set.session = session
        context.insert(set)
        return set
    }

    // MARK: LOG-03

    @MainActor static func correctionKeepsTheMoment(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-3_600)
        let session = WorkoutSession(title: "Correction", startedAt: t0.addingTimeInterval(-60))
        context.insert(session)
        let a1 = row("A", order: 0, index: 0, in: session, context: context)
        let a2 = row("A", order: 0, index: 1, in: session, context: context)
        let a3 = row("A", order: 0, index: 2, in: session, context: context)
        let a4 = row("A", order: 0, index: 3, in: session, context: context)
        let b1 = row("B", order: 1, index: 0, in: session, context: context, kg: 60, reps: 10)
        try context.save()

        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.complete(a1, restSeconds: nil, at: t0)
        workout.complete(a2, restSeconds: nil, at: t0.addingTimeInterval(180))
        // 80 typed, 100 lifted: the set every later one on this exercise has
        // to clear goes into the record 20 kg short.
        a3.startedAt = t0.addingTimeInterval(320)
        workout.complete(a3, restSeconds: nil, at: t0.addingTimeInterval(360))
        a3.rpe = SetFeel.solid.rawValue
        a3.averageHeartRate = 142
        a3.maxHeartRate = 161
        // Logging carries each load down the card, so the heavier set is
        // dialled in just before it is lifted, as it would be on the day.
        a4.weightKg = 90
        workout.complete(a4, restSeconds: nil, at: t0.addingTimeInterval(540))
        workout.complete(b1, restSeconds: nil, at: t0.addingTimeInterval(1_200))
        precondition(!workout.isPR(a3) && workout.isPR(a4),
                     "Setup: 90 kg beats the 80s logged before it")

        let loggedAt = a3.completedAt
        let startedAt = a3.startedAt
        let rpe = a3.rpe
        let restBefore = session.typicalRestSeconds
        let order = session.sets.filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }.map(\.id)

        workout.correct(a3, weightKg: 100, reps: 8, seconds: 45)

        precondition(a3.weightKg == 100 && a3.reps == 8, "The corrected numbers are written")
        precondition(a3.seconds == 0, "Seconds are only a weighted set's business when it is timed")
        precondition(a3.isCompleted, "A correction is not an undo")
        precondition(a3.completedAt == loggedAt, "A typo is not a new moment: completedAt stays")
        precondition(a3.startedAt == startedAt, "The measured start stays")
        precondition(a3.rpe == rpe, "The rating stays")
        precondition(a3.averageHeartRate == 142 && a3.maxHeartRate == 161, "The heart rate stays")
        precondition(workout.lastLoggedSetID == b1.id, "The correction is not the latest lift")
        precondition(session.typicalRestSeconds == restBefore, "Every rest either side is untouched")
        let after = session.sets.filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }.map(\.id)
        precondition(after == order, "The set keeps its place in the session's order")
        precondition(workout.isPR(a3), "100 kg beats everything logged before it")
        precondition(!workout.isPR(a4), "And 90 kg after it no longer clears the bar")

        workout.correct(a3, weightKg: 80, reps: 8, seconds: 0)
        precondition(!workout.isPR(a3) && workout.isPR(a4), "Correcting back puts the records back")

        let pending = row("A", order: 0, index: 4, in: session, context: context)
        workout.correct(pending, weightKg: 120, reps: 3, seconds: 0)
        precondition(pending.weightKg == 80 && pending.completedAt == nil,
                     "A set nobody logged is dialled through its own steppers, not corrected")
    }

    @MainActor static func correctionOfATimedSet(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_800)
        let session = WorkoutSession(title: "Timed", startedAt: t0)
        context.insert(session)
        let hold = row("plank-test", order: 0, index: 0, in: session, context: context,
                       kg: 0, reps: 0, seconds: 60, tracking: .duration)
        row("plank-test", order: 0, index: 1, in: session, context: context,
            kg: 0, reps: 0, seconds: 60, tracking: .duration)
        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.complete(hold, restSeconds: nil, at: t0.addingTimeInterval(90))
        let loggedAt = hold.completedAt

        workout.correct(hold, weightKg: hold.weightKg, reps: hold.reps, seconds: 75)
        precondition(hold.seconds == 75, "A timed set's seconds are its number")
        precondition(hold.completedAt == loggedAt)
    }

    @MainActor static func correctionWithdrawsAnOfferReadOffTheTypo(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-900)
        let session = WorkoutSession(title: "Offer", startedAt: t0)
        context.insert(session)
        let source = row("offer-test", order: 0, index: 0, in: session, context: context,
                         kg: 40, reps: 12, loggedAt: t0)
        row("offer-test", order: 0, index: 1, in: session, context: context, kg: 40, reps: 8)
        row("offer-test", order: 0, index: 2, in: session, context: context, kg: 40, reps: 8)
        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.rate(source, feel: .easy)
        guard workout.pendingNudge(for: source.catalogID)?.setID == source.id else {
            preconditionFailure("Setup: twelve easy reps at the top of 8-12 offers more weight")
        }

        workout.correct(source, weightKg: 40, reps: 9, seconds: 0)
        precondition(workout.pendingNudge(for: source.catalogID) == nil,
                     "An offer read off the typed numbers goes when they are corrected")
        precondition(source.rpe == SetFeel.easy.rawValue, "The answer itself stays")
        precondition(source.loadNudgeOutcome == nil,
                     "Nobody turned the offer down, so nothing is recorded about it")
    }

    // MARK: LOG-02

    @MainActor static func removeNeverTakesALoggedRow(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_200)
        let session = WorkoutSession(title: "Remove", startedAt: t0)
        context.insert(session)
        let r1 = row("R", order: 0, index: 0, in: session, context: context, loggedAt: t0)
        let r2 = row("R", order: 0, index: 1, in: session, context: context, loggedAt: t0 + 120)
        let r3 = row("R", order: 0, index: 2, in: session, context: context, loggedAt: t0 + 240)
        let workout = ActiveWorkout(session: session, context: context, history: [])

        // A finished exercise opened for review: every row is a lift.
        precondition(workout.removableSet(in: workout.groups[0]) == nil,
                     "Nothing to remove, so the button is hidden")
        workout.removeLastSet(from: workout.groups[0])
        precondition(workout.groups[0].sets.count == 3 && workout.groups[0].completedCount == 3,
                     "Remove never deletes logged work")

        // Set 2 taken back to fix it. Remove used to delete the logged set 3.
        r2.unlog()
        precondition(workout.removableSet(in: workout.groups[0])?.id == r2.id)
        workout.removeLastSet(from: workout.groups[0])
        precondition(workout.groups[0].sets.map(\.id) == [r1.id, r3.id],
                     "The row nobody logged goes; the logged set 3 stays")
        precondition(workout.groups[0].sets.map(\.setIndex) == [0, 1])
        precondition(workout.removableSet(in: workout.groups[0]) == nil)
    }

    @MainActor static func removePrefersAWorkingSet(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_200)

        // S2 skipped for a busy rack, S3 logged and taken further, the drop
        // row not lifted yet. *Add set* adds working sets; its pair takes one.
        let skipped = WorkoutSession(title: "Prefer", startedAt: t0)
        context.insert(skipped)
        let s1 = row("S", order: 0, index: 0, in: skipped, context: context, loggedAt: t0)
        let s2 = row("S", order: 0, index: 1, in: skipped, context: context)
        let s3 = row("S", order: 0, index: 2, in: skipped, context: context, loggedAt: t0 + 200)
        let drop = row("S", order: 0, index: 3, in: skipped, context: context, kg: 60, continuation: true)
        let first = ActiveWorkout(session: skipped, context: context, history: [])
        precondition(first.removableSet(in: first.groups[0])?.id == s2.id)
        first.removeLastSet(from: first.groups[0])
        precondition(first.groups[0].sets.map(\.id) == [s1.id, s3.id, drop.id],
                     "The empty working set goes before the drop row")
        precondition(drop.isContinuation && first.groups[0].sets.map(\.setIndex) == [0, 1, 2])

        // T2 taken back with its drop still under it. Removing T2 would leave
        // the drop claiming to continue T1.
        let held = WorkoutSession(title: "Held", startedAt: t0)
        context.insert(held)
        let t1 = row("T", order: 0, index: 0, in: held, context: context, loggedAt: t0)
        let t2 = row("T", order: 0, index: 1, in: held, context: context)
        let tDrop = row("T", order: 0, index: 2, in: held, context: context, kg: 60, continuation: true)
        let second = ActiveWorkout(session: held, context: context, history: [])
        precondition(second.removableSet(in: second.groups[0])?.id == tDrop.id,
                     "A row holding up a continuation is passed over")
        second.removeLastSet(from: second.groups[0])
        precondition(second.groups[0].sets.map(\.id) == [t1.id, t2.id])

        // And with the drop logged there is nothing Remove may take.
        let logged = WorkoutSession(title: "Logged drop", startedAt: t0)
        context.insert(logged)
        row("U", order: 0, index: 0, in: logged, context: context, loggedAt: t0)
        row("U", order: 0, index: 1, in: logged, context: context)
        row("U", order: 0, index: 2, in: logged, context: context, kg: 60, loggedAt: t0 + 300,
            continuation: true)
        let third = ActiveWorkout(session: logged, context: context, history: [])
        precondition(third.removableSet(in: third.groups[0]) == nil)
        third.removeLastSet(from: third.groups[0])
        precondition(third.groups[0].sets.count == 3)
    }

    // MARK: LOG-01

    @MainActor static func reviewLeavesTheWorkingPosition(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_200)
        let session = WorkoutSession(title: "Review", startedAt: t0)
        context.insert(session)
        row("A-review", order: 0, index: 0, in: session, context: context, loggedAt: t0)
        row("B-review", order: 1, index: 0, in: session, context: context)
        let c1 = row("C-review", order: 2, index: 0, in: session, context: context)
        row("C-review", order: 2, index: 1, in: session, context: context)
        let workout = ActiveWorkout(session: session, context: context, history: [])
        precondition(workout.currentGroup?.catalogID == "B-review")

        // B's rack is taken, so the lifter picks C and lifts.
        precondition(!workout.openFromQueue("C-review"), "An unfinished exercise is not a review")
        precondition(workout.currentGroup?.catalogID == "C-review")
        workout.complete(c1, restSeconds: nil, at: t0.addingTimeInterval(400))

        // During the rest they look back at A to rate its last set.
        precondition(workout.openFromQueue("A-review"), "A finished exercise opens for review")
        precondition(session.preferredExerciseID == "C-review",
                     "Looking at A does not move the working position")
        precondition(workout.currentGroup?.catalogID == "C-review",
                     "The wrist, Lock Screen and dock stay on C")
        precondition(workout.nextSet?.catalogID == "C-review")

        // Picking an unfinished exercise still moves it.
        precondition(!workout.openFromQueue("B-review"))
        precondition(workout.currentGroup?.catalogID == "B-review")
        precondition(!workout.openFromQueue("missing-review"))
        precondition(workout.currentGroup?.catalogID == "B-review")
    }
}
