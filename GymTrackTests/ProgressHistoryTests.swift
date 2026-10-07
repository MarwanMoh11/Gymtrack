import Testing
import Foundation
import Observation
import SwiftData
@testable import GymTrack

/// Protects the Progress tab's cache: every figure it keeps is the number the
/// tab always drew, a metric or window tap reads no set, and it rebuilds on the
/// saves that change the finished history and on nothing a workout in progress
/// writes.
///
/// `ProgressHistory` reads the wall clock and `Calendar.current` itself, and so
/// do the direct figures it is compared with, so both sides always agree on
/// which day is today. The history is 150 sessions of 15 rows: enough to cross
/// every window and the cache's horizon, small enough for a Debug simulator.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ProgressHistoryTests {

    static let layout = ProgressHistory.Layout(windowDays: [7, 30, 90], calendarDays: 17 * 7, trendWeeks: 8)

    /// A store holding a messy history, newest first, and the session still in
    /// progress.
    struct Fixture {
        let context: ModelContext
        let all: [WorkoutSession]
        let finished: [WorkoutSession]
        let active: WorkoutSession
    }

    private func makeFixture() throws -> Fixture {
        let context = try TestStore.context()
        let active = HistoryGenerator.generate(into: context, sessions: 150, setsEach: 15)
        try context.save()
        let all = try context.fetch(FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        return Fixture(context: context, all: all, finished: all.filter { !$0.isActive }, active: active)
    }

    /// Runs `body` with the app-wide unit set to `unit`, then puts it back.
    /// Volume is summed in the unit on screen.
    private func inUnit(_ unit: WeightUnit, _ body: () throws -> Void) rethrows {
        let saved = AppSettings.shared.weightUnit
        defer { AppSettings.shared.weightUnit = saved }
        AppSettings.shared.weightUnit = unit
        try body()
    }

    private func identical(_ lhs: [WorkoutSession], _ rhs: [WorkoutSession]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    private func describe(_ records: [TrainingStats.PersonalRecord]) -> [String] {
        records.map { "\($0.catalogID)|\($0.exerciseName)|\($0.measure)|\($0.achievedAt.timeIntervalSinceReferenceDate)" }
            .sorted()
    }

    /// Everything the dashboard's `body` does per pass once the history is
    /// cached: the cache lookup, the window's figures and the chart.
    private func tap(_ cache: ProgressHistoryCache, _ all: [WorkoutSession],
                     days: Int, metric: TrainingStats.Metric) -> Double {
        let history = cache.history(for: all, revision: 0)
        let window = history.window(days: days)
        let points = history.points(metric, days: days)
        let rolling = TrainingStats.rollingAverage(points, window: days == 7 ? 3 : 7)
        return window.total(metric) + (rolling.last?.value ?? 0) + history.weeklyTrend(metric).reduce(0, +)
            + Double(history.records.count) + history.lastWeekVolumeKg
    }

    // MARK: - The same numbers

    @Test(arguments: WeightUnit.allCases)
    func everyCachedFigureIsTheNumberTheTabAlwaysDrew(unit: WeightUnit) throws {
        try inUnit(unit) {
            let fixture = try makeFixture()
            let history = ProgressHistory(sessions: fixture.finished, layout: Self.layout)
            for days in Self.layout.windowDays {
                for metric in TrainingStats.Metric.allCases {
                    let direct = DirectFigures(allSessions: fixture.all, windowDays: days, metric: metric)
                    let window = history.window(days: days)
                    let points = history.points(metric, days: days)
                    let rolling = TrainingStats.rollingAverage(points, window: direct.rollingWindow)
                    let label = "\(days) days, \(metric.rawValue)"

                    #expect(identical(history.sessions, direct.sessions), "sessions: \(label)")
                    #expect(identical(window.windowed, direct.windowed), "windowed: \(label)")
                    #expect(identical(window.previous, direct.previous), "previous: \(label)")
                    #expect(identical(history.lastWeek, direct.lastWeek), "lastWeek: \(label)")
                    #expect(history.lastWeekVolumeKg == TrainingStats.totalVolume(direct.lastWeek), "\(label)")
                    #expect(history.streak.current == direct.streak.current, "\(label)")
                    #expect(history.streak.longest == direct.streak.longest, "\(label)")
                    #expect(history.muscleSets == direct.muscleSets, "\(label)")
                    #expect(history.ratios == direct.ratios, "\(label)")
                    #expect(history.coverage == direct.coverage, "\(label)")
                    #expect(history.behind == direct.behind, "\(label)")
                    #expect(points == direct.points, "\(label)")
                    #expect(rolling == direct.rolling, "\(label)")
                    #expect(history.volumeByDay == direct.volumeByDay, "\(label)")
                    #expect(history.trainedDays == direct.trainedDays, "\(label)")
                    #expect(describe(history.records) == describe(direct.records), "\(label)")
                    #expect(window.averageDuration == direct.averageDuration, "\(label)")
                    #expect(history.weeklySessionCounts == direct.weeklySessionCounts, "\(label)")
                    for each in TrainingStats.Metric.allCases {
                        #expect(window.total(each) == direct.total(each), "total(\(each)): \(label)")
                        #expect(window.delta(each) == direct.delta(each), "delta(\(each)): \(label)")
                        #expect(history.weeklyTrend(each) == direct.weeklyTrend(each), "weeklyTrend(\(each)): \(label)")
                    }
                }
            }
            for muscle in Muscle.allCases {
                let direct = TrainingStats.lastTrained(muscle, in: fixture.finished)
                #expect(history.lastTrained(muscle) == direct, "\(muscle)")
                // Asked again, the memo answers.
                #expect(history.lastTrained(muscle) == direct, "\(muscle), remembered")
            }
            #expect(history.points(.volume, days: 90).contains { $0.value > 0 }, "The generated history must chart")
        }
    }

    // MARK: - Training days

    /// The chart and the calendar beside it file a session that started at
    /// 00:30 under the night before, as Today and the streak do. Built from
    /// the wall clock, as the cache is, two nights back.
    @Test func aSessionStartedAfterMidnightIsChartedOnTheNightBefore() throws {
        try inUnit(.kg) {
            let context = try TestStore.context()
            let calendar = Calendar.current
            let night = TrainingStats.startOfDay(-2, from: TrainingDay.key(for: .now, calendar: calendar),
                                                 calendar: calendar)
            let morning = TrainingStats.startOfDay(1, from: night, calendar: calendar)
            let start = morning.addingTimeInterval(30 * 60)
            let session = WorkoutSession(title: "Late", startedAt: start)
            session.endedAt = start.addingTimeInterval(3_600)
            context.insert(session)
            let set = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press", exerciseOrder: 0,
                             setIndex: 0, weightKg: 100, reps: 5, tracking: .weightReps)
            set.isCompleted = true
            set.completedAt = start.addingTimeInterval(60)
            set.session = session
            context.insert(set)

            let history = ProgressHistory(sessions: [session], layout: Self.layout)
            #expect(history.trainedDays == [night])
            #expect(history.volumeByDay[night] == 500)
            #expect(history.volumeByDay[morning] == 0)
            #expect(history.points(.sets, days: 7).first { $0.date == night }?.value == 1)
        }
    }

    // MARK: - A tap reads no set

    @Test func aMetricOrWindowTapReadsNoSet() throws {
        let fixture = try makeFixture()
        let all = fixture.all
        let cache = ProgressHistoryCache(layout: Self.layout)
        _ = cache.history(for: all, revision: 0)
        let history = cache.history(for: all, revision: 0)
        for muscle in Muscle.allCases { _ = history.lastTrained(muscle) }

        // A loaded set, since a timed one's weight is never read by anything.
        // `sets` has no fixed order, so it is searched for rather than taken first.
        let victim = try #require(fixture.finished.lazy.flatMap(\.sets).first {
            $0.isCompleted && $0.tracking == .weightReps && $0.weightKg > 0
        })

        let cached = Flag()
        withObservationTracking {
            for days in Self.layout.windowDays {
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
        #expect(direct.isRaised, "Control: the old per-pass computation must be seen reading sets")
        #expect(!cached.isRaised, "A tap on the cached figures must not read any set")
        victim.weightKg -= 2.5
    }

    // MARK: - What rebuilds it

    @Test func savesToTheFinishedHistoryRebuildItAndAWorkoutInProgressDoesNot() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let saves = SaveLog()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) {
            saves.record($0)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        func affects(_ history: ProgressHistory, _ change: () -> Void) throws -> Bool {
            saves.reset()
            change()
            try context.save()
            let note = try #require(saves.last, "A save must post ModelContext.didSave")
            return history.isAffected(by: note)
        }

        let history = ProgressHistory(sessions: fixture.finished, layout: Self.layout)
        let old = fixture.finished[fixture.finished.count / 2]
        let oldSet = try #require(old.sets.first { $0.isCompleted })
        let activeSet = try #require(fixture.active.sets.first { !$0.isCompleted })
        let activeDone = try #require(fixture.active.sets.first { $0.isCompleted })

        // What a workout in progress writes.
        let logged = try affects(history) {
            activeSet.isCompleted = true
            activeSet.completedAt = .now
            activeSet.weightKg = 60
            activeSet.reps = 8
        }
        #expect(!logged, "Logging a set in the active session must not rebuild the history")
        let added = try affects(history) {
            let extra = SetLog(catalogID: "barbell-curl", exerciseName: "Barbell Curl",
                               exerciseOrder: 9, setIndex: 0, weightKg: 30, reps: 10, tracking: .weightReps)
            extra.session = fixture.active
            context.insert(extra)
        }
        #expect(!added, "Adding a row to the active session must not rebuild the history")
        let erased = try affects(history) { context.delete(activeDone) }
        #expect(!erased, "Erasing a set in the active session must not rebuild the history")
        let renamed = try affects(history) { fixture.active.title = "Renamed mid-workout" }
        #expect(!renamed, "Editing the active session must not rebuild the history")
        let weighed = try affects(history) { context.insert(BodyMetric(date: .now, weightKg: 80)) }
        #expect(!weighed, "A weigh-in must not rebuild the history")

        // What changes the finished history in place.
        let edited = try affects(history) { oldSet.weightKg += 5 }
        #expect(edited, "Editing a finished set must rebuild the history")
        let late = try affects(history) {
            let set = SetLog(catalogID: "barbell-curl", exerciseName: "Barbell Curl",
                             exerciseOrder: 9, setIndex: 0, weightKg: 30, reps: 10, tracking: .weightReps)
            set.isCompleted = true
            set.completedAt = old.endedAt
            set.session = old
            context.insert(set)
        }
        #expect(late, "A late set added to a finished session must rebuild the history")
        let custom = try affects(history) {
            context.insert(CustomExerciseRecord(name: "Landmine Row", muscles: [.lats],
                                                equipment: ["Barbell"], tracking: .weightReps))
        }
        #expect(custom, "A custom exercise change must rebuild the history")
        let deleted = try affects(history) { context.delete(fixture.finished[0]) }
        #expect(deleted, "Deleting a finished session must rebuild the history")
    }

    @Test func theCacheIsReusedUntilWhatItWasBuiltFromChanges() throws {
        try inUnit(.kg) {
            let fixture = try makeFixture()
            let all = fixture.all
            let cache = ProgressHistoryCache(layout: Self.layout)
            let first = cache.history(for: all, revision: 0)
            #expect(cache.history(for: all, revision: 0) === first, "An unchanged history must be reused")
            let bumped = cache.history(for: all, revision: 1)
            #expect(bumped !== first, "A revision bump must rebuild")
            AppSettings.shared.weightUnit = .lb
            let inPounds = cache.history(for: all, revision: 1)
            #expect(inPounds !== bumped, "A unit change must rebuild")
            AppSettings.shared.weightUnit = .kg
            let inKilograms = cache.history(for: all, revision: 1)
            fixture.active.endedAt = .now
            let afterFinish = cache.history(for: all, revision: 1)
            #expect(afterFinish !== inKilograms, "Finishing the active session must rebuild")
            #expect(afterFinish.sessions.count == inKilograms.sessions.count + 1, "With the finished session included")
        }
    }
}

/// Set from observation and notification callbacks, which may not capture a
/// mutable local.
private final class Flag: @unchecked Sendable {
    private(set) var isRaised = false
    func raise() { isRaised = true }
}

private final class SaveLog: @unchecked Sendable {
    private(set) var last: Notification?
    func record(_ note: Notification) { last = note }
    func reset() { last = nil }
}

/// The Progress figures exactly as the tab built them before the cache, on
/// every pass of `body`: the baseline every cached number must equal.
private struct DirectFigures {
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
            TrainingStats.daily(.volume, sessions: sessions, days: 17 * 7).map { ($0.date, $0.value) })
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

/// A deterministic, messy history over fourteen months up to today: sessions
/// either side of midnight, skipped and continued rows, every tracking mode, an
/// exercise the catalog doesn't know, an empty finished session, one dated
/// ahead of today and one still in progress.
@MainActor
private enum HistoryGenerator {
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
    static func generate(into context: ModelContext, sessions count: Int, setsEach: Int) -> WorkoutSession {
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
    static func addSession(into context: ModelContext, startedAt: Date, finished: Bool,
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
