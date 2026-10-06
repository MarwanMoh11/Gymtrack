import Foundation
import SwiftData

/// Run with scripts/test-library-fixes.sh; no simulator is needed.
///
/// Covers the library, plan-editing and number-entry fixes: search that an
/// alias may only widen (LIB-05), item order after a delete (LIB-06), deleting
/// a routine without touching history (LIB-09) and native digits in the
/// weight and rep fields (XC-11). The views themselves are covered by reading.
@main
struct LibraryFixesTests {
    @MainActor static func main() throws {
        searchNeverHidesALiteralMatch()
        typedEntryReadsNativeDigits()
        try itemOrderStaysDense()
        try deletingARoutineKeepsHistory()
        print("LibraryFixesTests passed")
    }

    // MARK: - LIB-05

    private static func names(_ query: String) -> [String] {
        ExerciseCatalog.shared.search(query).map(\.name)
    }

    @MainActor static func searchNeverHidesALiteralMatch() {
        precondition(!ExerciseCatalog.shared.all.isEmpty, "the bundled catalog loaded")

        // Every prefix of a word an alias rewrites must still find something.
        for word in ["calves", "flies", "quadriceps", "abdominals"] {
            for length in 2...word.count {
                let prefix = String(word.prefix(length))
                precondition(!names(prefix).isEmpty, "'\(prefix)' finds something")
            }
        }
        precondition(!names("calv").isEmpty)

        let ham = names("ham")
        precondition(ham.contains { $0.localizedCaseInsensitiveContains("Hammer Curl") },
                     "'ham' still shows Hammer Curl")
        precondition(ham.contains { ExerciseCatalog.shared.search("hamstrings").map(\.name).contains($0) },
                     "'ham' still reaches the hamstring entries")
        precondition(names("hamstring").count >= 10, "the alias still widens to hamstring work")

        precondition(names("ext rot").contains { $0.localizedCaseInsensitiveContains("External Rotation") },
                     "'ext rot' reaches External Rotation")
        precondition(names("ext rot").count > 0)

        // Shorthand keeps working, and a query nothing answers stays empty so
        // the library can offer to add it.
        precondition(!names("db press").isEmpty)
        precondition(names("zzqqxx").isEmpty && !ExerciseCatalog.shared.hasMatch(for: "zzqqxx"))
        precondition(ExerciseCatalog.shared.hasMatch(for: "calv"))
    }

    // MARK: - XC-11

    @MainActor static func typedEntryReadsNativeDigits() {
        let max = 500.0
        precondition(StepperEntry.parse("٦٠٫٥", maximum: max) == 60.5, "Arabic-Indic digits and separator")
        precondition(StepperEntry.parse("۶۰٫۵", maximum: max) == 60.5, "extended Arabic-Indic digits")
        precondition(StepperEntry.parse("٦٠", maximum: max) == 60)
        precondition(StepperEntry.parse("60,5", maximum: max) == 60.5)
        precondition(StepperEntry.parse("60.5", maximum: max) == 60.5)
        precondition(StepperEntry.parse("١٢", maximum: 100) == 12)

        // Everything else is refused.
        precondition(StepperEntry.parse("1٬000", maximum: 5_000) == nil, "the Arabic thousands mark")
        precondition(StepperEntry.parse("６０", maximum: max) == nil, "fullwidth digits")
        precondition(StepperEntry.parse("६०", maximum: max) == nil, "Devanagari digits")
        precondition(StepperEntry.parse("6 0", maximum: max) == nil, "a space inside the number")
        precondition(StepperEntry.parse("0x10", maximum: max) == nil, "hex")
        precondition(StepperEntry.parse("1e2", maximum: max) == nil, "exponent")
        precondition(StepperEntry.parse("6٠a", maximum: max) == nil)
        precondition(StepperEntry.parse("60.5.5", maximum: max) == nil)
        precondition(StepperEntry.parse("-5", maximum: max) == nil)
        precondition(StepperEntry.parse("٦٠٠", maximum: max) == nil, "still bounded by the ceiling")
    }

