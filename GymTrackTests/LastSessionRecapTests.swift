import Foundation
import SwiftData
import Testing
@testable import GymTrack

// What this file protects: the "last 80 × 8 · 42s" line on every set row, on the
// phone and on the wrist. It is the set opposite this one last session, paired
// the way the gain badge pairs it, and a row with no counterpart shows nothing
// rather than a number borrowed from another set. A duration appears only when
// the start was announced; one worked out any other way is a guess, and a guess
// beside the number being raced would read as a time to beat.

@MainActor @Suite(.serialized)
struct LastSessionRecapTests {

    private struct Past {
        var kg = 80.0
        var reps = 8
        var seconds = 0
        /// How long the set took if its start was announced, nil if it wasn't.
        var tookSeconds: Double?
    }

    /// A finished session one week back holding `sets` of one exercise.
    private func lastWeek(_ bench: WorkoutBench, _ sets: [Past], tracking: TrackingMode = .weightReps,
                          catalogID: String = WorkoutBench.bench) -> WorkoutSession {
        let past = bench.session(title: "Last week", startedAt: WorkoutBench.t0.addingTimeInterval(-7 * 86_400))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        for (index, lift) in sets.enumerated() {
            let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: 0, setIndex: index,
                             weightKg: lift.kg, reps: lift.reps, seconds: lift.seconds,
                             targetRepsLow: 8, targetRepsHigh: 12, tracking: tracking)
            let done = past.startedAt.addingTimeInterval(Double(index + 1) * 180)
            set.isCompleted = true
            set.completedAt = done
            if let took = lift.tookSeconds { set.startedAt = done.addingTimeInterval(-took) }
            set.session = past
            bench.context.insert(set)
        }
        try? bench.context.save()
        return past
    }

    private func today(_ bench: WorkoutBench, rows: Int, history: [WorkoutSession],
                       catalogID: String = WorkoutBench.bench,
                       tracking: TrackingMode = .weightReps) -> (rows: [SetLog], workout: ActiveWorkout) {
        let session = bench.session()
        let made = bench.addRows(catalogID, to: session, count: rows, tracking: tracking)
        return (made, bench.open(session, history: history))
    }

    // MARK: Pairing to rows

    @Test func eachRowReadsTheSetOppositeItFromLastSession() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(kg: 80, reps: 8), Past(kg: 82.5, reps: 7), Past(kg: 85, reps: 6)])
            let (rows, workout) = today(bench, rows: 3, history: [past])
            #expect(rows.map { workout.previousSet(for: $0)?.weightKg } == [80, 82.5, 85])
            #expect(rows.map { workout.previousSet(for: $0)?.reps } == [8, 7, 6])
        }
    }

    @Test func aRowBeyondLastSessionsSetsShowsNothingRatherThanBorrowing() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(kg: 80, reps: 8), Past(kg: 80, reps: 7)])
            let (rows, workout) = today(bench, rows: 4, history: [past])
            #expect(workout.previousSet(for: rows[1])?.reps == 7)
            #expect(workout.previousSet(for: rows[2]) == nil)
            #expect(workout.previousSet(for: rows[3]) == nil)
        }
    }

    @Test func fewerRowsTodayStillPairFromTheFirst() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(reps: 8), Past(reps: 7), Past(reps: 6)])
            let (rows, workout) = today(bench, rows: 2, history: [past])
            #expect(rows.map { workout.previousSet(for: $0)?.reps } == [8, 7])
        }
    }

    @Test func aDeletedMiddleRowLeavesTheRestPairedByPosition() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(reps: 8), Past(reps: 7), Past(reps: 6)])
            let (rows, workout) = today(bench, rows: 3, history: [past])
            bench.context.delete(rows[1])
            try bench.context.save()
            // Pairing is by position among the rows there are, the same as the
            // gain badge's, so the wrist and the phone cannot disagree.
            #expect(workout.previousSet(for: rows[0])?.reps == 8)
            #expect(workout.previousSet(for: rows[2])?.reps == 7)
        }
    }

    @Test func aDropUnderneathAHeavySetHasNoCounterpart() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(reps: 8), Past(reps: 7)])
            let (rows, workout) = today(bench, rows: 2, history: [past])
            rows[1].continuesPreviousSet = true
            #expect(workout.previousSet(for: rows[0])?.reps == 8)
            #expect(workout.previousSet(for: rows[1]) == nil)
        }
    }

    @Test func noHistoryMeansNoCounterpart() throws {
        try WorkoutBench.run { bench in
            let (rows, workout) = today(bench, rows: 2, history: [])
            #expect(rows.allSatisfy { workout.previousSet(for: $0) == nil })
        }
    }

    // MARK: Measured and unmeasured duration

    @Test func onlyAnAnnouncedStartGivesAMeasuredDuration() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(tookSeconds: 42), Past(tookSeconds: nil), Past(tookSeconds: 41.6)])
            let (rows, workout) = today(bench, rows: 3, history: [past])
            let recaps = rows.map { workout.previousSet(for: $0).map(LastSetRecap.init) }
            #expect(recaps[0]?.measuredSeconds == 42)
            #expect(recaps[1]?.measuredSeconds == nil, "no announced start, no duration")
            #expect(recaps[2]?.measuredSeconds == 42, "rounded to the second it is drawn in")
        }
    }

    @Test func aStartAfterTheLogIsNotADuration() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(tookSeconds: -30), Past(tookSeconds: 0)])
            let (rows, workout) = today(bench, rows: 2, history: [past])
            #expect(rows.allSatisfy { workout.previousSet(for: $0).map(LastSetRecap.init)?.measuredSeconds == nil })
        }
    }

    // MARK: Bodyweight and duration exercises

    @Test func aBodyweightSetReadsRepsAlone() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(kg: 0, reps: 12)], tracking: .bodyweightReps, catalogID: WorkoutBench.plank)
            let (rows, workout) = today(bench, rows: 1, history: [past], catalogID: WorkoutBench.plank,
                                        tracking: .bodyweightReps)
            let recap = try #require(workout.previousSet(for: rows[0]).map(LastSetRecap.init))
            #expect(recap.label(tracking: .bodyweightReps, scale: .standard(.kg)) == "12 reps")
        }
    }

    @Test func aDurationSetReadsItsTimeAndNeverAddsAnother() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(kg: 0, reps: 0, seconds: 45, tookSeconds: 45)], tracking: .duration,
                                catalogID: WorkoutBench.plank)
            let (rows, workout) = today(bench, rows: 1, history: [past], catalogID: WorkoutBench.plank,
                                        tracking: .duration)
            let recap = try #require(workout.previousSet(for: rows[0]).map(LastSetRecap.init))
            #expect(recap.label(tracking: .duration, scale: .standard(.kg)) == "45s")
        }
    }

    // MARK: The wrist's mirror

    @Test func theMirrorCarriesEachRowsCounterpartAndLeavesUnpairedRowsBare() throws {
        try WorkoutBench.run { bench in
            let past = lastWeek(bench, [Past(kg: 80, reps: 8, tookSeconds: 42), Past(kg: 80, reps: 7)])
            let (rows, workout) = today(bench, rows: 3, history: [past])
            let sets = try #require(workout.watchSnapshot.exercises.first).sets
            #expect(sets.map(\.id) == rows.map(\.id))
            #expect(sets[0].lastSession == LastSetRecap(weightKg: 80, reps: 8, seconds: 0, measuredSeconds: 42))
            #expect(sets[1].lastSession == LastSetRecap(weightKg: 80, reps: 7, seconds: 0, measuredSeconds: nil))
            #expect(sets[2].lastSession == nil)
        }
    }

    // MARK: Wording

    struct Wording: Sendable, CustomTestStringConvertible {
        var recap: LastSetRecap
        var tracking: WatchTracking
        var scale: LoadScale
        var expected: String
        var testDescription: String { expected }
    }

    private static let kg = LoadScale.standard(.kg)
    private static let lb = LoadScale(unit: .lb, increment: 5)

    private static let wordings: [Wording] = [
        .init(recap: .init(weightKg: 80, reps: 8, seconds: 0), tracking: .weightReps, scale: kg, expected: "80 × 8"),
        .init(recap: .init(weightKg: 82.5, reps: 6, seconds: 0), tracking: .weightReps, scale: kg, expected: "82.5 × 6"),
        .init(recap: .init(weightKg: 80, reps: 8, seconds: 0, measuredSeconds: 42), tracking: .weightReps,
              scale: kg, expected: "80 × 8 · 42s"),
        .init(recap: .init(weightKg: 80, reps: 8, seconds: 0, measuredSeconds: 75), tracking: .weightReps,
              scale: kg, expected: "80 × 8 · 1m 15s"),
        .init(recap: .init(weightKg: 80, reps: 8, seconds: 0, measuredSeconds: 60), tracking: .weightReps,
              scale: kg, expected: "80 × 8 · 1m 00s"),
        .init(recap: .init(weightKg: 80, reps: 8, seconds: 0, measuredSeconds: 0), tracking: .weightReps,
              scale: kg, expected: "80 × 8"),
        .init(recap: .init(weightKg: 100, reps: 5, seconds: 0), tracking: .weightReps, scale: lb, expected: "220 × 5"),
        .init(recap: .init(weightKg: 0, reps: 12, seconds: 0), tracking: .bodyweightReps, scale: kg,
              expected: "12 reps"),
        .init(recap: .init(weightKg: 0, reps: 12, seconds: 0, measuredSeconds: 30), tracking: .bodyweightReps,
              scale: kg, expected: "12 reps · 30s"),
        .init(recap: .init(weightKg: 0, reps: 10, seconds: 0), tracking: .weightReps, scale: kg, expected: "10 reps"),
        .init(recap: .init(weightKg: 0, reps: 0, seconds: 45), tracking: .duration, scale: kg, expected: "45s"),
        .init(recap: .init(weightKg: 0, reps: 0, seconds: 90, measuredSeconds: 90), tracking: .duration, scale: kg,
              expected: "1m 30s"),
    ]

    @Test(arguments: LastSessionRecapTests.wordings)
    func theLineIsWordedInTheExercisesOwnUnit(_ wording: Wording) {
        #expect(wording.recap.label(tracking: wording.tracking, scale: wording.scale) == wording.expected)
    }

    @Test(arguments: [(0, "0s"), (9, "9s"), (59, "59s"), (60, "1m 00s"), (125, "2m 05s"), (-3, "0s")])
    func secondsReadAsSecondsThenMinutes(_ seconds: Int, _ expected: String) {
        #expect(LastSetRecap.duration(seconds) == expected)
    }

    // MARK: The wrist's line

    private func wristExercise(label: String?, recap: LastSetRecap?) -> (WatchExerciseSnapshot, WatchSetSnapshot) {
        let set = WatchSetSnapshot(id: UUID(), index: 0, weightKg: 80, reps: 8, seconds: 0, targetRepsLow: 8,
                                   targetRepsHigh: 12, isCompleted: false, lastSession: recap)
        let exercise = WatchExerciseSnapshot(id: "x", name: "X", order: 0, tracking: .weightReps, restSeconds: 90,
                                             sets: [set], lastTimeLabel: label, scale: nil)
        return (exercise, set)
    }

    @Test func theWristPrefersTheSetsOwnLineAndFallsBackToTheExerciseLabel() {
        let own = LastSetRecap(weightKg: 80, reps: 8, seconds: 0, measuredSeconds: 42)
        let (withBoth, setWithBoth) = wristExercise(label: "85 × 6", recap: own)
        #expect(withBoth.lastTimeLine(for: setWithBoth, sessionUnit: .kg) == "last 80 × 8 · 42s")

        let (labelOnly, bare) = wristExercise(label: "85 × 6", recap: nil)
        #expect(labelOnly.lastTimeLine(for: bare, sessionUnit: .kg) == "last 85 × 6")
        #expect(labelOnly.lastTimeLine(for: nil, sessionUnit: .kg) == "last 85 × 6")

        let (nothing, none) = wristExercise(label: nil, recap: nil)
        #expect(nothing.lastTimeLine(for: none, sessionUnit: .kg) == nil)
    }

    @Test func theWristFormatsInTheSessionsUnitWhenTheExerciseHasNoScale() {
        let own = LastSetRecap(weightKg: 100, reps: 5, seconds: 0)
        let (exercise, set) = wristExercise(label: nil, recap: own)
        #expect(exercise.lastTimeLine(for: set, sessionUnit: .lb) == "last 220 × 5")
    }
}
