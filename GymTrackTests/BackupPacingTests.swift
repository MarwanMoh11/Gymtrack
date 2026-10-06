import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// Export, restore and erase froze the sheet for as long as the history was
/// long (DATA-14). The snapshot now walks the sessions in slices that hand the
/// main actor back, and the encode, decode and write run off it. What has to
/// stay true while they do: the file is the same bytes at every slice size, a
/// restore is one save at the end, so nothing reaches the store before it and a
/// failure part-way leaves the phone as it was, a second restore can't start on
/// top of a running one, a bad file is still refused before anything is
/// deleted, and the longest single hold on the main actor drops.
///
/// The stores here are on disk, as the app's is: the stall the slices exist
/// for only shows up with a real save.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(3)))
struct BackupPacingTests {

    private let stamp = PersistenceFixtures.stamp(at: TestClock.at("2026-09-22T22:30:00"), version: "1.4", build: "27")
    private let base = TestClock.at("2026-09-21T14:13:20")

    // MARK: - The sliced snapshot

    @Test func thePacedSnapshotIsTheSameFileAtEverySliceSize() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let disk = try DiskStores()
        let context = try disk.container("export").mainContext
        try fill(context, sessions: 120, sets: 12)
        let reference = try BackupService.exportData(context: context, stamp: stamp)

        for slice in [0.0, 2, 16, 1_000_000] {
            var reports: [Double] = []
            let archive = try await BackupService.makeArchivePaced(context: context, stamp: stamp, sliceMilliseconds: slice,
                                                                  progress: { reports.append($0) })
            #expect(try BackupService.encoded(archive) == reference, "\(slice) ms slices")
            #expect(zip(reports, reports.dropFirst()).allSatisfy { $0 <= $1 }, "Progress went backwards at \(slice) ms")
            #expect(reports.allSatisfy { (0...1).contains($0) }, "Progress left 0 to 1 at \(slice) ms")
            if slice == 0 {
                #expect(reports.count >= 120, "A zero slice reports once per session, got \(reports.count)")
            }
            if slice == 1_000_000 {
                #expect(reports.isEmpty, "A slice that is never used up never pauses or reports")
            }
        }

