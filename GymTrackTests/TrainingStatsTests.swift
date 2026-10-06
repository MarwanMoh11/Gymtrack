import Testing
import Foundation
import SwiftData
@testable import GymTrack

/// Protects the numbers behind Today and Progress: streaks, calendar weeks,
/// day counts, volume and personal records over finished sessions, including
/// the days that are 23 or 25 hours long and the sessions that straddle
/// midnight in a zone other than the runner's.
///
/// The native counterpart of the legacy `Tests/TrainingStats*Tests.swift`,
/// `Tests/RecordRankingTests.swift` and `Tests/StatsGapTests.swift`; the
/// progression suggestion has its own file.
@MainActor @Suite(.serialized)
struct TrainingStatsTests {

    /// One set to be logged, spelled out only where a test cares.
    fileprivate struct Work {
        var id = "barbell-bench-press"
        var kg: Double = 0
        var reps = 0
        var seconds = 0
        var tracking: TrackingMode? = .weightReps
        var drop = false
        var logged = true
        var at: Date?
    }

    /// An in-memory store that builds finished sessions from `Work`.
    @MainActor fileprivate final class Rig {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            container = try TestStore.container()
            context = ModelContext(container)
        }

        @discardableResult
        func session(_ start: Date, finished: Bool = true, _ work: [Work]) -> WorkoutSession {
            let session = WorkoutSession(title: "Test", startedAt: start)
            if finished { session.endedAt = start.addingTimeInterval(3_600) }
            context.insert(session)
            for (index, item) in work.enumerated() {
                let set = SetLog(catalogID: item.id, exerciseName: item.id, exerciseOrder: 0, setIndex: index,
                                 weightKg: item.kg, reps: item.reps, seconds: item.seconds, tracking: item.tracking)
                if item.logged {
                    set.isCompleted = true
                    set.completedAt = item.at ?? start.addingTimeInterval(Double(index + 1) * 60)
                }
                if item.drop { set.continuesPreviousSet = true }
                set.session = session
                context.insert(set)
            }
            return session
        }

