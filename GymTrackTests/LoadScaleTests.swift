import Testing
import Foundation
@testable import GymTrack

/// Protects the rule that every weight the app proposes is a rung the machine
/// in front of you actually has: `LoadScale` snapping, stepping, laddering and
/// formatting in both units, and the equipment table behind each default.
///
/// The native counterpart of the legacy `Tests/PoundLoadTests.swift` and
/// `Tests/LoadScale*Tests.swift`, which cover storage and merging; this file
/// covers the arithmetic and stays off the persisted overrides.
@MainActor @Suite(.serialized)
struct LoadScaleTests {

    /// Scales a real gym has, in both units: a barbell's microplates, a pin
    /// stack in pounds, a kettlebell rack.
    nonisolated static let scales: [LoadScale] = [
        LoadScale(unit: .kg, increment: 1.25), LoadScale(unit: .kg, increment: 2),
        LoadScale(unit: .kg, increment: 2.5), LoadScale(unit: .kg, increment: 4),
        LoadScale(unit: .kg, increment: 5), LoadScale(unit: .lb, increment: 2.5),
        LoadScale(unit: .lb, increment: 5), LoadScale(unit: .lb, increment: 10),
        LoadScale(unit: .lb, increment: 15),
    ]

    /// Whether a display-unit value sits on the scale's own ladder.
    private func isRung(_ display: Double, of scale: LoadScale) -> Bool {
        let rungs = display / scale.increment
        return abs(rungs - rungs.rounded()) < 1e-9
    }

    // MARK: - Construction

    @Test func aZeroOrNegativeIncrementFallsBackToTheUnitsStep() {
        // A zero step would freeze every stepper on the screen.
        #expect(LoadScale(unit: .kg, increment: 0).increment == 2.5)
        #expect(LoadScale(unit: .lb, increment: -5).increment == 5)
        #expect(LoadScale(unit: .kg, increment: .nan).increment == 2.5)
        #expect(LoadScale(unit: .kg, increment: 1.25).increment == 1.25)
        #expect(LoadScale.standard(.lb) == LoadScale(unit: .lb, increment: 5))
    }

    // MARK: - Snapping

    @Test(arguments: LoadScaleTests.scales)
    func everySnappedWeightIsARungOfTheMachinesOwnLadder(scale: LoadScale) {
        for kg in [0.1, 3.7, 17.3, 42.5, 59.99, 100.01, 187.7, 400] {
            let snapped = scale.snap(kg: kg)
            #expect(isRung(scale.display(snapped), of: scale), "\(kg) kg on \(scale.incrementLabel)")
            // Snapping never wanders further than half a rung from the request.
            #expect(abs(scale.display(snapped) - scale.display(kg)) <= scale.increment / 2 + 1e-9)
            // And snapping what is already a rung leaves it alone.
            #expect(abs(scale.snap(kg: snapped) - snapped) < 1e-9)
        }
    }

    @Test func aFivePoundRungIsAboutTwoPointTwoSevenKilograms() {
        let stack = LoadScale(unit: .lb, increment: 5)
        #expect(abs(stack.incrementKg - 2.2680) < 1e-3)
        // 60 kg is 132.3 lb, which a stack that moves in fives cannot show:
        // the nearest pin is 130 lb.
        #expect(stack.snap(display: 132.28) == 130)
        #expect(abs(stack.display(stack.snap(kg: 60)) - 130) < 1e-9)
    }

    @Test func microplatesLandOnQuarterKilograms() {
        let plates = LoadScale(unit: .kg, increment: 1.25)
        #expect(plates.snap(kg: 61) == 61.25)
        #expect(plates.snap(kg: 60.5) == 60)
        #expect(plates.snap(kg: 60.7) == 61.25)
    }

    @Test func nothingBelowHalfARungOrBelowZeroSnapsToAWeight() {
        let machine = LoadScale(unit: .kg, increment: 5)
        #expect(machine.snap(kg: 0) == 0)
        #expect(machine.snap(kg: -20) == 0)
        #expect(machine.snap(kg: 2.4) == 0)
        #expect(machine.snap(kg: 2.6) == 5)
        #expect(machine.snap(display: -3) == 0)
    }

    // MARK: - Stepping

    @Test func steppingMovesExactlyOneRung() {
        let barbell = LoadScale.kilograms
        #expect(barbell.step(display: 60, by: 1) == 62.5)
        #expect(barbell.step(display: 60, by: -1) == 57.5)
        #expect(barbell.step(display: 60, by: 0) == 60)
        // The size of the direction is ignored: one rung, however hard you push.
        #expect(barbell.step(display: 60, by: 9) == 62.5)
        #expect(barbell.step(display: 60, by: -9) == 57.5)
    }

    @Test func theFirstStepFromATypedWeightPullsItBackOntoTheLadder() {
        let barbell = LoadScale.kilograms
        #expect(barbell.step(display: 61, by: 1) == 62.5)
        #expect(barbell.step(display: 61, by: -1) == 60)
        #expect(barbell.step(display: 0.4, by: -1) == 0)
    }

