import Testing
import Foundation
import SwiftData
@testable import GymTrack

/// Protects the double-progression advice: work up the rep range at a load,
/// add exactly one rung of the machine's own ladder when every prescribed set
/// clears the top, back off only when the load was what stopped the lifter, and
/// never propose a weight the equipment cannot be set to, in kilograms or in
/// pounds. Also what the logger opens a planned slot at because of it.
@MainActor @Suite(.serialized)
struct ProgressionSuggestionTests {

    private let bench = "barbell-bench-press"
    typealias Action = TrainingStats.OverloadSuggestion.Action

    nonisolated static let poundsPerKilo = 2.20462262

    private func near(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.001 }

    /// Completed sets of the given weights and reps, logged in `tracking`
    /// whatever the catalog says now, and all rated `feel`.
    private func work(_ pairs: [(Double, Int)], id: String = "barbell-bench-press",
                      tracking: TrackingMode = .weightReps, feel: SetFeel? = nil) -> [SetLog] {
        pairs.enumerated().map { index, pair in
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                             weightKg: pair.0, reps: pair.1, targetRepsLow: 8, targetRepsHigh: 12, tracking: tracking)
            set.isCompleted = true
            set.rpe = feel?.rawValue
            return set
        }
    }

    /// Runs `body` with the app-wide unit set to `unit`, then puts it back.
    /// Every exercise nobody corrected reads its ladder through the unit, and an
    /// ID the catalog doesn't know has no equipment, so its ladder is the
    /// unit's finest: on a phone in pounds every rung below would move.
    private func inUnit(_ unit: WeightUnit, _ body: () throws -> Void) throws {
        let saved = AppSettings.shared.weightUnit
        defer { AppSettings.shared.weightUnit = saved }
        AppSettings.shared.weightUnit = unit
        try #require(LoadScaleBook.shared.overrides.isEmpty, "A ladder corrected elsewhere is still in force")
        try body()
    }

    /// The sets the logger opens a 3 x 8-12 slot of `id` with, after `last`.
    private func opening(after last: [SetLog], id: String, in context: ModelContext) throws -> [SetLog] {
        let plan = Plan(name: "Opening")
        let day = PlanDay(name: "Day", order: 0)
        let slot = PlanItem(catalogID: id, name: id, order: 0, targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
        let past = WorkoutSession(title: "Last", startedAt: TestClock.reference.addingTimeInterval(-86_400))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        context.insert(plan)
        context.insert(day)
        context.insert(slot)
        context.insert(past)
        day.plan = plan
        slot.day = day
        for set in last {
            set.session = past
            context.insert(set)
        }
        let built = SessionFactory.build(day: day, plan: plan, context: context, history: [past])
        return try #require(built.exerciseGroups.first).sets
    }

    private func item(_ id: String = "barbell-bench-press", sets: Int = 3, low: Int = 8, high: Int = 12,
                      target: Double = 40) -> PlanItem {
        PlanItem(catalogID: id, name: id, order: 0, targetSets: sets, targetRepsLow: low,
                 targetRepsHigh: high, targetWeightKg: target)
    }

    /// Completed sets at one weight, with an optional rating per set.
    private func sets(_ kg: Double, _ reps: [Int], rpe: [Double?] = [], seconds: Int = 0,
                      id: String = "barbell-bench-press") -> [SetLog] {
        reps.enumerated().map { index, count in
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                             weightKg: kg, reps: count, seconds: seconds)
            set.isCompleted = true
            set.rpe = index < rpe.count ? rpe[index] : nil
            return set
        }
    }

    /// Runs `body` with the exercise's ladder set to `scale`, then forgets it.
    private func pinned(_ scale: LoadScale, for id: String = "barbell-bench-press", _ body: () throws -> Void) rethrows {
        LoadScaleBook.shared.set(scale, for: id)
        defer { LoadScaleBook.shared.clearAll() }
        try body()
    }

    private func isRung(_ kg: Double, of scale: LoadScale) -> Bool {
        let rungs = scale.display(kg) / scale.increment
        return abs(rungs - rungs.rounded()) < 1e-9
    }

    // MARK: - First time and the climb

    @Test func withNoHistoryTheAdviceIsTheBaselineTheSlotAsksFor() {
        let advice = TrainingStats.suggestion(for: item(target: 40), lastSets: [])
        #expect(advice.action == .firstTime)
        #expect(advice.weightKg == 40)
        #expect(advice.reps == 8)
        #expect(!advice.message.isEmpty)
        #expect(TrainingStats.suggestion(for: item(target: 0), lastSets: []).weightKg == 0)
    }

    @Test(arguments: [
        (WeightUnit.kg, 2.5, 60.0), (.kg, 5, 100), (.kg, 1.25, 61.25), (.kg, 2, 24),
        (.lb, 5, 135), (.lb, 10, 140), (.lb, 2.5, 22.5),
    ])
    func clearingTheTopOfTheRangeOnEverySetAddsExactlyOneRung(unit: WeightUnit, increment: Double, start: Double) {
        let scale = LoadScale(unit: unit, increment: increment)
        let lastKg = scale.kilograms(start)
        pinned(scale) {
            let advice = TrainingStats.suggestion(for: item(), lastSets: sets(lastKg, [12, 12, 12]))
            #expect(advice.action == .increaseWeight)
            #expect(abs(scale.display(advice.weightKg) - (start + increment)) < 1e-9)
            #expect(abs((advice.weightKg - lastKg) - scale.incrementKg) < 1e-9)
            #expect(advice.reps == 8)
        }
    }

    @Test func insideTheRangeTheGoalIsOneMoreRepAtTheSameLoad() {
        pinned(.kilograms) {
            let advice = TrainingStats.suggestion(for: item(), lastSets: sets(60, [10, 10, 9]))
            #expect(advice.action == .addReps)
            #expect(advice.weightKg == 60)
            #expect(advice.reps == 10)
            // One short of the top asks for the top, and never past it.
            let near = TrainingStats.suggestion(for: item(), lastSets: sets(60, [12, 12, 11]))
            #expect(near.action == .addReps)
            #expect(near.reps == 12)
        }
    }

    @Test func aWeightOffTheLadderIsPulledOntoItBeforeAnythingIsPrescribed() {
        pinned(.kilograms) {
            let climb = TrainingStats.suggestion(for: item(), lastSets: sets(61, [12, 12, 12]))
            #expect(climb.weightKg == 62.5)
            let stay = TrainingStats.suggestion(for: item(), lastSets: sets(61, [10, 10, 10]))
            #expect(stay.weightKg == 60)
        }
    }

    // MARK: - Only a finished session moves the load

    @Test func aSessionThatSkippedSetsDoesNotBeatTheLoad() {
        pinned(.kilograms) {
            let short = TrainingStats.suggestion(for: item(sets: 3), lastSets: sets(60, [12, 12]))
            #expect(short.action == .repeatLoad)
            #expect(short.weightKg == 60)
            #expect(short.reps == 8)
            // A lighter technique set of the same lift is not one of the three.
            let mixed = sets(40, [12]) + sets(60, [12, 12])
            #expect(TrainingStats.suggestion(for: item(sets: 3), lastSets: mixed).action == .repeatLoad)
            // Nothing prescribed still means one set has to be done.
            let none = TrainingStats.suggestion(for: item(sets: 0), lastSets: sets(60, [12]))
            #expect(none.action == .increaseWeight)
        }
    }

    @Test func theHeaviestWeightDecidesWhichSetsCount() {
        pinned(.kilograms) {
            let advice = TrainingStats.suggestion(for: item(), lastSets: sets(40, [12]) + sets(60, [10, 10, 10]))
            #expect(advice.action == .addReps)
            #expect(advice.weightKg == 60)
            #expect(advice.reps == 11)
        }
    }

    @Test func aRangeWithNoTopCanNeverClimb() {
        pinned(.kilograms) {
            let advice = TrainingStats.suggestion(for: item(low: 0, high: 0), lastSets: sets(60, [12, 12, 12]))
            #expect(advice.action == .repeatLoad)
            #expect(advice.weightKg == 60)
            // It holds the reps that were done, not a range met by every set.
            let held = TrainingStats.suggestion(for: item(low: 0, high: 0), lastSets: sets(60, [10, 10, 10]))
            #expect(held.action != .increaseWeight)
            #expect(held.weightKg == 60)
            #expect(held.reps == 10)
        }
    }

    /// One set at the top of the range and then an early finish, or a light
    /// technique set, would otherwise read as the session cleared.
    @Test func onlyALastTimeThatDidThePrescribedWorkMovesTheLoad() throws {
        try inUnit(.kg) {
            let press = "progress-test"
            let early = TrainingStats.suggestion(for: item(press), lastSets: work([(60, 12)], id: press))
            #expect(early.action == .repeatLoad)
            #expect(early.weightKg == 60)
            #expect(early.reps == 8)
            let dropped = TrainingStats.suggestion(for: item(press), lastSets: work([(60, 12), (60, 12), (57.5, 12)], id: press))
            #expect(dropped.action == .repeatLoad, "Two of three sets at the load have not beaten it")
            #expect(dropped.weightKg == 60)
            let technique = TrainingStats.suggestion(for: item(press, low: 6, high: 8), lastSets: work([(40, 20)], id: press))
            #expect(technique.action != .increaseWeight)
            #expect(technique.weightKg == 40)
            let cleared = TrainingStats.suggestion(for: item(press), lastSets: work([(60, 12), (60, 12), (60, 12)], id: press))
            #expect(cleared.action == .increaseWeight)
            #expect(cleared.weightKg > 60)
        }
    }

    /// Last time's short count belongs to last time's load. A rebuild that
    /// opened at it would open at the reps it is meant to fix.
    @Test func aHeldOrLoweredLoadOpensAtTheBottomOfTheRange() throws {
        try inUnit(.kg) {
            let context = try TestStore.context()
            let press = "progress-test"
            let deload = try opening(after: work([(60, 4), (60, 4), (60, 4)], id: press, feel: .hard), id: press, in: context)
            #expect(deload.count == 3)
            #expect(deload.allSatisfy { $0.weightKg < 60 && $0.reps == 8 }, "A deload opens at 8, not at last time's 4")
            let easyShort = try opening(after: work([(60, 5), (60, 5), (60, 5)], id: press, feel: .easy), id: press, in: context)
            #expect(easyShort.count == 3)
            #expect(easyShort.allSatisfy { $0.weightKg == 60 && $0.reps == 8 }, "A held load opens at 8, not at last time's 5")
            let partial = try opening(after: work([(60, 12)], id: press), id: press, in: context)
            #expect(partial.count == 3)
            #expect(partial.allSatisfy { $0.weightKg == 60 && $0.reps == 8 })
        }
    }

    // MARK: - Both units

    /// A barbell's rung is 2.5 kg or 5 lb, read through the phone's unit. 60 kg
    /// is 132.3 lb, between two pound rungs, so a climb must land on 135 lb
    /// rather than on 132.3 plus a pound-sized step.
    @Test(arguments: WeightUnit.allCases)
    func aBarbellProgressesOnTheRungsOfThePhonesUnit(unit: WeightUnit) throws {
        let pounds = unit == .lb
        func onRung(_ kg: Double) -> Bool {
            let rungs = unit.fromKg(kg) / (pounds ? 5 : 2.5)
            return abs(rungs - rungs.rounded()) < 0.001
        }
        try inUnit(unit) {
            let climb = TrainingStats.suggestion(for: item(), lastSets: work([(60, 12), (60, 12), (60, 12)]))
            #expect(climb.action == .increaseWeight)
            #expect(near(climb.weightKg, pounds ? 135 / Self.poundsPerKilo : 62.5), "\(climb.weightKg)")
            #expect(onRung(climb.weightKg))

            // The load is pulled onto the ladder first: a rung comes back
            // exactly, and a load between rungs is held at the nearest one.
            let onLadder = pounds ? 135 / Self.poundsPerKilo : 60
            let held = TrainingStats.suggestion(for: item(), lastSets: work([(onLadder, 12)]))
            #expect(held.action == .repeatLoad)
            #expect(near(held.weightKg, onLadder))
            #expect(held.reps == 8)
            let snapped = TrainingStats.suggestion(for: item(), lastSets: work([(pounds ? 60 : 61, 12)]))
            #expect(snapped.action == .repeatLoad)
            #expect(near(snapped.weightKg, pounds ? 130 / Self.poundsPerKilo : 60), "\(snapped.weightKg)")

            let deload = TrainingStats.suggestion(for: item(), lastSets: work([(onLadder, 4), (onLadder, 4), (onLadder, 4)], feel: .hard))
            #expect(deload.action == .deload)
            #expect(near(deload.weightKg, pounds ? 130 / Self.poundsPerKilo : 57.5), "\(deload.weightKg)")
            let offDeload = TrainingStats.suggestion(for: item(), lastSets: work([(60, 4), (60, 4), (60, 4)], feel: .hard))
            #expect(offDeload.weightKg < 60)
            #expect(onRung(offDeload.weightKg))

            // 135 lb stored in kilograms reads back as 135.0000001 lb, and still
            // climbs exactly one rung.
            let next = TrainingStats.suggestion(for: item(), lastSets: work([(onLadder, 12), (onLadder, 12), (onLadder, 12)]))
            #expect(near(next.weightKg, pounds ? 140 / Self.poundsPerKilo : 62.5), "\(next.weightKg)")
        }
    }

    @Test(arguments: WeightUnit.allCases)
    func theLoggerOpensAClearedBarbellOnTheNextRungOfThePhonesUnit(unit: WeightUnit) throws {
        try inUnit(unit) {
            let context = try TestStore.context()
            let opened = try opening(after: work([(60, 12), (60, 12), (60, 12)]), id: bench, in: context)
            let expected = unit == .kg ? 62.5 : 135 / Self.poundsPerKilo
            #expect(opened.count == 3)
            #expect(opened.allSatisfy { near($0.weightKg, expected) }, "\(opened.map(\.weightKg))")
        }
    }

    // MARK: - Falling short

    @Test(arguments: [
        ([5, 5, 5], Action.deload), ([12, 12, 5], .deload), ([9, 6, 5], .deload), ([4, 4, 4], .deload),
        ([6, 6, 6], .addReps), ([12, 12, 6], .addReps), ([8, 7, 6], .addReps),
    ])
    func repsMoreThanTwoBelowTheRangeBackOffOneRung(reps: [Int], expected: Action) {
        pinned(.kilograms) {
            let advice = TrainingStats.suggestion(for: item(), lastSets: sets(60, reps))
            #expect(advice.action == expected)
            if expected == .deload {
                #expect(advice.weightKg == 57.5)
                #expect(advice.reps == 8)
            } else {
                #expect(advice.weightKg == 60)
            }
        }
    }

    @Test(arguments: [
        (6.0, Action.repeatLoad), (8.0, .repeatLoad), (9.0, .deload), (10.0, .deload),
    ])
    func shortRepsOnlyTakeWeightOffWhenTheWeightIsWhatStoppedYou(rating: Double, expected: Action) {
        pinned(.kilograms) {
            let advice = TrainingStats.suggestion(for: item(), lastSets: sets(60, [5, 5, 5], rpe: [rating, rating, rating]))
            #expect(advice.action == expected)
            #expect(advice.weightKg == (expected == .deload ? 57.5 : 60))
        }
    }

    @Test func theBottomRungIsNeverDeloadedBelow() {
        pinned(.kilograms) {
            let floor = TrainingStats.suggestion(for: item(), lastSets: sets(2.5, [3, 3, 3]))
            #expect(floor.action == .addReps)
            #expect(floor.weightKg == 2.5)
            let above = TrainingStats.suggestion(for: item(), lastSets: sets(5, [3, 3, 3]))
            #expect(above.action == .deload)
            #expect(above.weightKg == 2.5)
        }
    }

    // MARK: - How it felt

    @Test(arguments: [(6.0, 65.0), (8.0, 62.5), (9.0, 62.5), (10.0, 62.5)])
    func easyAtTheTopJumpsTwoRungsAndTheOtherAnswersOne(rating: Double, expected: Double) {
        pinned(.kilograms) {
            let rated = sets(60, [12, 12, 12], rpe: [rating, rating, rating])
            #expect(TrainingStats.suggestion(for: item(), lastSets: rated).weightKg == expected)
        }
    }

    @Test func eachAnswerIsAnswerableInTheAdviceItDraws() {
        pinned(.kilograms) {
            let ratings: [Double] = [6, 8, 9, 10]
            var inRange: [TrainingStats.OverloadSuggestion] = []
            var atTop: [TrainingStats.OverloadSuggestion] = []
            for rating in ratings {
                let ratedMid = sets(60, [10, 10, 10], rpe: [rating, rating, rating])
                inRange.append(TrainingStats.suggestion(for: item(), lastSets: ratedMid))
                let ratedTop = sets(60, [12, 12, 12], rpe: [rating, rating, rating])
                atTop.append(TrainingStats.suggestion(for: item(), lastSets: ratedTop))
            }
            // An answer that led to the same advice as every other would be a
            // question not worth asking.
            #expect(Set(inRange.map(\.message)).count == 4)
            #expect(inRange.allSatisfy { $0.action == .addReps && $0.weightKg == 60 })
            #expect(Set(atTop.map(\.message)).count == 4)
            #expect(atTop.allSatisfy { $0.action == .increaseWeight })
        }
    }

    @Test func unratedSetsDoNotDiluteTheMedian() {
        #expect(TrainingStats.medianRPE(of: []) == nil)
        #expect(TrainingStats.medianRPE(of: sets(60, [10, 10], rpe: [nil, nil])) == nil)
        #expect(TrainingStats.medianRPE(of: sets(60, [10, 10, 10], rpe: [nil, 9, nil])) == 9)
        #expect(TrainingStats.medianRPE(of: sets(60, [10, 10, 10, 10], rpe: [6, 8, 10, 9])) == 9)
        #expect(TrainingStats.feel(of: sets(60, [10, 10, 10], rpe: [nil, nil, 8.6])) == .hard)
        #expect(TrainingStats.feel(of: []) == nil)
        pinned(.kilograms) {
            // One set marked easy among three unmarked ones is still an easy session.
            let lone = sets(60, [12, 12, 12], rpe: [6, nil, nil])
            #expect(TrainingStats.suggestion(for: item(), lastSets: lone).weightKg == 65)
        }
    }

    // MARK: - Every weight is a rung

    @Test(arguments: [
        LoadScale(unit: .kg, increment: 2.5), LoadScale(unit: .kg, increment: 5), LoadScale(unit: .kg, increment: 1.25),
        LoadScale(unit: .lb, increment: 5), LoadScale(unit: .lb, increment: 10),
    ])
    func noMatterWhatWasLiftedTheAdviceLandsOnThisMachinesLadder(scale: LoadScale) {
        pinned(scale) {
            for lastKg in [47.3, 61, 77.7, 100.1] {
                for reps in [[12, 12, 12], [10, 10, 9], [5, 5, 5], [12, 12, 5]] {
                    let advice = TrainingStats.suggestion(for: item(), lastSets: sets(lastKg, reps))
                    #expect(isRung(advice.weightKg, of: scale), "\(lastKg) kg x \(reps) on \(scale.incrementLabel)")
                }
            }
        }
    }

    @Test func theIncrementTheCardNamesIsTheOneTheLadderUses() {
        pinned(.kilograms) {
            #expect(TrainingStats.weightIncrement(for: item()) == 2.5)
        }
        pinned(LoadScale(unit: .lb, increment: 5)) {
            #expect(abs(TrainingStats.weightIncrement(for: item()) - 2.2680) < 1e-3)
        }
    }

    // MARK: - Work with no weight to add

    @Test func unloadedWorkAddsRepsAndNeverInventsAWeight() {
        let pullUp = item("pull-up", target: 0)
        let top = TrainingStats.suggestion(for: pullUp, lastSets: sets(0, [12, 12, 12], id: "pull-up"))
        #expect(top.action == .addReps)
        #expect(top.weightKg == 0)
        #expect(top.reps == 13)
        let easy = TrainingStats.suggestion(for: pullUp, lastSets: sets(0, [12, 12, 12], rpe: [6, 6, 6], id: "pull-up"))
        #expect(easy.reps == 15)
        // Far below the range still does not deload a bar that was never loaded.
        let low = TrainingStats.suggestion(for: pullUp, lastSets: sets(0, [3, 3, 3], id: "pull-up"))
        #expect(low.action == .addReps)
        #expect(low.weightKg == 0)
    }

    @Test func aTimedHoldAsksForFiveMoreSecondsAndNoWeight() {
        let plank = item("plank-bodyweight", target: 0)
        let advice = TrainingStats.suggestion(for: plank, lastSets: sets(0, [0, 0], seconds: 45, id: "plank-bodyweight"))
        #expect(advice.action == .addReps)
        #expect(advice.weightKg == 0)
        #expect(advice.message.contains("50s"))
    }

    /// Movements the library once filed under strength are done at bodyweight.
    /// Rows logged before that keep the mode they were logged in, and a load of
    /// zero is no load in every mode: climbing a rung from it would prescribe a
    /// 1.25 kg dip nobody ever did.
    @Test func bodyweightWorkNeverClimbsToALoadNobodyLifted() throws {
        for id in ["chest-dip", "hyper-extension", "tibialis-raise", "ghd-back-extension"] {
            #expect(ExerciseCatalog.shared.exercise(id: id)?.tracking == .bodyweightReps, "\(id) is done at bodyweight")
        }
        for id in ["wrist-roller", "walking-lunge-weighted-vest"] {
            #expect(ExerciseCatalog.shared.exercise(id: id)?.tracking == .weightReps, "\(id) carries a real load")
        }
        try inUnit(.kg) {
            let snapshotted = work([(0, 12), (0, 12), (0, 12)], id: "chest-dip", tracking: .weightReps)
            #expect(snapshotted.allSatisfy { $0.tracking == .weightReps })
            let dip = TrainingStats.suggestion(for: item("chest-dip", target: 0), lastSets: snapshotted)
            #expect(dip.action != .increaseWeight)
            #expect(dip.weightKg == 0)
            let easy = work([(0, 12), (0, 12), (0, 12)], id: "progress-test", feel: .easy)
            let zero = TrainingStats.suggestion(for: item("progress-test", target: 0), lastSets: easy)
            #expect(zero.action != .increaseWeight)
            #expect(zero.weightKg == 0)
        }
    }

    // MARK: - An exercise the catalog doesn't know
    // With no equipment to go by, its ladder is the unit's finest: 1.25 kg.

    @Test func aLighterBackOffSetDoesNotHideAClearedLoad() throws {
        try inUnit(.kg) {
            let cleared = work([(60, 12), (60, 12), (60, 12), (40, 12)], id: "gap-test")
            #expect(TrainingStats.suggestion(for: item("gap-test"), lastSets: cleared).action == .increaseWeight)
        }
    }

    @Test func aHardSessionOneRepShortOfTheTopAimsForTheTopAndNoFurther() throws {
        try inUnit(.kg) {
            let hard = work([(60, 11), (60, 11), (60, 11)], id: "gap-test", feel: .hard)
            #expect(TrainingStats.suggestion(for: item("gap-test"), lastSets: hard).reps == 12)
        }
    }

    @Test func aHardSessionOnTheLightestRungHasNoRungBelowToDeloadTo() throws {
        try inUnit(.kg) {
            let slot = item("gap-test")
            let lightest = slot.loadScale.incrementKg
            let hard = work([(lightest, 4), (lightest, 4), (lightest, 4)], id: "gap-test", feel: .hard)
            #expect(TrainingStats.suggestion(for: slot, lastSets: hard).action != .deload)
        }
    }
}
