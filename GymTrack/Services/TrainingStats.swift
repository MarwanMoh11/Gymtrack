import Foundation

/// Pure functions over finished sessions. Keeping the analysis out of the views
/// means the same numbers back the Today card, the progress screen and the
/// overload suggestions.
enum TrainingStats {

    // MARK: - Streaks

    struct Streak {
        var current: Int
        var longest: Int
    }

    /// A streak counts consecutive *calendar days* with a trained session
    /// (see `isTrained`). Today not being trained yet doesn't break the
    /// streak — the streak only dies once yesterday is also missed.
    ///
    /// Days are compared as keys from `startOfDay` and stepped with
    /// `startOfDay(_:from:calendar:)`, never by asking how many days apart two
    /// keys are. The day the clocks spring forward is 23 hours long, reads as
    /// zero days before the next one, and split every streak that ran through
    /// it.
    static func streak(from sessions: [WorkoutSession],
                       calendar: Calendar = .current,
                       now: Date = .now) -> Streak {
        let days = trainedDays(in: sessions, calendar: calendar)
        guard !days.isEmpty else { return Streak(current: 0, longest: 0) }

        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for (previous, day) in zip(sorted, sorted.dropFirst()) {
            run = startOfDay(1, from: previous, calendar: calendar) == day ? run + 1 : 1
            longest = max(longest, run)
        }

        // Walk backwards from today (or yesterday) while days are present.
        let today = calendar.startOfDay(for: now)
        var cursor = days.contains(today) ? today : startOfDay(-1, from: today, calendar: calendar)
        var current = 0
        while days.contains(cursor) {
            current += 1
            cursor = startOfDay(-1, from: cursor, calendar: calendar)
        }

        return Streak(current: current, longest: max(longest, current))
    }

    /// Whether a session counts as training: finished, with at least one set
    /// logged. Finish closed with nothing logged is a mis-tap, not a day
    /// trained, and counting it had the streak, "This week" and the session
    /// tiles go up while the calendar beside them showed a rest day.
    ///
    /// Asked with `contains` rather than `completedSets`, so a real session
    /// answers from its first set instead of faulting in every one of them.
    /// The streak asks this of the whole history on every render of Today.
    static func isTrained(_ session: WorkoutSession) -> Bool {
        !session.isActive && session.sets.contains(where: \.isCompleted)
    }

    /// The start of the calendar day `offset` days from the one holding `date`.
    ///
    /// A day doesn't always start at midnight. Where the clocks spring forward
    /// at 00:00 (Cairo on the last Friday of April, Beirut, Santiago) that day
    /// starts at 01:00, and a plain `date(byAdding: .day)` from it lands on
    /// 01:00 of the neighbouring day, whose key is 00:00. The streak stopped there, and
    /// on the day itself every daily bucket and calendar cell was built at
    /// 01:00 and matched nothing. Stepping from twelve hours in, which is
    /// inside the day however long it is, and taking the start of the day that
    /// lands on gives exactly the key `startOfDay` gives a session.
    static func startOfDay(_ offset: Int, from date: Date, calendar: Calendar) -> Date {
        let midday = calendar.startOfDay(for: date).addingTimeInterval(12 * 60 * 60)
        let stepped = calendar.date(byAdding: .day, value: offset, to: midday) ?? midday
        return calendar.startOfDay(for: stepped)
    }

    /// The latest real workout finished today — what the Today card and the
    /// Today widget show as done instead of offering the same session again. An
    /// empty session is not a day trained, so closing a freestyle session
    /// without logging anything doesn't count.
    ///
    /// The day is checked before the sets. Asked the other way round, every
    /// finished session in the history had its sets faulted in from the store,
    /// on every render of the Today tab, to answer a question only today's
    /// sessions can.
    static func finishedToday(in sessions: [WorkoutSession], calendar: Calendar = .current) -> WorkoutSession? {
        sessions
            .filter { !$0.isActive && calendar.isDateInToday($0.endedAt ?? $0.startedAt) && !$0.completedSets.isEmpty }
            .max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
    }

    /// The workout that lets the Today card say "done for today", or `nil` when
    /// today's scheduled session is still there to be offered.
    ///
    /// `finishedToday` answers "did anything finish today", and the card used
    /// that as "the day's session is done". A ten-minute freestyle arm pump
    /// then hid Leg Day behind a victory card, and so did the tail of a session
    /// that started the night before, which the week strip files under the
    /// previous day.
    ///
    /// A session counts when it started today, like every other reader buckets
    /// it, and it trained a day of the active plan. The scheduled day wins when
    /// it was trained, but a deliberate swap counts too: a lifter who did Push
    /// on Leg Day has trained today, and a card still offering Legs would ask
    /// for a second workout. What was scheduled is asked of the history before
    /// today, because a rotation moves on the moment its day is trained. With
    /// nothing scheduled at all, a rest day or no plan, whatever was trained is
    /// the day's workout.
    static func completedToday(in sessions: [WorkoutSession],
                               plan: Plan?,
                               calendar: Calendar = .current,
                               now: Date = .now) -> WorkoutSession? {
        let trainedToday = sessions.filter {
            !$0.isActive && calendar.isDate($0.startedAt, inSameDayAs: now) && isTrained($0)
        }
        guard !trainedToday.isEmpty else { return nil }

        let dayStart = calendar.startOfDay(for: now)
        let earlier = sessions.filter { $0.startedAt < dayStart }
        let latest: ([WorkoutSession]) -> WorkoutSession? = {
            $0.max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
        }
        guard let plan, let scheduled = plan.nextDay(on: now, after: earlier, calendar: calendar) else {
            return latest(trainedToday)
        }
        if let onSchedule = latest(trainedToday.filter({ $0.planDayID == scheduled.id })) {
            return onSchedule
        }
        let planDays = Set(plan.days.map(\.id))
        return latest(trainedToday.filter { $0.planDayID.map(planDays.contains) ?? false })
    }

