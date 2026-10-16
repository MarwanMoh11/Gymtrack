import Foundation
import SwiftData

/// Keeps `Documents/Coach/snapshot.json` current, so a review on the Mac reads
/// the phone as it is rather than as it was when someone last remembered to
/// export.
///
/// The file is the backup archive, byte for byte: the same `makeArchivePaced`
/// and `encoded` the Settings export uses, so the coach and a restore read one
/// format. It is rewritten after any save that changes something the export
/// carries (finished sessions and their sets, notes and vitals, weigh-ins,
/// tape measurements, exercise notes, plans, custom exercises, load scales,
/// machines), after a workout finishes, after a proposal is applied, undone or
/// reverted, and once at every launch.
///
/// Nothing here may cost the lifter a tap or a frame mid-set. A request only
/// sets a flag; the write waits for things to go quiet, reads the store in
/// slices that hand the main actor back between them, and does the encoding and
/// the disk write on a background thread. Requests that arrive while one is
/// running fold into a single follow-up.
@MainActor
final class CoachSnapshot {

    static let shared = CoachSnapshot()

    /// How long a request waits for further ones before the write starts. A
    /// plan edit saves on every field the lifter touches, and writing once per
    /// save would re-read a year of history for each.
    var quietPeriod: Duration = .seconds(2)

    /// When the file was last written. Nil until this launch has written one.
    private(set) var lastWrittenAt: Date?

    private var store = CoachStore.standard
    private var context: ModelContext?
    private var container: ModelContainer?
    private var requested = false
    private var running: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?
    /// Bumped by an erase. A write that began under an earlier value read the
    /// store before the erase and must not put that data back on disk.
    private var generation = 0