    @Test func steppingNeverGoesBelowZero() {
        for scale in LoadScaleTests.scales {
            #expect(scale.step(display: 0, by: -1) == 0)
            #expect(scale.step(kg: 0, by: -1) == 0)
            #expect(scale.step(display: scale.increment / 2, by: -1) == 0)
        }
    }

    @Test func conversionNoiseDoesNotCostARung() {
        let barbell = LoadScale.kilograms
        // 62.5 plus or minus a float hair is still the 62.5 rung.
        #expect(barbell.step(display: 62.5 + 1e-10, by: 1) == 65)
        #expect(barbell.step(display: 62.5 - 1e-10, by: -1) == 60)
        // The same through a pounds round trip: 225 lb stored as kg and back.
        let stack = LoadScale(unit: .lb, increment: 5)
        for pounds in [45.0, 95, 135, 225, 315] {
            let kg = WeightUnit.lb.toKg(pounds)
            #expect(abs(stack.display(stack.step(kg: kg, by: 1)) - (pounds + 5)) < 1e-9)
            #expect(abs(stack.display(stack.step(kg: kg, by: -1)) - (pounds - 5)) < 1e-9)
        }
    }

    @Test(arguments: LoadScaleTests.scales)
    func upThenDownReturnsToTheStartingRung(scale: LoadScale) {
        let start = scale.snap(kg: 100)
        let there = scale.step(kg: start, by: 1)
        #expect(there > start)
        #expect(abs(scale.step(kg: there, by: -1) - start) < 1e-9)
        #expect(abs((there - start) - scale.incrementKg) < 1e-9)
    }

    // MARK: - Ladder

    @Test func theLadderIsAscendingAndKeepsTheCentre() {
        let kg = LoadScale.kilograms.ladder(around: 60)
        #expect(kg == [55, 57.5, 60, 62.5, 65])
        let lb = LoadScale(unit: .lb, increment: 5).ladder(around: 100)
        // 100 kg is 220.46 lb, so the centre rung is 220.
        #expect(lb == [210, 215, 220, 225, 230])
        #expect(LoadScale.kilograms.ladder(around: 60, rungs: 1) == [57.5, 60, 62.5])
        #expect(LoadScale.kilograms.ladder(around: 60, rungs: 0) == [60])
    }

    @Test func theLadderSlidesInsteadOfShrinkingNearZero() {
        let barbell = LoadScale.kilograms
        let atZero = barbell.ladder(around: 0)
        #expect(atZero == [0, 2.5, 5, 7.5, 10])
        let nearZero = barbell.ladder(around: 2.5, rungs: 3)
        #expect(nearZero.first == 0)
        #expect(nearZero.count == 7)
        #expect(nearZero.contains(2.5))
        #expect(barbell.ladder(around: -50).allSatisfy { $0 >= 0 })
        #expect(barbell.ladder(around: -50).count == 5)
    }

    @Test(arguments: LoadScaleTests.scales)
    func everyLadderRungIsOnTheLadder(scale: LoadScale) {
        let ladder = scale.ladder(around: 80, rungs: 4)
        #expect(ladder.count == 9)
        #expect(ladder == ladder.sorted())
        #expect(Set(ladder).count == ladder.count)
        #expect(ladder.allSatisfy { isRung($0, of: scale) })
    }

    // MARK: - Formatting

    @Test(arguments: [(5.0, 0), (2.0, 0), (2.5, 1), (0.5, 1), (1.25, 2), (0.25, 2)])
    func decimalsAreWhatTheLadderCanLandOn(increment: Double, places: Int) {
        #expect(LoadScale(unit: .kg, increment: increment).decimals == places)
    }

    @Test func textIsRoundedToWhatTheEquipmentCanExpress() {
        let stack = LoadScale(unit: .lb, increment: 2.5)
        // 60 kg on a machine marked in pounds is 132.3, not 132.28.
        #expect(stack.text(132.2774) == "132.3")
        #expect(stack.text(132) == "132")
        #expect(LoadScale(unit: .lb, increment: 5).text(132.2774) == "132")
        let plates = LoadScale(unit: .kg, increment: 1.25)
        #expect(plates.text(61.25) == "61.25")
        #expect(plates.text(61.2500001) == "61.25")
        #expect(plates.text(61.5) == "61.5")
        #expect(plates.text(60) == "60")
    }

    @Test func formatAndLabelsReadTheStoredKilograms() {
        #expect(LoadScale.kilograms.format(62.5) == "62.5 kg")
        #expect(LoadScale.kilograms.format(60, showUnit: false) == "60")
        #expect(LoadScale(unit: .lb, increment: 5).format(60) == "132 lb")
        #expect(LoadScale.kilograms.incrementLabel == "2.5 kg")
        #expect(LoadScale(unit: .lb, increment: 5).incrementLabel == "5 lb")
        #expect(LoadScale.kilograms.shortLabel == "kg · 2.5")
        #expect(LoadScale(unit: .lb, increment: 10).shortLabel == "lb · 10")
    }

