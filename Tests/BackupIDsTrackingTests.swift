import Foundation
import SwiftData

/// Run with scripts/test-backup-ids-tracking.sh; no simulator is needed.
///
/// Two things the wave-6 backup work has to hold:
///
/// - DATA-05: a file that repeats a session, plan or day ID is refused before
///   anything on the phone is touched, the way a repeated set ID already is.
/// - trackingRaw: a restored plan slot for one of the user's own exercises
///   carries that exercise's tracking, so it survives the exercise's deletion.
///
/// DATA-14 (a background context for the snapshot and the apply) was tried and
/// backed out: see the notes on `BackupService.exportOffMain`.
@main
struct BackupBackgroundContextTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    static let stamp = BackupService.ExportStamp(
        exportedAt: Date(timeIntervalSince1970: 1_790_116_200),
        timeZone: TimeZone(identifier: "Africa/Cairo")!, appVersion: "1.4", appBuild: "27")

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    static let modelTypes: [any PersistentModel.Type] = [
        Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
        ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
        ExerciseLoadPreference.self, HiddenExerciseRecord.self,
    ]

    @MainActor static func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// A small store with two finished sessions, so the ID checks have
    /// something to repeat.
    @MainActor static func fillSmall(_ context: ModelContext) throws {
        for p in 0..<2 {
            let plan = Plan(name: "Plan \(p)", isActive: p == 0)
            plan.id = uuid(0x100 + p)
            context.insert(plan)
            let day = PlanDay(name: "Day \(p)", order: 0, weekday: 2)
            day.id = uuid(0x200 + p)
            day.plan = plan
            context.insert(day)
            let session = WorkoutSession(title: "Session \(p)", planDayID: day.id,
                                         startedAt: base.addingTimeInterval(Double(p) * 86_400))
            session.id = uuid(0x300 + p)
            session.endedAt = session.startedAt.addingTimeInterval(3_000)
            context.insert(session)
        }
        try context.save()
    }

    @MainActor static func refusal(_ archive: BackupService.Archive, context: ModelContext) -> String? {
        do {
            try BackupService.restore(data: try BackupService.encoded(archive), context: context)
            return nil
        } catch BackupService.RestoreError.invalidValue(let field, _, _, _) {
            return field
        } catch {
            return "unexpected \(error)"
        }
    }

    @MainActor static func checkIDValidation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try fillSmall(context)
        let archive = try BackupService.makeArchive(context: context, stamp: stamp)
        check(archive.plans.count == 2 && archive.sessions.count == 2, "the fixture exports two plans and two sessions")
        check(refusal(archive, context: context) == nil, "an archive with distinct IDs restores")

        var sessions = archive
        sessions.sessions[1].id = sessions.sessions[0].id
        check(refusal(sessions, context: context) == "session ID", "a repeated session ID is refused and named")

        var plans = archive
        plans.plans[1].id = plans.plans[0].id
        check(refusal(plans, context: context) == "plan ID", "a repeated plan ID is refused and named")

        var days = archive
        days.plans[1].days[0].id = days.plans[0].days[0].id
        check(refusal(days, context: context) == "day ID", "a day ID repeated across two plans is refused and named")

        var sameDay = archive
        sameDay.plans[0].days.append(sameDay.plans[0].days[0])
        check(refusal(sameDay, context: context) == "day ID", "a day copied within a plan is refused and named")

        check(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 2
              && (try context.fetchCount(FetchDescriptor<Plan>())) == 2,
              "every refused file left the store as it was")
    }

    @MainActor static func checkTrackingSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = Plan(name: "P", isActive: true)
        context.insert(plan)
        let day = PlanDay(name: "D", order: 0)
        day.plan = plan
        context.insert(day)
        try context.save()

        var archive = try BackupService.makeArchive(context: context, stamp: stamp)
        func item(_ catalogID: String, tracking: String?) -> BackupService.ItemDTO {
            BackupService.ItemDTO(catalogID: catalogID, name: catalogID, order: 0, targetSets: 3,
                                  tracking: tracking)
        }
        archive.customExercises = [
            BackupService.CustomExerciseDTO(id: "custom-aaaa0001", name: "Sled hold", category: "Strength",
                                            muscleRaw: [], equipment: [], trackingRaw: "duration"),
            BackupService.CustomExerciseDTO(id: "custom-aaaa0002", name: "Odd curl", category: "Strength",
                                            muscleRaw: [], equipment: [], trackingRaw: "weightReps"),
        ]
        archive.plans[0].days[0].items = [
            item("custom-aaaa0001", tracking: nil),          // an older file: no snapshot
            item("custom-aaaa0002", tracking: "duration"),   // a snapshot that contradicts its exercise
            item("barbell-bench-press", tracking: nil),      // a bundled exercise: nothing to snapshot
            item("custom-gone0003", tracking: "duration"),   // its exercise was deleted before export
        ]
        for n in 0..<4 { archive.plans[0].days[0].items[n].order = n }
        try BackupService.restore(data: try BackupService.encoded(archive), context: context)

        let items = try context.fetch(FetchDescriptor<PlanItem>()).sorted { $0.order < $1.order }
        check(items.count == 4, "the four slots restore")
        check(items.first?.trackingRaw == "duration", "a custom slot with no snapshot takes its exercise's tracking")
        check(items.dropFirst().first?.trackingRaw == "weightReps", "a stale snapshot follows the exercise it was written under")
        check(items.dropFirst(2).first?.trackingRaw == nil, "a bundled exercise's slot stays without a snapshot")
        check(items.last?.trackingRaw == "duration", "a snapshot for an exercise no longer in the file is kept")

        // The point of the snapshot: the slot still reads as timed once the
        // exercise, and with it the catalog entry, is gone.
        for record in try context.fetch(FetchDescriptor<CustomExerciseRecord>()) { context.delete(record) }
        try context.save()
        context.refreshCustomExercises()
        let held = try context.fetch(FetchDescriptor<PlanItem>()).first { $0.catalogID == "custom-aaaa0001" }
        check(held?.tracking == .duration, "a restored custom slot stays timed after its exercise is deleted")
    }

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        do {
            try await MainActor.run { try checkIDValidation(); try checkTrackingSnapshot() }
        } catch {
            print("FAIL: threw \(error)")
            exit(1)
        }
        let failed = await MainActor.run { failures }
        if failed > 0 { exit(1) }
        print("Backup ID and tracking checks passed")
    }
}
