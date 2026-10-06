import Foundation
import SwiftData

/// Run with scripts/test-backup-service.sh. Restore takes no Health seam at
/// all, so every restore here runs against the recording `HealthKitService`
/// stub; erase's Health deletion is injected where a test needs it to fail.
@main
struct BackupServiceTests {
    enum InjectedFailure: Error { case beforeCommit }

    @MainActor static func main() async throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let original = WorkoutSession(title: "Original", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        original.endedAt = original.startedAt.addingTimeInterval(60)
        let healthID = UUID()
        original.healthWorkoutID = healthID
        context.insert(original)
        let plan = Plan(name: "Original plan", isActive: true)
        let day = PlanDay(name: "Day one", order: 0)
        let item = PlanItem(catalogID: "unknown-exercise", name: "Unknown exercise", order: 0)
        day.plan = plan
        item.day = day
        context.insert(plan)
        context.insert(day)
        context.insert(item)
        try context.save()
        AppSettings.shared.userName = "Before restore"

        let archiveURL = try BackupService.export(context: context)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(BackupService.Archive.self, from: Data(contentsOf: archiveURL))
        precondition(exported.version == 2)
        precondition(exported.sessions.first?.healthWorkoutID == healthID)

        var replacement = exported
        replacement.sessions[0].title = "Replacement"
        replacement.settings.userName = "After restore"
        let replacementURL = try write(replacement)
        defer { try? FileManager.default.removeItem(at: replacementURL) }

        let health = HealthKitService.shared
        do {
            try BackupService.restore(
                from: replacementURL, context: context,
                beforeCommit: { throw InjectedFailure.beforeCommit }
            )
            preconditionFailure("Injected restore failure must throw")
        } catch InjectedFailure.beforeCommit {
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            precondition(sessions.map(\.title) == ["Original"])
            let plans = try context.fetch(FetchDescriptor<Plan>())
            precondition(plans.count == 1 && plans[0].orderedDays.first?.orderedItems.count == 1,
                         "Rollback must keep plan descendants as well as sessions")
            precondition(AppSettings.shared.userName == "Before restore")
            precondition(health.deletedIDs.isEmpty, "Failed restore must not delete from Health")
        }

        try BackupService.restore(from: replacementURL, context: context)
        precondition(health.deletedIDs.isEmpty, "A replacement still linking the workout must leave Health alone")
        let retainedSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(retainedSessions.first?.healthWorkoutID == healthID)
        let restoredPlans = try context.fetch(FetchDescriptor<Plan>())
        precondition(restoredPlans.count == 1 && restoredPlans[0].orderedDays.first?.orderedItems.count == 1)
        precondition(AppSettings.shared.userName == "After restore")

        // A pre-linkage version-2 file has no key at all, not a null sentinel.
        var legacy = replacement
        legacy.sessions[0].healthWorkoutID = nil
        let legacyURL = try write(legacy)
        defer { try? FileManager.default.removeItem(at: legacyURL) }
        let legacyData = try Data(contentsOf: legacyURL)
        let legacyText = String(decoding: legacyData, as: UTF8.self)
        precondition(!legacyText.contains("healthWorkoutID"))
        let legacyDecoded = try decoder.decode(BackupService.Archive.self, from: legacyData)
        precondition(legacyDecoded.version == 2 && legacyDecoded.sessions[0].healthWorkoutID == nil)

        // Every backup written before linkage looks like this. Treating the
        // missing key as a vanished link deleted the workouts of the very
        // sessions being restored, and left them unlinked for good.
        try BackupService.restore(from: legacyURL, context: context)
        precondition(health.deletedIDs.isEmpty,
                     "Restoring the same session from a file without the key must leave Health alone")
        let legacySessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(legacySessions.count == 1 && legacySessions[0].healthWorkoutID == healthID,
                     "The restored session must keep the link this device already had")

        // A file taken between the phone's fallback save and the watch's own
        // names a workout this device has since replaced. The local link wins
        // and neither workout is touched.
        var stale = replacement
        stale.sessions[0].healthWorkoutID = UUID()
        let staleURL = try write(stale)
        defer { try? FileManager.default.removeItem(at: staleURL) }
        try BackupService.restore(from: staleURL, context: context)
        precondition(health.deletedIDs.isEmpty, "A differing link in the file must not delete either workout")
        let staleSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(staleSessions.count == 1 && staleSessions[0].healthWorkoutID == healthID,
                     "The local link must survive a file that names another workout")

        // A session the file doesn't hold leaves GymTrack, and its workout
        // stays in Health. Restore used to delete it, and a deletion there
        // reaches every device on the account with no way back.
        let later = WorkoutSession(title: "Later", startedAt: original.startedAt.addingTimeInterval(86_400))
        later.endedAt = later.startedAt.addingTimeInterval(60)
        let laterHealthID = UUID()
        later.healthWorkoutID = laterHealthID
        context.insert(later)
        try context.save()
        try BackupService.restore(from: legacyURL, context: context)
        precondition(health.deletedIDs.isEmpty,
                     "Restore must leave the workout of a session missing from the file in Health")
        let prunedSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(prunedSessions.count == 1 && prunedSessions[0].healthWorkoutID == healthID)

        // A plain erase keeps every Health workout, and says it never asked.
        precondition(BackupService.linkedHealthWorkoutCount(context: context) == 1)
        let plain = try await BackupService.wipe(context: context)
        precondition(plain == nil, "An erase that left Health alone must not report a cleanup")
        precondition(health.deletedIDs.isEmpty, "Erase must not touch Health unless asked to")
        let plainlyErased = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(plainlyErased.isEmpty)
        precondition(BackupService.linkedHealthWorkoutCount(context: context) == 0)

        // Only the explicit choice reaches Health, and the stub proves it
        // is the default path that does.
        try BackupService.restore(from: replacementURL, context: context)
        let second = WorkoutSession(title: "Second", startedAt: original.startedAt.addingTimeInterval(172_800))
        second.endedAt = second.startedAt.addingTimeInterval(60)
        second.healthWorkoutID = laterHealthID
        context.insert(second)
        try context.save()
        precondition(BackupService.linkedHealthWorkoutCount(context: context) == 2)
        let removed = try await BackupService.wipe(context: context, removingHealthWorkouts: true)
        precondition(removed?.isComplete == true)
        precondition(Set(health.deletedIDs) == [healthID, laterHealthID] && health.deletedIDs.count == 2,
                     "The explicit option must remove every linked workout once")

        // Refused deletions are still reported, over a local erase that stays.
        try BackupService.restore(from: replacementURL, context: context)
        let relinked = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(relinked.first?.healthWorkoutID == healthID)
        let incomplete = try await BackupService.wipe(
            context: context, removingHealthWorkouts: true,
            deletingHealthWorkout: { _ in false }
        )
        precondition(incomplete?.failedIDs == [healthID], "Failed Health cleanup must be reported")
        let erasedSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(erasedSessions.isEmpty,
                     "The local erase must remain committed if Health refuses deletion")

        print("Backup linkage, legacy decode, atomic restore and Health consent checks passed")
    }

    private static func write(_ archive: BackupService.Archive) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try encoder.encode(archive).write(to: url, options: .atomic)
        return url
    }
}
