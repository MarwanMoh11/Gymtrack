import Foundation

/// The channel between the app and the two things that run outside it: the
/// widgets, and the intents Siri, Spotlight and the Action Button fire.
///
/// Deliberately a small snapshot rather than a shared database. Moving the
/// SwiftData store into the group container would strand the history already on
/// the device, and a widget only ever needs a dozen numbers — so the app
/// restamps those numbers whenever they change, and nothing outside the app
/// writes here except to leave a pending action behind.
///
/// Every call is safe when the App Group isn't provisioned: a free Apple ID
/// can't have one, and in that case the writes simply land somewhere the widget
/// can't read. The app keeps working and the widgets show their placeholder,
/// which is the right failure for a capability the user may not be able to buy.
enum SharedStore {

    static let appGroup = "group.com.marwanmohamed.gymtrack"

    private static let snapshotKey = "gymtrack.snapshot"
    private static let actionKey = "gymtrack.pendingAction"
    private static let actionStampKey = "gymtrack.pendingActionAt"

    /// An action left behind by something outside the app, for the app to pick
    /// up the moment it comes to the front.
    enum PendingAction: String, Codable, Sendable {
        case startToday, startFreestyle, openSession
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    // MARK: - Snapshot

    static func write(_ snapshot: GymTrackSnapshot) {
        guard let data = try? JSONEncoder.shared.encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func readSnapshot() -> GymTrackSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder.shared.decode(GymTrackSnapshot.self, from: data)
    }

    // MARK: - Pending actions

    static func request(_ action: PendingAction) {
        defaults?.set(action.rawValue, forKey: actionKey)
        defaults?.set(Date.now.timeIntervalSince1970, forKey: actionStampKey)
    }

    /// Takes the action and clears it, so a workout is never started twice by
    /// one tap. Anything older than two minutes is dropped rather than replayed:
    /// a request that failed to reach the app when it was made is a request the
    /// user has long since given up on.
    static func takeAction() -> PendingAction? {
        guard let defaults,
              let raw = defaults.string(forKey: actionKey),
              let action = PendingAction(rawValue: raw)
        else { return nil }

        defaults.removeObject(forKey: actionKey)
        let stamp = defaults.double(forKey: actionStampKey)
        defaults.removeObject(forKey: actionStampKey)

        guard Date.now.timeIntervalSince1970 - stamp < 120 else { return nil }
        return action
    }
}

// MARK: - Widget kinds

/// The `kind` each widget is registered under, which the app names when it asks
/// WidgetKit to reload just that one. Kept here so the widget declaring a kind
/// and the app reloading it can't drift apart into a reload that silently
/// matches nothing.
enum GymTrackWidgetKind {
    static let today = "GymTrackToday"
    static let streak = "GymTrackStreak"

    static let all: Set<String> = [today, streak]
}

// MARK: - What a widget draws

/// Everything the widgets know. Flat and small on purpose — it is rewritten on
/// every logged set while a session is running.
struct GymTrackSnapshot: Codable, Hashable, Sendable {

    /// A session in progress, as a widget sees it.
    struct Running: Codable, Hashable, Sendable {
        var title: String
        var startedAt: Date
        var completedSets: Int
        var totalSets: Int
        var exercise: String
        var target: String
        var restEndsAt: Date?

        init(title: String, startedAt: Date, completedSets: Int, totalSets: Int,
                    exercise: String, target: String, restEndsAt: Date?) {
            self.title = title
            self.startedAt = startedAt
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.exercise = exercise
            self.target = target
            self.restEndsAt = restEndsAt
        }

        var progress: Double {
            totalSets > 0 ? min(1, Double(completedSets) / Double(totalSets)) : 0
        }

        /// How long a session can stay open before the app treats it as
        /// abandoned and closes it. The one definition: `WorkoutSession.staleAfter`
        /// reads this, because the widgets can't see the model and the two must
        /// never differ.
        static let staleAfter: TimeInterval = 12 * 3600

        /// Whether the app would close this session by `moment`. Nothing wakes
        /// the app to say so when the lifter simply walked out of the gym, so
        /// a widget has to reach the same verdict from the clock, or it shows a
        /// workout running until somebody next opens the app.
        func isStale(at moment: Date) -> Bool {
            moment.timeIntervalSince(startedAt) > Self.staleAfter
        }

        /// A moment `isStale` is true at, the first whole second after it turns,
        /// which is what the timeline needs an entry for. `isStale` is strict,
        /// so the turn itself would still read as running.
        var staleAt: Date { startedAt.addingTimeInterval(Self.staleAfter + 1) }

        /// A stand-in carrying nothing but "a session is running", for
        /// comparing what a widget that draws no session detail can see.
        fileprivate static let presence = Running(title: "", startedAt: .distantPast, completedSets: 0,
                                                  totalSets: 0, exercise: "", target: "", restEndsAt: nil)
    }

