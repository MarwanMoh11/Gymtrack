import Testing
import Foundation
@testable import GymTrack

/// Protects the double-progression advice: work up the rep range at a load,
/// add exactly one rung of the machine's own ladder when every prescribed set
/// clears the top, back off only when the load was what stopped the lifter, and
/// never propose a weight the equipment cannot be set to.
///
/// The native counterpart of the legacy `Tests/ProgressionSuggestionTests.swift`,
/// which covers the feel-by-feel wording; this file covers the arithmetic.
@MainActor @Suite(.serialized)
struct ProgressionSuggestionTests {

    private let bench = "barbell-bench-press"
    typealias Action = TrainingStats.OverloadSuggestion.Action

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
}
