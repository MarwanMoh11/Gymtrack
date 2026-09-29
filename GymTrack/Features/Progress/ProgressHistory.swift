import Foundation
import SwiftData

/// What one finished session adds to the Progress charts, read from its sets
/// once instead of on every tap.
///
/// The values are `Metric.value(of:)` itself, so a digest counts exactly what
/// `TrainingStats` counts: every kilogram for Volume, efforts for Sets.
struct SessionDigest {
    /// The day the session is charted on, which is the key `TrainingStats.daily`
    /// buckets by.
    let day: Date
    private let values: [TrainingStats.Metric: Double]

    init(_ session: WorkoutSession, calendar: Calendar) {
        day = calendar.startOfDay(for: session.startedAt)
        values = Dictionary(uniqueKeysWithValues: TrainingStats.Metric.allCases.map { ($0, $0.value(of: session)) })
    }

    func value(_ metric: TrainingStats.Metric) -> Double { values[metric] ?? 0 }
}

/// Everything on the Progress tab that follows from the finished history
/// alone, worked out once per change to that history.
///
/// The tab used to work all of this out inside `body`. Every metric tap, every
/// window tap and the bars' opening animation walked every set ever logged
/// about seven times, on the main thread, with each read registered for
/// observation. A few hundred sessions in, tapping a pill visibly stalled. Now
/// the walks run when the history changes, and a tap only looks up and adds up
/// what they left behind.
///
/// Every figure is either the `TrainingStats` call the screen always made, or
/// a sum over `SessionDigest`s taken in the order `TrainingStats` sums in, so
/// no number on the screen moves. What counts as a session in a window, a
/// trained day or a record stays `TrainingStats`' decision.
final class ProgressHistory {
    /// The spans the screen shows. They decide how far back digests are needed.
    struct Layout {
        let windowDays: [Int]
        let calendarDays: Int
        let trendWeeks: Int

        /// Every window is compared with the window before it, so the furthest
        /// back anything on screen reaches is twice the longest window.
        var horizonDays: Int { max((windowDays.max() ?? 0) * 2, calendarDays, trendWeeks * 7) }
    }

    /// One window pill's figures, and the window before it for the deltas.
    struct WindowFigures {
        let windowed: [WorkoutSession]
        let previous: [WorkoutSession]
        let averageDuration: Double
        fileprivate let totals: [TrainingStats.Metric: Double]
        fileprivate let previousTotals: [TrainingStats.Metric: Double]

        func total(_ metric: TrainingStats.Metric) -> Double { totals[metric] ?? 0 }

        func delta(_ metric: TrainingStats.Metric) -> Double? {
            TrainingStats.change(from: previousTotals[metric] ?? 0, to: total(metric))
        }
    }

    /// Finished sessions, newest first.
    let sessions: [WorkoutSession]
    /// The trained sessions of the current calendar week, the span Today and
    /// the widgets call "this week", so the hero card cannot disagree with them.
    let lastWeek: [WorkoutSession]
    /// The last seven days, which the heat map and the weekly-target verdicts
    /// read and say they read. Over the calendar week every muscle would be
    /// "behind" on a Monday morning, a verdict about the calendar rather than
    /// the training.
    let recentWeek: [WorkoutSession]
    /// Kilograms moved over `lastWeek`. Kept here because the hero card reads
    /// it on every pass, and asking for it walked the week's sets each time.
    let lastWeekVolumeKg: Double
    let streak: TrainingStats.Streak
    let muscleSets: [Muscle: Double]
    let ratios: [Muscle: Double]
    let coverage: Double
    /// Muscles under half their weekly target, biggest target first.
    let behind: [Muscle]
    let volumeByDay: [Date: Double]
    let trainedDays: Set<Date>
    let records: [TrainingStats.PersonalRecord]
    let weeklySessionCounts: [Double]

    private let layout: Layout
    private let digests: [ObjectIdentifier: SessionDigest]
    /// Each metric summed per charted day, over every digest.
    private let dailyTotals: [TrainingStats.Metric: [Date: Double]]
    private let grids: [Int: [Date]]
    private let windows: [Int: WindowFigures]
    private let weeklyTrends: [TrainingStats.Metric: [Double]]
    /// What this was built from, so a save can be matched against it.
    private let sessionIDs: Set<PersistentIdentifier>
    private let setIDs: Set<PersistentIdentifier>
    /// Filled muscle by muscle as the heat map asks. For a muscle that was
    /// never trained, `lastTrained` reads every set in the history, and the
    /// card used to ask again on every flip of the figure.
    private var lastTrainedByMuscle: [Muscle: Date?] = [:]

    private static let customExerciseEntity = String(describing: CustomExerciseRecord.self)