        var reports: [Double] = []
        let url = try await BackupService.exportOffMain(context: context, stamp: stamp, sliceMilliseconds: 0,
                                                        progress: { reports.append($0) })
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url) == reference)
        #expect(reports.last == 1)
        // The snapshot is reported done before the encode, which has no steps to count.
        #expect(reports.contains(0.6))
    }

    // MARK: - The paced restore

    @Test func aPacedRestoreReachesTheStoreOnlyAtItsOneSave() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let disk = try DiskStores()
        let source = try disk.container("source").mainContext
        try fill(source, sessions: 60, sets: 10)
        let data = try BackupService.exportData(context: source, stamp: stamp)
        let target = try disk.container("target")
        let context = target.mainContext
        try fill(context, sessions: 30, sets: 4, tag: 9)
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

        #expect(boundaries > 60, "The restore paused between slices \(boundaries) times")
        #expect(savedEarly == 0, "\(savedEarly) of \(boundaries) boundaries saw the store change before the save")
        #expect(reports.last == 1)
        #expect(zip(reports, reports.dropFirst()).allSatisfy { $0 <= $1 })
        let after = try counts(witness)
        #expect(after.sessions == 60 && after.sets == 600, "The one save brought the whole file")
        #expect(try BackupService.exportData(context: context, stamp: stamp) == data)
        #expect(context.autosaveEnabled)
    }

    @Test func aPacedRestoreThatFailsBeforeItsSaveLeavesThePhoneAsItWas() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let disk = try DiskStores()
        let source = try disk.container("source").mainContext
        try fill(source, sessions: 60, sets: 10)
        let data = try BackupService.exportData(context: source, stamp: stamp)
        let failing = try disk.container("failing")
        let context = failing.mainContext
        // `fill` puts no slot on its day: a rollback over a restored slot traps
        // inside SwiftData (see `BackupRestoreTests`).
        try fill(context, sessions: 30, sets: 4, tag: 9)
        let before = try BackupService.exportData(context: context, stamp: stamp)
        struct Refused: Error {}
        var lastFraction = 0.0

        do {
            try await BackupService.restoreOffMain(data: data, context: context, beforeCommit: { throw Refused() },
                                                   sliceMilliseconds: 0, progress: { lastFraction = $0 })
            Issue.record("A restore whose beforeCommit threw went through")
        } catch is Refused {
        }

        #expect(lastFraction < 1, "A failed restore never reports done")
        let stored = try counts(ModelContext(failing))
        #expect(stored.sessions == 30 && stored.sets == 120, "On disk")
        let held = try counts(context)
        #expect(held.sessions == 30 && held.sets == 120 && held.custom == 2, "In the context")
        #expect(try BackupService.exportData(context: context, stamp: stamp) == before)
        #expect(context.autosaveEnabled)
    }

    @Test func aSecondRestoreCannotStartOnTopOfARunningOne() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let disk = try DiskStores()
        let source = try disk.container("source").mainContext
        try fill(source, sessions: 40, sets: 5)
        let data = try BackupService.exportData(context: source, stamp: stamp)
        let context = try disk.container("target").mainContext
        try fill(context, sessions: 10, sets: 3, tag: 4)
        var second: Task<Void, Never>?
        var secondError: (any Error)?

        try await BackupService.restoreOffMain(data: data, context: context, sliceMilliseconds: 0, progress: { _ in
            guard second == nil else { return }
            second = Task { @MainActor in
                do { try await BackupService.restoreOffMain(data: data, context: context) }
                catch { secondError = error }
            }
        })
        await second?.value

        guard case .alreadyRunning? = secondError as? BackupService.RestoreError else {
            Issue.record("A restore started during another was not refused as already running: \(String(describing: secondError))")
            return
        }
        #expect(try counts(context).sessions == 40, "The one running restore finished with no doubled rows")
    }

    // MARK: - How long the main actor is held

    @Test func thePacedSnapshotAndRestoreHoldTheMainActorLessThanTheSynchronousOnes() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let disk = try DiskStores()
        let sessions = 300, sets = 25
        let context = try disk.container("source").mainContext
        try fill(context, sessions: sessions, sets: sets)
        let meter = MainActorMeter()

        // Before: the synchronous snapshot and apply are one hold each.
        var started = DispatchTime.now()
        let archive = try BackupService.makeArchive(context: context, stamp: stamp)
        let syncSnapshot = milliseconds(since: started)
        let data = try BackupService.encoded(archive)
        // Restored over a store that already holds a year, so the wipe is in
        // the hold too, as it is for a lifter restoring onto a used phone.
        let syncTarget = try disk.container("sync").mainContext
        try fill(syncTarget, sessions: sessions, sets: sets, tag: 3)
        started = .now()
        try BackupService.restore(data: data, context: syncTarget)
        let syncRestore = milliseconds(since: started)

        // After: the longest wait a ticker on the main actor saw.
        meter.start()
        let sliced = try await BackupService.makeArchivePaced(context: context, stamp: stamp)
        let slicedSnapshot = meter.stop()
        #expect(try BackupService.encoded(sliced) == data)

        let slicedTarget = try disk.container("sliced").mainContext
        try fill(slicedTarget, sessions: sessions, sets: sets, tag: 3)
        meter.start()
        try await BackupService.restoreOffMain(data: data, context: slicedTarget)
        let slicedRestore = meter.stop()
        #expect(try counts(slicedTarget).sets == sessions * sets)
        #expect(try BackupService.exportData(context: slicedTarget, stamp: stamp) == data)

        // Exporting again on the restored store is the sequence that once trapped.
        let again = try await BackupService.makeArchivePaced(context: slicedTarget, stamp: stamp)
        #expect(try BackupService.encoded(again) == data)

        #expect(slicedSnapshot < syncSnapshot / 2,
                "Snapshot held the main actor \(Int(slicedSnapshot)) ms sliced, \(Int(syncSnapshot)) ms in one go")
        #expect(slicedRestore < syncRestore,
                "Restore held the main actor \(Int(slicedRestore)) ms off main, \(Int(syncRestore)) ms on it")
    }

    // MARK: - A year, off the main actor

    @Test func aYearExportedOffMainIsTheSameFileAndLeavesTheMainActorFree() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try fillYear(context)

        let archive = try BackupService.makeArchive(context: context, stamp: stamp)
        let inline = try BackupService.encoded(archive)
        #expect(try BackupService.decodedArchive(from: inline).sessions.count == 300)
        let detached = try await Task.detached { try BackupService.encoded(archive) }.value
        #expect(detached == inline)

        // A ticker on the main actor advances while the export awaits its
        // encode and write.
        let meter = MainActorMeter()
        meter.start()
        let url = try await BackupService.exportOffMain(context: context, stamp: stamp)
        _ = meter.stop()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try Data(contentsOf: url) == inline)
        #expect(url.lastPathComponent == "GymTrack-2026-09-23.json")
        #expect(meter.ticks > 0, "The main actor never ran while the export was encoding and writing")
        let syncURL = try BackupService.export(context: context, stamp: stamp)
        #expect(try Data(contentsOf: syncURL) == inline)
    }

    @Test func aYearRestoredOffMainComesBackWholeAndABadFileMovesNothing() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let source = try TestStore.context()
        try fillYear(source)
        let file = try BackupService.exportData(context: source, stamp: stamp)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try file.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try TestStore.context()

        try await BackupService.restoreOffMain(from: url, context: context)

        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 300)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 300 * 25)
        #expect(try BackupService.exportData(context: context, stamp: stamp) == file)

        // Validation still finishes before anything is deleted.
        var bad = try BackupService.decodedArchive(from: file)
        bad.plans[0].days[0].weekday = 9
        do {
            try await BackupService.restoreOffMain(data: BackupService.encoded(bad), context: context)
            Issue.record("An out-of-range weekday was accepted")
        } catch BackupService.RestoreError.invalidValue {
        }
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 300)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 300 * 25)
        await #expect(throws: (any Error).self) {
            try await BackupService.restoreOffMain(data: Data("{ not json".utf8), context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 300)

        // A workout in progress refuses the restore before anything is read.
        context.insert(WorkoutSession(title: "Now", startedAt: base))
        do {
            try await BackupService.restoreOffMain(data: file, context: context)
            Issue.record("A restore over a running workout was accepted")
        } catch BackupService.RestoreError.workoutInProgress {
        }
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 300 * 25)
    }

    // MARK: - Fixtures

    /// `sessions` finished sessions of `sets` sets, a plan, two custom
    /// exercises, notes and weigh-ins, so every part of the file has a row.
    /// `tag` keeps two stores' IDs apart.
    private func fill(_ context: ModelContext, sessions: Int, sets: Int, tag: Int = 0) throws {
        let uuid = PersistenceFixtures.uuid
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
            let note = ExerciseNote(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name)
            note.text = "Note \(n)"
            note.session = session
            context.insert(note)
            for index in 0..<sets {
                let set = SetLog(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name,
                                 exerciseOrder: index / 5, setIndex: index % 5,
                                 weightKg: 40 + Double(index), reps: 8, tracking: .weightReps)
                set.id = uuid(tag * 1_000_000_000 + (n + 1) * 100 + index + 0x100000)
                set.isCompleted = true
                set.completedAt = session.startedAt.addingTimeInterval(Double(60 * (index + 1)))
                PersistenceFixtures.add(set, to: session, in: context)
            }
        }
        try context.save()
    }

    /// A year of history: 300 finished sessions of 25 sets, each linked to a
    /// Health workout.
    private func fillYear(_ context: ModelContext) throws {
        let uuid = PersistenceFixtures.uuid
        let plan = PersistenceFixtures.plan("A", createdAt: base, active: true, in: context)
        let day = PersistenceFixtures.day("Day", order: 0, weekday: 2, exercises: [], in: plan, context: context)
        for n in 0..<300 {
            let started = base.addingTimeInterval(Double(n) * 86_400)
            let session = PersistenceFixtures.session("Session \(n)", startedAt: started,
                                                      endedAt: started.addingTimeInterval(3_000),
                                                      planDayID: day.id, in: context)
            session.id = uuid(n + 1)
            session.healthWorkoutID = uuid(0xB000 + n)
            for index in 0..<25 {
                let set = SetLog(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name,
                                 exerciseOrder: index / 5, setIndex: index % 5,
                                 weightKg: 40 + Double(index), reps: 8, tracking: .weightReps)
                set.id = uuid((n + 1) * 100 + index + 0x100000)
                set.isCompleted = true
                set.completedAt = started.addingTimeInterval(Double(60 * (index + 1)))
                PersistenceFixtures.add(set, to: session, in: context)
            }
        }
        try context.save()
    }

    private func counts(_ context: ModelContext) throws -> (sessions: Int, sets: Int, custom: Int) {
        (try context.fetchCount(FetchDescriptor<WorkoutSession>()),
         try context.fetchCount(FetchDescriptor<SetLog>()),
         try context.fetchCount(FetchDescriptor<CustomExerciseRecord>()))
    }
}

