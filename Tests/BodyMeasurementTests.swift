import Foundation
import SwiftData

/// Run with scripts/test-body-measurements.sh; no simulator is needed.
///
/// Covers the rules behind the Measurements card: a blank field stores
/// nothing, a part is compared with the last check-in that measured that part
/// (not simply the last check-in), inches are accepted and stored as
/// centimetres, and a deleted check-in is gone from the store.
@main
struct BodyMeasurementTests {
    nonisolated(unsafe) static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date(timeIntervalSinceReferenceDate: 800_000_000))!
    }

    static func checkIn(_ offset: Int, _ parts: [BodyMeasurement.Part: Double]) -> BodyMeasurement {
        let row = BodyMeasurement(date: day(offset))
        for (part, cm) in parts { row.set(cm, for: part) }
        return row
    }

    @MainActor static func main() throws {
        // Typing: blank stores nothing, a real length is kept in centimetres,
        // and a slip is held back instead of being clamped into a value.
        check(MeasurementEntry.parse("", unit: .kg) == .blank, "An empty field is blank")
        check(MeasurementEntry.parse("  ", unit: .kg) == .blank, "A field of spaces is blank")
        check(MeasurementEntry.parse("36.5", unit: .kg) == .cm(36.5), "Centimetres are kept as typed")
        check(MeasurementEntry.parse("36,5", unit: .kg) == .cm(36.5), "A decimal comma is read")
        check(MeasurementEntry.parse("14.5", unit: .lb) == .cm(36.8), "Inches are stored as centimetres to a tenth")
        check(MeasurementEntry.parse("0", unit: .kg) == .invalid, "Zero is not a measurement")
        check(MeasurementEntry.parse("-4", unit: .kg) == .invalid, "A negative length is refused")
        check(MeasurementEntry.parse("380", unit: .kg) == .invalid, "A length no tape reads is refused")
        check(MeasurementEntry.parse("abc", unit: .kg) == .invalid, "Text is refused")
        check(MeasurementEntry.parse("nan", unit: .kg) == .invalid, "NaN is refused")

        // The model: only measured parts hold a value.
        let one = BodyMeasurement(date: day(0))
        check(!one.hasAnyPart, "A new check-in holds nothing")
        one.set(84, for: .waist)
        one.set(0, for: .arm)
        one.set(.nan, for: .chest)
        check(one.hasAnyPart && one.waistCm == 84, "A measured part is stored")
        check(one.armCm == nil && one.chestCm == nil, "A zero or NaN stores nothing, not a zero")
        one.set(nil, for: .waist)
        check(!one.hasAnyPart, "Clearing the only part leaves nothing")

        // The card: waist measured monthly, arm weekly. Each part compares
        // with its own previous reading, and a check-in that skipped a part
        // is passed over rather than read as no change.
        let history = [
            checkIn(0, [.arm: 36, .waist: 84]),
            checkIn(7, [.arm: 36.5]),
            checkIn(14, [.arm: 37]),
            checkIn(28, [.waist: 83, .thigh: 58]),
        ]
        let waist = MeasurementTrend.reading(for: .waist, in: history)
        check(waist?.cm == 83 && waist?.changeCm == -1 && waist?.previousDate == day(0),
              "Waist is 83, down 1 against the check-in on day 0, got \(String(describing: waist))")
        let arm = MeasurementTrend.reading(for: .arm, in: history)
        check(arm?.cm == 37 && arm?.changeCm == 0.5 && arm?.previousDate == day(7),
              "Arm is 37, up 0.5 against day 7, got \(String(describing: arm))")
        let thigh = MeasurementTrend.reading(for: .thigh, in: history)
        check(thigh?.cm == 58 && thigh?.changeCm == nil && thigh?.previousDate == nil,
              "A part measured once has no change")
        check(MeasurementTrend.reading(for: .chest, in: history) == nil, "A part never measured has no reading")
        check(MeasurementTrend.readings(in: history).map(\.part) == [.arm, .waist, .thigh],
              "Readings run in the order the check-in asks, without the unmeasured parts")
        check(MeasurementTrend.readings(in: []).isEmpty, "No check-ins, no readings")
        check(MeasurementTrend.newestFirst(history).map(\.date) == [day(28), day(14), day(7), day(0)],
              "Check-ins are listed newest first")

        // Display follows the unit setting.
        check(MeasurementTrend.length(84, unit: .kg) == "84 cm", "A whole centimetre drops its decimal")
        check(MeasurementTrend.length(36.5, unit: .kg) == "36.5 cm", "A fractional centimetre keeps one")
        check(MeasurementTrend.length(36.8, unit: .lb) == "14.5 in", "Centimetres show as inches under pounds")
        check(MeasurementTrend.change(1, unit: .kg) == "+1.0 cm", "A gain is signed")
        check(MeasurementTrend.change(-0.5, unit: .kg) == "-0.5 cm", "A loss is signed")
        check(MeasurementTrend.change(0.04, unit: .kg) == "no change", "A change that rounds to nothing says so")

        // Delete is a hard delete: the row is gone from a fresh context too.
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let kept = checkIn(0, [.waist: 84])
        let doomed = checkIn(7, [.waist: 90])
        context.insert(kept)
        context.insert(doomed)
        try context.save()
        context.delete(doomed)
        try context.save()
        let left = try ModelContext(container).fetch(FetchDescriptor<BodyMeasurement>())
        check(left.count == 1 && left[0].id == kept.id, "A deleted check-in must be gone from the store")
        let afterDelete = MeasurementTrend.reading(for: .waist, in: left)
        check(afterDelete?.cm == 84 && afterDelete?.changeCm == nil,
              "With the check-in deleted the card must read as if it never happened")

        guard failures == 0 else { preconditionFailure("\(failures) measurement check(s) failed") }
        print("Body measurement tests passed")
    }
}
