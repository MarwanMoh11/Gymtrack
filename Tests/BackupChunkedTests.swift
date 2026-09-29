import Foundation
import SwiftData

/// Run with scripts/test-backup-chunked.sh; no simulator is needed.
///
/// DATA-05: a file that repeats a custom exercise's ID is refused before the
/// wipe.
///
/// DATA-14: the snapshot and the restore apply hold the main actor a slice at
/// a time. What has to stay true while they do:
///
/// - the export is the same bytes, at every slice size;
/// - a restore is one save at the end, so nothing reaches the store before it,
///   and a failure part-way leaves the phone as it was;
/// - a second restore can't start on top of a running one;
/// - the longest single hold drops, which is printed for the report, measured
///   on an on-disk store at 300 sessions of 25 sets.
@main
struct BackupChunkedTests {
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
        ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
        ExerciseLoadPreference.self, HiddenExerciseRecord.self,
    ]

    static let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("gymtrack-backup-chunked-\(getpid())")

    /// An on-disk store: the stall only shows up with the real save.
    @MainActor static func makeContainer(_ name: String) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let schema = Schema(modelTypes)
        return try ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, url: scratch.appendingPathComponent("\(name).store")))
    }

    /// `sessions` finished sessions of `sets` sets, a plan, two custom
    /// exercises, notes and weigh-ins, so every part of the file has a row.
    @MainActor static func fill(_ context: ModelContext, sessions: Int, sets: Int, tag: Int = 0) throws {
        let plan = Plan(name: "Plan \(tag)", isActive: true)
        plan.id = uuid(0x100 + tag)
        context.insert(plan)
        let day = PlanDay(name: "Day", order: 0, weekday: 2)
        day.id = uuid(0x200 + tag)
        day.plan = plan
        context.insert(day)
        for c in 0..<2 {
            let custom = CustomExerciseRecord(name: "Custom \(tag)-\(c)", muscles: [], equipment: ["cable"],
                                              tracking: c == 0 ? .weightReps : .duration)
            custom.id = "custom-\(tag)-\(c)"
            context.insert(custom)
        }
        for m in 0..<20 {
            let metric = BodyMetric(date: base.addingTimeInterval(Double(m) * 86_400), weightKg: 80 + Double(m) / 10)
            metric.id = uuid(0x400 + tag * 1000 + m)
            context.insert(metric)
        }
        for n in 0..<sessions {
            let session = WorkoutSession(title: "Session \(n)", planDayID: day.id,
                                         startedAt: base.addingTimeInterval(Double(n) * 86_400))
            session.id = uuid(tag * 1_000_000 + n + 1)
            session.endedAt = session.startedAt.addingTimeInterval(3_000)
            context.insert(session)
            let note = ExerciseNote(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press")
            note.text = "Note \(n)"
            note.session = session
            context.insert(note)
            for index in 0..<sets {
                let set = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press",
                                 exerciseOrder: index / 5, setIndex: index % 5,
                                 weightKg: 40 + Double(index), reps: 8, tracking: .weightReps)
                set.id = uuid(tag * 1_000_000_000 + (n + 1) * 100 + index + 0x100000)
                set.isCompleted = true
                set.completedAt = session.startedAt.addingTimeInterval(Double(60 * (index + 1)))
                set.session = session
                context.insert(set)
            }
        }
        try context.save()
    }

    static func ms(_ since: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - since.uptimeNanoseconds) / 1_000_000
    }

    /// Wakes on the main actor between other work and records the longest gap
    /// it was kept waiting. A slice that holds the main actor for 60 ms shows
    /// up as a 60 ms gap; that is the hold a lifter's tap would wait behind.
    @MainActor final class HoldMeter {
        private(set) var longest = 0.0
        private var task: Task<Void, Never>?
        func start() {
            longest = 0
            task = Task { @MainActor in
                var last = DispatchTime.now()
                while !Task.isCancelled {
                    await Task.yield()
                    longest = max(longest, BackupChunkedTests.ms(last))
                    last = .now()
                }
            }
        }
        func stop() -> Double {
            task?.cancel()
            return longest
        }
    }

    static func counts(_ context: ModelContext) throws -> (sessions: Int, sets: Int, custom: Int) {
        (try context.fetchCount(FetchDescriptor<WorkoutSession>()),
         try context.fetchCount(FetchDescriptor<SetLog>()),
         try context.fetchCount(FetchDescriptor<CustomExerciseRecord>()))
    }

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        try? FileManager.default.removeItem(at: scratch)
        do { try await run() } catch {
            print("FAIL: threw \(error)")
            try? FileManager.default.removeItem(at: scratch)
            exit(1)
        }
        try? FileManager.default.removeItem(at: scratch)
        let failed = await MainActor.run { failures }
        if failed > 0 { exit(1) }
        print("Backup chunked checks passed")
    }

    @MainActor static func run() async throws {
        try await customExerciseIDs()
        try await exportIsByteIdentical()
        try await restoreIsOneSave()
        try await noSecondRestoreOnTop()
        try await holds()
    }

    // MARK: DATA-05

    @MainActor static func customExerciseIDs() async throws {
        let source = try makeContainer("ids-source")
        try fill(source.mainContext, sessions: 3, sets: 4)
        let data = try BackupService.exportData(context: source.mainContext, stamp: stamp)
        let good = try BackupService.decodedArchive(from: data)
        check(good.customExercises.count == 2, "the fixture carries two custom exercises")

        let target = try makeContainer("ids-target")
        try fill(target.mainContext, sessions: 5, sets: 2, tag: 7)
        let before = try counts(target.mainContext)
        let beforeBytes = try BackupService.exportData(context: target.mainContext, stamp: stamp)

        var repeated = good
        repeated.customExercises[1].id = repeated.customExercises[0].id
        let bad = try BackupService.encoded(repeated)

        func refusal(_ error: Error, _ label: String) {
            guard case let BackupService.RestoreError.invalidValue(field, value, _, _) = error else {
                return check(false, "\(label): refused as an invalid value, got \(error)")
            }
            check(field == "custom exercise ID", "\(label): the refusal names the custom exercise ID")
            check(value == repeated.customExercises[0].id, "\(label): the refusal names the repeated ID")
        }
        do {
            try BackupService.restore(data: bad, context: target.mainContext)
            check(false, "restore refuses a repeated custom exercise ID")
        } catch { refusal(error, "restore") }
        do {
            try await BackupService.restoreOffMain(data: bad, context: target.mainContext)
            check(false, "restoreOffMain refuses a repeated custom exercise ID")
        } catch { refusal(error, "restoreOffMain") }

        let after = try counts(target.mainContext)
        check(after == before, "a refused restore left every row where it was")
        check(try BackupService.exportData(context: target.mainContext, stamp: stamp) == beforeBytes,
              "a refused restore left the export byte-identical")

        // The file as written is fine, and distinct IDs are all it asks for.
        try await BackupService.restoreOffMain(data: data, context: target.mainContext)
        check(try counts(target.mainContext).custom == 2, "a file with distinct custom IDs restores")
    }

    // MARK: Export

    @MainActor static func exportIsByteIdentical() async throws {
        let container = try makeContainer("export")
        try fill(container.mainContext, sessions: 120, sets: 12)
        let context = container.mainContext
        let reference = try BackupService.exportData(context: context, stamp: stamp)

        for slice in [0.0, 2, 16, 1_000_000] {
            var reports: [Double] = []
            let archive = try await BackupService.makeArchivePaced(context: context, stamp: stamp,
                                                                  sliceMilliseconds: slice,
                                                             progress: { reports.append($0) })
            check(try BackupService.encoded(archive) == reference,
                  "the sliced snapshot is byte-identical at a \(slice) ms slice")
            check(zip(reports, reports.dropFirst()).allSatisfy { $0 <= $1 }, "progress never goes backwards (\(slice) ms)")
            check(reports.allSatisfy { (0...1).contains($0) }, "progress stays within 0 to 1 (\(slice) ms)")
            if slice == 0 {
                check(reports.count >= 120, "a zero slice reports once per session, got \(reports.count)")
            }
            if slice == 1_000_000 {
                check(reports.isEmpty, "a slice that is never used up never pauses or reports")
            }
        }

        var reports: [Double] = []
        let url = try await BackupService.exportOffMain(context: context, stamp: stamp,
                                                        sliceMilliseconds: 0, progress: { reports.append($0) })
        check(try Data(contentsOf: url) == reference, "exportOffMain writes the same bytes as the synchronous export")
        check(reports.last == 1, "exportOffMain ends at 1")
        check(reports.contains(0.6), "exportOffMain reports the snapshot done before it encodes")
    }

    // MARK: Restore

    @MainActor static func restoreIsOneSave() async throws {
        let source = try makeContainer("restore-source")
        try fill(source.mainContext, sessions: 60, sets: 10)
        let data = try BackupService.exportData(context: source.mainContext, stamp: stamp)

        let target = try makeContainer("restore-target")
        try fill(target.mainContext, sessions: 30, sets: 4, tag: 9)
        let context = target.mainContext
        let oldBytes = try BackupService.exportData(context: context, stamp: stamp)
        let old = try counts(context)

        // A second context reads the store itself, so it sees only what has
        // been saved. At every slice boundary that has to be the old data.
        let witness = ModelContext(target)
        var boundaries = 0
        var savedEarly = 0
        var reports: [Double] = []
        try await BackupService.restoreOffMain(data: data, context: context, sliceMilliseconds: 0, progress: { fraction in
            reports.append(fraction)
            guard fraction < 1 else { return }
            boundaries += 1
            let seen = try? counts(witness)
            if seen.map({ $0.sessions != old.sessions || $0.sets != old.sets }) ?? true { savedEarly += 1 }
        })
        check(boundaries > 60, "the restore paused between slices (\(boundaries) boundaries)")
        check(savedEarly == 0, "nothing reached the store before the final save (\(savedEarly) of \(boundaries) boundaries saw it)")
        check(reports.last == 1, "the restore ends at 1")
        check(zip(reports, reports.dropFirst()).allSatisfy { $0 <= $1 }, "restore progress never goes backwards")
        let after = try counts(witness)
        check(after.sessions == 60 && after.sets == 600, "the one save brought the whole file (\(after))")
        check(try BackupService.exportData(context: context, stamp: stamp) == data,
              "export, sliced restore, export is byte-stable")

        // A failure between the last insert and the save leaves the phone as
        // it was, on disk and in the context.
        let failing = try makeContainer("restore-failing")
        try fill(failing.mainContext, sessions: 30, sets: 4, tag: 9)
        let failingBytes = try BackupService.exportData(context: failing.mainContext, stamp: stamp)
        struct Refused: Error {}
        var lastFraction = 0.0
        do {
            try await BackupService.restoreOffMain(data: data, context: failing.mainContext, beforeCommit: {
                throw Refused()
            }, sliceMilliseconds: 0, progress: { lastFraction = $0 })
            check(false, "a throwing beforeCommit fails the restore")
        } catch is Refused {}
        check(lastFraction < 1, "a failed restore never reports done")
        let failedWitness = try counts(ModelContext(failing))
        check(failedWitness.sessions == 30 && failedWitness.sets == 120, "a failed restore left the store as it was")
        check(try counts(failing.mainContext) == (30, 120, 2), "a failed restore left the context as it was")
        check(try BackupService.exportData(context: failing.mainContext, stamp: stamp) == failingBytes,
              "a failed restore left the export byte-identical")
        check(failing.mainContext.autosaveEnabled, "autosave is back on after a failed restore")
        check(context.autosaveEnabled, "autosave is back on after a restore")
    }

    @MainActor static func noSecondRestoreOnTop() async throws {
        let source = try makeContainer("second-source")
        try fill(source.mainContext, sessions: 40, sets: 5)
        let data = try BackupService.exportData(context: source.mainContext, stamp: stamp)
        let target = try makeContainer("second-target")
        try fill(target.mainContext, sessions: 10, sets: 3, tag: 4)

        var second: Task<Void, Error>?
        var secondError: Error?
        try await BackupService.restoreOffMain(data: data, context: target.mainContext, sliceMilliseconds: 0, progress: { _ in
            guard second == nil else { return }
            second = Task { @MainActor in
                do { try await BackupService.restoreOffMain(data: data, context: target.mainContext) }
                catch { secondError = error }
            }
        })
        _ = try? await second?.value
        check({ if case .alreadyRunning? = secondError as? BackupService.RestoreError { return true } else { return false } }(),
              "a restore started while another is working is refused, got \(String(describing: secondError))")
        check(try counts(target.mainContext).sessions == 40, "the one running restore finished with no doubled rows")
    }

    // MARK: The hold, for the report

    @MainActor static func holds() async throws {
        let sessions = 300, sets = 25
        let source = try makeContainer("holds-source")
        try fill(source.mainContext, sessions: sessions, sets: sets)
        let context = source.mainContext
        let meter = HoldMeter()

        // Before: the synchronous snapshot and apply are one hold each.
        var t = DispatchTime.now()
        let archive = try BackupService.makeArchive(context: context, stamp: stamp)
        let syncSnapshot = ms(t)
        let data = try BackupService.encoded(archive)

        // Restored over a store that already holds a year, so the wipe is in
        // the hold too, which is what a lifter restoring onto a used phone has.
        let syncTarget = try makeContainer("holds-sync")
        try fill(syncTarget.mainContext, sessions: sessions, sets: sets, tag: 3)
        t = .now()
        try BackupService.restore(data: data, context: syncTarget.mainContext)
        let syncRestore = ms(t)

        // After: the longest wait a ticker on the main actor saw.
        meter.start()
        let sliced = try await BackupService.makeArchivePaced(context: context, stamp: stamp)
        let slicedSnapshot = meter.stop()
        check(try BackupService.encoded(sliced) == data, "the sliced snapshot at 300 x 25 is byte-identical")

        let slicedTarget = try makeContainer("holds-sliced")
        try fill(slicedTarget.mainContext, sessions: sessions, sets: sets, tag: 3)
        meter.start()
        t = .now()
        try await BackupService.restoreOffMain(data: data, context: slicedTarget.mainContext)
        let slicedTotal = ms(t)
        let slicedRestore = meter.stop()
        check(try counts(slicedTarget.mainContext).sets == sessions * sets, "the sliced restore at 300 x 25 brought every set")
        check(try BackupService.exportData(context: slicedTarget.mainContext, stamp: stamp) == data,
              "export after the sliced on-disk restore is byte-stable")

        // Export again on the restored store, the sequence that once trapped.
        meter.start()
        let again = try await BackupService.makeArchivePaced(context: slicedTarget.mainContext, stamp: stamp)
        _ = meter.stop()
        check(try BackupService.encoded(again) == data, "a sliced export after a restore is byte-identical")

        print("longest main-actor hold, on-disk store, \(sessions) sessions x \(sets) sets:")
        print("  snapshot: before \(Int(syncSnapshot)) ms, after \(Int(slicedSnapshot)) ms")
        print("  restore apply: before \(Int(syncRestore)) ms, after \(Int(slicedRestore)) ms (whole restore \(Int(slicedTotal)) ms)")
        check(slicedSnapshot < syncSnapshot / 2, "the sliced snapshot holds the main actor for under half the synchronous time")
        check(slicedRestore < syncRestore, "the sliced restore holds the main actor for less than the synchronous one")
    }
}
