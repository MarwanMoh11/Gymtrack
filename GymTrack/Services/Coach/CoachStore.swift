import Foundation

/// Where the coach loop's files live, and the reading and writing of them.
/// Nothing here touches SwiftData, so it can run off the main actor.
///
/// ```
/// Documents/Coach/snapshot.json         written by the app
/// Documents/Coach/decisions.json        written by the app
/// Documents/Coach/Inbox/proposal.json   written by the Mac
/// Documents/Coach/Inbox/ratings.json    written by the app, only while a
///                                       proposal is waiting undecided
/// ```
///
/// The Mac reaches these through `devicectl`, which copies a file's bytes at
/// whatever moment it is asked, so every write here is atomic: a half-written
/// file would be pulled as if it were the real one.
struct CoachStore: Sendable {

    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// `Documents/Coach` in the app's container.
    static var standard: CoachStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return CoachStore(root: documents.appendingPathComponent("Coach", isDirectory: true))
    }

    var snapshotURL: URL { root.appendingPathComponent("snapshot.json") }
    var decisionsURL: URL { root.appendingPathComponent("decisions.json") }
    var inboxURL: URL { root.appendingPathComponent("Inbox", isDirectory: true) }
    var proposalURL: URL { inboxURL.appendingPathComponent("proposal.json") }
    var pendingRatingsURL: URL { inboxURL.appendingPathComponent("ratings.json") }

    /// Creates the inbox, so the Mac's push has somewhere to land on a phone
    /// that has never been asked for a snapshot.
    func prepare() {
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
    }

    // MARK: Proposal

    func proposalData() -> Data? {
        try? Data(contentsOf: proposalURL)
    }

    /// When the file last changed, which for a push is when it arrived.
    func proposalArrivedAt() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: proposalURL.path))?[.modificationDate] as? Date
    }

    // MARK: Decisions

    /// The decisions on file, or an empty record when there is none.
    ///
    /// A file that will not decode is moved aside rather than treated as empty
    /// and overwritten by the next decision: whatever it holds is the user's
    /// history, and losing it silently is worse than carrying a stray file.
    func loadDecisions() -> CoachDecisionFile {
        guard let data = try? Data(contentsOf: decisionsURL) else { return CoachDecisionFile() }
        if let file = try? CoachJSON.decoded(CoachDecisionFile.self, from: data) { return file }
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = root.appendingPathComponent("decisions.unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: decisionsURL, to: aside)
        return CoachDecisionFile()
    }

    func saveDecisions(_ file: CoachDecisionFile) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try CoachJSON.encoded(file).write(to: decisionsURL, options: .atomic)
    }

    // MARK: Pending ratings

    /// The ratings waiting on an undecided proposal, or nil when there are none
    /// or the file is not ours. Unreadable is treated as absent rather than
    /// moved aside like the decisions: it holds opinions about a proposal that
    /// has not been acted on, and the next rating overwrites it.
    func loadPendingRatings() -> CoachPendingRatings? {
        guard let data = try? Data(contentsOf: pendingRatingsURL),
              let file = try? CoachJSON.decoded(CoachPendingRatings.self, from: data),
              file.format == CoachPendingRatings.format else { return nil }
        return file
    }

    func savePendingRatings(_ file: CoachPendingRatings) throws {
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        try CoachJSON.encoded(file).write(to: pendingRatingsURL, options: .atomic)
    }

    /// Succeeds when there is nothing to delete: the point is that no file is
    /// left, not that one was removed.
    func clearPendingRatings() throws {
        guard FileManager.default.fileExists(atPath: pendingRatingsURL.path) else { return }
        try FileManager.default.removeItem(at: pendingRatingsURL)
    }

    // MARK: Snapshot

    var hasSnapshot: Bool {
        FileManager.default.fileExists(atPath: snapshotURL.path)
    }

    func writeSnapshot(_ data: Data) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: snapshotURL, options: .atomic)
    }
}