    init(sessions: [WorkoutSession], layout: Layout, calendar: Calendar = .current) {
        self.sessions = sessions
        self.layout = layout

        let lastWeek = TrainingStats.sessionsThisWeek(sessions, calendar: calendar)
        self.lastWeek = lastWeek
        lastWeekVolumeKg = TrainingStats.totalVolume(lastWeek)
        streak = TrainingStats.streak(from: sessions)
        let recentWeek = TrainingStats.sessions(in: sessions, days: 7)
        self.recentWeek = recentWeek
        muscleSets = TrainingStats.setsPerMuscle(recentWeek)
        let ratios = TrainingStats.muscleRatios(recentWeek)
        self.ratios = ratios
        coverage = TrainingStats.coverage(ratios)
        behind = Muscle.allCases
            .filter { (ratios[$0] ?? 0) < 0.5 }
            .sorted { lhs, rhs in
                lhs.weeklySetTarget == rhs.weeklySetTarget
                    ? (ratios[lhs] ?? 0) < (ratios[rhs] ?? 0)
                    : lhs.weeklySetTarget > rhs.weeklySetTarget
            }
        trainedDays = TrainingStats.trainedDays(in: sessions)
        records = TrainingStats.records(in: sessions)
        weeklySessionCounts = TrainingStats.weeklySessionCounts(sessions, weeks: layout.trendWeeks)

        // Sessions older than anything on screen are never read. The extra day
        // is margin, so no calendar edge can leave a charted day half-summed.
        let today = calendar.startOfDay(for: .now)
        let horizon = calendar.date(byAdding: .day, value: -(layout.horizonDays + 1), to: today) ?? .distantPast
        var digests: [ObjectIdentifier: SessionDigest] = [:]
        var dailyTotals: [TrainingStats.Metric: [Date: Double]] = [:]
        // Summed newest first, as `daily` sums, so every bucket adds the same
        // doubles in the same order and lands on the same value to the bit.
        for session in sessions where session.startedAt >= horizon {
            let digest = SessionDigest(session, calendar: calendar)
            digests[ObjectIdentifier(session)] = digest
            for metric in TrainingStats.Metric.allCases {
                dailyTotals[metric, default: [:]][digest.day, default: 0] += digest.value(metric)
            }
        }
        self.digests = digests
        self.dailyTotals = dailyTotals

        grids = Dictionary(uniqueKeysWithValues: layout.windowDays.map { ($0, Self.grid(days: $0)) })
        volumeByDay = Dictionary(uniqueKeysWithValues:
            Self.points(.volume, on: Self.grid(days: layout.calendarDays), from: dailyTotals)
                .map { ($0.date, $0.value) })

        let trendGrid = Self.grid(days: layout.trendWeeks * 7)
        weeklyTrends = Dictionary(uniqueKeysWithValues: TrainingStats.Metric.allCases.map { metric in
            let daily = Self.points(metric, on: trendGrid, from: dailyTotals)
            return (metric, stride(from: 0, to: daily.count, by: 7).map { start in
                daily[start..<min(start + 7, daily.count)].reduce(0) { $0 + $1.value }
            })
        })

        windows = Dictionary(uniqueKeysWithValues: layout.windowDays.map { days in
            (days, Self.figures(days: days, sessions: sessions, digests: digests))
        })

        sessionIDs = Set(sessions.map(\.persistentModelID))
        setIDs = Set(sessions.flatMap { $0.sets.map(\.persistentModelID) })
    }

    func window(days: Int) -> WindowFigures {
        windows[days] ?? Self.figures(days: days, sessions: sessions, digests: digests)
    }

    /// One point per day for the last `days` days, oldest first, as
    /// `TrainingStats.daily` draws them.
    func points(_ metric: TrainingStats.Metric, days: Int) -> [TrainingStats.DayPoint] {
        guard days <= layout.horizonDays else {
            return TrainingStats.daily(metric, sessions: sessions, days: days)
        }
        return Self.points(metric, on: grids[days] ?? Self.grid(days: days), from: dailyTotals)
    }

    /// Weekly totals, oldest first: the shape behind each headline number.
    func weeklyTrend(_ metric: TrainingStats.Metric) -> [Double] { weeklyTrends[metric] ?? [] }

    func lastTrained(_ muscle: Muscle) -> Date? {
        if let known = lastTrainedByMuscle[muscle] { return known }
        let date = TrainingStats.lastTrained(muscle, in: sessions)
        lastTrainedByMuscle.updateValue(date, forKey: muscle)
        return date
    }

