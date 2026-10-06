import Testing
import Foundation
@testable import GymTrack

/// Protects the one place kilograms become pounds, and the small formatters
/// that turn numbers into the words on screen: `WeightUnit`, the duration and
/// volume labels, and `SetFeel`, the four effort answers. Also the way back,
/// `StepperEntry.parse`, which reads what is typed into a weight or rep field.
///
/// The native counterpart of the arithmetic half of the legacy
/// `Tests/PoundLoadTests.swift`; the per-machine ladder lives in
/// `LoadScaleTests`.
@MainActor @Suite(.serialized)
struct UnitsTests {

    // MARK: - kg and lb

    @Test(arguments: [0.0, 0.5, 20, 60, 142.5, 997.9, 1_000])
    func kilogramsSurviveAPoundsRoundTrip(kg: Double) {
        let there = WeightUnit.lb.fromKg(kg)
        let back = WeightUnit.lb.toKg(there)
        #expect(abs(back - kg) < 1e-9)
        // Kilograms are the storage unit, so asking for them must be exact.
        #expect(WeightUnit.kg.fromKg(kg) == kg)
        #expect(WeightUnit.kg.toKg(kg) == kg)
    }

    @Test func conversionIsPlainArithmeticAtTheEdges() {
        #expect(WeightUnit.lb.fromKg(0) == 0)
        // A conversion does not clamp: refusing a negative is the entry
        // field's job, and a silent clamp here would hide it from a bad import.
        #expect(abs(WeightUnit.lb.fromKg(-10) + 22.0462262) < 1e-6)
        #expect(abs(WeightUnit.lb.fromKg(1_000) - 2_204.62262) < 1e-6)
        #expect(abs(WeightUnit.lb.toKg(45) - 20.4117) < 1e-3)
    }

    @Test func theTwoCeilingsAgreeInKilograms() {
        // A stepper in pounds must not let someone load a heavier bar than the
        // same stepper in kilograms, or flipping the unit would move the cap.
        let kgCeiling = LoadScale.kilograms.kilograms(LoadScale.kilograms.displayCeiling)
        let lbCeiling = LoadScale.standard(.lb).kilograms(LoadScale.standard(.lb).displayCeiling)
        #expect(kgCeiling == 1_000)
        #expect(abs(lbCeiling - kgCeiling) / kgCeiling < 0.01)
    }

    @Test func stepsAreTheOnesEachUnitsPlatesAreMadeIn() {
        #expect(WeightUnit.kg.step == 2.5)
        #expect(WeightUnit.lb.step == 5)
        #expect(WeightUnit.allCases == [.kg, .lb])
    }

    // MARK: - snap

    @Test(arguments: [
        (60.24, 60.0), (60.25, 60.5), (60.74, 60.5), (60.75, 61.0), (0.0, 0.0), (0.2, 0.0),
    ])
    func kilogramsSnapToHalves(input: Double, expected: Double) {
        #expect(WeightUnit.kg.snap(input) == expected)
    }

    @Test(arguments: [(135.4, 135.0), (135.5, 136.0), (0.4, 0.0), (0.5, 1.0), (1_000.0, 1_000.0)])
    func poundsSnapToWholes(input: Double, expected: Double) {
        #expect(WeightUnit.lb.snap(input) == expected)
    }

    @Test func snapIsIdempotent() {
        for unit in WeightUnit.allCases {
            for value in [0.0, 17.3, 62.5, 135.0, 999.9] {
                let once = unit.snap(value)
                #expect(unit.snap(once) == once)
            }
        }
    }

    // MARK: - format

    @Test func formatDropsTheDecimalOnWholeNumbersOnly() {
        #expect(WeightUnit.kg.format(60) == "60 kg")
        #expect(WeightUnit.kg.format(62.5) == "62.5 kg")
        #expect(WeightUnit.kg.format(0) == "0 kg")
        #expect(WeightUnit.kg.format(1_000) == "1000 kg")
        #expect(WeightUnit.kg.format(-5) == "-5 kg")
        // 60 kg is 132.277 lb: one decimal, not the two that would claim a
        // precision the plates do not have.
        #expect(WeightUnit.lb.format(60) == "132.3 lb")
        #expect(WeightUnit.lb.format(0) == "0 lb")
    }

    @Test func formatHonoursShowUnitAndDecimals() {
        #expect(WeightUnit.kg.format(60, showUnit: false) == "60")
        #expect(WeightUnit.kg.format(60, decimals: 2) == "60.00 kg")
        #expect(WeightUnit.kg.format(62.4, showUnit: false, decimals: 0) == "62")
        #expect(WeightUnit.lb.format(1, showUnit: false, decimals: 3) == "2.205")
        #expect(WeightUnit.kg.short == "kg")
        #expect(WeightUnit.lb.short == "lb")
    }

    @Test(arguments: [3.0, 6, 11, 12, 13, 22])
    func aWholeNumberOfPoundsReadsAsWhole(pounds: Double) {
        // 3 / 2.20462262 * 2.20462262 is 3.0000000000000004. These are the
        // first pound values whose trip through kilograms left that noise, and
        // each was labelled "3.0 lb" rather than "3 lb" (#3).
        let stored = WeightUnit.lb.toKg(pounds)
        #expect(WeightUnit.lb.format(stored) == "\(Int(pounds)) lb")
    }

    @Test func everyWholePoundUpToTheCeilingReadsAsWhole() {
        // About one whole pound value in ten picks up noise on the way through
        // kilograms, so a handful of examples cannot show none is left.
        let ceiling = Int(LoadScale.standard(.lb).displayCeiling)
        for pounds in 0...ceiling {
            let stored = WeightUnit.lb.toKg(Double(pounds))
            #expect(WeightUnit.lb.format(stored) == "\(pounds) lb")
        }
    }

