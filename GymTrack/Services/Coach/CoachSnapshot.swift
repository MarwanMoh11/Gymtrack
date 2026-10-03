import Foundation
import SwiftData

/// Keeps `Documents/Coach/snapshot.json` current, so a review on the Mac reads
/// the phone as it is rather than as it was when someone last remembered to
/// export.
///
/// The file is the backup archive, byte for byte: the same `makeArchivePaced`
/// and `encoded` the Settings export uses, so the coach and a restore read one
/// format. It is rewritten after a workout finishes, after the plan is saved,
/// after a proposal is applied, undone or reverted, and at launch when there is
/// none.
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
    private var requested = false
    private var running: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?

    /// Starts watching for plan edits, makes sure the inbox folder exists, and
    /// asks for a snapshot if the file is missing.
    func start(container: ModelContainer, store: CoachStore = .standard) {
        self.store = store
        context = container.mainContext
        store.prepare()
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        // Plan edits are saved from several screens and by a restore, so the
        // store is watched rather than each of them asked to say so.
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard Self.touchesPlan(note) || Self.insertsFinishedSession(note) else { return }
                self?.request()
            }
        }
        if !store.hasSnapshot { request() }
    }

    /// Stops watching for saves. The app never calls this; a check that starts
    /// several of these in one process does, so they don't answer each other's
    /// saves.
    func stop() {
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
    }

    /// True when a save inserted, changed or deleted a plan, a day or a slot.
    ///
    /// A save that touches only sets and sessions is ignored: logging saves
    /// after every set, and none of it is a reason to rewrite the file while
    /// the lifter is mid-workout. The workout's own end asks for a snapshot.
    nonisolated static func touchesPlan(_ note: Notification) -> Bool {
        let planEntities: Set<String> = ["Plan", "PlanDay", "PlanItem"]
        return [ModelContext.NotificationKey.insertedIdentifiers,
                .updatedIdentifiers, .deletedIdentifiers].contains { key in
            let identifiers = note.userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []
            return identifiers.contains { planEntities.contains($0.entityName) }
        }
    }

    /// True when a save inserted a session that is already finished: a workout
    /// logged afterwards, or one a restore brought back. A session the logger
    /// starts is inserted open, and its end is announced by the finish itself.
    static func insertsFinishedSession(_ note: Notification) -> Bool {
        guard let context = note.object as? ModelContext else { return false }
        let key = ModelContext.NotificationKey.insertedIdentifiers.rawValue
        let inserted = note.userInfo?[key] as? [PersistentIdentifier] ?? []
        return inserted.contains { id in
            guard id.entityName == "WorkoutSession",
                  let session: WorkoutSession = context.registeredModel(for: id) else { return false }
            return !session.isActive
        }
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

    private func drain() async {
        while requested {
            try? await Task.sleep(for: quietPeriod)
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
        do {
            let archive = try await BackupService.makeArchivePaced(context: context, stamp: stamp)
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