    @Test(arguments: [
        (0.0, "0"), (60.0, "60"), (62.5, "62.5"), (1.25, "1.25"), (1.2501, "1.25"), (-2.5, "-2.5"),
    ])
    func trimKeepsOnlyThePrecisionTheNumberNeeds(value: Double, label: String) {
        #expect(LoadScale.trim(value) == label)
    }

    // MARK: - Choices and conversion

    @Test(arguments: WeightUnit.allCases)
    func theOfferedIncrementsAreAscendingAndIncludeTheUnitsDefault(unit: WeightUnit) {
        let choices = LoadScale.choices(for: unit)
        #expect(!choices.isEmpty)
        #expect(choices == choices.sorted())
        #expect(Set(choices).count == choices.count)
        #expect(choices.allSatisfy { $0 > 0 })
        #expect(choices.contains(unit.step))
    }

    @Test(arguments: [
        (WeightUnit.kg, 2.5, WeightUnit.lb, 5.0), (.kg, 5, .lb, 10), (.kg, 1.25, .lb, 2.5),
        (.kg, 10, .lb, 20), (.lb, 5, .kg, 2.5), (.lb, 10, .kg, 5), (.lb, 15, .kg, 5),
        (.lb, 25, .kg, 10), (.lb, 1, .kg, 0.5),
    ])
    func flippingAMachinesUnitKeepsTheJumpRoughlyWhatItWas(
        from: WeightUnit, increment: Double, to: WeightUnit, expected: Double
    ) {
        let converted = LoadScale(unit: from, increment: increment).converted(to: to)
        #expect(converted.unit == to)
        #expect(converted.increment == expected)
        #expect(LoadScale.choices(for: to).contains(converted.increment))
    }

    @Test func convertingToTheSameUnitChangesNothing() {
        let scale = LoadScale(unit: .kg, increment: 4)
        #expect(scale.converted(to: .kg) == scale)
    }

    @Test(arguments: [1.25, 2.5, 5.0])
    func aKilogramScaleSurvivesAPoundsDetour(increment: Double) {
        let original = LoadScale(unit: .kg, increment: increment)
        #expect(original.converted(to: .lb).converted(to: .kg) == original)
    }

    // MARK: - Equipment defaults

    @Test(arguments: [
        ("Machine", 5.0, 10.0), ("Cable", 2.5, 5.0), ("Kettlebell", 4.0, 5.0), ("Dumbbell", 2.0, 5.0),
        ("Barbell", 2.5, 5.0), ("Plate", 1.25, 2.5), ("Band", 1.0, 2.5),
    ])
    func eachKindOfKitHasItsOwnJumpInBothUnits(equipment: String, kg: Double, lb: Double) {
        #expect(LoadScaleBook.increment(for: equipment, in: .kg) == kg)
        #expect(LoadScaleBook.increment(for: equipment, in: .lb) == lb)
    }

    @Test(arguments: ["", "Trampoline", "barbell", "Bench", "Other"])
    func equipmentNobodyListedGetsTheBodyweightBeltDefault(equipment: String) {
        // Spelled exactly: a lower-case "barbell" is not a barbell here, and
        // the catalog's own spelling is what the table is keyed on.
        #expect(LoadScaleBook.increment(for: equipment, in: .kg) == 1.25)
        #expect(LoadScaleBook.increment(for: equipment, in: .lb) == 2.5)
    }

    @Test func theMostSpecificEquipmentDecidesTheJump() {
        func exercise(_ equipment: [String]) -> CatalogExercise {
            CatalogExercise(id: "x", name: "X", category: "strength", muscleGroups: ["Chest"],
                            equipment: equipment, details: nil, difficulty: nil, tracking: .weightReps)
        }
        // A cable crossover is a stack, even with a bench listed beside it.
        #expect(LoadScaleBook.defaultIncrement(for: exercise(["Cable", "Bench"]), in: .kg) == 2.5)
        // A machine beats a barbell, as in a smith or hack squat.
        #expect(LoadScaleBook.defaultIncrement(for: exercise(["Barbell", "Machine"]), in: .kg) == 5)
        #expect(LoadScaleBook.defaultIncrement(for: exercise(["Barbell", "Bench"]), in: .lb) == 5)
        #expect(LoadScaleBook.defaultIncrement(for: exercise([]), in: .kg) == 1.25)
        #expect(LoadScaleBook.defaultIncrement(for: nil, in: .lb) == 2.5)
    }

    @Test func aDerivedScaleTakesTheRequestedUnitNotTheSettings() {
        let barbell = CatalogExercise(id: "x", name: "X", category: "strength", muscleGroups: ["Chest"],
                                      equipment: ["Barbell"], details: nil, difficulty: nil, tracking: .weightReps)
        #expect(LoadScaleBook.derived(for: barbell, unit: .lb) == LoadScale(unit: .lb, increment: 5))
        #expect(LoadScaleBook.derived(for: barbell, unit: .kg) == LoadScale(unit: .kg, increment: 2.5))
        #expect(LoadScaleBook.derived(for: nil, unit: .kg) == LoadScale(unit: .kg, increment: 1.25))
    }
}