    // MARK: - LIB-06

    @MainActor private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor private static func count<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<T>()).count
    }

    @MainActor private static func addItem(_ name: String, to day: PlanDay, in context: ModelContext) {
        let item = PlanItem(catalogID: name, name: name, order: day.nextItemOrder, targetSets: 3,
                            targetRepsLow: 8, targetRepsHigh: 12)
        item.day = day
        context.insert(item)
    }

    @MainActor static func itemOrderStaysDense() throws {
        let context = try makeContext()
        let plan = Plan(name: "P")
        let day = PlanDay(name: "D", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        for name in ["A", "B", "C", "D"] { addItem(name, to: day, in: context) }
        try context.save()

        // Delete the first and then a middle one, saving in between as the
        // editor does, and add another.
        day.removeItems([day.orderedItems[0]], in: context)
        try context.save()
        day.removeItems([day.orderedItems[1]], in: context)
        try context.save()
        addItem("E", to: day, in: context)
        try context.save()

        let orders = day.orderedItems.map(\.order)
        precondition(orders == Array(0..<orders.count), "orders are 0...n-1 with no repeats: \(orders)")
        precondition(day.orderedItems.map(\.name) == ["B", "D", "E"], "survivors keep their sequence")

        // Without a save between, the deleted row is still in the relationship.
        let doomed = day.orderedItems[0]
        day.removeItems([doomed], in: context)
        addItem("F", to: day, in: context)
        let live = day.orderedItems.filter { $0 !== doomed }
        precondition(Set(live.map(\.order)).count == live.count, "no two live items share an order: \(live.map(\.order))")
    }

    // MARK: - LIB-09

    @MainActor static func deletingARoutineKeepsHistory() throws {
        let context = try makeContext()
        let first = Plan.blank(in: context, makeActive: true)
        first.createdAt = Date(timeIntervalSince1970: 1)
        let second = Plan.blank(in: context, makeActive: false)
        second.createdAt = Date(timeIntervalSince1970: 2)
        let day = PlanDay(name: "Push", order: 0)
        day.plan = first
        context.insert(day)
        addItem("bench", to: day, in: context)

        let finished = WorkoutSession(title: "Push", planDayID: day.id, planName: "My Routine")
        finished.endedAt = .now
        context.insert(finished)
        let set = SetLog(catalogID: "bench", exerciseName: "Bench", exerciseOrder: 0, setIndex: 0, weightKg: 60, reps: 8)
        set.session = finished
        context.insert(set)
        try context.save()

        // A session still open from this routine blocks the delete.
        let open = WorkoutSession(title: "Push", planDayID: day.id, planName: "My Routine")
        context.insert(open)
        try context.save()
        precondition(!Plan.remove(first, among: [first, second], openSessions: [open], in: context),
                     "an open session blocks the delete")
        precondition(first.modelContext != nil)
        open.endedAt = .now
        try context.save()

        precondition(Plan.remove(first, among: [first, second], openSessions: [], in: context))
        try context.save()

        precondition(second.isActive, "the next routine takes over as active")
        let plans = try context.fetch(FetchDescriptor<Plan>())
        precondition(plans.count == 1)
        let nPlanDay = try count(PlanDay.self, context)
        precondition(nPlanDay == 0, "days went with the routine")
        let nPlanItem = try count(PlanItem.self, context)
        precondition(nPlanItem == 0)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(sessions.count == 2, "history is untouched")
        precondition(sessions.contains { $0.planName == "My Routine" && $0.planDayID == day.id },
                     "a session keeps its plan name and a day id that no longer resolves")
        let nSetLog = try count(SetLog.self, context)
        precondition(nSetLog == 1, "sets are untouched")

        // The last routine can be deleted too, leaving no plan at all.
        precondition(Plan.remove(second, among: [second], openSessions: [], in: context))
        try context.save()
        let nPlan = try count(Plan.self, context)
        precondition(nPlan == 0)
    }
}
