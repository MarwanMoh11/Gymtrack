import Foundation
import Observation
import SwiftData

/// Run with scripts/test-progress-history.sh; no simulator is needed.
///
/// Proves that the Progress tab's cached figures are the numbers it always
/// drew, that a metric or window tap no longer reads a single set, and that
/// the cache rebuilds on the saves that change the finished history and on
/// nothing a workout in progress writes. Prints a crude timing comparison.
@main
struct ProgressHistoryTests {
    static let layout = ProgressHistory.Layout(windowDays: [7, 30, 90], calendarDays: 17 * 7, trendWeeks: 8)

    @MainActor static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let active = HistoryGenerator.generate(into: context, sessions: 300, setsEach: 25)
        try context.save()

        let all = try context.fetch(FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        let finished = all.filter { !$0.isActive }
        let setCount = finished.reduce(0) { $0 + $1.sets.count }
        print("History: \(finished.count) finished sessions, \(setCount) sets, one active session")

        for unit in [WeightUnit.kg, .lb] {
            AppSettings.shared.weightUnit = unit
            checkMatchesDirect(all, finished: finished)
        }
        AppSettings.shared.weightUnit = .kg
        print("Cached figures equal the direct computation for every window, metric and unit")

        checkTapsReadNoSets(all, finished: finished)
        print("A metric or window tap reads no set; the old per-pass computation read them all")

        try checkInvalidation(context, all: all, finished: finished, active: active)
        print("Saves to the finished history invalidate the cache; saves from a workout in progress do not")

        timing(all)
    }

    // MARK: - Same numbers

    @MainActor static func checkMatchesDirect(_ all: [WorkoutSession], finished: [WorkoutSession]) {
        let history = ProgressHistory(sessions: finished, layout: layout)
        for days in layout.windowDays {
            for metric in TrainingStats.Metric.allCases {
                let direct = DirectFigures(allSessions: all, windowDays: days, metric: metric)
                let window = history.window(days: days)
                let points = history.points(metric, days: days)
                let rolling = TrainingStats.rollingAverage(points, window: direct.rollingWindow)
                let label = "\(days) days, \(metric.rawValue), \(AppSettings.shared.weightUnit)"

                precondition(identical(history.sessions, direct.sessions), "sessions differ: \(label)")
                precondition(identical(window.windowed, direct.windowed), "windowed differs: \(label)")
                precondition(identical(window.previous, direct.previous), "previous differs: \(label)")
                precondition(identical(history.lastWeek, direct.lastWeek), "lastWeek differs: \(label)")
                precondition(history.lastWeekVolumeKg == TrainingStats.totalVolume(direct.lastWeek),
                             "last week's volume differs: \(label)")
                precondition(history.streak.current == direct.streak.current
                             && history.streak.longest == direct.streak.longest, "streak differs: \(label)")
                precondition(history.muscleSets == direct.muscleSets, "muscleSets differ: \(label)")
                precondition(history.ratios == direct.ratios, "ratios differ: \(label)")
                precondition(history.coverage == direct.coverage, "coverage differs: \(label)")
                precondition(history.behind == direct.behind, "behind differs: \(label)")
                precondition(points == direct.points, "points differ: \(label)")
                precondition(rolling == direct.rolling, "rolling differs: \(label)")
                precondition(history.volumeByDay == direct.volumeByDay, "volumeByDay differs: \(label)")
                precondition(history.trainedDays == direct.trainedDays, "trainedDays differ: \(label)")
                precondition(describe(history.records) == describe(direct.records), "records differ: \(label)")
                precondition(window.averageDuration == direct.averageDuration, "averageDuration differs: \(label)")
                precondition(history.weeklySessionCounts == direct.weeklySessionCounts,
                             "weeklySessionCounts differ: \(label)")
                for each in TrainingStats.Metric.allCases {
                    precondition(window.total(each) == direct.total(each), "total(\(each)) differs: \(label)")
                    precondition(window.delta(each) == direct.delta(each), "delta(\(each)) differs: \(label)")
                    precondition(history.weeklyTrend(each) == direct.weeklyTrend(each),
                                 "weeklyTrend(\(each)) differs: \(label)")
                }
            }
        }
        for muscle in Muscle.allCases {
            let direct = TrainingStats.lastTrained(muscle, in: finished)
            precondition(history.lastTrained(muscle) == direct, "lastTrained(\(muscle)) differs")
            precondition(history.lastTrained(muscle) == direct, "memoised lastTrained(\(muscle)) differs")
        }
        precondition(points(of: history, days: 90).contains { $0.value > 0 }, "The generated history must chart")
    }

