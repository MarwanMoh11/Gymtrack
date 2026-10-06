import Testing
import Foundation
import SwiftData
@testable import GymTrack

/// Protects the bundled exercise library and the starter plans built from it.
/// Every plan slot, set and backup row refers to a catalog ID, so an ID that
/// vanishes, repeats or means something else strands somebody's history.
///
/// Reads the real `exercises.json` from the app bundle, which is what a hosted
/// run loads. Also covers searching it, the lifter's own exercises joining it,
/// and the launch load a headless start from the watch depends on.
///
/// The catalog is process-wide. Every test that gives it custom or hidden
/// exercises does so in its own synchronous body through `withCleanLibrary`,
/// which empties both again afterwards, so no other suite's search or lookup
/// sees what one test registered.
@MainActor @Suite(.serialized)
struct CatalogIntegrityTests {

    private var catalog: ExerciseCatalog { ExerciseCatalog.shared }

    /// Runs `body` on a catalog with nothing custom and nothing hidden, and
    /// leaves it that way. `loadLibrary` hides whatever the store says, and a
    /// search that assumed nothing was hidden would fail on what one left.
    private func withCleanLibrary(_ body: () throws -> Void) rethrows {
        catalog.setCustom([])
        catalog.setHidden([])
        defer {
            catalog.setCustom([])
            catalog.setHidden([])
        }
        try body()
    }

    private func names(_ query: String) -> [String] {
        catalog.search(query).map(\.name)
    }

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

    // MARK: - Search

    /// An alias may only widen a search. Each prefix typed on the way to a
    /// word the aliases rewrite once found nothing, and the library offered to
    /// add an exercise it already had.
    @Test(arguments: ["calves", "flies", "quadriceps", "abdominals"])
    func everyPrefixOfAWordAnAliasRewritesStillFindsSomething(word: String) {
        withCleanLibrary {
            for length in 2...word.count {
                let prefix = String(word.prefix(length))
                #expect(!names(prefix).isEmpty, "'\(prefix)' finds nothing")
            }
        }
    }

    @Test func aShortQueryKeepsItsLiteralMatchesBesideWhatTheAliasAdds() {
        withCleanLibrary {
            let ham = names("ham")
            #expect(ham.contains { $0.localizedCaseInsensitiveContains("Hammer Curl") })
            let hamstrings = Set(names("hamstrings"))
            #expect(ham.contains { hamstrings.contains($0) }, "'ham' no longer reaches the hamstring entries")
            #expect(names("hamstring").count >= 10, "the alias no longer widens to hamstring work")
            #expect(names("ext rot").contains { $0.localizedCaseInsensitiveContains("External Rotation") })
        }
    }

    @Test func shorthandStillFindsAndAQueryNothingAnswersStaysEmpty() {
        withCleanLibrary {
            #expect(!names("db press").isEmpty)
            #expect(!names("calv").isEmpty)
            #expect(catalog.hasMatch(for: "calv"))
            // Empty is what lets the library offer to add it.
            #expect(names("zzqqxx").isEmpty)
            #expect(!catalog.hasMatch(for: "zzqqxx"))
        }
    }

    // MARK: - The lifter's own exercises

    /// How each row of a session started from `day` would be measured.
    private func trackings(_ day: PlanDay, _ plan: Plan, _ context: ModelContext) -> [TrackingMode] {
        SessionFactory.build(day: day, plan: plan, context: context, history: [])
            .exerciseGroups.flatMap(\.sets).map(\.tracking)
    }