    /// One weekday of the routine, as much of it as a widget draws.
    struct ScheduledDay: Codable, Hashable, Sendable {
        /// 1 = Sunday … 7 = Saturday, the way `PlanDay.weekday` counts.
        var weekday: Int
        var title: String
        var exerciseCount: Int
        var setCount: Int
        var muscles: [String]
        /// Whether this weekday carries the rotation's next day rather than a
        /// day pinned to it — see `GymTrackSnapshot.todayIsRotation`. Optional
        /// so a snapshot from an older build still decodes, as "Today".
        var isRotation: Bool? = nil
    }

    /// The workout already finished today, if there was one with anything in
    /// it — the thing the phone's Today card shows instead of offering the same
    /// session again.
    struct Finished: Codable, Hashable, Sendable {
        var title: String
        var sets: Int
        var volumeKg: Double
        var endedAt: Date
    }

    var updatedAt: Date
    /// Midnight of the training day everything "today" below was worked out
    /// for; see `TrainingDay`.
    ///
    /// The app only restamps the snapshot when it runs, and nothing wakes it at
    /// midnight — so a widget reloading at 00:01 used to read back exactly what
    /// it had at 23:59 and go on offering yesterday's session as today's, next
    /// to a streak that had already lapsed. With the day stamped, and the week
    /// the routine repeats on carried alongside, the widget can re-read the
    /// snapshot as of any later moment itself — see `asOf`. The watch's idle
    /// mirror solved the same problem the same way.
    ///
    /// Optional only so a snapshot written by an older build still decodes; one
    /// without a day is taken at its word.
    var day: Date?
    /// What each training weekday of the routine prescribes. Empty with no
    /// routine; absent on a snapshot from an older build.
    var schedule: [ScheduledDay]?
    /// The last training day a session was finished on, which is all it takes
    /// to tell whether the streak below has survived to a later day.
    var lastTrainedDay: Date?
    /// The start of the week `sessionsThisWeek` and `weekVolumeKg` count.
    var weekStart: Date?
    var finishedToday: Finished?
    /// Whether there's an active routine at all, which is what separates "rest
    /// day" from "nothing set up yet".
    var hasPlan: Bool
    /// Today's scheduled session. `nil` on a rest day, and with no plan.
    var todayTitle: String?
    /// Whether today's session is the plan's next in turn rather than the one
    /// pinned to this weekday, which the widgets then call "Next up".
    ///
    /// "Today" on a rotation day states a schedule the plan never set, and the
    /// phone's Today card already stopped saying it. Optional so a snapshot
    /// written by an older build still decodes, and reads as "Today" as before.
    var todayIsRotation: Bool?
    var todayExerciseCount: Int
    var todaySetCount: Int
    var todayMuscles: [String]
    var streak: Int
    var sessionsThisWeek: Int
    var weekVolumeKg: Double
    var unit: WeightUnit
    var session: Running?

    init(updatedAt: Date = .now,
                day: Date? = nil,
                schedule: [ScheduledDay]? = nil,
                lastTrainedDay: Date? = nil,
                weekStart: Date? = nil,
                finishedToday: Finished? = nil,
                hasPlan: Bool = false,
                todayTitle: String? = nil,
                todayExerciseCount: Int = 0,
                todaySetCount: Int = 0,
                todayMuscles: [String] = [],
                streak: Int = 0,
                sessionsThisWeek: Int = 0,
                weekVolumeKg: Double = 0,
                unit: WeightUnit = .kg,
                session: Running? = nil,
                todayIsRotation: Bool? = nil) {
        self.updatedAt = updatedAt
        self.day = day
        self.schedule = schedule
        self.lastTrainedDay = lastTrainedDay
        self.weekStart = weekStart
        self.finishedToday = finishedToday
        self.hasPlan = hasPlan
        self.todayTitle = todayTitle
        self.todayIsRotation = todayIsRotation
        self.todayExerciseCount = todayExerciseCount
        self.todaySetCount = todaySetCount
        self.todayMuscles = todayMuscles
        self.streak = streak
        self.sessionsThisWeek = sessionsThisWeek
        self.weekVolumeKg = weekVolumeKg
        self.unit = unit
        self.session = session
    }

    /// Today is a training day with something prescribed on it.
    var hasSessionToday: Bool { todayTitle != nil }

