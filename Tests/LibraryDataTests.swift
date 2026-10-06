import Foundation
import SwiftData

/// Run with scripts/test-library-data.sh; no simulator is needed.
///
/// Two test gaps from the 2026-09-28 review that the earlier scripts left open.
///
/// XC-06: the GT-012 rep reset was only tested through repeated slots and
/// through the held and deloaded loads. What a plain, non-repeated slot opens
/// at after a cleared session (the branch GT-012 originally fixed) and after
/// one that earned more reps rather than more load was not.
///
/// LIB-10: `LoadScale` round trips in pounds, where every value goes through a
/// 2.20462 conversion and a stored kilogram never lands exactly on a rung, and
/// edits to a custom exercise reaching the catalog and search. The search
/// prefix cases and the tracking-edit retrack already live in
/// test-library-fixes.sh and test-custom-exercise-launch.sh; the export side of
/// custom edits and of lb scales is in test-backup-round-trip.sh.
@main
struct LibraryDataTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor static func main() throws {
        let container = try makeContainer()
        try openingRepsOnASingleSlot(ModelContext(container))
        try lbLadderRoundTrips()
        try lbScalePersistsAndDrivesTheOpeningWeight(container)
        try editedCustomExerciseReachesCatalogAndSearch(ModelContext(container))
        guard failures == 0 else { preconditionFailure("\(failures) library data check(s) failed") }
        print("Rep reset on plain slots, lb ladders and custom exercise edits passed")
    }

    // MARK: - XC-06

    @MainActor static func lastTime(_ id: String, _ work: [(Double, Int)], in session: WorkoutSession,
                                    context: ModelContext) {
        for (index, pair) in work.enumerated() {
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                             weightKg: pair.0, reps: pair.1, targetRepsLow: 8, targetRepsHigh: 12,
                             tracking: .weightReps)
            set.isCompleted = true
            set.session = session
            context.insert(set)
        }
    }

    /// One plain slot, last time as given; what the new session's rows open at.
    @MainActor static func opening(_ context: ModelContext, work: [(Double, Int)],
                                   targetSets: Int = 3) -> (rows: [SetLog], action: TrainingStats.OverloadSuggestion.Action) {
        let plan = Plan(name: "Plain")
        let day = PlanDay(name: "Day", order: 0)
        day.plan = plan
        let item = PlanItem(catalogID: "plain-slot-test", name: "Press", order: 0, targetSets: targetSets,
                            targetRepsLow: 8, targetRepsHigh: 12)
        item.day = day
        let past = WorkoutSession(title: "Last", startedAt: .now.addingTimeInterval(-86_400))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        for model in [plan, day, item, past] as [any PersistentModel] { context.insert(model) }
        lastTime("plain-slot-test", work, in: past, context: context)
        let rows = SessionFactory.build(day: day, plan: plan, context: context, history: [past])
            .exerciseGroups[0].sets
        return (rows, TrainingStats.suggestion(for: item, lastSets: past.sets.sorted { $0.setIndex < $1.setIndex }).action)
    }

    @MainActor static func openingRepsOnASingleSlot(_ context: ModelContext) throws {
        // A cleared session moves the load on, and the new rung opens at the
        // bottom of the range, not at the 12 that belonged to the old load.
        let cleared = opening(context, work: [(60, 12), (60, 12), (60, 12)])
        check(cleared.action == .increaseWeight, "Fixture: three sets at the top of the range must climb")
        check(cleared.rows.count == 3 && cleared.rows.allSatisfy { $0.weightKg > 60 && $0.reps == 8 },
              "A climb must open every set at the bottom of the range, got \(cleared.rows.map { "\($0.weightKg)x\($0.reps)" })")

        // Asking for a fourth set of a three-set session is not clearing the
        // prescription, so the load is held; every row, the one with no set of
        // last time to copy included, opens at the prescription.
        let longer = opening(context, work: [(60, 12), (60, 12), (60, 12)], targetSets: 4)
        check(longer.action == .repeatLoad, "Fixture: three of four prescribed sets must hold the load")
        check(longer.rows.count == 4 && longer.rows.allSatisfy { $0.reps == 8 && $0.weightKg == 60 },
              "A held load must open every row, including one past last time's count, at the prescription, got \(longer.rows.map { "\($0.weightKg)x\($0.reps)" })")

        // Earning reps, not load: the per-set counts carry over, because those
        // reps belong to the load that is being kept.
        let building = opening(context, work: [(60, 10), (60, 10), (60, 9)])
        check(building.action == .addReps, "Fixture: cleared sets short of the top must add reps, got \(building.action)")
        check(building.rows.map(\.reps) == [10, 10, 9] && building.rows.allSatisfy { $0.weightKg == 60 },
              "Building reps must open each set at last time's count, got \(building.rows.map { "\($0.weightKg)x\($0.reps)" })")

        // A plain slot beside a repeated pair: the reset belongs to each slot.
        let plan = Plan(name: "Mixed")
        let day = PlanDay(name: "Day", order: 0)
        day.plan = plan
        let past = WorkoutSession(title: "Last", startedAt: .now.addingTimeInterval(-86_400))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        context.insert(plan); context.insert(day); context.insert(past)
        for (order, id, sets) in [(0, "mixed-plain", 3), (1, "mixed-pair", 2), (2, "mixed-pair", 2)] {
            let item = PlanItem(catalogID: id, name: id, order: order, targetSets: sets,
                                targetRepsLow: 8, targetRepsHigh: 12)
            item.day = day
            context.insert(item)
        }
        lastTime("mixed-plain", [(60, 12), (60, 12), (60, 12)], in: past, context: context)
        lastTime("mixed-pair", Array(repeating: (40.0, 12), count: 4), in: past, context: context)
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [past])
        let plain = session.sets.filter { $0.catalogID == "mixed-plain" }
        check(!plain.isEmpty && plain.allSatisfy { $0.weightKg > 60 && $0.reps == 8 },
              "A plain slot beside a repeated pair must still reset its reps after a climb")
    }

    // MARK: - LIB-10: LoadScale in pounds

    static func nearlyEqual(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @MainActor static func lbLadderRoundTrips() throws {
        for increment in LoadScale.choices(for: .lb) {
            let scale = LoadScale(unit: .lb, increment: increment)
            var displayValue = 0.0
            while displayValue <= 300 {
                // A rung stored as kilograms and read back must be the same rung,
                // not 44.99999 lb that prints as 45 and steps to 45 again.
                let kg = scale.kilograms(displayValue)
                check(nearlyEqual(scale.display(kg), displayValue),
                      "\(displayValue) lb did not survive kg conversion at \(increment) lb steps")
                check(nearlyEqual(scale.display(scale.snap(kg: kg)), displayValue),
                      "\(displayValue) lb stored as kg snapped to \(scale.display(scale.snap(kg: kg))) at \(increment) lb steps")
                if displayValue > 0 {
                    let up = scale.display(scale.step(kg: kg, by: 1))
                    let down = scale.display(scale.step(kg: kg, by: -1))
                    check(nearlyEqual(up, displayValue + increment),
                          "Stepping up from \(displayValue) lb by \(increment) gave \(up)")
                    check(nearlyEqual(down, max(0, displayValue - increment)),
                          "Stepping down from \(displayValue) lb by \(increment) gave \(down)")
                }
                check(Double(scale.text(displayValue)) != nil
                      && nearlyEqual(Double(scale.text(displayValue))!, displayValue),
                      "\(displayValue) lb printed as \(scale.text(displayValue))")
                displayValue += increment
            }
            check(scale.step(kg: 0, by: -1) == 0, "Stepping down from empty must stay at zero")
            let ladder = scale.ladder(around: scale.kilograms(100), rungs: 2).map { $0 / increment }
            check(ladder.allSatisfy { abs($0.rounded() - $0) < 1e-9 }, "A lb ladder holds only rungs of \(increment)")
            check(scale.snap(kg: 0) == 0 && scale.snap(kg: -3) == 0, "Nothing and less than nothing snap to nothing")
        }

        // A weight typed while the app was in kilograms, opened on a stack marked in fives.
        let fives = LoadScale(unit: .lb, increment: 5)
        check(nearlyEqual(fives.display(fives.snap(kg: 27.76)), 60), "27.76 kg must open as 60 lb on a stack in fives")
        // A machine marked in 2.5 lb keeps its half rungs.
        let twoHalf = LoadScale(unit: .lb, increment: 2.5)
        check(twoHalf.text(twoHalf.display(twoHalf.kilograms(52.5))) == "52.5", "2.5 lb rungs must print their half")

        // Switching unit lands on an increment the app offers, and staying put is the identity.
        for choice in LoadScale.choices(for: .lb) {
            let scale = LoadScale(unit: .lb, increment: choice)
            check(scale.converted(to: .lb) == scale, "Converting to the same unit must change nothing")
            check(LoadScale.choices(for: .kg).contains(scale.converted(to: .kg).increment),
                  "\(choice) lb converted to kg must land on an offered increment")
        }
        check(LoadScale(unit: .lb, increment: 0).increment == WeightUnit.lb.step,
              "A zero increment must fall back to the unit's step, or every stepper freezes")
    }

    @MainActor static func lbScalePersistsAndDrivesTheOpeningWeight(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        let book = LoadScaleBook.shared
        book.configure(container: container)
        book.clearAll()

        let fives = LoadScale(unit: .lb, increment: 5)
        book.set(fives, for: "lb-machine-test")
        check(book.scale(for: "lb-machine-test") == fives, "The book must return the lb scale it was given")

        // What is on disk is what a restart reads back.
        let rows = try context.fetch(FetchDescriptor<ExerciseLoadPreference>())
        check(rows.count == 1 && rows[0].scale == fives, "The stored row must hold the lb scale exactly")
        book.configure(container: container)
        check(book.scale(for: "lb-machine-test") == fives && book.isCustomised("lb-machine-test"),
              "A reloaded book must still hold the lb correction")

        // The correction changes what the next session opens at: a rung of this machine.
        let plan = Plan(name: "Pounds")
        let day = PlanDay(name: "Day", order: 0)
        day.plan = plan
        let item = PlanItem(catalogID: "lb-machine-test", name: "Stack Press", order: 0, targetSets: 3,
                            targetRepsLow: 8, targetRepsHigh: 12)
        item.day = day
        let past = WorkoutSession(title: "Last", startedAt: .now.addingTimeInterval(-86_400))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        for model in [plan, day, item, past] as [any PersistentModel] { context.insert(model) }
        // 130 lb logged as kilograms, three clean sets at the top of the range.
        lastTime("lb-machine-test", Array(repeating: (fives.kilograms(130), 12), count: 3), in: past, context: context)
        let rows2 = SessionFactory.build(day: day, plan: plan, context: context, history: [past])
            .exerciseGroups[0].sets
        let opened = rows2.map { fives.display($0.weightKg) }
        check(opened.allSatisfy { nearlyEqual($0, 135) && $0.truncatingRemainder(dividingBy: 5) == 0 },
              "A clean session at 130 lb on a stack in fives must open at 135 lb, got \(opened)")

        book.clear("lb-machine-test")
        let remaining = try context.fetch(FetchDescriptor<ExerciseLoadPreference>())
        check(!book.isCustomised("lb-machine-test") && remaining.isEmpty,
              "Clearing the correction must remove it from the store as well as the book")
    }

    // MARK: - LIB-10: custom exercise edits

    @MainActor static func editedCustomExerciseReachesCatalogAndSearch(_ context: ModelContext) throws {
        let record = CustomExerciseRecord(name: "Sledge Drag", muscles: [.quads], equipment: ["Sled"],
                                          tracking: .weightReps)
        context.insert(record)
        try context.save()
        let catalog = ExerciseCatalog.shared
        catalog.setCustom([record.asCatalogExercise])
        check(catalog.search("sledge").contains { $0.id == record.id }, "A new custom exercise is searchable")

        record.apply(name: "Prowler Push", muscles: [.glutes, .hamstrings], equipment: ["Prowler"],
                     tracking: .bodyweightReps)
        try context.save()
        catalog.setCustom([record.asCatalogExercise])

        let renamed = catalog.exercise(id: record.id)
        check(renamed?.name == "Prowler Push" && renamed?.equipment == ["Prowler"]
              && renamed?.tracking == .bodyweightReps && renamed?.isCustom == true,
              "An edit must reach the catalog entry: \(String(describing: renamed))")
        check(renamed?.muscleGroups == [Muscle.glutes.name, Muscle.hamstrings.name],
              "Edited muscles must replace the old ones, got \(renamed?.muscleGroups ?? [])")
        check(catalog.search("prowler").contains { $0.id == record.id }, "The new name must be searchable")
        check(!catalog.search("sledge").contains { $0.id == record.id }, "The old name must stop matching")
        check(catalog.search("", muscle: .glutes).contains { $0.id == record.id },
              "The edited muscle must be filterable")
        check(!catalog.search("", muscle: .quads).contains { $0.id == record.id },
              "The removed muscle must stop filtering it in")
        check(catalog.search("", equipment: "Prowler").contains { $0.id == record.id },
              "The edited equipment must be filterable")
        check(catalog.hasMatch(for: "prowler") && !catalog.hasMatch(for: "sledge"),
              "hasMatch must follow the rename, or the library offers to add a duplicate")

        catalog.setCustom([])
        check(catalog.exercise(id: record.id) == nil, "Deleting the record must drop it from the catalog")
    }
}