    /// Whether a `ModelContext.didSave` touched anything this was built from.
    ///
    /// Only the finished history counts. Logging a set saves the active
    /// session, its rows and often a plan slot, and rebuilding on those would
    /// put every history walk back on *Log set* while this tab sits under the
    /// logger. A set added to a finished session, by a late log from the watch
    /// or a restore, arrives with its session among the updated objects.
    /// Custom exercises count because their names and muscles feed the
    /// records and the heat map.
    func isAffected(by note: Notification) -> Bool {
        guard let info = note.userInfo else { return false }
        if let all = info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] as? [PersistentIdentifier],
           !all.isEmpty {
            return true
        }
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        return keys.contains { key in
            (info[key.rawValue] as? [PersistentIdentifier] ?? []).contains { id in
                sessionIDs.contains(id) || setIDs.contains(id) || id.entityName == Self.customExerciseEntity
            }
        }
    }

    /// The days `TrainingStats.daily` draws, asked of `daily` itself with no
    /// sessions, so the chart keeps `TrainingStats`' own calendar arithmetic
    /// and follows any fix made to it.
    private static func grid(days: Int) -> [Date] {
        TrainingStats.daily(.sets, sessions: [], days: days).map(\.date)
    }

    private static func points(_ metric: TrainingStats.Metric,
                               on grid: [Date],
                               from dailyTotals: [TrainingStats.Metric: [Date: Double]]) -> [TrainingStats.DayPoint] {
        let totals = dailyTotals[metric] ?? [:]
        return grid.map { TrainingStats.DayPoint(date: $0, value: totals[$0] ?? 0) }
    }

    private static func figures(days: Int,
                                sessions: [WorkoutSession],
                                digests: [ObjectIdentifier: SessionDigest]) -> WindowFigures {
        let windowed = TrainingStats.sessions(in: sessions, days: days)
        let previous = TrainingStats.previousWindow(sessions, days: days)
        return WindowFigures(
            windowed: windowed,
            previous: previous,
            averageDuration: windowed.isEmpty ? 0 : windowed.reduce(0.0) { $0 + $1.duration } / Double(windowed.count),
            totals: totals(of: windowed, digests: digests),
            previousTotals: totals(of: previous, digests: digests)
        )
    }

    /// `TrainingStats.total`, with each session's value read from its digest.
    /// A session without one is measured directly, so the total stays right
    /// even if a window ever reaches past the horizon.
    private static func totals(of sessions: [WorkoutSession],
                               digests: [ObjectIdentifier: SessionDigest]) -> [TrainingStats.Metric: Double] {
        Dictionary(uniqueKeysWithValues: TrainingStats.Metric.allCases.map { metric in
            (metric, sessions.reduce(0) { $0 + (digests[ObjectIdentifier($1)]?.value(metric) ?? metric.value(of: $1)) })
        })
    }
}

/// Keeps the last `ProgressHistory` and hands it back until what it was built
/// from changes.
///
/// It is filled in from `body`, which is why it is a plain class and not
/// `@Observable`: an observed write from inside `body` would schedule another
/// pass of the body that made it.
final class ProgressHistoryCache {
    /// What a history is rebuilt on.
    ///
    /// - The finished sessions' ids, in query order. Finishing, deleting or
    ///   restoring a session changes the list. The whole list is compared,
    ///   rather than a count, the latest `endedAt` and a hash: for a few
    ///   hundred sessions it costs about the same and cannot collide. `id` is
    ///   used and not `persistentModelID`, which changes when a new session is
    ///   first saved and would cost a second rebuild for nothing.
    /// - Today, because every window counts back from it. The first pass after
    ///   midnight rebuilds, as the screen always recomputed on its next pass.
    /// - The weight unit, because volume is summed in the unit on screen.
    /// - A revision the view bumps when a save changes the history in place: a
    ///   late set from the watch, a restore over existing sessions, a deleted
    ///   custom exercise backfilling its logged rows. None of those changes the
    ///   list of ids.
    private struct Key: Equatable {
        let sessionIDs: [UUID]
        let today: Date
        let weightUnit: WeightUnit
        let revision: Int
    }

    private let layout: ProgressHistory.Layout
    private var key: Key?
    private var current: ProgressHistory?

    init(layout: ProgressHistory.Layout) {
        self.layout = layout
    }

    func history(for allSessions: [WorkoutSession], revision: Int) -> ProgressHistory {
        let finished = allSessions.filter { !$0.isActive }
        let key = Key(sessionIDs: finished.map(\.id),
                      today: Calendar.current.startOfDay(for: .now),
                      weightUnit: AppSettings.shared.weightUnit,
                      revision: revision)
        if let current, key == self.key { return current }
        let built = ProgressHistory(sessions: finished, layout: layout)
        current = built
        self.key = key
        return built
    }

    func isAffected(by note: Notification) -> Bool {
        current?.isAffected(by: note) ?? false
    }
}
