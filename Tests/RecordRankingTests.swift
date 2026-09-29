import Foundation
import SwiftData

/// STATS-08, LOG-07 and LOG-13: which set holds a record, and how the session
/// summary picks and prints the ones set today. Run with
/// scripts/test-record-ranking.sh; no simulator is needed.
@main
struct RecordRankingTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let day0 = Date(timeIntervalSinceReferenceDate: 700_000_000)
        func day(_ n: Int) -> Date { day0.addingTimeInterval(Double(n) * 86_400) }

        func set(_ id: String, _ name: String, kg: Double = 0, reps: Int = 0, seconds: Int = 0,
                 order: Int = 0, index: Int = 0, tracking: TrackingMode = .weightReps) -> SetLog {
            SetLog(catalogID: id, exerciseName: name, exerciseOrder: order, setIndex: index,
                   weightKg: kg, reps: reps, seconds: seconds, tracking: tracking)
        }
        /// Each set is stamped a minute after the last, so a session's sets have an order.
        func finished(on date: Date, _ sets: [SetLog]) -> WorkoutSession {
            let session = WorkoutSession(title: "Test", startedAt: date)
            session.endedAt = date.addingTimeInterval(3_600)
            context.insert(session)
            for (offset, set) in sets.enumerated() {
                set.isCompleted = true
                set.completedAt = date.addingTimeInterval(Double(offset + 1) * 60)
                set.session = session
                context.insert(set)
            }
            return session
        }
        func record(_ id: String, in records: [TrainingStats.PersonalRecord], kind: String? = nil) -> TrainingStats.PersonalRecord? {
            records.first { $0.catalogID == id && (kind == nil || $0.measure.kindName == kind) }
        }
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.01 }

        // STATS-08: a tie keeps the date the figure was first reached, in
        // whichever order the history arrives.
        let firstBench = set("bench", "Bench Press", kg: 100, reps: 5)
        let repeatBench = set("bench", "Bench Press", kg: 100, reps: 5)
        let tieOld = finished(on: day(0), [firstBench])
        let tieNew = finished(on: day(60), [repeatBench])
        for history in [[tieOld, tieNew], [tieNew, tieOld]] {
            guard let bench = record("bench", in: TrainingStats.records(in: history)) else {
                preconditionFailure("The tied bench record vanished")
            }
            precondition(bench.achievedAt == firstBench.completedAt,
                         "A later tie must not move the record's date")
        }
        precondition(!TrainingStats.isPersonalRecord(repeatBench, among: [firstBench, repeatBench]),
                     "The card and the logger must agree that a tie is not a record")

        // STATS-08: reps past the cap add nothing to the estimate.
        let heavyFive = set("squat", "Squat", kg: 100, reps: 5)
        let lightThirty = set("squat", "Squat", kg: 60, reps: 30)
        precondition(close(lightThirty.estimatedOneRepMax, 120), "The uncapped Epley figure this guards against")
        let squatHistory = [finished(on: day(0), [heavyFive]), finished(on: day(1), [lightThirty])]
        guard let squat = record("squat", in: TrainingStats.records(in: squatHistory)),
              case let .weight(squatKg, squatReps, squatEstimate) = squat.measure else {
            preconditionFailure("Squat record missing")
        }
        precondition(squatKg == 100 && squatReps == 5 && squatEstimate.map({ close($0, 116.67) }) == true,
                     "60 kg x 30 must not outrank 100 kg x 5")
        precondition(squat.achievedAt == heavyFive.completedAt)
        precondition(!TrainingStats.isPersonalRecord(lightThirty, among: [heavyFive, lightThirty]),
                     "The logger must not award a trophy for the light long set")
        let cap = TrainingStats.oneRepMaxRepCap
        guard let atCap = TrainingStats.standing(of: set("x", "X", kg: 50, reps: cap)),
              let pastCap = TrainingStats.standing(of: set("x", "X", kg: 50, reps: cap + 1)) else {
            preconditionFailure("Standing missing")
        }
        precondition(atCap.score.value == pastCap.score.value && atCap.score < pastCap.score,
                     "Past the cap the estimate stops rising, and only breaks a tie")

        // A long set is still a record against other long sets: more reps at
        // the same load, or a heavier load for as many.
        func logged(_ set: SetLog, day n: Int) -> SetLog {
            set.isCompleted = true
            set.completedAt = day(n)
            return set
        }
        let raise15 = logged(set("lateral-raise", "Lateral Raise", kg: 12, reps: 15), day: 0)
        let raise20 = logged(set("lateral-raise", "Lateral Raise", kg: 12, reps: 20), day: 1)
        let raiseLight = logged(set("lateral-raise", "Lateral Raise", kg: 10, reps: 40), day: 2)
        let raiseHeavy = logged(set("lateral-raise", "Lateral Raise", kg: 14, reps: 15), day: 3)
        precondition(TrainingStats.isPersonalRecord(raise20, among: [raise15, raise20]))
        precondition(!TrainingStats.isPersonalRecord(raiseLight, among: [raise15, raise20, raiseLight]),
                     "A lighter load for many more reps is not a heavier lift")
        precondition(TrainingStats.isPersonalRecord(raiseHeavy, among: [raise15, raise20, raiseHeavy]))
        let raiseHistory = [finished(on: day(0), [set("lateral-raise", "Lateral Raise", kg: 12, reps: 15)]),
                            finished(on: day(1), [set("lateral-raise", "Lateral Raise", kg: 12, reps: 20)])]
        let raiseRecords = TrainingStats.records(in: raiseHistory)
        guard let raise = record("lateral-raise", in: raiseRecords),
              case .weight(12, 20, nil) = raise.measure else {
            preconditionFailure("A set past the cap shows its load and reps, and no estimate")
        }
        precondition(raise.achievedAt == raiseHistory[1].sets.first?.completedAt)

        // STATS-08: the load, the estimate and the date are one set.
        let single = set("press", "Overhead Press", kg: 105, reps: 1)
        let five = set("press", "Overhead Press", kg: 100, reps: 5)
        let pressHistory = [finished(on: day(0), [single]), finished(on: day(9), [five])]
        guard let press = record("press", in: TrainingStats.records(in: pressHistory)),
              case let .weight(pressKg, pressReps, pressEstimate) = press.measure else {
            preconditionFailure("Press record missing")
        }
        precondition(pressKg == 100 && pressReps == 5 && pressEstimate.map({ close($0, 116.67) }) == true,
                     "The row must show the set the estimate came from, not the heaviest set")
        precondition(press.achievedAt == five.completedAt)

        // STATS-08: unloaded reps and added load are separate records.
        let unloaded = set("pull-up", "Pull-up", reps: 12, tracking: .bodyweightReps)
        let weighted = set("pull-up", "Pull-up", kg: 10, reps: 8, tracking: .bodyweightReps)
        let dipOnly = set("dip", "Dip", kg: 20, reps: 5, tracking: .bodyweightReps)
        let bodyweightRecords = TrainingStats.records(in: [finished(on: day(0), [unloaded]),
                                                           finished(on: day(5), [weighted, dipOnly])])
        guard let pullReps = record("pull-up", in: bodyweightRecords, kind: "reps"),
              case .reps(12) = pullReps.measure,
              let pullAdded = record("pull-up", in: bodyweightRecords, kind: "added"),
              case .addedLoad(kg: 10, reps: 8) = pullAdded.measure else {
            preconditionFailure("Pull-ups must hold an unloaded record and an added-load record")
        }
        precondition(pullReps.achievedAt == unloaded.completedAt && pullAdded.achievedAt == weighted.completedAt)
        precondition(pullReps.id != pullAdded.id)
        precondition(record("dip", in: bodyweightRecords, kind: "reps") == nil,
                     "Weighted reps must not stand in for an unloaded record")

        // LOG-07: the summary ranks and prints each record by its own kind.
        let plank60 = set("plank", "Plank", seconds: 60, order: 1, index: 0, tracking: .duration)
        let plank75 = set("plank", "Plank", seconds: 75, order: 1, index: 1, tracking: .duration)
        let reps12 = set("pull-up", "Pull-up", reps: 12, order: 2, index: 0, tracking: .bodyweightReps)
        let reps15 = set("pull-up", "Pull-up", reps: 15, order: 2, index: 1, tracking: .bodyweightReps)
        let added = set("pull-up", "Pull-up", kg: 10, reps: 5, order: 2, index: 2, tracking: .bodyweightReps)
        let lighter = set("bench", "Bench Press", kg: 110, reps: 1, order: 0, index: 1)
        let stronger = set("bench", "Bench Press", kg: 100, reps: 5, order: 0, index: 0)
        let long = set("bench", "Bench Press", kg: 60, reps: 30, order: 0, index: 2)
        let candidates = [plank60, plank75, reps12, reps15, added, lighter, stronger, long]
        for ordering in [candidates, candidates.reversed(), candidates.shuffled()] {
            let rows = TrainingStats.summaryRecords(from: Array(ordering))
            precondition(rows.map(\.id) == [stronger, plank75, reps15, added].map(\.id),
                         "One row per exercise and kind, the best of each, in session order: got \(rows.map(TrainingStats.setLabel))")
        }
        precondition(TrainingStats.setLabel(reps15) == "15 reps", "An unloaded set must not print a weight")
        precondition(TrainingStats.setLabel(set("x", "X", reps: 1, tracking: .bodyweightReps)) == "1 rep")
        precondition(TrainingStats.setLabel(plank75) == "75s")
        precondition(TrainingStats.setLabel(stronger) == "\(stronger.weightLabel) × 5")
        precondition(TrainingStats.setLabel(added) == "+\(added.weightLabel) × 5")
        precondition(!TrainingStats.setLabel(set("x", "X", reps: 10)).contains("kg"),
                     "A rep set with no load entered must not claim 0 kg")

        // Through the real path: two holds in one session, both beating the
        // prior best, list the longer one.
        let priorPlank = set("plank", "Plank", seconds: 50, tracking: .duration)
        let todayA = set("plank", "Plank", seconds: 60, index: 0, tracking: .duration)
        let todayB = set("plank", "Plank", seconds: 75, index: 1, tracking: .duration)
        let history = finished(on: day(1), [priorPlank])
        let today = finished(on: day(2), [todayA, todayB])
        let summary = TrainingStats.summaryRecords(for: today, history: [today, history])
        precondition(summary.map(\.id) == [todayB.id], "Today's plank record is the 75 s hold")

        // LOG-13: typing in the note does not change what the summary is keyed
        // on, so it does not recompute; a set appearing or leaving does.
        let before = TrainingStats.SummaryRecordsKey(today)
        today.notes = "Felt strong"
        today.notes = "Felt strong today, ate well"
        precondition(TrainingStats.SummaryRecordsKey(today) == before, "A note edit must not invalidate the records")
        todayB.isCompleted = false
        precondition(TrainingStats.SummaryRecordsKey(today) != before, "A change in the session's sets must")
        todayB.isCompleted = true
        precondition(TrainingStats.SummaryRecordsKey(today) == before)

        // The view keeps the answer in state and asks in `.task`; it must not
        // fetch the whole history as a query, which re-runs per save.
        let view = try String(contentsOfFile: "GymTrack/Features/Session/SessionSummaryView.swift", encoding: .utf8)
        precondition(!view.contains("@Query"), "The summary must not hold a live query over every session")
        precondition(view.contains(".task(id: recordsKey)") && view.contains("@State private var prs"))
        precondition(!view.contains("recordSets("), "The view must go through summaryRecords, once, in .task")

        print("Record ranking: tie date, rep cap, same-set rows, per-kind summary and once-per-change passed")
    }
}