    /// The same snapshot, read as of a later moment.
    ///
    /// Everything that answers "today" or "this week" is worked out again for
    /// that moment from what was stamped: the weekday's session off the
    /// routine, the streak kept only while the last trained day is still today
    /// or yesterday — which is exactly when `TrainingStats.streak` keeps one —
    /// and the week's count and volume zeroed once a new week has begun.
    /// Anything that isn't about the day is left exactly as the app wrote it,
    /// including a session still running past midnight — but only until the
    /// app itself would have closed it as abandoned; see `Running.isStale`.
    /// That is asked before the day is, because a session left open goes stale
    /// at any hour of the day it started on as well as the next.
    func asOf(_ date: Date, calendar: Calendar = .current) -> GymTrackSnapshot {
        var next = self
        if let session, session.isStale(at: date) { next.session = nil }
        // The day turns over at the cutoff, as the app's does, so a widget at
        // 00:30 still describes the night it is part of. See `TrainingDay`.
        let trainingDay = TrainingDay.key(for: date, calendar: calendar)
        guard let day, trainingDay > day, !calendar.isDate(day, inSameDayAs: trainingDay) else { return next }
        next.day = trainingDay
        next.finishedToday = nil

        if let schedule {
            let weekday = calendar.component(.weekday, from: trainingDay)
            let today = schedule.first { $0.weekday == weekday }
            next.todayTitle = today?.title
            next.todayIsRotation = today?.isRotation
            next.todayExerciseCount = today?.exerciseCount ?? 0
            next.todaySetCount = today?.setCount ?? 0
            next.todayMuscles = today?.muscles ?? []
        }

        if (lastTrainedDay ?? .distantPast) < Self.startOfDay(before: trainingDay, calendar: calendar) {
            next.streak = 0
        }

        if let weekStart, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: trainingDay)?.start,
           thisWeek > weekStart {
            next.sessionsThisWeek = 0
            next.weekVolumeKg = 0
            next.weekStart = thisWeek
        }
        return next
    }

    /// The start of the day before the one holding `date`, as the phone keys
    /// `lastTrainedDay`.
    ///
    /// A day doesn't always start at midnight: where the clocks spring forward
    /// at 00:00, as Cairo's do in late April, that day starts at 01:00. A plain
    /// day subtracted from 01:00 lands on 01:00 the day before, an hour after
    /// the phone's key for it, and a streak trained yesterday read as lapsed
    /// all through the day the clocks changed. Stepped from midday, which is
    /// inside the day however long it is, exactly as
    /// `TrainingStats.startOfDay(_:from:calendar:)` does; that one isn't
    /// compiled into the widgets, so the rule is repeated here.
    private static func startOfDay(before date: Date, calendar: Calendar) -> Date {
        let midday = calendar.startOfDay(for: date).addingTimeInterval(12 * 60 * 60)
        let stepped = calendar.date(byAdding: .day, value: -1, to: midday) ?? midday
        return calendar.startOfDay(for: stepped)
    }

    /// Which widget kinds have something new to draw once this snapshot
    /// replaces `old`; empty when nothing a widget draws has moved.
    ///
    /// WidgetKit gives an app a small daily budget of reloads, and a session
    /// logged from the wrist with the phone locked spends it a set at a time.
    /// Most of those changes are about the running session, which only the
    /// Today widget draws in any detail: the Streak widget says "Session
    /// running" and nothing finer. So a change confined to the session's
    /// numbers reloads Today alone, and one that changes nothing reloads
    /// nothing.
    ///
    /// Compared as encoded, to the millisecond, not as values: a snapshot read
    /// back from the store has been through the wire format and can differ from
    /// the one it was written from by less than a widget could draw. Comparing
    /// values made a process with no memory of what it last wrote — every
    /// background wake — reload for nothing. `updatedAt` is held level: it
    /// moves on every write by definition.
    func widgetKindsToReload(replacing old: GymTrackSnapshot?) -> Set<String> {
        guard let old,
              let before = old.comparableForm(sessionDetail: true),
              let after = comparableForm(sessionDetail: true)
        else { return GymTrackWidgetKind.all }
        if before == after { return [] }

        var kinds: Set<String> = [GymTrackWidgetKind.today]
        if old.comparableForm(sessionDetail: false) != comparableForm(sessionDetail: false) {
            kinds.insert(GymTrackWidgetKind.streak)
        }
        return kinds
    }

    /// The wire form with `updatedAt` fixed, and with the running session
    /// reduced to whether there is one when the caller only needs that.
    private func comparableForm(sessionDetail: Bool) -> Data? {
        var copy = self
        copy.updatedAt = Date(timeIntervalSince1970: 0)
        if !sessionDetail { copy.session = copy.session.map { _ in Running.presence } }
        return try? JSONEncoder.comparing.encode(copy)
    }

    /// What the widget gallery shows, and what a widget falls back to before
    /// the app has ever written a snapshot.
    static let placeholder = GymTrackSnapshot(
        hasPlan: true,
        todayTitle: "Push Day",
        todayExerciseCount: 5,
        todaySetCount: 18,
        todayMuscles: ["Chest", "Shoulders", "Triceps"],
        streak: 4,
        sessionsThisWeek: 3,
        weekVolumeKg: 14_800
    )
}

// MARK: - Wire format

private extension JSONEncoder {
    static let shared: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()
}

private extension JSONEncoder {
    /// For comparing two snapshots rather than storing one: keys in a fixed
    /// order, which `shared` leaves to chance, and dates rounded to the whole
    /// millisecond. The wire format keeps the fraction of a millisecond, and a
    /// date that has been through it and back can come out a hair off, so
    /// either would read as a change no widget could draw.
    static let comparing: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode((date.timeIntervalSince1970 * 1000).rounded())
        }
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}

private extension JSONDecoder {
    static let shared: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
