import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// The rules behind the Measurements card: a blank field stores nothing, a
/// part is compared with the last check-in that measured that part (not simply
/// the last check-in), inches are accepted and stored as centimetres, and a
/// deleted check-in is gone from the store.
///
/// What the export writes for a check-in is in `BackupExportFidelityTests`.
@MainActor @Suite(.serialized)
struct BodyMeasurementTests {

    private func day(_ offset: Int) -> Date {
        TestClock.calendar.date(byAdding: .day, value: offset, to: TestClock.reference)!
    }

    private func checkIn(_ offset: Int, _ parts: [BodyMeasurement.Part: Double]) -> BodyMeasurement {
        let row = BodyMeasurement(date: day(offset))
        for (part, cm) in parts { row.set(cm, for: part) }
        return row
    }

    /// Waist measured monthly, arm weekly, and the thigh once.
    private func history() -> [BodyMeasurement] {
        [
            checkIn(0, [.arm: 36, .waist: 84]),
            checkIn(7, [.arm: 36.5]),
            checkIn(14, [.arm: 37]),
            checkIn(28, [.waist: 83, .thigh: 58]),
        ]
    }

    // MARK: - Typing

    @Test(arguments: ["", "  "])
    func aBlankFieldStoresNothing(text: String) {
        #expect(MeasurementEntry.parse(text, unit: .kg) == .blank)
    }

    @Test(arguments: [
        ("36.5", WeightUnit.kg, 36.5),
        ("36,5", .kg, 36.5),
        // Inches, stored as centimetres to a tenth.
        ("14.5", .lb, 36.8),
    ])
    func aLengthIsKeptInCentimetres(text: String, unit: WeightUnit, cm: Double) {
        #expect(MeasurementEntry.parse(text, unit: unit) == .cm(cm))
    }

    /// Zero, a negative, a length no tape reads, text and NaN. Held back
    /// rather than clamped into a value, so the slip is seen.
    @Test(arguments: ["0", "-4", "380", "abc", "nan"])
    func aSlipIsHeldBackRatherThanStored(text: String) {
        #expect(MeasurementEntry.parse(text, unit: .kg) == .invalid)
    }

    // MARK: - The model

    @Test func onlyAMeasuredPartHoldsAValue() {
        let one = BodyMeasurement(date: day(0))
        #expect(!one.hasAnyPart)

        one.set(84, for: .waist)
        one.set(0, for: .arm)
        one.set(.nan, for: .chest)
        #expect(one.hasAnyPart)
        #expect(one.waistCm == 84)
        // A zero or a NaN stores nothing, not a zero.
        #expect(one.armCm == nil)
        #expect(one.chestCm == nil)

        one.set(nil, for: .waist)
        #expect(!one.hasAnyPart, "clearing the only part must leave nothing")
    }

    // MARK: - The card

    /// A check-in that skipped a part is passed over rather than read as no
    /// change.
    @Test func eachPartComparesWithItsOwnPreviousReading() throws {
        let waist = try #require(MeasurementTrend.reading(for: .waist, in: history()))
        #expect(waist.cm == 83)
        #expect(waist.changeCm == -1)
        #expect(waist.previousDate == day(0))

        let arm = try #require(MeasurementTrend.reading(for: .arm, in: history()))
        #expect(arm.cm == 37)
        #expect(arm.changeCm == 0.5)
        #expect(arm.previousDate == day(7))

        let thigh = try #require(MeasurementTrend.reading(for: .thigh, in: history()))
        #expect(thigh.cm == 58)
        #expect(thigh.changeCm == nil, "a part measured once has no change")
        #expect(thigh.previousDate == nil)

        #expect(MeasurementTrend.reading(for: .chest, in: history()) == nil)
    }

    @Test func readingsFollowTheCheckInsOrderAndCheckInsListNewestFirst() {
        #expect(MeasurementTrend.readings(in: history()).map(\.part) == [.arm, .waist, .thigh])
        #expect(MeasurementTrend.readings(in: []).isEmpty)
        #expect(MeasurementTrend.newestFirst(history()).map(\.date) == [day(28), day(14), day(7), day(0)])
    }

    @Test(arguments: [
        // A whole centimetre drops its decimal, a fractional one keeps it.
        (84.0, WeightUnit.kg, "84 cm"),
        (36.5, .kg, "36.5 cm"),
        (36.8, .lb, "14.5 in"),
    ])
    func aLengthShowsInTheUnitSetting(cm: Double, unit: WeightUnit, label: String) {
        #expect(MeasurementTrend.length(cm, unit: unit) == label)
    }

    @Test(arguments: [
        (1.0, "+1.0 cm"),
        (-0.5, "-0.5 cm"),
        // A move that rounds to nothing says so, rather than reporting a gain.
        (0.04, "no change"),
    ])
    func aChangeIsSignedOrSaysThereIsNone(cm: Double, label: String) {
        #expect(MeasurementTrend.change(cm, unit: .kg) == label)
    }

    // MARK: - Deleting

    @Test func aDeletedCheckInIsGoneFromTheStoreAndTheCardReadsAsIfItNeverHappened() throws {
        let container = try TestStore.context().container
        let context = ModelContext(container)
        let kept = checkIn(0, [.waist: 84])
        let doomed = checkIn(7, [.waist: 90])
        context.insert(kept)
        context.insert(doomed)
        try context.save()

        context.delete(doomed)
        try context.save()

        // A fresh context reads the store, not the first one's objects.
        let left = try ModelContext(container).fetch(FetchDescriptor<BodyMeasurement>())
        #expect(left.map(\.id) == [kept.id])
        let waist = try #require(MeasurementTrend.reading(for: .waist, in: left))
        #expect(waist.cm == 84)
        #expect(waist.changeCm == nil)
    }
}
