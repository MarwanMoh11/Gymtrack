import Foundation

/// A session the lifter finished or discarded on the wrist, remembered until
/// the phone stops describing it as live.
///
/// Finish and Discard reach the phone through the delivery queue, and nothing
/// orders that queue against the mirrors coming back. Until the phone has read
/// the command, every mirror it sends, and the application context a relaunched
/// watch app starts from, still carries the session as in progress. Taken at
/// its word, the watch put the lifter back into a workout they had just ended,
/// and the recorder began a second Health workout backdated to the session's
/// start, which the phone then linked in place of the real one.
///
/// Persisted, because a relaunch is exactly when that stale context arrives.
/// It holds nothing but the ID: the sets the phone has not confirmed stay in
/// `WatchPendingActions`, where they still have to reach it.
struct WatchSessionTombstone: Equatable, Sendable {

    static let defaultsKey = "watch.endedLocally"

    private(set) var sessionID: UUID?

    init(sessionID: UUID? = nil) {
        self.sessionID = sessionID
    }

    init(defaults: UserDefaults) {
        sessionID = defaults.string(forKey: Self.defaultsKey).flatMap(UUID.init(uuidString:))
    }

    func save(to defaults: UserDefaults) {
        if let sessionID {
            defaults.set(sessionID.uuidString, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    mutating func mark(_ id: UUID) {
        sessionID = id
    }

    /// Whether a session may be drawn as in progress and recorded to Health.
    /// Only the ended one is refused: a session started after it owes nothing
    /// to the queued Finish, and has to show at once.
    func admits(_ id: UUID) -> Bool {
        id != sessionID
    }

    /// Retires the mark once the phone has stopped calling the session live.
    /// Only a mirror fresh from the phone counts. The cached context can
    /// predate the Finish, or the session itself, so its silence proves
    /// nothing about whether the phone has heard the command; retiring on it
    /// would let the next stale reply bring the session back.
    mutating func settle(with mirror: WatchMirror, fromCache: Bool) {
        guard !fromCache, let ended = sessionID, mirror.session?.sessionID != ended else { return }
        sessionID = nil
    }

    /// The mirrored session the wrist may treat as in progress, before its own
    /// unconfirmed changes are folded in.
    func liveSession(in mirror: WatchMirror, awaitingFreshMirror: Bool,
                     now: Date = .now) -> WatchSessionSnapshot? {
        guard !awaitingFreshMirror, let session = mirror.session else { return nil }
        // The phone closes an unfinished session after twelve hours on its
        // next launch. Its old application context can reach this watch first,
        // and treating that snapshot as live would start a new Health workout
        // for yesterday's session before the phone has a chance to correct it.
        guard session.startedAt.timeIntervalSince(now) > -12 * 3600 else { return nil }
        guard admits(session.sessionID) else { return nil }
        return session
    }
}

// MARK: - The phone's half

/// What a finished session links to when the watch reports a Health workout.
///
/// The phone's own save is a fallback, written only because the watch's ID was
/// late, and the watch's workout carries the beat-by-beat heart rate, so it
/// takes the fallback's place. A second *watch* workout for the same session is
/// never better than the first: the wrist saves once, when the session ends,
/// and anything after that is a recording restarted for a session that was
/// already over, backdated to its start and carrying none of its metadata.
/// Letting it replace the first sent the accurate workout to the cleanup list.
///
/// A linked ID the phone has no record of writing is treated as the watch's.
/// Keeping a link that could have been improved costs far less than
/// retiring one that could not.
enum WatchWorkoutLink: Equatable, Sendable {
    /// The session already points at this workout.
    case alreadyLinked
    /// Nothing linked yet; the watch's workout becomes the link.
    case link
    /// The phone's fallback is retired in favour of the watch's workout.
    case replacePhoneFallback(UUID)
    /// A watch workout is already linked; the later one is ignored.
    case keepExisting

    static func decide(current: UUID?, incoming: UUID, phoneWritten: Set<UUID>) -> WatchWorkoutLink {
        guard let current else { return .link }
        if current == incoming { return .alreadyLinked }
        return phoneWritten.contains(current) ? .replacePhoneFallback(current) : .keepExisting
    }
}
