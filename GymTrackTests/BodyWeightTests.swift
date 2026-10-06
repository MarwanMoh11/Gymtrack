import Testing
import Foundation
import SwiftData
@testable import GymTrack

/// Protects which Health sample a body-weight correction or delete may take
/// back out of Health: only the one GymTrack wrote for that day's weigh-in,
/// and never a reading imported from a scale. The HealthKit calls themselves
/// need a real phone.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BodyWeightTests {

    private let calendar = TestClock.calendar
    /// 08:00 on the reference Wednesday.
    private let today = TestClock.at("2026-03-11T08:00:00")

    private func day(_ offset: Int) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: offset, to: today))
    }

    /// Health hands back a sample's ID only once it has written one, so a new
    /// entry claiming one would point a later delete at nothing, or at
    /// someone else's sample.
    @Test func aNewWeighInHoldsNoSampleAndReadsBackWithoutOne() throws {
        let container = try TestStore.container()
        let context = ModelContext(container)
        let fresh = BodyMetric(date: try day(-2), weightKg: 81)
        #expect(fresh.healthSampleID == nil)
        #expect(fresh.writtenSampleID == nil)
        #expect(fresh.source == BodyMetric.Source.manual.rawValue)
        context.insert(fresh)
        try context.save()

        let reread = try ModelContext(container).fetch(FetchDescriptor<BodyMetric>())
        #expect(reread.count == 1)
        #expect(reread.first?.healthSampleID == nil)
    }

    @Test func aSameDayCorrectionRemovesOnlyThatDaysSample() throws {
        let yesterday = try day(-1)
        let threeDaysAgo = try day(-3)
        let typedA = UUID()
        let typedB = UUID()
        let mistyped = BodyMetric(date: today, weightKg: 8.2)
        mistyped.healthSampleID = typedA
        let dayBefore = BodyMetric(date: yesterday, weightKg: 82.4)
        dayBefore.healthSampleID = typedB
        let untouched = BodyMetric(date: try day(-2), weightKg: 81)
        let metrics = [mistyped, dayBefore, untouched]

        let replaced = BodyMetric.entry(sameDayAs: today.addingTimeInterval(4 * 3_600), in: metrics, calendar: calendar)
        #expect(replaced === mistyped, "A weigh-in later the same day corrects that day's entry")
        #expect(replaced?.writtenSampleID == typedA)
        #expect(BodyMetric.entry(sameDayAs: yesterday, in: metrics, calendar: calendar)?.writtenSampleID == typedB)
        // A weigh-in on an empty day replaces nothing, so no sample is removed.
        #expect(BodyMetric.entry(sameDayAs: threeDaysAgo, in: metrics, calendar: calendar) == nil)
    }

    /// A scale's reading is a real measurement. Deleting a mistyped entry must
    /// never take it out of Health with it, whatever ID something left on it.
    @Test func aReadingImportedFromHealthNeverNamesASampleToDelete() throws {
        let scale = BodyMetric(date: today, weightKg: 82.1)
        scale.source = BodyMetric.Source.health.rawValue
        #expect(scale.writtenSampleID == nil)
        scale.healthSampleID = UUID()
        #expect(scale.writtenSampleID == nil)

        let dayBefore = BodyMetric(date: try day(-1), weightKg: 82.4)
        dayBefore.healthSampleID = UUID()
        let corrected = BodyMetric.entry(sameDayAs: today.addingTimeInterval(4 * 3_600), in: [scale, dayBefore],
                                         calendar: calendar)
        #expect(corrected === scale)
        #expect(corrected?.writtenSampleID == nil)
    }

    /// The ID survives a save, so a delete after a relaunch still knows which
    /// sample to remove.
    @Test func theWrittenSamplesIDIsStoredWithTheEntry() throws {
        let container = try TestStore.container()
        let typed = UUID()
        let entry = BodyMetric(date: today, weightKg: 82.4)
        entry.healthSampleID = typed
        let context = ModelContext(container)
        context.insert(entry)
        try context.save()

        let stored = try ModelContext(container).fetch(FetchDescriptor<BodyMetric>()).first { $0.id == entry.id }
        #expect(stored?.healthSampleID == typed)
    }
}