    // MARK: - Calendar weeks

    /// The calendar week holding `date`, in the calendar's own first weekday.
    /// Today, the widgets and the watch all count from this same interval, so
    /// "this week" is one span everywhere. Progress used to count the last
    /// seven days under the same words, and on a Monday after training three
    /// times the two screens gave different numbers for the same week.
    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        if let week = calendar.dateInterval(of: .weekOfYear, for: date) { return week }
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: startOfDay(1, from: start, calendar: calendar))
    }

    /// The trained sessions of the calendar week holding `now`.
    static func sessionsThisWeek(_ sessions: [WorkoutSession],
                                 calendar: Calendar = .current,
                                 now: Date = .now) -> [WorkoutSession] {
        let week = weekInterval(containing: now, calendar: calendar)
        return sessions.filter { $0.startedAt >= week.start && $0.startedAt < week.end && isTrained($0) }
    }

    /// The first day of the consistency grid: the start of the week that opens
    /// the newest `weeks` columns, so today sits in the last one. Columns open
    /// on the calendar's first weekday. The grid was hard-coded to Sunday, which
    /// put a Monday-first or Saturday-first locale's week across two columns.
    static func gridStart(weeks: Int, calendar: Calendar, now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        return startOfDay(-offset - 7 * (max(weeks, 1) - 1), from: today, calendar: calendar)
    }

    /// The `weekdaySymbols` index of each grid row, top to bottom, so the
    /// labels beside the grid follow the day the columns open on.
    static func gridWeekdayIndices(calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
    }

    /// Whole calendar days from the day holding `earlier` to the day holding
    /// `later`.
    ///
    /// Asked of the two days' starts, `dateComponents([.day])` reads a day that
    /// starts at 01:00 as short of a full day. Where the clocks spring forward
    /// at midnight, a session on that day was "today" all through the next
    /// one. Twelve o'clock on each day exists on every day, so the count is
    /// between two readings of the same wall-clock time. The day's number in
    /// the era was tried first and dropped: on the day after a clock change it
    /// gave 23:59 and 00:01 the same number.
    static func dayCount(from earlier: Date, to later: Date, calendar: Calendar) -> Int {
        func midday(_ date: Date) -> Date {
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)
                ?? calendar.startOfDay(for: date).addingTimeInterval(12 * 60 * 60)
        }
        return calendar.dateComponents([.day], from: midday(earlier), to: midday(later)).day ?? 0
    }

    // MARK: - Body weight trend

    /// Where each weigh-in sits along the sparkline, 0 for the first and 1 for
    /// the last, in proportion to the day it was taken. Dates are oldest first.
    ///
    /// The line was spaced by position, so ten weigh-ins in one week followed
    /// by one ten weeks later drew a long wiggle and one short segment. The
    /// shape is the card's whole purpose, and that shape misstated the rate.
    /// Days are counted with `dayCount`, so a daylight-saving hour never moves
    /// a point, and two weigh-ins on one day share a position. With no time
    /// between them there is nothing to space, and every point sits centred.
    static func weighInPositions(_ dates: [Date], calendar: Calendar) -> [Double] {
        guard let first = dates.first, let last = dates.last else { return [] }
        let total = dayCount(from: first, to: last, calendar: calendar)
        guard total > 0 else { return dates.map { _ in 0.5 } }
        return dates.map { Double(dayCount(from: first, to: $0, calendar: calendar)) / Double(total) }
    }

    /// "6 weeks" or "9 days": how long the body-weight change figure spans.
    /// `nil` for a span under a day, which is no period at all. Weeks are
    /// rounded to the nearest, and the wording is the system's own, so it
    /// follows the language and the plural rules of the device.
    static func changeSpan(days: Int, locale: Locale = .current) -> String? {
        guard days > 0 else { return nil }
        let duration = Duration.seconds(days * 86_400)
        if days < 14 {
            let style = Duration.UnitsFormatStyle.units(allowed: [.days], width: .wide, maximumUnitCount: 1)
            return duration.formatted(style.locale(locale))
        }
        let style = Duration.UnitsFormatStyle.units(allowed: [.weeks], width: .wide, maximumUnitCount: 1,
                                                    fractionalPart: .hide(rounded: .toNearestOrAwayFromZero))
        return duration.formatted(style.locale(locale))
    }

    // MARK: - Volume

    /// The trained sessions of the last `days` calendar days, today included.
    static func sessions(in sessions: [WorkoutSession],
                         days: Int,
                         calendar: Calendar = .current,
                         now: Date = .now) -> [WorkoutSession] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let cutoff = startOfDay(1 - days, from: today, calendar: calendar)
        let end = startOfDay(1, from: today, calendar: calendar)
        return sessions.filter { $0.startedAt >= cutoff && $0.startedAt < end && isTrained($0) }
    }

    /// Days with a logged effort, including duration and unloaded bodyweight
    /// workouts that contribute no weight volume to the chart.
    static func trainedDays(in sessions: [WorkoutSession], calendar: Calendar = .current) -> Set<Date> {
        Set(sessions.filter(isTrained).map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Hard sets per muscle over a window. A set credits its exercise's first
    /// two muscles — direct work counts fully, the secondary at half.
    static func setsPerMuscle(_ sessions: [WorkoutSession]) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for session in sessions {
            // Efforts, not rows: a drop set is one hard set taken further. Its
            // back-off rows counted here would show as extra weekly volume the
            // lifter never added, and the heat map would warm up because they
            // stripped a plate.
            for set in session.effortSets {
                guard let exercise = ExerciseCatalog.shared.exercise(id: set.catalogID) else { continue }
                for (index, muscle) in exercise.muscles.prefix(2).enumerated() {
                    result[muscle, default: 0] += index == 0 ? 1.0 : 0.5
                }
            }
        }
        return result
    }

    static func totalVolume(_ sessions: [WorkoutSession]) -> Double {
        sessions.reduce(0) { $0 + $1.totalVolumeKg }
    }

    // MARK: - Exercise history

    struct ExerciseSessionSummary: Identifiable {
        let id: UUID
        let date: Date
        let sets: [SetLog]
        let topSet: SetLog?
        let volumeKg: Double
        let bestEstimatedOneRepMax: Double
        let totalReps: Int
    }

    /// Every session that included `catalogID`, newest first.
    static func history(for catalogID: String, in sessions: [WorkoutSession]) -> [ExerciseSessionSummary] {
        let canonicalID = ExerciseCatalog.canonicalID(for: catalogID)
        return sessions
            .filter { !$0.isActive }
            .compactMap { session -> ExerciseSessionSummary? in
                let sets = session.completedSets
                    .filter { ExerciseCatalog.canonicalID(for: $0.catalogID) == canonicalID }
                    .sorted(by: SetLog.precedesInSession)
                guard !sets.isEmpty else { return nil }
                let top = sets.max { lhs, rhs in
                    if lhs.weightKg != rhs.weightKg { return lhs.weightKg < rhs.weightKg }
                    return lhs.reps < rhs.reps
                }
                return ExerciseSessionSummary(
                    id: session.id,
                    date: session.startedAt,
                    sets: sets,
                    topSet: top,
                    volumeKg: sets.reduce(0) { $0 + $1.volumeKg },
                    // Strength estimated off the sets that stood on their own.
                    // A drop's rows are lifted pre-fatigued, as part of the set
                    // above them, so a light row taken for a lot of reps says
                    // nothing about a one-rep max — see `isPersonalRecord`,
                    // which draws the same line. The volume and the rep count
                    // above keep them, because those reps happened.
                    bestEstimatedOneRepMax: sets.filter { !$0.isContinuation }
                        .map(\.estimatedOneRepMax).max() ?? 0,
                    totalReps: sets.reduce(0) { $0 + $1.reps }
                )
            }
            .sorted { $0.date > $1.date }
    }

    /// The most recent completed sets for an exercise, used to prefill the
    /// logger, to show "last time" next to each set, and as the whole input to
    /// the progression.
    ///
    /// Only the sets that were sets. A row that continued the one above it is
    /// not a working set, and everything downstream of this reads it positionally
    /// or by weight and would read it wrong:
    ///
    /// * The "was 62.5 × 8" hints pair this session's sets against last
    ///   session's by position. One drop taken last week shifts every set under
    ///   it down a place, so set 2 would be hinted with set 1's numbers for the
    ///   rest of the exercise — and the shift moves around from session to
    ///   session, so it can't even be wrong consistently.
    /// * `suggestion` takes the heaviest weight, then the worst rep count among
    ///   the sets at it. A cluster is taken at exactly that weight for three or
    ///   four reps, which lands in that group and reads as a working set that
    ///   collapsed — the app would prescribe a deload off the back of the
    ///   lifter deliberately doing more work. That is the silent wrong answer
    ///   this filter exists to stop, and it is why the cut is made here, at the
    ///   one place the progression gets its input, rather than in each reader.
    ///
    /// What actually happened is not lost: the session itself still holds every
    /// row, and that is what the history screen and the export read.
    static func lastPerformance(of catalogID: String,
                                in sessions: [WorkoutSession],
                                excluding sessionID: UUID? = nil) -> [SetLog] {
        let canonicalID = ExerciseCatalog.canonicalID(for: catalogID)
        let candidates = sessions
            .filter { $0.id != sessionID && !$0.isActive }
            .sorted { $0.startedAt > $1.startedAt }
        for session in candidates {
            let sets = session.effortSets
                .filter { ExerciseCatalog.canonicalID(for: $0.catalogID) == canonicalID }
                .sorted(by: SetLog.precedesInSession)
            if !sets.isEmpty { return sets }
        }
        return []
    }

    // MARK: - Records

    enum RecordMeasure: Equatable {
        /// The set that holds the record, as it was lifted. `estimatedOneRepMax`
        /// is absent when the set ran past `oneRepMaxRepCap`: nothing is
        /// estimated from a set that long, so nothing is shown.
        case weight(kg: Double, reps: Int, estimatedOneRepMax: Double?)
        /// The heaviest load added to a bodyweight movement, and the reps it was
        /// done for. Unloaded reps are a different record; see `RecordKind`.
        case addedLoad(kg: Double, reps: Int)
        case reps(Int)
        case duration(seconds: Int)

        /// Distinguishes the rows one exercise can hold at once.
        var kindName: String {
            switch self {
            case .weight: "weight"
            case .addedLoad: "added"
            case .reps: "reps"
            case .duration: "duration"
            }
        }
    }

    /// One record: one set, so the load, the estimate and the date on its row
    /// can never come from different sets.
    struct PersonalRecord: Identifiable {
        let catalogID: String
        let exerciseName: String
        let measure: RecordMeasure
        let achievedAt: Date
        var id: String { "\(catalogID)|\(measure.kindName)" }
    }

    /// The most reps a one-rep-max estimate is trusted for. Epley was fitted to
    /// sets of about ten and its multiplier keeps growing linearly, so past that
    /// a long set mostly measures endurance. Uncapped, 60 kg × 30 estimated
    /// 120 kg and beat 100 kg × 5 (117 kg): the logger awarded a trophy, and the
    /// Progress card printed a set that says nothing about strength. Twelve keeps
    /// every rep range a plan is likely to ask for (the usual 5 to 12) inside
    /// the ranking and stops the formula where the advice stops.
    static let oneRepMaxRepCap = 12

    /// What a set can be a record of. Seconds, reps and kilograms cannot be put
    /// on one scale, and a weighted set never competes with an unloaded one.
    enum RecordKind: Hashable {
        case duration, reps, load
    }

    /// A set's standing among the sets of its kind, as one comparable value.
    struct RecordScore: Comparable {
        /// Seconds, reps, or the capped one-rep-max estimate.
        let value: Double
        /// Reps past `oneRepMaxRepCap`. They earn nothing on the estimate, but
        /// at the same load more reps is still progress, so they break a tie.
        let surplusReps: Int

        static func < (lhs: RecordScore, rhs: RecordScore) -> Bool {
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.surplusReps < rhs.surplusReps
        }
    }

    struct RecordStanding {
        let kind: RecordKind
        let score: RecordScore
    }

    /// Where a set stands, or nothing when it cannot be a record: no seconds,
    /// no reps, or reps with no load on a movement that is not bodyweight. The
    /// last would otherwise claim a zero-kilogram record.
    static func standing(of set: SetLog) -> RecordStanding? {
        standing(tracking: set.tracking, weightKg: set.weightKg, reps: set.reps, seconds: set.seconds)
    }

    private static func standing(tracking: TrackingMode, weightKg: Double,
                                 reps: Int, seconds: Int) -> RecordStanding? {
        if tracking == .duration {
            guard seconds > 0 else { return nil }
            return RecordStanding(kind: .duration, score: RecordScore(value: Double(seconds), surplusReps: 0))
        }
        guard reps > 0 else { return nil }
        if weightKg > 0 {
            let trusted = min(reps, oneRepMaxRepCap)
            let estimate = trusted == 1 ? weightKg : weightKg * (1 + Double(trusted) / 30.0)
            return RecordStanding(kind: .load,
                                  score: RecordScore(value: estimate, surplusReps: reps - trusted))
        }
        guard tracking == .bodyweightReps else { return nil }
        return RecordStanding(kind: .reps, score: RecordScore(value: Double(reps), surplusReps: 0))
    }

    /// One set with everything the ranking reads from it, taken once. A set is a
    /// SwiftData object, and its tracking, its load and its session each cost a
    /// lookup every time they are read; the old comparison read the session on
    /// every step of a `max`, which was most of what building the Progress tab
    /// still cost.
    private struct RecordEntry {
        let set: SetLog
        let date: Date
        let tracking: TrackingMode
        let reps: Int
        let standing: RecordStanding?
    }

    static func records(in sessions: [WorkoutSession]) -> [PersonalRecord] {
        var byExercise: [String: [RecordEntry]] = [:]
        for session in sessions where !session.isActive {
            let startedAt = session.startedAt
            // Records are set by sets, not by the rows underneath one. See
            // `isPersonalRecord` — the same line, for the same reason.
            for set in session.effortSets {
                let tracking = set.tracking
                let reps = set.reps
                let entry = RecordEntry(
                    set: set,
                    date: set.completedAt ?? startedAt,
                    tracking: tracking,
                    reps: reps,
                    standing: standing(tracking: tracking, weightKg: set.weightKg,
                                       reps: reps, seconds: set.seconds)
                )
                byExercise[ExerciseCatalog.canonicalID(for: set.catalogID), default: []].append(entry)
            }
        }

        // Seconds, reps and kilograms cannot be ranked on one numeric scale.
        // Show the most recently achieved records first, and break a shared
        // date by ID so the order does not shuffle from one refresh to the next.
        return byExercise
            .flatMap { catalogID, entries in records(for: catalogID, entries: entries) }
            .sorted { lhs, rhs in
                lhs.achievedAt != rhs.achievedAt ? lhs.achievedAt > rhs.achievedAt : lhs.id < rhs.id
            }
    }

    private static func records(for catalogID: String, entries: [RecordEntry]) -> [PersonalRecord] {
        guard let latest = entries.max(by: { $0.date < $1.date }) else { return [] }
        let matching = entries.filter { $0.tracking == latest.tracking }
        let name = ExerciseCatalog.shared.exercise(id: catalogID)?.name ?? latest.set.exerciseName

        func record(_ entry: RecordEntry?, _ measure: (RecordEntry) -> RecordMeasure) -> PersonalRecord? {
            guard let entry else { return nil }
            return PersonalRecord(catalogID: catalogID, exerciseName: name,
                                  measure: measure(entry), achievedAt: entry.date)
        }
        func ranked(_ kind: RecordKind) -> RecordEntry? {
            firstBest(of: matching) { $0.standing.flatMap { $0.kind == kind ? $0.score : nil } }
        }
        func rows(_ found: PersonalRecord?...) -> [PersonalRecord] { found.compactMap { $0 } }
        func loaded(_ entry: RecordEntry) -> RecordMeasure {
            .weight(kg: entry.set.weightKg, reps: entry.reps,
                    estimatedOneRepMax: entry.reps <= oneRepMaxRepCap ? entry.standing?.score.value : nil)
        }

        switch latest.tracking {
        case .duration:
            return rows(record(ranked(.duration)) { .duration(seconds: $0.set.seconds) })
        case .bodyweightReps:
            // Two records, two sets, two dates. Folding them into one row would
            // date the row by one and print the other's figure beside it.
            return rows(
                record(ranked(.reps)) { .reps($0.reps) },
                record(ranked(.load)) { .addedLoad(kg: $0.set.weightKg, reps: $0.reps) }
            )
        case .weightReps:
            if let best = ranked(.load) { return rows(record(best, loaded)) }
            // No load was ever entered, so the reps are all there is to rank.
            let mostReps = firstBest(of: matching) {
                $0.reps > 0 ? RecordScore(value: Double($0.reps), surplusReps: 0) : nil
            }
            return rows(record(mostReps) { .reps($0.reps) })
        }
    }

    /// The highest-scoring entry, and of equal scores the one that got there
    /// first. A record is set the day it is first reached; a later tie is the
    /// same figure, not a new record, and dating the row by it made an exercise
    /// jump to the top of the card on a day the logger awarded nothing.
    private static func firstBest(of entries: [RecordEntry],
                                  score: (RecordEntry) -> RecordScore?) -> RecordEntry? {
        var best: (entry: RecordEntry, score: RecordScore)?
        for entry in entries {
            guard let value = score(entry) else { continue }
            if let current = best {
                let ahead = value > current.score
                let firstToReachIt = value == current.score
                    && (entry.date < current.entry.date
                        || (entry.date == current.entry.date && SetLog.precedesInSession(entry.set, current.entry.set)))
                guard ahead || firstToReachIt else { continue }
            }
            best = (entry, value)
        }
        return best?.entry
    }

    /// One row per exercise and kind from the sets that set a record in a
    /// session, so a ladder of rungs that each beat the last lists once. The
    /// best is judged by the set's own kind: seconds for a hold, reps for
    /// unloaded work, the capped estimate for a load. Ranking every kind on the
    /// estimate, which is 0 for the first two, picked whichever came first.
    static func summaryRecords(from recordSets: [SetLog]) -> [SetLog] {
        struct Slot: Hashable {
            let catalogID: String
            let kind: RecordKind
        }
        var best: [Slot: (set: SetLog, score: RecordScore)] = [:]
        for set in recordSets {
            guard let standing = standing(of: set) else { continue }
            let slot = Slot(catalogID: ExerciseCatalog.canonicalID(for: set.catalogID), kind: standing.kind)
            if let current = best[slot], current.score >= standing.score { continue }
            best[slot] = (set, standing.score)
        }
        return best.values.map(\.set).sorted(by: SetLog.precedesInSession)
    }

    /// What the session summary's records depend on: which session, and how
    /// many sets it holds. Typing into the session note saves the session on
    /// every character and never moves either, so keying the summary's one
    /// computation on this keeps a keystroke from re-walking the whole history.
    struct SummaryRecordsKey: Equatable {
        let sessionID: UUID
        let completedSetCount: Int

        init(_ session: WorkoutSession) {
            sessionID = session.id
            completedSetCount = session.completedSets.count
        }
    }

    /// A set as it should be printed. Seconds for a hold, bare reps when no
    /// load was logged (it used to read "0 kg × 15", a weight nobody entered),
    /// and an added load marked as added.
    static func setLabel(_ set: SetLog) -> String {
        if set.tracking == .duration { return "\(set.seconds)s" }
        if set.weightKg == 0 { return set.reps == 1 ? "1 rep" : "\(set.reps) reps" }
        let load = set.tracking == .bodyweightReps ? "+\(set.weightLabel)" : set.weightLabel
        return "\(load) × \(set.reps)"
    }

    /// Whether `set` beats everything logged for that exercise before it.
    /// Compared on estimated 1RM so heavier-for-fewer and lighter-for-more are
    /// both recognised. Reps past `oneRepMaxRepCap` add nothing to the estimate,
    /// so a light set of thirty cannot outrank a heavy set of five; at the same
    /// load, though, the longer set still wins.
    ///
    /// The first measured set in each mode is a baseline, not a record. A
    /// weighted pull-up cannot make an unloaded rep count a load baseline, or
    /// the first unloaded set after weighted work a rep record.
    ///
    /// A row that continued the set above it can neither set a record nor stop
    /// one. It was lifted inside another set, already fatigued, off a load
    /// chosen to be survivable — twenty reps at 40 kg after eight at 62.5
    /// estimates a higher one-rep max than the 62.5 did, and it would both
    /// light up the trophy on a back-off row and raise the bar every real set
    /// after it has to clear. Both directions are the same mistake: comparing
    /// a piece of a set against whole ones.
    static func isPersonalRecord(_ set: SetLog, in sessions: [WorkoutSession]) -> Bool {
        isPersonalRecord(set, among: sessions.flatMap(\.sets))
    }

    /// The same question, asked of sets already gathered — see
    /// `recordCandidates`. Anything in the list that isn't the same exercise,
    /// isn't a whole logged set or wasn't logged before this one is ignored, so
    /// the two forms can't disagree.
    static func isPersonalRecord(_ set: SetLog, among candidates: [SetLog]) -> Bool {
        guard set.isCompleted, !set.isContinuation, let mine = standing(of: set) else { return false }

        // Only sets of the same kind count. The first measured set in a kind is
        // a baseline, so with nothing to beat there is nothing to break.
        let best = earlierSets(than: set, in: candidates)
            .compactMap { other in standing(of: other).flatMap { $0.kind == mine.kind ? $0.score : nil } }
            .max()
        guard let best else { return false }
        return mine.score > best
    }

    private static func earlierSets(than set: SetLog, in candidates: [SetLog]) -> [SetLog] {
        let boundary = set.completedAt ?? .now
        let catalogID = ExerciseCatalog.canonicalID(for: set.catalogID)
        return candidates.filter {
            ExerciseCatalog.canonicalID(for: $0.catalogID) == catalogID
            && $0.tracking == set.tracking
            && $0.isCompleted
            && !$0.isContinuation
            && $0.id != set.id
            && (($0.completedAt ?? .distantPast) < boundary)
        }
    }

    /// Every set a record could be measured against, by exercise: one walk
    /// through the history, for callers that ask the record question often.
    ///
    /// The logger asks it on every *Log set* and the summary asks it of every
    /// set in the session, and both used to answer it by reading every set in
    /// the whole history each time — on the tap that most needs to feel
    /// instant, and on each redraw of the screen that pays it off.
    static func recordCandidates(in sessions: [WorkoutSession]) -> [String: [SetLog]] {
        var index: [String: [SetLog]] = [:]
        for session in sessions {
            for set in session.sets where set.isCompleted && !set.isContinuation {
                index[ExerciseCatalog.canonicalID(for: set.catalogID), default: []].append(set)
            }
        }
        return index
    }

    /// The sets in one session that set a record, answered with a single walk
    /// through the history rather than one per set.
    static func recordSets(in session: WorkoutSession, history: [WorkoutSession]) -> [SetLog] {
        let earlier = recordCandidates(in: history.filter { $0.id != session.id })
        let today = Dictionary(grouping: session.sets) { ExerciseCatalog.canonicalID(for: $0.catalogID) }
        return session.completedSets.filter { set in
            let catalogID = ExerciseCatalog.canonicalID(for: set.catalogID)
            return isPersonalRecord(set, among: (earlier[catalogID] ?? []) + (today[catalogID] ?? []))
        }
    }

    // MARK: - Progressive overload

    struct OverloadSuggestion {
        enum Action { case increaseWeight, addReps, repeatLoad, deload, firstTime }
        let action: Action
        let weightKg: Double
        let reps: Int
        let message: String
    }

    /// The effort behind a group of sets, when the lifter recorded it.
    ///
    /// Median rather than mean: one brutal last set shouldn't recolour a whole
    /// exercise, and sets left unrated shouldn't dilute the ones that were.
    static func medianRPE(of sets: [SetLog]) -> Double? {
        let values = sets.compactMap(\.rpe).sorted()
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }

    /// The same thing in the word the lifter actually answered with, which is
    /// what the suggestions are written in.
    static func feel(of sets: [SetLog]) -> SetFeel? {
        medianRPE(of: sets).map(SetFeel.nearest(to:))
    }

    /// `LoadScale.step` moves exactly one rung however big the direction is, so
    /// climbing two means asking twice — and asking twice is also the only way
    /// to land on rungs the machine has when they aren't evenly spaced.
    private static func climb(_ scale: LoadScale, from kg: Double, rungs: Int) -> Double {
        (0..<max(1, rungs)).reduce(kg) { weight, _ in scale.step(kg: weight, by: 1) }
    }

    /// Double progression: work up the rep range at a fixed load, then add
    /// weight and drop back to the bottom of the range.
    static func suggestion(for item: PlanItem, lastSets: [SetLog]) -> OverloadSuggestion {
        // Every weight this returns has to be one the equipment can actually be
        // set to, so the progression is read off the exercise's own ladder.
        let scale = item.loadScale
        let increment = scale.incrementKg

        guard !lastSets.isEmpty else {
            return OverloadSuggestion(
                action: .firstTime,
                weightKg: item.targetWeightKg,
                reps: item.targetRepsLow,
                message: "First time logging this — set a baseline you can repeat."
            )
        }

        // What was actually lifted — used to find the sets that count, so it has
        // to match the stored numbers exactly.
        let lastWeight = lastSets.map(\.weightKg).max() ?? item.targetWeightKg
        let setsAtWeight = lastSets.filter { $0.weightKg == lastWeight }
        let allHitTop = !setsAtWeight.isEmpty && setsAtWeight.allSatisfy { $0.reps >= item.targetRepsHigh }
        let minReps = setsAtWeight.map(\.reps).min() ?? 0

        // What today is prescribed from: the same load, pulled onto the ladder
        // this machine has. Otherwise the card names 60.5 kg while the logger
        // opens on the 60 the stack can actually do.
        let workingWeight = scale.snap(kg: lastWeight)

        if item.tracking == .duration {
            let best = lastSets.map(\.seconds).max() ?? item.targetSeconds
            return OverloadSuggestion(
                action: .addReps, weightKg: 0, reps: 0,
                message: "Last time you held \(best)s. Aim for \(best + 5)s."
            )
        }

        // Unloaded work has no weight to add — the progression is reps, then
        // eventually a belt or a vest. Zero is read as no load in every mode,
        // not only bodyweight: a dip logged as weight × reps before the library
        // called it bodyweight keeps that mode on its row, and climbing a rung
        // from zero would prescribe a 1.25 kg dip nobody ever did.
        let isUnloaded = lastWeight == 0

        // A reps exercise with no range has no top to clear. Read as a range,
        // 0–0 is met by every set, and the progression would add weight every
        // session while resetting the reps to nothing.
        guard item.targetRepsHigh > 0 else {
            let load = isUnloaded ? "the same work" : scale.format(workingWeight)
            return OverloadSuggestion(
                action: .repeatLoad, weightKg: workingWeight, reps: minReps,
                message: "This slot has no rep range to progress through. Repeat \(load), or give it a range in the plan."
            )
        }

        // Only a session that did the prescribed work at its load says the load
        // is beaten. One set at the top of the range and then an early finish,
        // or a light technique set of the same lift, would otherwise read as a
        // whole session cleared and move the load on the strength of it.
        let prescribedSets = max(1, item.targetSets)
        guard setsAtWeight.count >= prescribedSets else {
            let done = setsAtWeight.count == 1
                ? "Only 1 of \(prescribedSets) sets was"
                : "Only \(setsAtWeight.count) of \(prescribedSets) sets were"
            let message = isUnloaded
                ? "\(done) done last time. Repeat it and finish every set before pushing past the range."
                : "\(done) done at \(scale.format(workingWeight)) last time. Stay there and finish every set before adding weight."
            return OverloadSuggestion(action: .repeatLoad, weightKg: workingWeight,
                                      reps: item.targetRepsLow, message: message)
        }

        // How hard it actually was, when the lifter said so. Reps alone can't
        // tell a set that had three left in the tank from one that had none,
        // which is why plain double progression climbs at the same rung a
        // session either way.
        //
        // Each of the four answers changes something here. An answer that led
        // to the same advice as every other answer would be a question not
        // worth asking.
        let feel = feel(of: setsAtWeight)

        if allHitTop {
            if isUnloaded {
                if feel == .easy {
                    return OverloadSuggestion(
                        action: .addReps, weightKg: 0, reps: item.targetRepsHigh + 3,
                        message: "You cleared \(item.targetRepsHigh) reps and it felt easy — that's not close to failure. Push well past it, or start adding weight."
                    )
                }
                return OverloadSuggestion(
                    action: .addReps, weightKg: 0, reps: item.targetRepsHigh + 1,
                    message: "You cleared \(item.targetRepsHigh) reps on every set. Push past it, or start adding weight."
                )
            }
            // Two rungs when there was clearly room left. One stays the default,
            // and stays it for every exercise that has never been rated.
            let rungs = feel == .easy ? 2 : 1
            let next = climb(scale, from: workingWeight, rungs: rungs)
            let cleared = "You cleared \(item.targetRepsHigh) reps on every set"
            let message: String
            switch feel {
            case .easy:
                message = "\(cleared) and it felt easy — there's room. Jump two steps to \(scale.format(next)) and reset to \(item.targetRepsLow) reps."
            case .hard:
                message = "\(cleared), and it was hard. Go to \(scale.format(next)) and expect a fight for the bottom of the range."
            case .allOut:
                message = "\(cleared) with nothing left. Go to \(scale.format(next)), but expect to sit at \(item.targetRepsLow) reps for a few sessions."
            case .solid, nil:
                message = "\(cleared). Go to \(scale.format(next)) and reset to \(item.targetRepsLow) reps."
            }
            return OverloadSuggestion(action: .increaseWeight, weightKg: next,
                                      reps: item.targetRepsLow, message: message)
        }

        if minReps < item.targetRepsLow - 2 && workingWeight > increment && !isUnloaded {
            // Falling short of the range is only a reason to take weight off if
            // the weight is what stopped you. Short reps that felt easy is a set
            // that was ended early, and deloading it would fix the wrong thing.
            switch feel {
            case .easy:
                return OverloadSuggestion(
                    action: .repeatLoad, weightKg: workingWeight, reps: item.targetRepsLow,
                    message: "Reps fell short, but you called it easy — the load isn't what stopped you. Stay at \(scale.format(workingWeight)) and take it closer to failure."
                )
            case .solid:
                return OverloadSuggestion(
                    action: .repeatLoad, weightKg: workingWeight, reps: item.targetRepsLow,
                    message: "Reps fell short at a solid effort — there was still something in the tank. Stay at \(scale.format(workingWeight)) and get the range before touching the weight."
                )
            case .hard, .allOut, nil:
                let backOff = scale.step(kg: workingWeight, by: -1)
                return OverloadSuggestion(
                    action: .deload, weightKg: backOff, reps: item.targetRepsLow,
                    message: "Reps fell below the range last time. Back off to \(scale.format(backOff)) and rebuild."
                )
            }
        }

        let goal = min(item.targetRepsHigh, minReps + 1)
        let message: String
        if isUnloaded {
            message = "Chase \(goal) reps on every set."
        } else {
            switch feel {
            case .easy:
                // Inside the range and it still felt easy: the sets are being
                // ended before they get hard, not stopped by the load.
                message = "It felt easy and still stopped short of \(item.targetRepsHigh). Stay at \(scale.format(workingWeight)) and take every set to at least \(goal)."
            case .allOut:
                // Already at the limit inside the range: another rep is the
                // goal, but repeating the session honestly is how it's earned.
                message = "Stay at \(scale.format(workingWeight)) — last time took everything you had. Repeat it before you chase \(goal)."
            case .hard:
                message = "Stay at \(scale.format(workingWeight)) and chase \(goal). Last time was hard, so that rep has to be earned."
            case .solid, nil:
                message = "Stay at \(scale.format(workingWeight)) and chase \(goal) reps on every set."
            }
        }
        return OverloadSuggestion(action: .addReps, weightKg: workingWeight, reps: goal, message: message)
    }

    /// Smallest jump that's actually loadable for the equipment in question,
    /// in kilograms. Now a question for `LoadScaleBook` — it knows both what the
    /// equipment implies and what the user has corrected it to.
    static func weightIncrement(for item: PlanItem) -> Double { item.loadScale.incrementKg }
}