    @Test func anEditedCustomExerciseReachesTheCatalogAndSearchAndADeletedOneLeaves() throws {
        try withCleanLibrary {
            let context = try TestStore.context()
            let record = CustomExerciseRecord(name: "Sledge Drag", muscles: [.quads], equipment: ["Sled"],
                                              tracking: .weightReps)
            context.insert(record)
            try context.save()
            catalog.setCustom([record.asCatalogExercise])
            #expect(catalog.search("sledge").contains { $0.id == record.id })

            record.apply(name: "Prowler Push", muscles: [.glutes, .hamstrings], equipment: ["Prowler"],
                         tracking: .bodyweightReps)
            try context.save()
            catalog.setCustom([record.asCatalogExercise])

            let renamed = try #require(catalog.exercise(id: record.id))
            #expect(renamed.name == "Prowler Push")
            #expect(renamed.equipment == ["Prowler"])
            #expect(renamed.tracking == .bodyweightReps)
            #expect(renamed.isCustom)
            #expect(renamed.muscleGroups == [Muscle.glutes.name, Muscle.hamstrings.name],
                    "edited muscles must replace the old ones")
            #expect(catalog.search("prowler").contains { $0.id == record.id })
            #expect(!catalog.search("sledge").contains { $0.id == record.id }, "the old name still matches")
            #expect(catalog.search("", muscle: .glutes).contains { $0.id == record.id })
            #expect(!catalog.search("", muscle: .quads).contains { $0.id == record.id })
            #expect(catalog.search("", equipment: "Prowler").contains { $0.id == record.id })
            // Following the rename, or the library offers to add a duplicate.
            #expect(catalog.hasMatch(for: "prowler"))
            #expect(!catalog.hasMatch(for: "sledge"))

            catalog.setCustom([])
            #expect(catalog.exercise(id: record.id) == nil)
        }
    }

    /// A workout started from the watch while the phone app is terminated is
    /// built on a background launch, where no view runs. Before
    /// `GymTrackApp.configureServices` reads the store, the catalog holds no
    /// custom exercise, which is what this starts from.
    @Test func aHeadlessStartBuildsCustomSlotsInTheirOwnTrackingOnceTheLibraryIsLoaded() throws {
        try withCleanLibrary {
            let container = try TestStore.context().container
            let context = ModelContext(container)
            let hold = CustomExerciseRecord(name: "Farmer Hold", muscles: [], equipment: [], tracking: .duration)
            let press = CustomExerciseRecord(name: "Gym Press", muscles: [], equipment: ["Machine"],
                                             tracking: .weightReps)
            context.insert(hold)
            context.insert(press)
            context.insert(HiddenExerciseRecord(catalogID: "hidden-test"))
            let plan = Plan(name: "Custom")
            let day = PlanDay(name: "Monday", order: 0)
            day.plan = plan
            context.insert(plan)
            context.insert(day)
            // Added before slots kept a snapshot: only the catalog can say
            // this one is timed.
            let slot = PlanItem(catalogID: hold.id, name: hold.name, order: 0, targetSets: 3,
                                targetRepsLow: 0, targetRepsHigh: 0, targetSeconds: 40)
            slot.day = day
            context.insert(slot)
            try context.save()

            // The failure, reproduced: nothing has read the store yet.
            #expect(trackings(day, plan, context) == [.weightReps, .weightReps, .weightReps])
            #expect(LoadScaleBook.shared.scale(for: press.id) == LoadScaleBook.derived(for: nil))

            // What configureServices runs, from a fresh context as it does there.
            catalog.loadLibrary(from: ModelContext(container))
            #expect(trackings(day, plan, context) == [.duration, .duration, .duration])
            #expect(catalog.isHidden("hidden-test"), "the launch load must bring the hidden list, as RootView does")
            // A custom machine steps on its own ladder from the wrist.
            #expect(LoadScaleBook.shared.scale(for: press.id) == LoadScaleBook.derived(for: press.asCatalogExercise))
            #expect(LoadScaleBook.derived(for: press.asCatalogExercise) != LoadScaleBook.derived(for: nil))
        }
    }

    /// The snapshot a new custom slot keeps, so a catalog miss can never fall
    /// back to weight × reps.
    @Test func aSnapshottedCustomSlotStaysTimedWhenTheCatalogMisses() throws {
        try withCleanLibrary {
            let context = try TestStore.context()
            let custom = CustomExerciseRecord(name: "Farmer Hold", muscles: [], equipment: [],
                                              tracking: .duration).asCatalogExercise
            #expect(custom.slotTrackingSnapshot == TrackingMode.duration.rawValue)
            // A bundled exercise always resolves and must not gain a plan key
            // in the export.
            let bundled = try #require(catalog.builtIn.first { $0.tracking == .duration })
            #expect(bundled.slotTrackingSnapshot == nil)

            let plan = Plan(name: "Snapshotted")
            let day = PlanDay(name: "Tuesday", order: 0)
            day.plan = plan
            context.insert(plan)
            context.insert(day)
            let slot = PlanItem(catalogID: custom.id, name: custom.name, order: 0, targetSets: 2,
                                targetRepsLow: 0, targetRepsHigh: 0, targetSeconds: 40)
            slot.trackingRaw = custom.slotTrackingSnapshot
            slot.day = day
            context.insert(slot)
            try context.save()

            let rows = SessionFactory.build(day: day, plan: plan, context: context, history: [])
                .exerciseGroups.flatMap(\.sets)
            #expect(rows.map(\.tracking) == [.duration, .duration])
        }
    }

    @Test func aTrackingEditCarriesOntoSnapshotsAndARangeTheLifterSetSurvivesIt() throws {
        let context = try TestStore.context()
        let custom = CustomExerciseRecord(name: "Farmer Hold", muscles: [], equipment: [],
                                          tracking: .duration).asCatalogExercise
        let snapshotted = PlanItem(catalogID: custom.id, name: custom.name, order: 0, targetSets: 2,
                                   targetRepsLow: 0, targetRepsHigh: 0, targetSeconds: 40)
        snapshotted.trackingRaw = custom.slotTrackingSnapshot
        let unsnapshotted = PlanItem(catalogID: custom.id, name: custom.name, order: 0)
        for (name, slot) in [("Tuesday", snapshotted), ("Wednesday", unsnapshotted)] {
            let plan = Plan(name: name)
            let day = PlanDay(name: name, order: 0)
            day.plan = plan
            slot.day = day
            context.insert(plan)
            context.insert(day)
            context.insert(slot)
        }
        try context.save()

        try context.retrackPlanSlots(of: custom.id, to: .bodyweightReps)
        #expect(snapshotted.trackingRaw == TrackingMode.bodyweightReps.rawValue)
        // A slot with no snapshot keeps following the catalog and gains no key.
        #expect(unsnapshotted.trackingRaw == nil)
        // Added while timed, it gains the range a new reps slot starts on.
        #expect(snapshotted.targetRepsLow == 8 && snapshotted.targetRepsHigh == 12)

        // A range the lifter chose is theirs, whichever way the tracking moves.
        unsnapshotted.targetRepsLow = 5
        unsnapshotted.targetRepsHigh = 5
        try context.retrackPlanSlots(of: custom.id, to: .weightReps)
        #expect(unsnapshotted.targetRepsLow == 5 && unsnapshotted.targetRepsHigh == 5)
        // Moving to a timed mode leaves the range alone, so a move back finds it intact.
        try context.retrackPlanSlots(of: custom.id, to: .duration)
        #expect(snapshotted.targetRepsLow == 8)
        #expect(snapshotted.trackingRaw == TrackingMode.duration.rawValue)
    }
}