    /// Starts watching for saves, makes sure the inbox folder exists, and asks
    /// for a snapshot.
    func start(container: ModelContainer, store: CoachStore = .standard) {
        self.store = store
        context = container.mainContext
        self.container = container
        store.prepare()
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        // Exported records are saved from many screens, from Health and from a
        // restore, so the store is watched rather than each of them asked to
        // say so.
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                // Another store's saves (a second container in a check, or a
                // separate context on this one, as Health's backfill uses) are
                // told apart by container, not by context.
                guard let self, let saved = note.object as? ModelContext,
                      saved.container === self.container, Self.changesExport(note) else { return }
                self.request()
            }
        }
        // An existing file is refreshed too. It can be stale from a save the
        // app was killed before the debounce wrote, or from a build that did not
        // watch every record, and nothing else would correct it for a lifter
        // who then neither trains nor edits. One write per launch, after the
        // quiet period, costs far less than a file that stays wrong; telling a
        // stale file from a current one would take the same read of the store.
        //
        // Not while a workout is open: relaunching mid-set (a crash, a
        // memory-pressure kill) would otherwise run the full paced export
        // against the lifter. The workout's finish or discard writes it.
        if !Self.hasActiveSession(container.mainContext) { request() }
    }

    /// Stops watching for saves. The app never calls this; a check that starts
    /// several of these in one process does, so they don't answer each other's
    /// saves.
    func stop() {
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
    }

    /// The entities the export carries whose every change matters. Sessions,
    /// sets and exercise notes are decided separately, because most of their
    /// saves are a live workout that is not exported until it finishes.
    private static let alwaysExported: Set<String> = [
        "Plan", "PlanDay", "PlanItem", "BodyMetric", "BodyMeasurement", "CustomExerciseRecord",
        "ExerciseLoadPreference", "HiddenExerciseRecord", "FormVideoRecord", "MachineSetupRecord",
    ]

    /// True when a save inserted, changed or deleted something the export carries.
    ///
    /// Logging saves after every set, and none of it is a reason to rewrite the
    /// file while the lifter is mid-workout: a set, note or session that belongs
    /// to the workout in progress is skipped, and its finish asks for a
    /// snapshot. A change to a finished session (a correction, a note, a late
    /// Health vital) is not skipped.
    ///
    /// A deleted row can no longer be asked which session it belonged to. A
    /// deleted session, set or note therefore counts unless a workout is in
    /// progress; then it is most likely part of that workout, and anything
    /// older that went with it is picked up when the workout finishes.
    ///
    /// Machine-setup records are the one always-exported entity that is also
    /// saved from the logger; while a workout is open they are skipped like the
    /// workout's own saves, because the finish or discard writes everything.
    static func changesExport(_ note: Notification) -> Bool {
        guard let context = note.object as? ModelContext else { return true }
        var unresolvableRemoval = false
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        for key in keys {
            let ids = note.userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []
            for id in ids {
                if id.entityName == "MachineSetupRecord" {
                    // Choosing a machine or nudging a seat happens in the logger.
                    // Mid-workout it waits for the workout's own finish, like the
                    // sets beside it, rather than running a full export under a
                    // lifter who is between sets.
                    if !hasActiveSession(context) { return true }
                    continue
                }
                if alwaysExported.contains(id.entityName) { return true }
                switch id.entityName {
                case "WorkoutSession", "SetLog", "ExerciseNote":
                    if key == .deletedIdentifiers { unresolvableRemoval = true; continue }
                    if belongsToFinishedSession(id, in: context) { return true }
                default:
                    continue
                }
            }
        }
        return unresolvableRemoval && !hasActiveSession(context)
    }

    /// True for a finished session, or a set or note of one. The row is looked
    /// up rather than taken from the objects the context happens to hold: the
    /// context keeps saved models only as long as something else does. A row
    /// that still cannot be resolved is assumed to count: refreshing once too
    /// often is cheaper than serving a stale file.
    private static func belongsToFinishedSession(_ id: PersistentIdentifier, in context: ModelContext) -> Bool {
        switch id.entityName {
        case "WorkoutSession":
            guard let session = context.model(for: id) as? WorkoutSession else { return true }
            return !session.isActive
        case "SetLog":
            guard let set = context.model(for: id) as? SetLog else { return true }
            return set.session.map { !$0.isActive } ?? false
        default:
            guard let note = context.model(for: id) as? ExerciseNote else { return true }
            return note.session.map { !$0.isActive } ?? false
        }
    }

    private static func hasActiveSession(_ context: ModelContext) -> Bool {
        let open = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt == nil })
        return ((try? context.fetchCount(open)) ?? 0) > 0
    }

    /// Asks for a fresh snapshot. Cheap, safe to call from anywhere on the main
    /// actor, and never waits for the write.
    func request() {
        requested = true
        guard running == nil, context != nil else { return }
        running = Task { await drain() }
    }

    /// Returns once no write is running or waiting.
    func settled() async {
        await running?.value
    }

    /// Drops any write that is waiting and waits out one that is running, so
    /// that nothing written afterwards can come from data read before an
    /// erase. A write already in the middle of reading the store is told its
    /// data is stale and writes nothing. Called by the erase before it deletes
    /// anything, so a paced read cannot resume over models the erase just
    /// removed; an erase that then fails asks for a fresh write with `request()`.
    func cancelWrites() async {
        generation += 1
        requested = false
        running?.cancel()
        await running?.value
    }

    private func drain() async {
        while requested && !Task.isCancelled {
            try? await Task.sleep(for: quietPeriod)
            guard !Task.isCancelled else { break }
            requested = false
            await writeNow()
        }
        running = nil
    }

    /// Reads, encodes and writes once, for a test or a caller that wants the
    /// file on disk before it carries on. `stamp` is what a test holds still so
    /// two exports of one store can be compared byte for byte.
    func writeNow(stamp: BackupService.ExportStamp = .current()) async {
        guard let context else { return }
        let store = store
        let started = generation
        do {
            let archive = try await BackupService.makeArchivePaced(context: context, stamp: stamp)
            guard started == generation else { return }
            try await Task.detached(priority: .utility) {
                try store.writeSnapshot(try BackupService.encoded(archive))
            }.value
            lastWrittenAt = .now
        } catch {
            // A snapshot that cannot be written is the Mac pulling an older
            // one, which it can see from the file's own `exportedAt`. It is not
            // something to tell the lifter about mid-set.
        }
    }
}
