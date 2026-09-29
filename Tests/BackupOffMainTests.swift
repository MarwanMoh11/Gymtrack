import Foundation
import SwiftData

/// Run with scripts/test-backup-off-main.sh; no simulator is needed.
///
/// DATA-14: export, restore and erase froze the sheet for as long as the
/// history was long. The work that does not need the store now runs off the
/// main actor; these checks hold the line that moving it changed nothing else:
/// the file is the same bytes, a bad file is still refused before anything is
/// deleted, and Health gets every workout once, in one call.
@main
struct BackupOffMainTests {
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

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    static let sessionCount = 300
    static let setsPerSession = 25

    /// A year of history: 300 finished sessions of 25 sets, each linked to a
    /// Health workout, except that the last two share one link.
    @MainActor static func fill(_ context: ModelContext) -> Set<UUID> {
        let plan = Plan(name: "A", isActive: true)
        context.insert(plan)
        let day = PlanDay(name: "Day", order: 0, weekday: 2)
        day.plan = plan
        context.insert(day)
        var workouts = Set<UUID>()
        for n in 0..<sessionCount {
            let session = WorkoutSession(title: "Session \(n)", planDayID: day.id,
                                         startedAt: base.addingTimeInterval(Double(n) * 86_400))
            session.id = uuid(n + 1)
            session.endedAt = session.startedAt.addingTimeInterval(3_000)
            session.healthWorkoutID = uuid(0xB000 + min(n, sessionCount - 2))
            workouts.insert(session.healthWorkoutID!)
            context.insert(session)
            for index in 0..<setsPerSession {
                let set = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press",
                                 exerciseOrder: index / 5, setIndex: index % 5,
                                 weightKg: 40 + Double(index), reps: 8, tracking: .weightReps)
                set.id = uuid((n + 1) * 100 + index + 0x100000)
                set.isCompleted = true
                set.completedAt = session.startedAt.addingTimeInterval(Double(60 * (index + 1)))
                set.session = session
                context.insert(set)
            }
        }
        try? context.save()
        return workouts
    }

    static func ms(_ since: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - since.uptimeNanoseconds) / 1_000_000
    }

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        do { try await run() } catch {
            print("FAIL: threw \(error)")
            exit(1)
        }
        let failed = await MainActor.run { failures }
        if failed > 0 { exit(1) }
        print("Backup off-main checks passed")
    }

    @MainActor static func run() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workouts = fill(context)

        // The time split, so the report can say what moved off the main thread.
        var t = DispatchTime.now()
        let archive = try BackupService.makeArchive(context: context, stamp: stamp)
        let snapshotMs = ms(t)
        t = .now()
        let inline = try BackupService.encoded(archive)
        let encodeMs = ms(t)
        t = .now()
        let decoded = try BackupService.decodedArchive(from: inline)
        let decodeMs = ms(t)
        print("split (\(sessionCount) sessions x \(setsPerSession) sets, \(inline.count / 1024) KiB): "
              + "snapshot on main \(Int(snapshotMs)) ms | encode+write off main \(Int(encodeMs)) ms | "
              + "read+decode+validate off main \(Int(decodeMs)) ms")
        check(decoded.sessions.count == sessionCount, "decode keeps every session")

        // Off-main encoding is the same bytes as on-main encoding.
        let detached = try await Task.detached { try BackupService.encoded(archive) }.value
        check(detached == inline, "detached encode is byte-identical to the inline one")

        // The whole off-main export writes those bytes, and the main actor is
        // free while it does: a ticker on it advances during the await.
        var ticks = 0
        let ticker = Task { @MainActor in
            while !Task.isCancelled { ticks += 1; await Task.yield() }
        }
        let url = try await BackupService.exportOffMain(context: context, stamp: stamp)
        ticker.cancel()
        check(try Data(contentsOf: url) == inline, "exportOffMain writes the same bytes as export")
        check(url.lastPathComponent == "GymTrack-2026-09-23.json", "the file is named for the export day in the lifter's timezone")
        check(ticks > 0, "the main actor ran while the export was encoding and writing")
        let syncURL = try BackupService.export(context: context, stamp: stamp)
        check(try Data(contentsOf: syncURL) == inline, "the synchronous export is unchanged")

        // Restore off main, into a different store, then export again.
        let otherContainer = try makeContainer()
        let other = otherContainer.mainContext
        t = .now()
        try await BackupService.restoreOffMain(from: url, context: other)
        print("restore total (decode off main, apply on main) \(Int(ms(t))) ms")
        check(try other.fetchCount(FetchDescriptor<WorkoutSession>()) == sessionCount, "restore brings back every session")
        check(try other.fetchCount(FetchDescriptor<SetLog>()) == sessionCount * setsPerSession, "restore brings back every set")
        check(try BackupService.exportData(context: other, stamp: stamp) == inline,
              "export, off-main restore, export is byte-stable")

        // Validation still finishes before anything is deleted.
        let sessionsBefore = try other.fetchCount(FetchDescriptor<WorkoutSession>())
        var bad = decoded
        bad.plans[0].days[0].weekday = 9
        let badData = try BackupService.encoded(bad)
        do {
            try await BackupService.restoreOffMain(data: badData, context: other)
            check(false, "an out-of-range weekday is refused")
        } catch let error as BackupService.RestoreError {
            check({ if case .invalidValue = error { return true } else { return false } }(), "refusal names the invalid value")
        }
        check(try other.fetchCount(FetchDescriptor<WorkoutSession>()) == sessionsBefore,
              "a refused restore left every session in place")
        check(try other.fetchCount(FetchDescriptor<SetLog>()) == sessionCount * setsPerSession,
              "a refused restore left every set in place")
        do {
            try await BackupService.restoreOffMain(data: Data("{ not json".utf8), context: other)
            check(false, "garbage is refused")
        } catch {}
        check(try other.fetchCount(FetchDescriptor<WorkoutSession>()) == sessionsBefore,
              "a file that doesn't decode left everything in place")

        // A workout in progress refuses the restore before anything is read.
        let open = WorkoutSession(title: "Now", startedAt: base)
        other.insert(open)
        do {
            try await BackupService.restoreOffMain(data: inline, context: other)
            check(false, "restore is refused while a workout is open")
        } catch let error as BackupService.RestoreError {
            check({ if case .workoutInProgress = error { return true } else { return false } }(), "the open workout is named")
        }
        other.delete(open)
        try other.save()

        // Erase hands Health every workout ID once, in one call.
        var calls: [[UUID]] = []
        let result = try await BackupService.wipe(
            context: context, removingHealthWorkouts: true,
            deletingHealthWorkouts: { ids in calls.append(ids); return [] })
        check(calls.count == 1, "Health was asked once, not once per workout (\(calls.count) calls)")
        let received = calls.first ?? []
        check(received.count == workouts.count && Set(received) == workouts,
              "every workout ID reached the batch, exactly once (\(received.count) of \(workouts.count))")
        check(received == received.sorted { $0.uuidString < $1.uuidString }, "the batch is in a defined order")
        check(result?.isComplete == true, "a batch that removed everything is a complete cleanup")
        check(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0, "erase left no session")
        check(try context.fetchCount(FetchDescriptor<SetLog>()) == 0, "erase left no set")

        // IDs the batch could not remove come back as the failures, and
        // Health is not asked at all unless the lifter chose it.
        let thirdContainer = try makeContainer()
        let third = thirdContainer.mainContext
        _ = fill(third)
        let keep = try await BackupService.wipe(context: third, deletingHealthWorkouts: { _ in
            check(false, "Health was asked without being chosen"); return []
        })
        check(keep == nil, "an erase that didn't ask Health reports no cleanup")
        let fourthContainer = try makeContainer()
        let fourth = fourthContainer.mainContext
        let partial = try await { () async throws -> BackupService.HealthCleanupResult? in
            _ = fill(fourth)
            return try await BackupService.wipe(context: fourth, removingHealthWorkouts: true,
                                                deletingHealthWorkouts: { ids in [ids[0]] })
        }()
        check(partial?.failedIDs.count == 1, "a workout the batch left in Health is reported")

        // The default path goes through the service's batch call.
        let fifthContainer = try makeContainer()
        let fifth = fifthContainer.mainContext
        let fifthWorkouts = fill(fifth)
        HealthKitService.shared.deletedIDs = []
        _ = try await BackupService.wipe(context: fifth, removingHealthWorkouts: true)
        check(HealthKitService.shared.deletedIDs.count == fifthWorkouts.count
              && Set(HealthKitService.shared.deletedIDs) == fifthWorkouts,
              "the default erase deletes every workout ID once through HealthKitService")
        withExtendedLifetime((container, otherContainer, thirdContainer, fourthContainer, fifthContainer)) {}
    }

}
