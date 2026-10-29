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
/// It holds the ID, for a Finish what the idle screen may say about it, and
/// the Finish itself: the sets the phone has not confirmed stay in
/// `WatchPendingActions`, where they still have to reach it.
struct WatchSessionTombstone: Equatable, Sendable {

    static let defaultsKey = "watch.endedLocally"
    static let finishedKey = "watch.endedLocally.finished"
    static let finishCommandKey = "watch.endedLocally.finishCommand"

    private(set) var sessionID: UUID?
    /// Set when the session ended with a Finish that had sets in it, until
    /// the phone answers for it. See `WatchIdleRules.doneCard`.
    private(set) var finished: WatchWristFinish?
    /// The Finish that ended the session, as the wrist last sent it, until the
    /// phone answers for it. `nil` for a Discard. See `finishToResend`.
    private(set) var finishCommand: WatchCommand?

    init(sessionID: UUID? = nil) {
        self.sessionID = sessionID
    }

    init(defaults: UserDefaults) {
        sessionID = defaults.string(forKey: Self.defaultsKey).flatMap(UUID.init(uuidString:))
        let saved = defaults.data(forKey: Self.finishedKey)
            .flatMap { try? JSONDecoder().decode(WatchWristFinish.self, from: $0) }
        // Saved by a build that wrote the two keys apart, or half-written: a
        // record of another session says nothing about this one.
        finished = saved?.sessionID == sessionID ? saved : nil
        let command = defaults.data(forKey: Self.finishCommandKey)
            .flatMap { try? JSONDecoder().decode(WatchCommand.self, from: $0) }
        finishCommand = command.flatMap { Self.finishes($0, sessionID) ? $0 : nil }
    }

    func save(to defaults: UserDefaults) {
        if let sessionID {
            defaults.set(sessionID.uuidString, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        if let finished, let data = try? JSONEncoder().encode(finished) {
            defaults.set(data, forKey: Self.finishedKey)
        } else {
            defaults.removeObject(forKey: Self.finishedKey)
        }
        if let finishCommand, let data = try? JSONEncoder().encode(finishCommand) {
            defaults.set(data, forKey: Self.finishCommandKey)
        } else {
            defaults.removeObject(forKey: Self.finishCommandKey)
        }
    }

    /// - Parameters:
    ///   - finished: what a Finish with sets in it may show until the phone
    ///     answers; `nil` for a Discard, or a Finish with nothing logged.
    ///   - batch: the Finish's batch, taken at the tap; `nil` for a Discard.
    ///     Kept from here rather than from the send, which waits on Health: a
    ///     wrist app that ends during that wait never sends it at all.
    mutating func mark(_ id: UUID, finished: WatchWristFinish? = nil, finishing batch: WatchFinishBatch? = nil) {
        sessionID = id
        self.finished = finished?.sessionID == id ? finished : nil
        finishCommand = batch.flatMap { $0.sessionID == id ? .finishSession($0, metrics: nil) : nil }
    }

    /// Keeps the Finish as it went out, with the workout Health saved for it,
    /// so a resend hands that workout over too and the phone does not write
    /// its own copy. Only while the session it ends is still marked: one the
    /// phone answered for while Health saved has nothing left to resend.
    mutating func noteSent(_ command: WatchCommand) {
        guard finishCommand != nil, Self.finishes(command, sessionID) else { return }
        finishCommand = command
    }

    /// The Finish to send again, when a mirror fresh from the phone still
    /// calls the session it ended live.
    ///
    /// Sending a command once is no promise it is applied: a live message is
    /// lost with a phone app that ends before it is handled, and the wrist
    /// app can end before its Finish leaves. The phone then kept the session
    /// running and named it in every mirror, the tombstone refused every one
    /// of them, and the wrist said "Saving on your phone" for good. A fresh
    /// mirror naming the session is the phone saying it has not heard, so the
    /// Finish goes again. A repeat is safe: the phone finishes a session once,
    /// and a Finish for one it has closed or deleted only fills in what the
    /// first left out.
    ///
    /// The cached context proves nothing, as in `settle`. A Discard is never
    /// sent again: arriving late, it deleted whatever the lifter had gone on to
    /// log on the phone.
    func finishToResend(after mirror: WatchMirror, fromCache: Bool) -> WatchCommand? {
        guard !fromCache, let finishCommand, let ended = sessionID,
              mirror.session?.sessionID == ended else { return nil }
        return finishCommand
    }

    private static func finishes(_ command: WatchCommand, _ id: UUID?) -> Bool {
        guard case .finishSession(let batch, _) = command else { return false }
        return batch.sessionID == id
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
    ///
    /// The finish record goes with it. The phone sends a session's end in the
    /// same mirror as the idle screen that counts it, so from here on that idle
    /// screen is what says whether today is done.
    mutating func settle(with mirror: WatchMirror, fromCache: Bool) {
        guard !fromCache, let ended = sessionID, mirror.session?.sessionID != ended else { return }
        sessionID = nil
        finished = nil
        finishCommand = nil
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
        guard session.startedAt.timeIntervalSince(now) > -GymTrackSnapshot.Running.staleAfter else { return nil }
        guard admits(session.sessionID) else { return nil }
        return session
    }
}

/// What the wrist can vouch for about a session it finished, for the time
/// between the tap and the phone's answer.
///
/// No sets, volume or time: the wrist can have missed a set logged on the
/// phone, so its count can be lower than the phone's. Those numbers are the
/// phone's to give.
struct WatchWristFinish: Codable, Equatable, Sendable {
    var sessionID: UUID
    var title: String
    /// What files the session under a training day, as the phone files it.
    var startedAt: Date
    /// Empty for a freestyle session, which the phone does not count as the
    /// day's workout while a day of the plan is scheduled.
    var planName: String
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