        /// A finished session with one working set, which is all a streak needs.
        @discardableResult
        func trained(_ stamp: String, in zone: String = "UTC") -> WorkoutSession {
            session(TestClock.at(stamp, in: zone), [Work(kg: 100, reps: 5)])
        }
    }

    private let utc = TestClock.calendar
    /// A Wednesday at noon UTC.
    private let now = TestClock.reference

    // MARK: - Streaks

    @Test func noHistoryIsNoStreak() {
        let streak = TrainingStats.streak(from: [], calendar: utc, now: now)
        #expect(streak.current == 0)
        #expect(streak.longest == 0)
    }

    @Test func oneSessionTodayIsAStreakOfOne() throws {
        let rig = try Rig()
        let sessions = [rig.trained("2026-03-11T07:00:00")]
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: now)
        #expect(streak.current == 1)
        #expect(streak.longest == 1)
    }

    @Test func todayNotTrainedYetDoesNotBreakYesterdaysStreak() throws {
        let rig = try Rig()
        let sessions = [rig.trained("2026-03-09T09:00:00"), rig.trained("2026-03-10T09:00:00")]
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: now)
        #expect(streak.current == 2)
        #expect(streak.longest == 2)
    }

    @Test func missingYesterdayEndsTheCurrentStreakButKeepsTheLongest() throws {
        let rig = try Rig()
        let sessions = ["2026-03-07T09:00:00", "2026-03-08T09:00:00", "2026-03-09T09:00:00"].map { rig.trained($0) }
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: now)
        #expect(streak.current == 0)
        #expect(streak.longest == 3)
    }

    @Test func aDayCountsOnceAndMisTapsDoNotCount() throws {
        let rig = try Rig()
        let sessions = [
            rig.trained("2026-03-09T09:00:00"),
            rig.trained("2026-03-09T18:00:00"),
            // Finish pressed with nothing logged: a mis-tap, not a day trained.
            rig.session(TestClock.at("2026-03-10T08:00:00"), [Work(kg: 100, reps: 5, logged: false)]),
            // Still running: not finished, so not yet a day trained.
            rig.session(TestClock.at("2026-03-10T09:00:00"), finished: false, [Work(kg: 100, reps: 5)]),
        ]
        let days = TrainingStats.trainedDays(in: sessions, calendar: utc)
        #expect(days == [TestClock.at("2026-03-09T00:00:00")])
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: TestClock.at("2026-03-10T12:00:00"))
        #expect(streak.current == 1)
        #expect(streak.longest == 1)
    }

    /// A session at 23:59 and the next at 00:01 are on consecutive local days in
    /// every zone below, and on the same UTC day in all of them.
    @Test(arguments: ["America/New_York", "Africa/Cairo", "Pacific/Kiritimati"])
    func sessionsEitherSideOfLocalMidnightAreTwoDaysInThatZoneAndOneInUTC(zone: String) throws {
        let rig = try Rig()
        let sessions = [rig.trained("2026-03-09T23:59:00", in: zone), rig.trained("2026-03-10T00:01:00", in: zone)]
        let morning = TestClock.at("2026-03-10T09:00:00", in: zone)

        let local = TrainingStats.streak(from: sessions, calendar: TestClock.calendar(in: zone), now: morning)
        #expect(local.current == 2)
        #expect(local.longest == 2)

        let utcDays = TrainingStats.trainedDays(in: sessions, calendar: utc)
        #expect(utcDays.count == 1)
        #expect(TrainingStats.streak(from: sessions, calendar: utc, now: morning).current == 1)
    }

    struct StreakCase: Sendable, CustomTestStringConvertible {
        let zone: String
        let stamps: [String]
        let now: String
        let current: Int
        var testDescription: String { "\(zone) \(stamps.first ?? "")" }
    }

    /// The days the clocks change are not 24 hours long, and a streak that ran
    /// through one used to split in two there.
    @Test(arguments: [
        StreakCase(zone: "America/New_York",
                   stamps: ["2026-03-07T20:00:00", "2026-03-08T12:00:00", "2026-03-09T08:00:00"],
                   now: "2026-03-09T18:00:00", current: 3),
        StreakCase(zone: "America/New_York",
                   stamps: ["2026-10-31T22:00:00", "2026-11-01T00:30:00", "2026-11-01T23:30:00", "2026-11-02T08:00:00"],
                   now: "2026-11-02T12:00:00", current: 3),
        // Cairo springs forward at midnight, so Friday 24 April starts at 01:00.
        StreakCase(zone: "Africa/Cairo",
                   stamps: ["2026-04-23T20:00:00", "2026-04-24T01:30:00", "2026-04-25T10:00:00"],
                   now: "2026-04-25T12:00:00", current: 3),
    ])
    func aStreakRunsThroughTheDayTheClocksChange(_ scenario: StreakCase) throws {
        let rig = try Rig()
        let calendar = TestClock.calendar(in: scenario.zone)
        let sessions = scenario.stamps.map { rig.trained($0, in: scenario.zone) }
        let streak = TrainingStats.streak(from: sessions, calendar: calendar,
                                          now: TestClock.at(scenario.now, in: scenario.zone))
        #expect(streak.current == scenario.current)
        #expect(streak.longest == scenario.current)
    }

    // MARK: - Calendar weeks

    @Test func theWeekFollowsTheCalendarsFirstWeekday() {
        let monday = TrainingStats.weekInterval(containing: now, calendar: utc)
        #expect(monday.start == TestClock.at("2026-03-09T00:00:00"))
        #expect(monday.end == TestClock.at("2026-03-16T00:00:00"))

        var sundayFirst = utc
        sundayFirst.firstWeekday = 1
        let sunday = TrainingStats.weekInterval(containing: now, calendar: sundayFirst)
        #expect(sunday.start == TestClock.at("2026-03-08T00:00:00"))
        #expect(sunday.end == TestClock.at("2026-03-15T00:00:00"))
    }

    @Test func aWeekOwnsItsFirstInstantAndNotItsLast() {
        let start = TestClock.at("2026-03-09T00:00:00")
        let end = TestClock.at("2026-03-16T00:00:00")
        #expect(TrainingStats.weekInterval(containing: start, calendar: utc).start == start)
        #expect(TrainingStats.weekInterval(containing: end.addingTimeInterval(-1), calendar: utc).start == start)
        #expect(TrainingStats.weekInterval(containing: end, calendar: utc).start == end)
    }

    @Test func theWeekOfTheSpringForwardIsOneHourShort() {
        let calendar = TestClock.calendar(in: "America/New_York")
        let week = TrainingStats.weekInterval(containing: TestClock.at("2026-03-08T12:00:00", in: "America/New_York"),
                                              calendar: calendar)
        #expect(week.start == TestClock.at("2026-03-02T00:00:00", in: "America/New_York"))
        #expect(week.end == TestClock.at("2026-03-09T00:00:00", in: "America/New_York"))
        #expect(week.duration == 167 * 3_600)
    }

    @Test func thisWeekCountsFinishedTrainingStartedInsideItsEdges() throws {
        let rig = try Rig()
        let inside = [
            rig.trained("2026-03-09T00:00:00"), rig.trained("2026-03-11T09:00:00"), rig.trained("2026-03-15T23:59:59"),
        ]
        let outside = [
            rig.trained("2026-03-08T23:59:59"), rig.trained("2026-03-16T00:00:00"),
            rig.session(TestClock.at("2026-03-10T08:00:00"), [Work(kg: 100, reps: 5, logged: false)]),
            rig.session(TestClock.at("2026-03-10T09:00:00"), finished: false, [Work(kg: 100, reps: 5)]),
        ]
        let found = TrainingStats.sessionsThisWeek(inside + outside, calendar: utc, now: now)
        #expect(Set(found.map(\.id)) == Set(inside.map(\.id)))
        #expect(TrainingStats.sessionsThisWeek([], calendar: utc, now: now).isEmpty)
    }

    @Test func aLateSundayInNewYorkBelongsToLastWeekThere() throws {
        let rig = try Rig()
        let zone = "America/New_York"
        // 23:30 on Sunday 8 March in New York is 03:30 UTC on Monday the 9th.
        let lateSunday = rig.trained("2026-03-08T23:30:00", in: zone)
        let wednesday = TestClock.at("2026-03-11T12:00:00", in: zone)
        let local = TrainingStats.sessionsThisWeek([lateSunday], calendar: TestClock.calendar(in: zone), now: wednesday)
        let universal = TrainingStats.sessionsThisWeek([lateSunday], calendar: utc, now: wednesday)
        #expect(local.isEmpty)
        #expect(universal.count == 1)
    }

    // MARK: - Counting days

    struct DayCase: Sendable, CustomTestStringConvertible {
        let zone: String
        let from: String
        let to: String
        let days: Int
        var testDescription: String { "\(zone) \(from) to \(to)" }
    }

    @Test(arguments: [
        DayCase(zone: "UTC", from: "2026-03-10T23:59:00", to: "2026-03-11T00:01:00", days: 1),
        DayCase(zone: "UTC", from: "2026-03-11T00:00:00", to: "2026-03-11T23:59:59", days: 0),
        DayCase(zone: "UTC", from: "2026-03-12T10:00:00", to: "2026-03-11T10:00:00", days: -1),
        DayCase(zone: "America/New_York", from: "2026-03-07T23:30:00", to: "2026-03-09T00:30:00", days: 2),
        DayCase(zone: "America/New_York", from: "2026-03-08T00:30:00", to: "2026-03-09T00:30:00", days: 1),
        DayCase(zone: "America/New_York", from: "2026-03-08T00:10:00", to: "2026-03-08T23:50:00", days: 0),
        DayCase(zone: "America/New_York", from: "2026-11-01T00:30:00", to: "2026-11-02T00:30:00", days: 1),
        DayCase(zone: "Africa/Cairo", from: "2026-04-24T01:30:00", to: "2026-04-25T00:30:00", days: 1),
        DayCase(zone: "Pacific/Kiritimati", from: "2026-03-10T23:59:00", to: "2026-03-11T00:01:00", days: 1),
    ])
    func wholeCalendarDaysAreCountedBetweenWallClockMiddays(_ scenario: DayCase) {
        let calendar = TestClock.calendar(in: scenario.zone)
        let count = TrainingStats.dayCount(from: TestClock.at(scenario.from, in: scenario.zone),
                                           to: TestClock.at(scenario.to, in: scenario.zone), calendar: calendar)
        #expect(count == scenario.days)
    }

    @Test func dailyBucketsLandOnTheirOwnDaysAcrossTheSpringForward() throws {
        let rig = try Rig()
        let zone = "America/New_York"
        let calendar = TestClock.calendar(in: zone)
        let sessions = [
            rig.session(TestClock.at("2026-03-07T20:00:00", in: zone), [Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-08T00:30:00", in: zone), [Work(kg: 100, reps: 5), Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-08T15:00:00", in: zone), [Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-10T09:00:00", in: zone), [Work(kg: 100, reps: 5)]),
        ]
        let points = TrainingStats.daily(.sets, sessions: sessions, days: 4, calendar: calendar,
                                         now: TestClock.at("2026-03-10T12:00:00", in: zone))
        #expect(points.map(\.value) == [1, 3, 0, 1])
        let expectedDays = ["2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"]
            .map { TestClock.at("\($0)T00:00:00", in: zone) }
        #expect(points.map(\.date) == expectedDays)
        #expect(TrainingStats.daily(.sets, sessions: sessions, days: 0, calendar: calendar, now: now).isEmpty)
        #expect(TrainingStats.daily(.sets, sessions: sessions, days: -3, calendar: calendar, now: now).isEmpty)
    }

    @Test func sevenDayBucketsIncludeTheirFirstDayAndNotTheNextBucketsLast() throws {
        let rig = try Rig()
        let sessions = [
            "2026-03-11T08:00:00", "2026-03-08T08:00:00", "2026-03-05T00:00:00",
            "2026-03-04T23:59:00", "2026-02-26T00:00:00", "2026-02-25T23:59:00",
        ].map { rig.trained($0) }
        let counts = TrainingStats.weeklySessionCounts(sessions, weeks: 2, calendar: utc, now: now)
        #expect(counts == [2, 3])
        #expect(TrainingStats.weeklySessionCounts(sessions, weeks: 0, calendar: utc, now: now).isEmpty)
    }

    @Test func changeNeedsABaselineAndAverageNeedsNoFullWindow() {
        #expect(TrainingStats.change(from: 0, to: 5) == nil)
        #expect(TrainingStats.change(from: -3, to: 5) == nil)
        #expect(TrainingStats.change(from: 100, to: 125) == 0.25)
        #expect(TrainingStats.change(from: 100, to: 50) == -0.5)

        let points = [3.0, 6, 9, 12].enumerated().map {
            TrainingStats.DayPoint(date: now.addingTimeInterval(Double($0.offset) * 86_400), value: $0.element)
        }
        #expect(TrainingStats.rollingAverage(points, window: 3).map(\.value) == [3, 4.5, 6, 9])
        #expect(TrainingStats.rollingAverage(points, window: 1).map(\.value) == [3, 6, 9, 12])
        #expect(TrainingStats.rollingAverage([], window: 3).isEmpty)
    }

    // MARK: - Volume

    @Test func volumeCountsEveryKilogramThatMovedAndNothingThatDidNot() throws {
        let rig = try Rig()
        let big = rig.session(TestClock.at("2026-03-09T09:00:00"), [
            Work(kg: 100, reps: 5),
            Work(kg: 200, reps: 5, logged: false),
            // A drop's back-off row: a set the lifter did not add, but weight they lifted.
            Work(kg: 80, reps: 6, drop: true),
            Work(id: "pull-up", kg: 0, reps: 10, tracking: .bodyweightReps),
            Work(id: "pull-up", kg: 20, reps: 8, tracking: .bodyweightReps),
            Work(id: "plank-bodyweight", seconds: 60, tracking: .duration),
        ])
        let small = rig.trained("2026-03-10T09:00:00")
        #expect(big.completedSets.count == 5)
        #expect(big.effortSets.count == 4)
        #expect(big.totalVolumeKg == 500 + 480 + 160)
        #expect(TrainingStats.totalVolume([big, small]) == 500 + 480 + 160 + 500)
        #expect(TrainingStats.totalVolume([]) == 0)

        // Kilograms are the storage unit: the display unit never reaches the total.
        let original = AppSettings.shared.weightUnit
        defer { AppSettings.shared.weightUnit = original }
        AppSettings.shared.weightUnit = .lb
        #expect(TrainingStats.totalVolume([big, small]) == 500 + 480 + 160 + 500)
    }

    @Test func aSessionOfUnloggedSetsMovedNothing() throws {
        let rig = try Rig()
        let empty = rig.session(TestClock.at("2026-03-09T09:00:00"), [Work(kg: 100, reps: 5, logged: false)])
        #expect(empty.totalVolumeKg == 0)
        #expect(TrainingStats.totalVolume([empty]) == 0)
    }

    // MARK: - Records

    /// A session's sets in the order they were logged; a relationship array
    /// makes no promise about its own order.
    private func logged(_ session: WorkoutSession) -> [SetLog] {
        session.sets.sorted { $0.setIndex < $1.setIndex }
    }

    private func weightRecord(_ record: TrainingStats.PersonalRecord) throws -> (kg: Double, reps: Int, oneRepMax: Double?) {
        guard case let .weight(kg, reps, oneRepMax) = record.measure else {
            Issue.record("Expected a weight record, got \(record.measure)")
            throw CancellationError()
        }
        return (kg, reps, oneRepMax)
    }

    @Test func theRecordIsTheSetWithTheBestEstimatedMaxNotTheHeaviestOrTheLongest() throws {
        let rig = try Rig()
        let sessions = [
            rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-04T09:00:00"), [Work(kg: 90, reps: 8)]),
            rig.session(TestClock.at("2026-03-06T09:00:00"), [Work(kg: 110, reps: 1)]),
        ]
        let records = TrainingStats.records(in: sessions)
        #expect(records.count == 1)
        let best = try weightRecord(#require(records.first))
        #expect(best.kg == 100)
        #expect(best.reps == 5)
        // 100 x 5 estimates 116.7 against 114 for 90 x 8 and 110 for the single.
        let estimate = try #require(best.oneRepMax)
        #expect(abs(estimate - 116.667) < 0.01)
        #expect(TrainingStats.records(in: []).isEmpty)
    }

    @Test func aTiedRecordBelongsToTheSetThatReachedItFirst() throws {
        let rig = try Rig()
        let early = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 100, reps: 5)])
        let late = rig.session(TestClock.at("2026-03-09T09:00:00"), [Work(kg: 100, reps: 5)])
        // Handed over newest first, so only the dates can be what decides.
        let record = try #require(TrainingStats.records(in: [late, early]).first)
        #expect(record.achievedAt == logged(early)[0].completedAt)
    }

    @Test func bodyweightAndTimedWorkKeepTheirOwnKindsOfRecord() throws {
        let rig = try Rig()
        let pull = "pull-up"
        let sessions = [
            rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: pull, reps: 12, tracking: .bodyweightReps)]),
            rig.session(TestClock.at("2026-03-04T09:00:00"), [Work(id: pull, reps: 15, tracking: .bodyweightReps)]),
            rig.session(TestClock.at("2026-03-06T09:00:00"), [Work(id: pull, kg: 10, reps: 6, tracking: .bodyweightReps)]),
            rig.session(TestClock.at("2026-03-03T09:00:00"), [Work(id: "plank-bodyweight", seconds: 45, tracking: .duration)]),
            rig.session(TestClock.at("2026-03-05T09:00:00"), [Work(id: "plank-bodyweight", seconds: 60, tracking: .duration)]),
        ]
        let records = TrainingStats.records(in: sessions)
        let measures = records.map(\.measure)
        #expect(measures.count == 3)
        #expect(measures.contains(.reps(15)))
        #expect(measures.contains(.addedLoad(kg: 10, reps: 6)))
        #expect(measures.contains(.duration(seconds: 60)))
        // Newest achievement first.
        #expect(records.map(\.achievedAt) == records.map(\.achievedAt).sorted(by: >))
    }

    @Test func aRowThatContinuedASetCanNeitherSetNorBlockARecord() throws {
        let rig = try Rig()
        let first = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 62.5, reps: 8)])
        // 62 x 10 estimates a higher max than 62.5 x 8, but it was lifted
        // already fatigued, inside the set above it.
        let second = rig.session(TestClock.at("2026-03-09T09:00:00"), [
            Work(kg: 60, reps: 8), Work(kg: 62, reps: 10, drop: true),
        ])
        let sessions = [first, second]
        let best = try weightRecord(#require(TrainingStats.records(in: sessions).first))
        #expect(best.kg == 62.5)
        #expect(best.reps == 8)
        #expect(!TrainingStats.isPersonalRecord(logged(second)[1], in: sessions))
        #expect(!TrainingStats.isPersonalRecord(logged(second)[0], in: sessions))
    }

    @Test func aPersonalRecordMustBeatEverythingBeforeItNotJustMatchIt() throws {
        let rig = try Rig()
        let first = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 100, reps: 5)])
        let tie = rig.session(TestClock.at("2026-03-04T09:00:00"), [Work(kg: 100, reps: 5)])
        let better = rig.session(TestClock.at("2026-03-06T09:00:00"), [Work(kg: 102.5, reps: 5)])
        let unlogged = rig.session(TestClock.at("2026-03-08T09:00:00"), [Work(kg: 200, reps: 5, logged: false)])
        let history = [first, tie, better, unlogged]
        // The first set of a kind is a baseline, with nothing to break.
        #expect(!TrainingStats.isPersonalRecord(logged(first)[0], in: history))
        #expect(!TrainingStats.isPersonalRecord(logged(tie)[0], in: history))
        #expect(TrainingStats.isPersonalRecord(logged(better)[0], in: history))
        #expect(!TrainingStats.isPersonalRecord(logged(unlogged)[0], in: history))
    }

    // MARK: - Exercise history

    @Test func lastPerformanceIsTheNewestFinishedSessionsOwnSetsAndHistoryKeepsTheDrops() throws {
        let rig = try Rig()
        let older = rig.session(TestClock.at("2026-03-02T09:00:00"), [
            Work(kg: 100, reps: 5), Work(kg: 90, reps: 10, drop: true),
        ])
        let newer = rig.session(TestClock.at("2026-03-09T09:00:00"), [Work(kg: 102.5, reps: 5)])
        let running = rig.session(TestClock.at("2026-03-10T09:00:00"), finished: false, [Work(kg: 105, reps: 5)])
        let all = [older, newer, running]
        let bench = "barbell-bench-press"

        #expect(TrainingStats.lastPerformance(of: bench, in: all).map(\.weightKg) == [102.5])
        // Excluding the newest falls back to the one before, without its drop row.
        #expect(TrainingStats.lastPerformance(of: bench, in: all, excluding: newer.id).map(\.weightKg) == [100])
        #expect(TrainingStats.lastPerformance(of: "deadlift", in: all).isEmpty)
        #expect(TrainingStats.lastPerformance(of: bench, in: []).isEmpty)

        let history = TrainingStats.history(for: bench, in: all)
        #expect(history.map(\.id) == [newer.id, older.id])
        let summary = try #require(history.last)
        #expect(summary.volumeKg == 500 + 900)
        #expect(summary.topSet?.weightKg == 100)
        // 90 x 10 would estimate 120, but a drop's rows say nothing about strength.
        #expect(abs(summary.bestEstimatedOneRepMax - 116.667) < 0.01)
    }

    @Test func aMergedExercisesOldIDFindsItsHistory() throws {
        let rig = try Rig()
        let old = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "scaption-dumbbell", kg: 8, reps: 12)])
        #expect(TrainingStats.lastPerformance(of: "scaption", in: [old]).count == 1)
        #expect(TrainingStats.history(for: "scaption-dumbbell", in: [old]).count == 1)
    }
}
