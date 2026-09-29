import Foundation
import SwiftData

/// SESS-01, SESS-02, the carried-load undo and the one-walk history read.
/// Run with scripts/test-slot-offers.sh; no simulator is needed.
@main
struct SlotOffersTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        try repeatedSlotOffer(context)
        try supersetKeepsBothOffers(context)
        try undoRestoresCarriedPrefill(context)
        try historyWalkMatchesPerExerciseReads(context)
        print("Slot offer checks passed")
    }

    @MainActor
    static func row(_ id: String, _ index: Int, kg: Double, reps: Int, range: (Int, Int),
                    in session: WorkoutSession, done: Bool = false,
                    _ context: ModelContext) -> SetLog {
        let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                         weightKg: kg, reps: reps, targetRepsLow: range.0, targetRepsHigh: range.1,
                         tracking: .weightReps)
        if done { set.isCompleted = true; set.completedAt = .now }
        set.session = session
        context.insert(set)
        return set
    }

    /// A top pair and a back-off three of one movement, last done as three
    /// heavy sets and two back-offs, so the two slots' histories differ in size.
    @MainActor static func repeatedSlotOffer(_ context: ModelContext) throws {
        let plan = Plan(name: "Slots"), day = PlanDay(name: "Day", order: 0)
        day.plan = plan
        context.insert(plan); context.insert(day)
        for (order, count, kg, reps) in [(0, 2, 60.0, 6), (1, 3, 40.0, 10)] {
            let item = PlanItem(catalogID: "slot-test", name: "slot-test", order: order, targetSets: count,
                                targetRepsLow: reps, targetRepsHigh: reps, targetWeightKg: kg)
            item.day = day
            context.insert(item)
        }
        let past = WorkoutSession(title: "Last week", startedAt: .now.addingTimeInterval(-86_400 * 7))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        context.insert(past)
        let lastWeek: [(Double, Int)] = [(60, 6), (60, 6), (60, 6), (40, 10), (45, 10)]
        for (index, (kg, reps)) in lastWeek.enumerated() {
            _ = row("slot-test", index, kg: kg, reps: reps, range: (reps, reps), in: past, done: true, context)
        }
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [past])
        let workout = ActiveWorkout(session: session, context: context, history: [past])
        let rows = session.exerciseGroups[0].sets
        precondition(rows.count == 5)
        let (top0, top1, back0, back1) = (rows[0], rows[1], rows[2], rows[3])
        let backLoad = back0.weightKg, topLoad = top0.weightKg

        // The card reads its own slot: the prescription, and last time's share.
        precondition(workout.planItem(for: top0)?.targetSets == 2)
        precondition(workout.planItem(for: back0)?.targetSets == 3,
                     "The back-off card must read the back-off prescription, not the first slot's")
        precondition(workout.lastPerformance(for: top0).map(\.weightKg) == [60, 60, 60])
        precondition(workout.lastPerformance(for: back1).map(\.weightKg) == [40, 45],
                     "The back-off must be read against last time's back-off")
        precondition(workout.previousSet(for: back0)?.weightKg == 40,
                     "Pairing is by position within the slot; the merged position gave a heavy set")
        precondition(workout.previousSet(for: back1)?.weightKg == 45)

        // An offer made on the top set covers the top slot and nothing else.
        top0.reps = 6
        workout.complete(top0, restSeconds: nil)
        workout.rate(top0, feel: .easy)
        guard let offer = workout.pendingNudge(for: "slot-test") else { preconditionFailure("Missing offer") }
        precondition(offer.setCount == 1, "Offer counted \(offer.setCount) sets; the top slot has one left")
        workout.apply(offer)
        precondition(top1.weightKg == offer.toKg)
        precondition([back0, back1, rows[4]].allSatisfy { $0.weightKg == backLoad },
                     "Taking the top slot's offer moved the back-off's sets")

        // Lifting a back-off set does not answer the top slot's offer.
        workout.complete(back0, restSeconds: nil)
        precondition(workout.takenNudge(for: "slot-test") != nil, "A back-off set settled the top slot's take")
        workout.undoTakenNudge(workout.takenNudge(for: "slot-test")!)
        precondition(top1.weightKg == topLoad && back1.weightKg == back0.weightKg)
    }

    /// Rating the other half of a superset used to overwrite the standing offer.
    @MainActor static func supersetKeepsBothOffers(_ context: ModelContext) throws {
        let session = WorkoutSession(title: "Superset")
        context.insert(session)
        var rows: [String: [SetLog]] = [:]
        for (order, id) in ["ss-a", "ss-b"].enumerated() {
            rows[id] = (0..<3).map { index in
                let set = row(id, index, kg: 40, reps: index == 0 ? 12 : 8, range: (8, 12), in: session, context)
                set.exerciseOrder = order
                return set
            }
        }
        let workout = ActiveWorkout(session: session, context: context, history: [])
        for id in ["ss-a", "ss-b"] {
            workout.complete(rows[id]![0], restSeconds: nil)
            workout.rate(rows[id]![0], feel: .easy)
        }
        precondition(workout.pendingNudge(for: "ss-a") != nil, "Rating the partner dropped the first offer")
        precondition(workout.pendingNudge(for: "ss-b") != nil)
        let (offerA, offerB) = (workout.pendingNudge(for: "ss-a")!, workout.pendingNudge(for: "ss-b")!)
        workout.apply(offerA)
        workout.apply(offerB)
        guard let takenA = workout.takenNudge(for: "ss-a"), workout.takenNudge(for: "ss-b") != nil else {
            preconditionFailure("The second take cost the first its undo")
        }
        workout.undoTakenNudge(takenA)
        precondition(rows["ss-a"]![1].weightKg == 40 && rows["ss-b"]![1].weightKg == offerB.toKg)
        precondition(workout.pendingNudge(for: "ss-a") != nil && workout.pendingNudge(for: "ss-b") == nil)

        // Re-rating the same exercise still replaces its own offer.
        workout.rate(rows["ss-a"]![0], feel: .solid)
        precondition(workout.pendingNudge(for: "ss-a") == nil)
    }

    /// Undoing a set takes back the load it carried onto the rows below.
    @MainActor static func undoRestoresCarriedPrefill(_ context: ModelContext) throws {
        let session = WorkoutSession(title: "Carry")
        context.insert(session)
        let sets = (0..<3).map { row("carry-test", $0, kg: 50, reps: 8, range: (8, 12), in: session, context) }
        let workout = ActiveWorkout(session: session, context: context, history: [])
        sets[0].weightKg = 60
        workout.complete(sets[0], restSeconds: nil)
        precondition(sets[1].weightKg == 60 && sets[2].weightKg == 60)
        workout.uncomplete(sets[0])
        precondition(sets[1].weightKg == 50 && sets[2].weightKg == 50,
                     "The rows below kept the weight of a set that was undone")

        // A row the lifter has since typed into is theirs and stays.
        workout.complete(sets[0], restSeconds: nil)
        sets[1].weightKg = 65
        workout.uncomplete(sets[0])
        precondition(sets[1].weightKg == 65 && sets[2].weightKg == 50)
    }

    /// The single walk answers what the one-at-a-time reads answer.
    @MainActor static func historyWalkMatchesPerExerciseReads(_ context: ModelContext) throws {
        var history: [WorkoutSession] = []
        for (age, ids) in [(1, ["hw-a"]), (2, ["hw-a", "hw-b"]), (3, ["hw-c", "hw-b"])] {
            let past = WorkoutSession(title: "Past \(age)", startedAt: .now.addingTimeInterval(-86_400 * Double(age)))
            past.endedAt = past.startedAt.addingTimeInterval(3_000)
            context.insert(past)
            for id in ids {
                for index in 0..<2 {
                    _ = row(id, index, kg: Double(age) * 10 + Double(index), reps: 8, range: (8, 12),
                            in: past, done: true, context)
                }
            }
            history.append(past)
        }
        let open = WorkoutSession(title: "Open")
        context.insert(open)
        history.append(open)
        let wanted: Set<String> = ["hw-a", "hw-b", "hw-c", "hw-never"]
        let walked = SessionFactory.lastPerformances(of: wanted, in: history)
        for id in wanted {
            precondition(walked[id]?.map(\.id) == TrainingStats.lastPerformance(of: id, in: history).map(\.id),
                         "History walk disagrees for \(id)")
        }
        precondition(walked["hw-never"] == [] && walked["hw-a"]?.first?.weightKg == 10)
        let without = SessionFactory.lastPerformances(of: ["hw-a"], in: history, excluding: history[0].id)
        precondition(without["hw-a"]?.first?.weightKg == 20)
    }
}
