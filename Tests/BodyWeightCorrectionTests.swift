import Foundation
import SwiftData

/// Run with scripts/test-body-weight-correction.sh; no simulator is needed.
///
/// Covers the rules that decide which Health sample a correction or a delete
/// may take back out. The HealthKit calls themselves need a real phone.
@main
struct BodyWeightCorrectionTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now).addingTimeInterval(8 * 3600)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        // A new entry holds no sample until Health confirms one was written,
        // and one saved without it reads back without it.
        let fresh = BodyMetric(date: twoDaysAgo, weightKg: 81)
        precondition(fresh.healthSampleID == nil, "A new weigh-in must not claim a Health sample")
        precondition(fresh.writtenSampleID == nil, "A new weigh-in has no sample to remove")
        precondition(fresh.source == BodyMetric.Source.manual.rawValue, "A new weigh-in is typed")
        context.insert(fresh)
        try context.save()
        let reread = try ModelContext(container).fetch(FetchDescriptor<BodyMetric>())
        precondition(reread.count == 1 && reread[0].healthSampleID == nil,
                     "An entry stored without a sample must read back without one")

        // A same-day correction removes the sample the first weigh-in wrote,
        // and nothing from another day.
        let typedA = UUID()
        let typedB = UUID()
        let mistyped = BodyMetric(date: today, weightKg: 8.2)
        mistyped.healthSampleID = typedA
        let dayBefore = BodyMetric(date: yesterday, weightKg: 82.4)
        dayBefore.healthSampleID = typedB
        let metrics = [mistyped, dayBefore, fresh]

        let laterToday = today.addingTimeInterval(4 * 3600)
        let replaced = BodyMetric.entry(sameDayAs: laterToday, in: metrics, calendar: calendar)
        precondition(replaced === mistyped, "A weigh-in later the same day must correct that day's entry")
        precondition(replaced?.writtenSampleID == typedA,
                     "A same-day correction must remove the sample the first weigh-in wrote")
        precondition(BodyMetric.entry(sameDayAs: yesterday, in: metrics, calendar: calendar)?.writtenSampleID == typedB,
                     "Each day's entry names only its own sample")
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        precondition(BodyMetric.entry(sameDayAs: threeDaysAgo, in: metrics, calendar: calendar) == nil,
                     "A weigh-in on an empty day replaces nothing, so no sample is removed")

        // A reading imported from a scale is never taken out of Health, even
        // if something ever left an ID on it.
        let scale = BodyMetric(date: today, weightKg: 82.1)
        scale.source = BodyMetric.Source.health.rawValue
        precondition(scale.writtenSampleID == nil, "An imported reading has no sample of ours to remove")
        scale.healthSampleID = UUID()
        precondition(scale.writtenSampleID == nil,
                     "An imported reading must never name a sample to delete, whatever ID it holds")
        let importedDay = BodyMetric.entry(sameDayAs: laterToday, in: [scale, dayBefore], calendar: calendar)
        precondition(importedDay === scale && importedDay?.writtenSampleID == nil,
                     "Correcting a day that came from Health must leave the scale's sample alone")

        // The ID survives a save, so a delete after a relaunch still knows
        // which sample to remove.
        context.insert(mistyped)
        try context.save()
        let stored = try ModelContext(container).fetch(FetchDescriptor<BodyMetric>())
            .first { $0.id == mistyped.id }
        precondition(stored?.healthSampleID == typedA, "The written sample's ID must be stored with the entry")

        print("Body weight correction tests passed")
    }
}