    @Test(arguments: [(0.1, "0.1 lb"), (2.5, "2.5 lb"), (100.1, "100.1 lb"), (2_199.9, "2199.9 lb")])
    func aFractionOfAPoundKeepsItsDecimal(pounds: Double, label: String) {
        // The whole-number test forgives float noise, not a tenth the lifter
        // typed in.
        #expect(WeightUnit.lb.format(WeightUnit.lb.toKg(pounds)) == label)
    }

    // MARK: - Typed numbers

    /// The keypad types whatever the phone's region uses, so the weight and
    /// rep fields read Arabic-Indic and extended Arabic-Indic digits, the
    /// Arabic decimal separator and the decimal comma.
    @Test(arguments: [
        ("٦٠٫٥", 500.0, 60.5), ("۶۰٫۵", 500, 60.5), ("٦٠", 500, 60), ("60,5", 500, 60.5),
        ("60.5", 500, 60.5), ("١٢", 100, 12),
    ])
    func aTypedNumberIsReadInTheDigitsTheKeypadTypes(text: String, maximum: Double, value: Double) {
        #expect(StepperEntry.parse(text, maximum: maximum) == value)
    }

    /// Everything else is refused rather than guessed at: the Arabic thousands
    /// mark, fullwidth and Devanagari digits nobody's keypad offers, a space
    /// inside the number, hex, an exponent, mixed text, a second point, a
    /// negative, and a number past the field's ceiling.
    @Test(arguments: [
        ("1٬000", 5_000.0), ("６０", 500), ("६०", 500), ("6 0", 500), ("0x10", 500), ("1e2", 500),
        ("6٠a", 500), ("60.5.5", 500), ("-5", 500), ("٦٠٠", 500),
    ])
    func anythingElseTypedIsRefused(text: String, maximum: Double) {
        #expect(StepperEntry.parse(text, maximum: maximum) == nil)
    }

    // MARK: - Volume and duration labels

    @Test(arguments: [
        (0.0, "0"), (999.0, "999"), (1_000.0, "1.0k"), (12_400.0, "12.4k"), (100_000.0, "100.0k"),
    ])
    func compactVolumeSwitchesToKiloAtAThousand(volume: Double, label: String) {
        #expect(volume.compactVolume == label)
    }

    @Test(arguments: [
        (0.0, "0:00"), (59.0, "0:59"), (60.0, "1:00"), (3_599.0, "59:59"),
        (3_600.0, "1:00:00"), (3_661.0, "1:01:01"), (59.6, "1:00"),
    ])
    func clockStringRollsOverAtTheMinuteAndTheHour(seconds: TimeInterval, label: String) {
        #expect(seconds.clockString == label)
    }

    @Test(arguments: [
        (0.0, "0m"), (59.0, "0m"), (2_880.0, "48m"), (3_600.0, "1:00"), (3_661.0, "1:01"), (43_200.0, "12:00"),
    ])
    func shortDurationDropsSecondsAndSwitchesToClockAtAnHour(seconds: TimeInterval, label: String) {
        #expect(seconds.shortDurationString == label)
    }

    @Test(arguments: [
        (0.0, "0s"), (59.0, "59s"), (60.0, "1m"), (2_880.0, "48m"), (3_600.0, "1h 0m"), (3_661.0, "1h 1m"),
    ])
    func summaryDurationNamesTheLargestUnits(seconds: TimeInterval, label: String) {
        #expect(seconds.durationString == label)
    }

    // MARK: - SetFeel

    @Test func theFourAnswersStoreTheNumbersTheProgressionAlwaysRead() {
        #expect(SetFeel.allCases.map(\.rawValue) == [6, 8, 9, 10])
        #expect(SetFeel.allCases.map(\.label) == ["Easy", "Solid", "Hard", "All out"])
        #expect(Set(SetFeel.allCases.map(\.id)).count == 4)
    }

    @Test(arguments: [7.0, 8.5, 5, 0, 11, 10.0001, -8, .nan])
    func aStoredRatingThatIsNotOneOfTheFourIsNotAnAnswer(value: Double) {
        // A 7 from the old five-number strip is a number the lifter chose.
        // Calling it "Solid" would put a word in their mouth.
        #expect(SetFeel.answer(forStored: value) == nil)
    }

    @Test func eachStoredNumberIsExactlyOneAnswer() {
        #expect(SetFeel.answer(forStored: 6) == .easy)
        #expect(SetFeel.answer(forStored: 8) == .solid)
        #expect(SetFeel.answer(forStored: 9) == .hard)
        #expect(SetFeel.answer(forStored: 10) == .allOut)
        for feel in SetFeel.allCases {
            #expect(SetFeel.answer(forStored: feel.rawValue) == feel)
            #expect(SetFeel.nearest(to: feel.rawValue) == feel)
        }
    }

    @Test(arguments: [
        (-3.0, SetFeel.easy), (5.0, .easy), (6.9, .easy), (7.1, .solid), (8.6, .hard),
        (9.6, .allOut), (11.0, .allOut), (1_000.0, .allOut),
    ])
    func oldRatingsStillDrawAsTheNearestWord(value: Double, expected: SetFeel) {
        #expect(SetFeel.nearest(to: value) == expected)
    }

    @Test func exportKeysAreStableCamelCaseWords() {
        // The coach reads these out of the backup; relabelling a button must
        // never change them.
        #expect(SetFeel.allCases.map(\.exportKey) == ["easy", "solid", "hard", "allOut"])
    }
}