/// On-disk stores in a folder of their own, removed with it when the test
/// that made them ends.
@MainActor
private final class DiskStores {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("BackupPacingTests-\(UUID().uuidString)")
    private var containers: [ModelContainer] = []

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The containers go first, so SQLite has closed the files before they are
    /// removed rather than finding them unlinked under it.
    deinit {
        containers.removeAll()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Kept here, because a context does not keep its container alive.
    func container(_ name: String) throws -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, url: folder.appendingPathComponent("\(name).store"), cloudKitDatabase: .none))
        containers.append(container)
        return container
    }
}

/// Wakes on the main actor between other work, counting each wake and keeping
/// the longest gap it was kept waiting. A slice that holds the main actor for
/// 60 ms shows up as a 60 ms gap: the hold a lifter's tap would wait behind.
@MainActor
private final class MainActorMeter {
    private(set) var ticks = 0
    private(set) var longest = 0.0
    private var task: Task<Void, Never>?

    func start() {
        ticks = 0
        longest = 0
        // Weak, so a test that throws before `stop` can't leave this spinning
        // on the main actor under every test after it.
        task = Task { @MainActor [weak self] in
            var last = DispatchTime.now()
            while !Task.isCancelled {
                await Task.yield()
                guard let self else { return }
                self.ticks += 1
                self.longest = max(self.longest, milliseconds(since: last))
                last = .now()
            }
        }
    }

    /// The longest gap seen since `start`.
    func stop() -> Double {
        task?.cancel()
        task = nil
        return longest
    }
}

private func milliseconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}