    // MARK: - Taps read no sets

    /// Everything the dashboard's `body` does per pass once the history is
    /// cached: the cache lookup, the window's figures and the chart.
    @MainActor static func tap(_ cache: ProgressHistoryCache, _ all: [WorkoutSession],
                               days: Int, metric: TrainingStats.Metric) -> Double {
        let history = cache.history(for: all, revision: 0)
        let window = history.window(days: days)
        let points = history.points(metric, days: days)
        let rolling = TrainingStats.rollingAverage(points, window: days == 7 ? 3 : 7)
        return window.total(metric) + (rolling.last?.value ?? 0) + history.weeklyTrend(metric).reduce(0, +)
            + Double(history.records.count) + history.lastWeekVolumeKg
    }

    @MainActor static func checkTapsReadNoSets(_ all: [WorkoutSession], finished: [WorkoutSession]) {
        let cache = ProgressHistoryCache(layout: layout)
        _ = cache.history(for: all, revision: 0)
        let history = cache.history(for: all, revision: 0)
        for muscle in Muscle.allCases { _ = history.lastTrained(muscle) }

        // A loaded set, since a timed one's weight is never read by anything.
        // `sets` has no fixed order, so it is searched for rather than taken first.
        guard let victim = finished.lazy.flatMap(\.sets).first(where: {
            $0.isCompleted && $0.tracking == .weightReps && $0.weightKg > 0
        }) else { preconditionFailure("No completed loaded set to edit") }

        let cached = Flag()
        withObservationTracking {
            for days in layout.windowDays {
                for metric in TrainingStats.Metric.allCases { _ = tap(cache, all, days: days, metric: metric) }
            }
            for muscle in Muscle.allCases { _ = history.lastTrained(muscle) }
        } onChange: {
            cached.raise()
        }
        let direct = Flag()
        withObservationTracking {
            _ = DirectFigures(allSessions: all, windowDays: 30, metric: .volume)
        } onChange: {
            direct.raise()
        }

        victim.weightKg += 2.5
        precondition(direct.isRaised, "Control: the old per-pass computation must be seen reading sets")
        precondition(!cached.isRaised, "A tap on the cached figures must not read any set")
        victim.weightKg -= 2.5
    }

    // MARK: - Invalidation

