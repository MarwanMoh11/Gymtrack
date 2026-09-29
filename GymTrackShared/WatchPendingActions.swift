import Foundation

/// The wrist's optimistic changes, persisted until a matching phone mirror
/// confirms them. WatchConnectivity keeps queued messages, but after a watch
/// relaunch the UI needs these values to avoid offering completed sets again.
struct WatchPendingActions: Codable {
    private(set) var sessionID: UUID?
    var logs: [UUID: WatchPendingLog] = [:]
    var undos: Set<UUID> = []
    /// The completion each pending undo takes back, as `WatchCommand.undoSet`
    /// sends it. Kept beside `undos` because the phone refuses an undo whose
    /// stamp names a log the row no longer holds, and without the stamp the
    /// wrist could not tell that refusal from an undo still on its way: the set
    /// stayed drawn as undone, and a Finish carried the same stale undo over the
    /// re-log. Absent for an undo with no stamp, and in state saved by a build
    /// that predates this field.
    private(set) var undoStamps: [UUID: Date] = [:]
    var starts: [UUID: Date] = [:]
    var cancels: Set<UUID> = []
    var focus: String?

    init() {}

    /// Written out so that state saved before `undoStamps` existed still
    /// decodes: the synthesized decoder demands every key, and a watch that
    /// updated mid-workout would lose its overlay for the sets it had just
    /// logged.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decodeIfPresent(UUID.self, forKey: .sessionID)
        logs = try values.decodeIfPresent([UUID: WatchPendingLog].self, forKey: .logs) ?? [:]
        undos = try values.decodeIfPresent(Set<UUID>.self, forKey: .undos) ?? []
        undoStamps = try values.decodeIfPresent([UUID: Date].self, forKey: .undoStamps) ?? [:]
        starts = try values.decodeIfPresent([UUID: Date].self, forKey: .starts) ?? [:]
        cancels = try values.decodeIfPresent(Set<UUID>.self, forKey: .cancels) ?? []
        focus = try values.decodeIfPresent(String.self, forKey: .focus)
    }

    mutating func adopt(_ id: UUID) {
        guard sessionID != id else { return }
        self = WatchPendingActions()
        sessionID = id
    }

    mutating func clear() { self = WatchPendingActions() }

    /// Notes an undo from the wrist and the completion it answers.
    mutating func recordUndo(of set: UUID, completedAt completion: Date?) {
        undos.insert(set)
        undoStamps[set] = completion
    }

    /// Forgets an undo, because the lifter logged the set again or the phone
    /// has settled it.
    mutating func forgetUndo(of set: UUID) {
        undos.remove(set)
        undoStamps.removeValue(forKey: set)
    }

    /// Whether the phone is known to have refused this undo: its mirror shows
    /// the set logged, but as a different completion from the one the undo
    /// takes back. That is the phone's own refusal test
    /// (`SetLog.admitsWristUndo`), so a mirror that still shows the stamped log
    /// means the undo has not landed yet and is not a verdict on anything.
    func undoWasRefused(_ set: UUID, mirroredCompletion: Date?) -> Bool {
        guard let stamp = undoStamps[set] else { return false }
        return !WatchCommand.isSameCompletion(stamp, as: mirroredCompletion)
    }

    /// Snapshots the latest local action for each set. A wrist undo removes its
    /// pending log and stays in `undos`, so Finish cannot resurrect that set.
    func finishBatch(for id: UUID, ratings: [WatchSetRating]) -> WatchFinishBatch {
        guard sessionID == id else {
            return WatchFinishBatch(sessionID: id, logs: [], undos: [], starts: [:],
                                    cancels: [], ratings: ratings.filter { $0.sessionID == id })
        }
        return WatchFinishBatch(sessionID: id, logs: Array(logs.values), undos: undos,
                                starts: starts, cancels: cancels,
                                ratings: ratings.filter { $0.sessionID == id })
    }
}
