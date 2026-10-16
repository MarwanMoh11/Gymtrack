import Foundation
import Testing
@testable import GymTrack

/// The plate calculator's arithmetic and the rule for which lifts get one.
@MainActor @Suite(.serialized)
struct PlateMathTests {

    private struct Case: CustomTestStringConvertible {
        let total: Double
        let unit: WeightUnit
        let perSide: [Double]
        var testDescription: String { "\(total) \(unit.short)" }
    }

    // MARK: - Exact loads

    @Test(arguments: [
        Case(total: 20, unit: .kg, perSide: []),
        Case(total: 60, unit: .kg, perSide: [20]),
        Case(total: 100, unit: .kg, perSide: [25, 15]),
        Case(total: 92.5, unit: .kg, perSide: [25, 10, 1.25]),
        Case(total: 62.5, unit: .kg, perSide: [20, 1.25]),
        Case(total: 22.5, unit: .kg, perSide: [1.25]),
        Case(total: 190, unit: .kg, perSide: [25, 25, 25, 10]),
        Case(total: 45, unit: .lb, perSide: []),
        Case(total: 135, unit: .lb, perSide: [45]),
        Case(total: 185, unit: .lb, perSide: [45, 25]),
        Case(total: 225, unit: .lb, perSide: [45, 45]),
        Case(total: 50, unit: .lb, perSide: [2.5]),
        Case(total: 95, unit: .lb, perSide: [25]),
    ])
    private func anExactLoadListsItsPlatesHeaviestFirst(_ c: Case) {
        #expect(PlateMath.outcome(total: c.total, unit: c.unit) == .exact(perSide: c.perSide))
    }

    @Test func aWeightConvertedFromKilogramsStillMakesExactly() {
        // Float noise from a stored kilogram value, in either unit, may not
        // leave an exact load a hair short.
        let kg = 62.5 + 1e-12
        let lb = WeightUnit.lb.fromKg(WeightUnit.lb.toKg(135))
        #expect(PlateMath.outcome(total: kg, unit: .kg) == .exact(perSide: [20, 1.25]))
        #expect(PlateMath.outcome(total: lb, unit: .lb) == .exact(perSide: [45]))
    }

    // MARK: - Unreachable

    @Test(arguments: [
        // total, unit, plates made, short
        (61.0, WeightUnit.kg, [20.0], 1.0),
        (20.5, WeightUnit.kg, [Double](), 0.5),
        (62.4, WeightUnit.kg, [20.0], 2.4),
        (46.0, WeightUnit.lb, [Double](), 1.0),
        (136.0, WeightUnit.lb, [45.0], 1.0),
    ])
    private func aLoadNoPlatesMakeSaysHowFarShortItFalls(
        _ total: Double, _ unit: WeightUnit, _ made: [Double], _ short: Double
    ) {
        guard case .unreachable(let perSide, let gap) = PlateMath.outcome(total: total, unit: unit) else {
            Issue.record("expected unreachable for \(total) \(unit.short)"); return
        }
        #expect(perSide == made)
        #expect(abs(gap - short) < 0.0001)
    }

    // MARK: - Below the bar

    @Test(arguments: [
        (19.0, WeightUnit.kg, 1.0),
        (0.0, WeightUnit.kg, 20.0),
        (44.0, WeightUnit.lb, 1.0),
        (0.0, WeightUnit.lb, 45.0),
    ])
    private func aLoadLighterThanTheBarIsNotAPlateLoad(_ total: Double, _ unit: WeightUnit, _ by: Double) {
        guard case .belowBar(let gap) = PlateMath.outcome(total: total, unit: unit) else {
            Issue.record("expected belowBar"); return
        }
        #expect(abs(gap - by) < 0.0001)
        #expect(PlateMath.outcome(total: total, unit: unit).perSide == nil)
    }

    @Test func aLighterBarMovesTheArithmetic() {
        #expect(PlateMath.outcome(total: 60, bar: 15, plates: PlateMath.standardPlates(.kg))
                == .exact(perSide: [20, 2.5]))
        #expect(PlateMath.outcome(total: 20, bar: 15, plates: PlateMath.standardPlates(.kg))
                == .exact(perSide: [2.5]))
    }

    @Test func platesAreUsedFromWhateverSetIsGiven() {
        // No 25s in this rack: 100 kg is 40 a side, so two 20s.
        #expect(PlateMath.outcome(total: 100, bar: 20, plates: [20, 10, 5]) == .exact(perSide: [20, 20]))
        #expect(PlateMath.outcome(total: 100, bar: 20, plates: []) == .unreachable(perSide: [], short: 80))
    }

    // MARK: - Words

    @Test(arguments: [
        ([25.0, 10, 2.5], "25 + 10 + 2.5"),
        ([1.25], "1.25"),
        ([Double](), "Bar only"),
    ])
    private func aCaptionReadsAsThePlatesAreStamped(_ plates: [Double], _ expected: String) {
        #expect(PlateMath.caption(plates) == expected)
    }

    @Test func theWristCaptionJoinsWithDots() {
        #expect(PlateMath.caption([20, 10, 2.5], separator: "·") == "20·10·2.5")
    }

    // MARK: - Which lifts

    @Test(arguments: [
        ("barbell-bench-press", ["Barbell", "Bench"], true),
        ("deadlift", ["Barbell"], true),
        ("barbell-back-squat", ["Barbell", "Other"], true),
        ("overhead-press", ["Barbell"], true),
        ("trap-bar-deadlift", ["Barbell"], false),
        ("preacher-curl-ez", ["Barbell", "Bench"], false),
        ("t-bar-row", ["Barbell", "Other"], false),
        ("landmine-press", ["Barbell"], false),
        ("dumbbell-bench-press", ["Dumbbell", "Bench"], false),
        ("lat-pulldown", ["Cable"], false),
        ("leg-press", ["Machine"], false),
        ("weighted-dip", ["Plate"], false),
        ("pull-up", ["None"], false),
        ("custom-thing", [], false),
    ])
    private func onlyAPlainBarGetsAPlateLine(_ id: String, _ equipment: [String], _ expected: Bool) {
        #expect(PlateMath.usesPlainBar(catalogID: id, equipment: equipment) == expected)
    }

    @Test func everyExcludedLiftIsARealCatalogBarbellExercise() {
        for id in PlateMath.notAPlainBar {
            let exercise = ExerciseCatalog.shared.exercise(id: id)
            #expect(exercise?.equipment.contains("Barbell") == true, "\(id) should be tagged Barbell")
        }
    }

    // MARK: - The bar

    @Test func theBarFollowsTheExercisesUnit() {
        #expect(BarWeight.standard.weight(in: .kg) == 20)
        #expect(BarWeight.standard.weight(in: .lb) == 45)
        let bench = ExerciseCatalog.shared.exercise(id: "barbell-bench-press")
        #expect(PlateLoading.bar(for: bench, scale: .standard(.lb), preset: .standard) == 45)
        #expect(PlateLoading.bar(for: bench, scale: .kilograms, preset: .light) == 15)
        let press = ExerciseCatalog.shared.exercise(id: "dumbbell-bench-press")
        #expect(PlateLoading.bar(for: press, scale: .kilograms, preset: .standard) == nil)
    }
}
