import Foundation
import Testing
@testable import GymTrack

// What this file protects: what a number typed into a stepper, or stepped to,
// is allowed to become. Every rule here exists because of a crash or a stored
// value nobody lifted: twenty digits trapped `Int(_:)` mid-workout, `1e999`
// became a weight of infinity that the backup could not encode, and 1000 typed
// for 100 went into the record as a measured set.

@MainActor @Suite(.serialized)
struct StepperEntryTests {
    /// A weight field's ceiling, as the logger hands it to `parse`.
    private static let weight = 500.0

    // MARK: Typed text

    @Test(arguments: ["1e999", "inf", "nan", "1000", "-5", ""])
    func typedTextThatIsNoLiftableWeightIsRefused(text: String) {
        // Infinity, not a number, past the ceiling, negative, and nothing at all:
        // each leaves the field as it was.
        #expect(StepperEntry.parse(text, maximum: Self.weight) == nil)
    }

    @Test func twentyDigitsAreRefusedRatherThanTrapping() {
        #expect(StepperEntry.parse("99999999999999999999", maximum: 3_600) == nil)
    }

    @Test(arguments: [("500", 500.0), (" 100 ", 100), ("60,5", 60.5), ("٦٠٫٥", 60.5)])
    func typedTextInsideTheRangeReadsAsItsNumber(text: String, value: Double) {
        // The ceiling itself, surrounding spaces, the decimal comma, and
        // Arabic-Indic digits with their own separator.
        #expect(StepperEntry.parse(text, maximum: Self.weight) == value)
    }

    @Test func negativeZeroReadsAsZeroSoAFieldNeverShowsMinusZero() {
        #expect(StepperEntry.parse("-0", maximum: Self.weight).map(\.sign) == .plus)
    }

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

    // MARK: Whole counts

    @Test(arguments: [
        (value: 1e20, maximum: 100, current: 8, expected: nil as Int?),
        (value: Double.infinity, maximum: 100, current: 8, expected: nil),
        (value: Double.nan, maximum: 100, current: 8, expected: nil),
        (value: Double(Int.max), maximum: 100, current: Int.max, expected: nil),
        (value: 12.7, maximum: 100, current: 8, expected: 12),
        (value: 101, maximum: StepperEntry.maximumReps, current: 100, expected: nil),
        // A count stored before the ceiling can still be stepped down.
        (value: 149, maximum: 100, current: 150, expected: 149),
    ])
    func aCountIsCheckedBeforeItBecomesAnInt(value: Double, maximum: Int, current: Int, expected: Int?) {
        #expect(StepperEntry.count(value, maximum: maximum, current: current) == expected)
    }

    // MARK: Steps

    @Test(arguments: [
        (value: 1_000.0, current: 100.0, accepted: false),
        // On the way down from a weight stored before there was a ceiling.
        (value: 997.5, current: 1_000.0, accepted: true),
        (value: -2.5, current: 0.0, accepted: false),
    ])
    func aStepIsTakenInsideTheRangeOrDownTowardsIt(value: Double, current: Double, accepted: Bool) {
        #expect(StepperEntry.accepts(value, maximum: Self.weight, current: current) == accepted)
    }
}