// MARK: - Progress screen metrics

extension TrainingStats {

    /// What the volume chart is plotting. Volume is the headline number, but a
    /// week of heavy triples and a week of high-rep hypertrophy look nothing
    /// alike, so sets and reps are one tap away.
    enum Metric: String, CaseIterable, Identifiable {
        case volume = "Volume"
        case sets = "Sets"
        case reps = "Reps"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .volume: "scalemass.fill"
            case .sets: "square.stack.3d.up.fill"
            case .reps: "arrow.trianglehead.2.clockwise"
            }
        }

        /// Unit shown next to the axis and the headline.
        var unit: String {
            switch self {
            case .volume: AppSettings.shared.weightUnit.short
            case .sets: "sets"
            case .reps: "reps"
            }
        }

        func value(of session: WorkoutSession) -> Double {
            switch self {
            // Volume counts every kilogram moved; sets count efforts. A drop
            // set adds to the first and not the second, which is exactly the
            // difference the two charts exist to show.
            case .volume: AppSettings.shared.weightUnit.fromKg(session.totalVolumeKg)
            case .sets: Double(session.effortSets.count)
            case .reps: Double(session.totalReps)
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .volume: value.compactVolume
            case .sets, .reps: String(format: "%.0f", value)
            }
        }
    }

    struct DayPoint: Identifiable, Equatable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// One point per calendar day, oldest first, including the empty days —
    /// gaps are the most useful thing on a consistency chart.
    static func daily(_ metric: Metric,
                      sessions: [WorkoutSession],
                      days: Int,
                      calendar: Calendar = .current,
                      now: Date = .now) -> [DayPoint] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: Double] = [:]
        for session in sessions where !session.isActive {
            buckets[calendar.startOfDay(for: session.startedAt), default: 0] += metric.value(of: session)
        }
        return (0..<max(days, 0)).reversed().map { offset in
            let date = startOfDay(-offset, from: today, calendar: calendar)
            return DayPoint(date: date, value: buckets[date] ?? 0)
        }
    }

    /// Trailing mean, which is what turns a spiky bar chart into a trend.
    static func rollingAverage(_ points: [DayPoint], window: Int) -> [DayPoint] {
        points.enumerated().map { index, point in
            let start = max(0, index - window + 1)
            let slice = points[start...index]
            return DayPoint(date: point.date,
                            value: slice.reduce(0) { $0 + $1.value } / Double(slice.count))
        }
    }

    /// The window immediately before the current one, for like-for-like deltas.
    static func previousWindow(_ sessions: [WorkoutSession],
                               days: Int,
                               calendar: Calendar = .current,
                               now: Date = .now) -> [WorkoutSession] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let start = startOfDay(1 - days * 2, from: today, calendar: calendar)
        let end = startOfDay(1 - days, from: today, calendar: calendar)
        return sessions.filter { $0.startedAt >= start && $0.startedAt < end && isTrained($0) }
    }

    /// Percentage change, or nil when there is no baseline to compare against.
    static func change(from previous: Double, to current: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous
    }

    static func total(_ metric: Metric, _ sessions: [WorkoutSession]) -> Double {
        sessions.reduce(0) { $0 + metric.value(of: $1) }
    }

    /// Seven-calendar-day buckets, oldest first, with today in the newest one.
    static func weeklySessionCounts(_ sessions: [WorkoutSession],
                                    weeks: Int = 8,
                                    calendar: Calendar = .current,
                                    now: Date = .now) -> [Double] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(weeks, 0)).reversed().map { offset in
            let end = startOfDay(1 - 7 * offset, from: today, calendar: calendar)
            let start = startOfDay(-7, from: end, calendar: calendar)
            return Double(sessions.filter { $0.startedAt >= start && $0.startedAt < end && isTrained($0) }.count)
        }
    }

    // MARK: Muscles

    /// Sets ÷ weekly target for every muscle — the number the heat map shades.
    static func muscleRatios(_ sessions: [WorkoutSession]) -> [Muscle: Double] {
        let sets = setsPerMuscle(sessions)
        return Dictionary(uniqueKeysWithValues: Muscle.allCases.map {
            ($0, (sets[$0] ?? 0) / Double($0.weeklySetTarget))
        })
    }

    /// Share of the weekly plan actually covered, counting no credit for
    /// exceeding a target — hammering chest doesn't cover your legs.
    static func coverage(_ ratios: [Muscle: Double]) -> Double {
        let capped = Muscle.allCases.map { min(ratios[$0] ?? 0, 1) }
        return capped.reduce(0, +) / Double(capped.count)
    }

    /// Average completion for a region, again capped per muscle.
    static func coverage(of region: Muscle.Region, ratios: [Muscle: Double]) -> Double {
        let muscles = Muscle.allCases.filter { $0.region == region }
        guard !muscles.isEmpty else { return 0 }
        return muscles.reduce(0.0) { $0 + min(ratios[$1] ?? 0, 1) } / Double(muscles.count)
    }

    /// Newest first, stopping at the first session that hit it. The answer is
    /// nearly always in the last week or two, and reading every set of every
    /// session ever logged to find it made each tap on the heat map slower
    /// the longer somebody had used the app.
    static func lastTrained(_ muscle: Muscle, in sessions: [WorkoutSession]) -> Date? {
        sessions
            .sorted { $0.startedAt > $1.startedAt }
            .first { session in
                session.completedSets.contains { set in
                    guard let exercise = ExerciseCatalog.shared.exercise(id: set.catalogID) else { return false }
                    return exercise.muscles.prefix(2).contains(muscle)
                }
            }?
            .startedAt
    }

    /// Which movements are actually feeding a muscle, heaviest contributor
    /// first — the answer to "why is this still cold?".
    static func topExercises(for muscle: Muscle,
                             in sessions: [WorkoutSession],
                             limit: Int = 3) -> [(name: String, sets: Double)] {
        var tally: [String: Double] = [:]
        for session in sessions {
            // Counted the same way `setsPerMuscle` counts, since this is the
            // breakdown of that number — otherwise the parts wouldn't add up
            // to the whole they're explaining.
            for set in session.effortSets {
                guard let exercise = ExerciseCatalog.shared.exercise(id: set.catalogID) else { continue }
                for (index, candidate) in exercise.muscles.prefix(2).enumerated() where candidate == muscle {
                    tally[set.exerciseName, default: 0] += index == 0 ? 1.0 : 0.5
                }
            }
        }
        return tally
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, sets: $0.value) }
    }
}