    @MainActor static func checkInvalidation(_ context: ModelContext, all: [WorkoutSession],
                                             finished: [WorkoutSession], active: WorkoutSession) throws {
        let saves = SaveLog()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) {
            saves.record($0)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        // The previous check edited a finished set and put it back unsaved;
        // flushed here, or it would ride along with the first save below.
        try context.save()

        func affects(_ history: ProgressHistory, _ change: () -> Void) -> Bool {
            saves.reset()
            change()
            do { try context.save() } catch { preconditionFailure("Save failed: \(error)") }
            guard let note = saves.last else { preconditionFailure("A save must post ModelContext.didSave") }
            return history.isAffected(by: note)
        }

        let history = ProgressHistory(sessions: finished, layout: layout)
        let old = finished[finished.count / 2]
        guard let oldSet = old.sets.first(where: \.isCompleted),
              let activeSet = active.sets.first(where: { !$0.isCompleted }),
              let activeDone = active.sets.first(where: \.isCompleted) else {
            preconditionFailure("The generated history lacks the rows this check edits")
        }

        // What a workout in progress writes.
        precondition(!(affects(history) {
            activeSet.isCompleted = true
            activeSet.completedAt = .now
            activeSet.weightKg = 60
            activeSet.reps = 8
        }), "Logging a set in the active session must not rebuild the history")
        precondition(!(affects(history) {
            let extra = SetLog(catalogID: "barbell-curl", exerciseName: "Barbell Curl",
                               exerciseOrder: 9, setIndex: 0, weightKg: 30, reps: 10, tracking: .weightReps)
            extra.session = active
            context.insert(extra)
        }), "Adding a row to the active session must not rebuild the history")
        precondition(!(affects(history) { context.delete(activeDone) }),
                     "Erasing a set in the active session must not rebuild the history")
        precondition(!(affects(history) { active.title = "Renamed mid-workout" }),
                     "Editing the active session must not rebuild the history")
        precondition(!(affects(history) {
            context.insert(BodyMetric(date: .now, weightKg: 80))
        }), "A weigh-in must not rebuild the history")

        // What changes the finished history in place.
        precondition(affects(history) { oldSet.weightKg += 5 },
                     "Editing a finished set must rebuild the history")
        precondition(affects(history) {
            let late = SetLog(catalogID: "barbell-curl", exerciseName: "Barbell Curl",
                              exerciseOrder: 9, setIndex: 0, weightKg: 30, reps: 10, tracking: .weightReps)
            late.isCompleted = true
            late.completedAt = old.endedAt
            late.session = old
            context.insert(late)
        }, "A late set added to a finished session must rebuild the history")
        precondition(affects(history) {
            context.insert(CustomExerciseRecord(name: "Landmine Row", muscles: [.lats],
                                                equipment: ["Barbell"], tracking: .weightReps))
        }, "A custom exercise change must rebuild the history")
        precondition(affects(history) { context.delete(finished[0]) },
                     "Deleting a finished session must rebuild the history")

        // The cache itself: same inputs, same history; any key part changed, a new one.
        let remaining = try context.fetch(FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        let cache = ProgressHistoryCache(layout: layout)
        let first = cache.history(for: remaining, revision: 0)
        precondition(cache.history(for: remaining, revision: 0) === first, "An unchanged history must be reused")
        let bumped = cache.history(for: remaining, revision: 1)
        precondition(bumped !== first, "A revision bump must rebuild")
        AppSettings.shared.weightUnit = .lb
        let inPounds = cache.history(for: remaining, revision: 1)
        precondition(inPounds !== bumped, "A unit change must rebuild")
        AppSettings.shared.weightUnit = .kg
        let inKilograms = cache.history(for: remaining, revision: 1)
        active.endedAt = .now
        let afterFinish = cache.history(for: remaining, revision: 1)
        precondition(afterFinish !== inKilograms && afterFinish.sessions.count == inKilograms.sessions.count + 1,
                     "Finishing the active session must rebuild with it included")
    }

    // MARK: - Timing

    @MainActor static func timing(_ all: [WorkoutSession]) {
        let taps = layout.windowDays.flatMap { days in TrainingStats.Metric.allCases.map { (days, $0) } }

        var sink = 0.0
        let directStart = Date()
        for (days, metric) in taps {
            let figures = DirectFigures(allSessions: all, windowDays: days, metric: metric)
            sink += figures.total(metric)
        }
        let directPerTap = Date().timeIntervalSince(directStart) / Double(taps.count)

        let cache = ProgressHistoryCache(layout: layout)
        let buildStart = Date()
        _ = cache.history(for: all, revision: 0)
        let build = Date().timeIntervalSince(buildStart)

        let rounds = 20
        let tapStart = Date()
        for _ in 0..<rounds {
            for (days, metric) in taps { sink += tap(cache, all, days: days, metric: metric) }
        }
        let cachedPerTap = Date().timeIntervalSince(tapStart) / Double(taps.count * rounds)

        func ms(_ seconds: TimeInterval) -> String { String(format: "%.2f ms", seconds * 1000) }
        print("Timing (macOS, in-memory store, not asserted):")
        print("  before: every pass rebuilt everything  \(ms(directPerTap)) per tap")
        print("  after:  one build per history change   \(ms(build))")
        print("          each tap on the cached history \(ms(cachedPerTap)) per tap")
        if sink.isNaN { print("") }
    }

    // MARK: - Helpers

    static func identical(_ lhs: [WorkoutSession], _ rhs: [WorkoutSession]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    static func describe(_ records: [TrainingStats.PersonalRecord]) -> [String] {
        records.map { "\($0.catalogID)|\($0.exerciseName)|\($0.measure)|\($0.achievedAt.timeIntervalSinceReferenceDate)" }
            .sorted()
    }

    static func points(of history: ProgressHistory, days: Int) -> [TrainingStats.DayPoint] {
        history.points(.volume, days: days)
    }
}

/// Set from observation and notification callbacks, which may not capture a
/// mutable local.
final class Flag: @unchecked Sendable {
    private(set) var isRaised = false
    func raise() { isRaised = true }
}

final class SaveLog: @unchecked Sendable {
    private(set) var last: Notification?
    func record(_ note: Notification) { last = note }
    func reset() { last = nil }
}

/// The Progress figures exactly as `ProgressFigures.init` built them before the
/// cache, on every pass of `body`: the baseline every cached number must equal.
struct DirectFigures {
    let sessions: [WorkoutSession]
    let windowed: [WorkoutSession]
    let previous: [WorkoutSession]
    let lastWeek: [WorkoutSession]
    let streak: TrainingStats.Streak
    let muscleSets: [Muscle: Double]
    let ratios: [Muscle: Double]
    let coverage: Double
    let behind: [Muscle]
    let points: [TrainingStats.DayPoint]
    let rolling: [TrainingStats.DayPoint]
    let rollingWindow: Int
    let volumeByDay: [Date: Double]
    let trainedDays: Set<Date>
    let records: [TrainingStats.PersonalRecord]
    let averageDuration: Double
    let weeklySessionCounts: [Double]
    private let totals: [TrainingStats.Metric: Double]
    private let previousTotals: [TrainingStats.Metric: Double]
    private let weeklyTrends: [TrainingStats.Metric: [Double]]

    init(allSessions: [WorkoutSession], windowDays: Int, metric: TrainingStats.Metric) {
        let sessions = allSessions.filter { !$0.isActive }
        self.sessions = sessions
        let windowed = TrainingStats.sessions(in: sessions, days: windowDays)
        let previous = TrainingStats.previousWindow(sessions, days: windowDays)
        let lastWeek = TrainingStats.sessionsThisWeek(sessions)
        self.windowed = windowed
        self.previous = previous
        self.lastWeek = lastWeek
        streak = TrainingStats.streak(from: sessions)

        let recentWeek = TrainingStats.sessions(in: sessions, days: 7)
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

        rollingWindow = windowDays == 7 ? 3 : 7
        let points = TrainingStats.daily(metric, sessions: sessions, days: windowDays)
        self.points = points
        rolling = TrainingStats.rollingAverage(points, window: rollingWindow)

        volumeByDay = Dictionary(uniqueKeysWithValues:
            TrainingStats.daily(.volume, sessions: sessions, days: 17 * 7)
                .map { ($0.date, $0.value) })
        trainedDays = TrainingStats.trainedDays(in: sessions)
        records = TrainingStats.records(in: sessions)
        averageDuration = windowed.isEmpty ? 0 : windowed.reduce(0.0) { $0 + $1.duration } / Double(windowed.count)

        let metrics = TrainingStats.Metric.allCases
        totals = Dictionary(uniqueKeysWithValues: metrics.map { ($0, TrainingStats.total($0, windowed)) })
        previousTotals = Dictionary(uniqueKeysWithValues: metrics.map { ($0, TrainingStats.total($0, previous)) })
        weeklyTrends = Dictionary(uniqueKeysWithValues: metrics.map { ($0, Self.weeklyTrend($0, sessions: sessions)) })
        weeklySessionCounts = TrainingStats.weeklySessionCounts(sessions)
    }

    func total(_ metric: TrainingStats.Metric) -> Double { totals[metric] ?? 0 }

    func delta(_ metric: TrainingStats.Metric) -> Double? {
        TrainingStats.change(from: previousTotals[metric] ?? 0, to: total(metric))
    }

    func weeklyTrend(_ metric: TrainingStats.Metric) -> [Double] { weeklyTrends[metric] ?? [] }

    private static func weeklyTrend(_ metric: TrainingStats.Metric, sessions: [WorkoutSession], weeks: Int = 8) -> [Double] {
        let daily = TrainingStats.daily(metric, sessions: sessions, days: weeks * 7)
        return stride(from: 0, to: daily.count, by: 7).map { start in
            daily[start..<min(start + 7, daily.count)].reduce(0) { $0 + $1.value }
        }
    }
}

/// A deterministic, messy history: several sessions on some days, sessions
/// either side of midnight, skipped and continued rows, every tracking mode,
/// an exercise the catalog doesn't know, an empty finished session, one dated
/// ahead of today and one still in progress.
enum HistoryGenerator {
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
        mutating func chance(_ percent: Int) -> Bool { int(0...99) < percent }
    }

    static let exercises: [(id: String, name: String, tracking: TrackingMode)] = [
        ("barbell-bench-press", "Barbell Bench Press", .weightReps),
        ("barbell-back-squat", "Barbell Back Squat", .weightReps),
        ("deadlift", "Deadlift", .weightReps),
        ("leg-press", "Leg Press", .weightReps),
        ("dumbbell-lateral-raise", "Dumbbell Lateral Raise", .weightReps),
        ("barbell-curl", "Barbell Curl", .weightReps),
        ("pull-up", "Pull-up", .bodyweightReps),
        ("push-up", "Push-up", .bodyweightReps),
        ("plank-bodyweight", "Plank", .duration),
        ("scaption-dumbbell", "Dumbbell Scaption Raise", .weightReps),
        ("not-in-the-catalog", "Mystery Machine", .weightReps),
    ]

    /// Inserts the history and returns the session still in progress.
    @MainActor static func generate(into context: ModelContext, sessions count: Int, setsEach: Int) -> WorkoutSession {
        var random = Random(state: 20_260_928)
        let today = Calendar.current.startOfDay(for: .now)
        let perExercise = 5
        for index in 0..<count {
            let dayOffset = index * 420 / count
            let minute: Int
            switch index % 10 {
            case 0: minute = 23 * 60 + 50
            case 1: minute = 10
            default: minute = random.int(5 * 60...22 * 60)
            }
            let start = today.addingTimeInterval(TimeInterval(-dayOffset * 86_400 + minute * 60))
            addSession(into: context, startedAt: start, finished: true, sets: setsEach,
                       perExercise: perExercise, random: &random)
        }
        let empty = WorkoutSession(title: "Nothing logged", startedAt: today.addingTimeInterval(-86_400 + 3_600))
        empty.endedAt = empty.startedAt.addingTimeInterval(120)
        context.insert(empty)
        addSession(into: context, startedAt: today.addingTimeInterval(2 * 86_400 + 3_600), finished: true,
                   sets: 10, perExercise: perExercise, random: &random)
        return addSession(into: context, startedAt: Date.now.addingTimeInterval(-1_800), finished: false,
                          sets: 10, perExercise: perExercise, random: &random)
    }

    @discardableResult
    @MainActor static func addSession(into context: ModelContext, startedAt: Date, finished: Bool,
                                      sets: Int, perExercise: Int, random: inout Random) -> WorkoutSession {
        let session = WorkoutSession(title: "Session", startedAt: startedAt)
        if finished { session.endedAt = startedAt.addingTimeInterval(TimeInterval(random.int(40...95) * 60)) }
        context.insert(session)
        let first = random.int(0...(exercises.count - 1))
        for row in 0..<sets {
            let exercise = exercises[(first + row / perExercise) % exercises.count]
            let setIndex = row % perExercise
            let set: SetLog
            switch exercise.tracking {
            case .weightReps:
                set = SetLog(catalogID: exercise.id, exerciseName: exercise.name, exerciseOrder: row / perExercise,
                             setIndex: setIndex, weightKg: Double(random.int(8...56)) * 2.5,
                             reps: random.int(3...15), tracking: .weightReps)
            case .bodyweightReps:
                set = SetLog(catalogID: exercise.id, exerciseName: exercise.name, exerciseOrder: row / perExercise,
                             setIndex: setIndex, weightKg: random.chance(30) ? Double(random.int(2...8)) * 2.5 : 0,
                             reps: random.int(4...20), tracking: .bodyweightReps)
            case .duration:
                set = SetLog(catalogID: exercise.id, exerciseName: exercise.name, exerciseOrder: row / perExercise,
                             setIndex: setIndex, seconds: random.int(20...90), tracking: .duration)
            }
            if random.chance(finished ? 90 : 50) {
                set.isCompleted = true
                set.completedAt = startedAt.addingTimeInterval(TimeInterval((row + 1) * 150))
            }
            if setIndex > 0, random.chance(10) { set.continuesPreviousSet = true }
            set.session = session
            context.insert(set)
        }
        return session
    }
}
