import Foundation
import SwiftData

/// STATS-12: what the other stats scripts leave uncovered. Every branch of the
/// progression's advice, the streak's grace day and gaps, and calendars whose
/// zone is nowhere near the machine's, Monday-first and Sunday-first. Run with
/// scripts/test-stats-gaps.sh; no simulator is needed.
@main
struct StatsGapTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        suggestions(context)
        streaks(context)
        weeks(context)
        print("Stats gap tests passed")
    }

    // MARK: - Suggestion

    @MainActor static func suggestions(_ context: ModelContext) {
        let item = PlanItem(catalogID: "gap-test", name: "Press", order: 0,
                            targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
        context.insert(item)
        let scale = item.loadScale
        let increment = scale.incrementKg

        func sets(_ work: [(Double, Int)], feel: SetFeel? = nil, seconds: Int = 0,
                  tracking: TrackingMode = .weightReps) -> [SetLog] {
            work.enumerated().map { index, pair in
                let set = SetLog(catalogID: "gap-test", exerciseName: "Press", exerciseOrder: 0, setIndex: index,
                                 weightKg: pair.0, reps: pair.1, seconds: seconds,
                                 targetRepsLow: 8, targetRepsHigh: 12, tracking: tracking)
                set.isCompleted = true
                set.rpe = feel.map { Double($0.rawValue) }
                return set
            }
        }
        func advice(_ work: [(Double, Int)], feel: SetFeel? = nil, for item: PlanItem = item) -> TrainingStats.OverloadSuggestion {
            TrainingStats.suggestion(for: item, lastSets: sets(work, feel: feel))
        }
        let three = { (kg: Double, reps: Int) in [(kg, reps), (kg, reps), (kg, reps)] }

        let first = TrainingStats.suggestion(for: item, lastSets: [])
        precondition(first.action == .firstTime && first.reps == item.targetRepsLow,
                     "No history is a baseline, not advice")

        let timed = PlanItem(catalogID: "gap-hold", name: "Hold", order: 0, targetSets: 3,
                             targetRepsLow: 0, targetRepsHigh: 0)
        timed.trackingRaw = TrackingMode.duration.rawValue
        context.insert(timed)
        let hold = TrainingStats.suggestion(for: timed, lastSets: sets([(0, 0)], seconds: 40, tracking: .duration))
        precondition(hold.action == .addReps && hold.message.contains("45s"), "A hold asks for five more seconds")

        // Cleared: one rung by default, two when it was easy, and never a
        // question left unasked of the answer.
        let solid = advice(three(60, 12))
        let easy = advice(three(60, 12), feel: .easy)
        let hard = advice(three(60, 12), feel: .hard)
        let allOut = advice(three(60, 12), feel: .allOut)
        let oneRung = scale.step(kg: 60, by: 1)
        precondition(solid.action == .increaseWeight && solid.weightKg == oneRung, "A cleared session climbs one rung")
        precondition(hard.weightKg == oneRung && allOut.weightKg == oneRung, "A hard clear still climbs one rung")
        precondition(easy.weightKg == scale.step(kg: oneRung, by: 1) && easy.weightKg > solid.weightKg,
                     "An easy clear climbs two rungs")
        precondition(Set([solid.message, easy.message, hard.message, allOut.message]).count == 4,
                     "Each answer to how it felt changes the advice")

        // Inside the range: chase one more rep, capped at the top.
        let inRange = advice(three(60, 9))
        precondition(inRange.action == .addReps && inRange.weightKg == 60 && inRange.reps == 10,
                     "Inside the range the goal is one more rep at the same load")
        precondition(advice(three(60, 11)).reps == 12 && advice(three(60, 11), feel: .hard).reps == 12,
                     "The goal never passes the top of the range")
        precondition(advice(three(60, 9), feel: .easy).action == .addReps
                     && advice(three(60, 9), feel: .allOut).action == .addReps)

        // Well under the range: the load is what stopped the lifter, unless
        // they said it was not.
        let short = three(60, 4)
        precondition(advice(short).action == .deload && advice(short).weightKg == scale.step(kg: 60, by: -1),
                     "Short reps with no answer take a rung off")
        precondition(advice(short, feel: .hard).action == .deload && advice(short, feel: .allOut).action == .deload)
        precondition(advice(short, feel: .easy).action == .repeatLoad && advice(short, feel: .easy).weightKg == 60,
                     "Short reps that felt easy were not stopped by the load")
        precondition(advice(short, feel: .solid).action == .repeatLoad, "Short reps at a solid effort hold the load")
        precondition(advice(three(increment, 4), feel: .hard).action != .deload,
                     "There is no rung below the lightest one to deload to")

        // Unloaded work climbs in reps, and never invents a load.
        let bodyweight = advice(three(0, 12))
        precondition(bodyweight.action == .addReps && bodyweight.weightKg == 0 && bodyweight.reps == 13)
        precondition(advice(three(0, 12), feel: .easy).reps == 15, "An easy unloaded clear jumps three reps")
        precondition(advice(three(0, 5)).action == .addReps && advice(three(0, 5)).weightKg == 0)

        // The load is read from the heaviest weight, and prescribed on the ladder.
        let mixed = advice([(60, 12), (60, 12), (60, 12), (40, 12)])
        precondition(mixed.action == .increaseWeight, "A lighter back-off set does not hide a cleared load")
        let offLadder = advice(three(60 + increment / 4, 9))
        precondition(offLadder.weightKg == scale.snap(kg: 60 + increment / 4),
                     "The prescribed load is a rung the equipment has")
    }

    // MARK: - Non-local calendars

    /// A calendar in a zone far from the machine's. Kiritimati is UTC+14 and
    /// Pago Pago UTC-11, 25 hours apart, so at least one of them is a different
    /// calendar day from wherever this runs, at any hour.
    static func calendar(_ zone: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static let farZones = ["Pacific/Kiritimati", "Pacific/Pago_Pago"]

    @MainActor static func finished(_ start: Date, _ context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: "Gap test", startedAt: start)
        session.endedAt = start.addingTimeInterval(1_800)
        context.insert(session)
        let set = SetLog(catalogID: "gap-test", exerciseName: "Press", exerciseOrder: 0, setIndex: 0,
                         weightKg: 60, reps: 8, tracking: .weightReps)
        set.isCompleted = true
        set.completedAt = start.addingTimeInterval(60)
        set.session = session
        context.insert(set)
        return session
    }

    // MARK: - Streak

    @MainActor static func streaks(_ context: ModelContext) {
        for zone in farZones {
            for firstWeekday in [1, 2] {
                let cal = calendar(zone, firstWeekday: firstWeekday)
                let label = "\(zone), weekday \(firstWeekday)"
                func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
                    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
                }
                func run(_ days: [Int], hour: Int = 12) -> [WorkoutSession] {
                    days.map { finished(at($0, hour), context) }
                }
                let now = at(20, 9)

                var streak = TrainingStats.streak(from: run([18, 19, 20]), calendar: cal, now: now)
                precondition(streak.current == 3 && streak.longest == 3, "Three days running: \(label)")

                streak = TrainingStats.streak(from: run([18, 19]), calendar: cal, now: now)
                precondition(streak.current == 2, "Today not trained yet keeps yesterday's streak: \(label)")

                streak = TrainingStats.streak(from: run([17, 18]), calendar: cal, now: now)
                precondition(streak.current == 0 && streak.longest == 2,
                             "A missed day ends the current streak and keeps the best: \(label)")

                streak = TrainingStats.streak(from: run([12, 13, 14, 18, 19]), calendar: cal, now: now)
                precondition(streak.current == 2 && streak.longest == 3, "The best run is not the current one: \(label)")

                precondition(TrainingStats.streak(from: [], calendar: cal, now: now).current == 0)

                // A minute either side of midnight is two days, not one.
                let midnight = [finished(at(19, 23, 59), context), finished(at(20, 0, 1), context)]
                streak = TrainingStats.streak(from: midnight, calendar: cal, now: now)
                precondition(streak.current == 2, "Either side of local midnight are two days: \(label)")

                // Two sessions on one local day are one day.
                let sameDay = [finished(at(20, 0, 30), context), finished(at(20, 23, 30), context)]
                streak = TrainingStats.streak(from: sameDay, calendar: cal, now: at(20, 23, 45))
                precondition(streak.current == 1 && streak.longest == 1, "One local day is one day: \(label)")
            }
        }

        // The day is the calendar's, not UTC's: these sessions are a day apart
        // in UTC and two days apart in Kiritimati.
        let kiritimati = calendar("Pacific/Kiritimati", firstWeekday: 2)
        let utc = calendar("UTC", firstWeekday: 2)
        let early = finished(kiritimati.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 0, minute: 30))!, context)
        let late = finished(kiritimati.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 23, minute: 30))!, context)
        let now = kiritimati.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        let local = TrainingStats.streak(from: [early, late], calendar: kiritimati, now: now)
        let inUTC = TrainingStats.streak(from: [early, late], calendar: utc, now: now)
        precondition(local.current == 1 && local.longest == 1, "A skipped local day must split the streak")
        precondition(inUTC.longest == 2, "The scenario is only a test if UTC would have got it wrong")
    }

    // MARK: - Week

    @MainActor static func weeks(_ context: ModelContext) {
        for zone in farZones {
            // Sunday 8 March 2026. A Monday-first week holds the Wednesday and
            // Saturday before it and stops at the Sunday's midnight, so Monday's
            // 1 am is next week's; a Sunday-first week has only just begun and
            // holds the Sunday and that Monday. The session on 1 March is in
            // neither.
            for (firstWeekday, expected, name) in [(2, 3, "Monday-first"), (1, 2, "Sunday-first")] {
                let cal = calendar(zone, firstWeekday: firstWeekday)
                func at(_ day: Int, _ hour: Int) -> Date {
                    cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
                }
                let now = at(8, 10)
                precondition(cal.component(.weekday, from: now) == 1, "The fixture day must be a Sunday")
                let sessions = [finished(at(4, 12), context), finished(at(7, 12), context),
                                finished(at(8, 9), context), finished(at(1, 12), context),
                                finished(at(9, 1), context)]
                let week = TrainingStats.sessionsThisWeek(sessions, calendar: cal, now: now)
                precondition(week.count == expected, "\(name) week in \(zone) held \(week.count), not \(expected)")

                let interval = TrainingStats.weekInterval(containing: now, calendar: cal)
                precondition(cal.component(.weekday, from: interval.start) == firstWeekday
                             && cal.component(.hour, from: interval.start) == 0,
                             "\(name) week in \(zone) must open at local midnight on its first weekday")
            }
        }
    }
}
