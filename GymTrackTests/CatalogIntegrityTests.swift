import Testing
import Foundation
import SwiftData
@testable import GymTrack

/// Protects the bundled exercise library and the starter plans built from it.
/// Every plan slot, set and backup row refers to a catalog ID, so an ID that
/// vanishes, repeats or means something else strands somebody's history.
///
/// Reads the real `exercises.json` from the app bundle, which is what a hosted
/// run loads. The native counterpart of the legacy `Tests/LibraryDataTests.swift`.
@MainActor @Suite(.serialized)
struct CatalogIntegrityTests {

    private var catalog: ExerciseCatalog { ExerciseCatalog.shared }

    /// What the bundled file says, before the app merges and filters it.
    private func rawRows() throws -> [[String: Any]] {
        let url = try #require(Bundle.main.url(forResource: "exercises", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    /// Muscle labels the app deliberately maps to no single region.
    private static let wholeBodyLabels: Set<String> = ["Full Body", "Cardio", "Cardiovascular", "Upper Body"]

    // MARK: - The library

    @Test func theBundledLibraryLoadsAndIsPlausiblyComplete() {
        // Not an exact count: adding an exercise must not break this.
        #expect(catalog.builtIn.count > 300)
        #expect(catalog.all.count >= catalog.builtIn.count)
    }

    @Test func idsAreUniqueAndSpelledTheSameWay() {
        let ids = catalog.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
        // One ID was shipped with a leading space and a capital. Nothing trims
        // IDs, and history may already be stored under that spelling, so it is
        // allowed and nothing else is.
        let known: Set<String> = [" Cossack-squat-bodyweight"]
        let pattern = #/[a-z0-9]+(-[a-z0-9]+)*/#
        let odd = Set(ids.filter { $0.wholeMatch(of: pattern) == nil })
        #expect(odd == known)
    }

    @Test func mergedIDsAreDroppedFromTheListAndResolveToTheirSurvivor() throws {
        let listed = Set(catalog.builtIn.map(\.id))
        for (loser, survivor) in ExerciseCatalog.merges {
            #expect(!listed.contains(loser), "\(loser) should not be listed")
            #expect(listed.contains(survivor), "\(survivor) must exist")
            #expect(catalog.exercise(id: loser)?.id == survivor)
            #expect(ExerciseCatalog.canonicalID(for: loser) == survivor)
        }
        // The file itself keeps the losers, which is why the merge has to filter.
        let rawIDs = Set(try rawRows().compactMap { $0["id"] as? String })
        #expect(rawIDs.subtracting(ExerciseCatalog.merges.keys) == listed)
    }

    @Test(arguments: ["", "no-such-exercise", "Deadlift", "deadlift ", "barbell bench press"])
    func anIDThatIsNotInTheLibraryResolvesToNothing(id: String) {
        #expect(catalog.exercise(id: id) == nil)
        #expect(ExerciseCatalog.canonicalID(for: id) == id)
    }

    @Test func everyExerciseHasANameAMuscleAndAKnownCategory() {
        let categories: Set<String> = ["strength", "core", "bodyweight", "mobility", "cardio", "warmup", "plyometrics"]
        for exercise in catalog.builtIn {
            #expect(!exercise.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(exercise.id) has no name")
            #expect(categories.contains(exercise.category), "\(exercise.id): category \(exercise.category)")
            #expect(!exercise.muscleGroups.isEmpty, "\(exercise.id) lists no muscle")
            #expect(!exercise.symbol.isEmpty)
            if let difficulty = exercise.difficulty {
                #expect(["beginner", "intermediate", "advanced"].contains(difficulty), "\(exercise.id): \(difficulty)")
            }
        }
    }

    @Test func everyMuscleLabelMapsToARegionOrIsWholeBodyOnPurpose() {
        // A new label like "Neck" would otherwise silently drop out of the heat
        // map, the per-muscle volume and the coverage ring.
        for exercise in catalog.builtIn {
            let unmapped = exercise.muscleGroups.filter { Muscle.match($0) == nil }
            #expect(unmapped.allSatisfy { Self.wholeBodyLabels.contains($0) }, "\(exercise.id): \(unmapped)")
            #expect(exercise.muscles.first == exercise.primaryMuscle)
            #expect(Set(exercise.muscles).count == exercise.muscles.count)
        }
    }

    @Test func trackingFollowsTheUnitAndTheEquipment() throws {
        let units = try Dictionary(uniqueKeysWithValues: rawRows().compactMap { row -> (String, String)? in
            guard let id = row["id"] as? String, let unit = row["defaultUnit"] as? String else { return nil }
            return (id, unit)
        })
        // Loaded with nothing the library lists as equipment.
        let loadedAnyway: Set<String> = ["walking-lunge-weighted-vest", "wrist-roller"]
        let loadable: Set<String> = ["Barbell", "Dumbbell", "Machine", "Cable", "Kettlebell", "Plate", "Band"]
        for exercise in catalog.builtIn {
            let unit = try #require(units[exercise.id], "\(exercise.id) is not in the file")
            let timed = unit == "s" || unit == "min"
            #expect((exercise.tracking == .duration) == timed, "\(exercise.id): \(unit)")
            guard !timed else { continue }
            let hasLoad = !loadable.isDisjoint(with: exercise.equipment) || loadedAnyway.contains(exercise.id)
            #expect((exercise.tracking == .weightReps) == hasLoad, "\(exercise.id): \(exercise.equipment)")
        }
        let modes = Set(catalog.builtIn.map(\.tracking))
        #expect(modes == Set(TrackingMode.allCases))
    }

    @Test func everyKindOfKitWithALadderIsUsedBySomeExercise() {
        let used = Set(catalog.builtIn.flatMap(\.equipment))
        for equipment in LoadScaleBook.equipmentPriority {
            #expect(used.contains(equipment), "no exercise lists \(equipment), so its row in the table is dead")
        }
        for exercise in catalog.builtIn {
            for unit in WeightUnit.allCases {
                #expect(LoadScaleBook.defaultIncrement(for: exercise, in: unit) > 0)
            }
        }
    }

    // MARK: - The starter plans

    @Test func everyTemplateIsWellFormedAndPointsOnlyAtRealExercises() {
        #expect(Set(PlanTemplate.all.map(\.id)).count == PlanTemplate.all.count)
        for template in PlanTemplate.all {
            #expect(!template.name.isEmpty)
            #expect(template.daysPerWeek == template.days.filter { !$0.isRest }.count, "\(template.id)")
            let weekdays = template.days.compactMap(\.weekday)
            #expect(weekdays.allSatisfy { (1...7).contains($0) }, "\(template.id)")
            #expect(Set(weekdays).count == weekdays.count, "\(template.id) pins two days to one weekday")
            for day in template.days {
                for item in day.items {
                    #expect(catalog.exercise(id: item.catalogID) != nil, "\(template.id): \(item.catalogID)")
                    #expect(item.sets > 0)
                    #expect(item.repsLow <= item.repsHigh)
                    #expect(item.restSeconds >= 0)
                }
            }
        }
    }

    @Test(arguments: PlanTemplate.all)
    func aTemplateMaterialisesIntoOneActivePlanWithEveryDayAndSlot(template: PlanTemplate) throws {
        let container = try TestStore.container()
        let context = ModelContext(container)
        let plan = template.materialise(in: context, makeActive: true)
        try context.save()

        let plans = try context.fetch(FetchDescriptor<Plan>())
        #expect(plans.count == 1)
        #expect(plans.filter(\.isActive).count == 1)
        #expect(plan.days.count == template.days.count)
        #expect(plan.orderedDays.map(\.order) == Array(0..<template.days.count))
        for (built, source) in zip(plan.orderedDays, template.days) {
            #expect(built.name == source.name)
            #expect(built.weekday == source.weekday)
            #expect(built.items.count == source.items.count)
            #expect(built.items.map(\.catalogID).sorted() == source.items.map(\.catalogID).sorted())
            if let weekday = source.weekday, !source.isRest {
                #expect(plan.day(onWeekday: weekday)?.name == source.name)
            }
        }
        #expect(try context.fetch(FetchDescriptor<PlanItem>()).count == template.days.flatMap(\.items).count)
    }

    @Test func aSecondTemplateAddedInactiveDoesNotTakeOverTheActivePlan() throws {
        let context = try TestStore.context()
        let first = PlanTemplate.minimalist.materialise(in: context, makeActive: true)
        let second = PlanTemplate.fullBody.materialise(in: context, makeActive: false)
        #expect(first.isActive)
        #expect(!second.isActive)
        #expect(try context.fetch(FetchDescriptor<Plan>()).filter(\.isActive).count == 1)
    }
}
