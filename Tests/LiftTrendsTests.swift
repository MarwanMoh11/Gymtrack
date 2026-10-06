import Foundation
import SwiftData

/// STATS-13: the Lifts card's tags. Run with scripts/test-lift-trends.sh; no
/// simulator is needed.
@main
struct LiftTrendsTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSinceReferenceDate: 780_000_000)

        struct Work {
            let id: String
            let kg: Double
            let reps: Int
            var drop = false
            var tracking: TrackingMode = .weightReps
            var seconds = 0
        }
        /// A finished session `daysAgo` before now, holding the given sets.
        func session(_ daysAgo: Int, _ work: [Work]) -> WorkoutSession {
            let start = now.addingTimeInterval(-Double(daysAgo) * 86_400)
            let session = WorkoutSession(title: "Test", startedAt: start)
            session.endedAt = start.addingTimeInterval(3_600)
            context.insert(session)
            for (index, item) in work.enumerated() {
                let set = SetLog(catalogID: item.id, exerciseName: item.id, exerciseOrder: 0, setIndex: index,
                                 weightKg: item.kg, reps: item.reps, seconds: item.seconds, tracking: item.tracking)
                set.isCompleted = true
                set.completedAt = start.addingTimeInterval(Double(index + 1) * 60)
                if item.drop { set.continuesPreviousSet = true }
                set.session = session
                context.insert(set)
            }
            return session
        }
        /// One lift trained every `gap` days for as many sessions as loads, oldest first.
        func series(_ id: String, loads: [Double], reps: Int = 5, gap: Int = 7, newest: Int = 0) -> [WorkoutSession] {
            loads.enumerated().map { index, kg in
                session(newest + (loads.count - 1 - index) * gap, [Work(id: id, kg: kg, reps: reps)])
            }
        }
        func trends(_ sessions: [WorkoutSession], limit: Int = LiftTrends.maximumRows) -> [LiftTrends.Lift] {
            LiftTrends.lifts(in: sessions, now: now, calendar: calendar, incrementKg: { _ in 2.5 }, limit: limit)
        }
        func trend(_ id: String, _ sessions: [WorkoutSession]) -> LiftTrends.Trend? {
            trends(sessions).first { $0.catalogID == id }?.trend
        }

        precondition(trend("bench", series("bench", loads: [60, 60, 62.5, 65, 67.5, 70])) == .moving,
                     "A lift climbing by several rungs is moving")
        precondition(trend("squat", series("squat", loads: [100, 100, 100, 100, 100])) == .flat,
                     "A lift held at one load is flat")
        precondition(trend("row", series("row", loads: [100, 100, 95, 90, 85])) == .sliding,
                     "A lift losing several rungs is sliding")

        // One rung is what a plate does to a good day, not progress. Two is.
        precondition(trend("ohp", series("ohp", loads: [100, 100, 102.5, 102.5])) == .flat,
                     "One rung of change must read as flat")
        precondition(trend("ohp", series("ohp", loads: [100, 100, 105, 105])) == .moving,
                     "Two rungs of change is progress")
        precondition(trend("ohp", series("ohp", loads: [100, 100, 97.5, 97.5])) == .flat,
                     "One rung down must read as flat, not sliding")
        precondition(trend("ohp", series("ohp", loads: [100, 100, 95, 95])) == .sliding,
                     "Two rungs down is a slide")

        // The rung is the exercise's own: a 5 kg machine is not moved by 2.5.
        let machine = series("press", loads: [100, 100, 105, 105])
        precondition(LiftTrends.lifts(in: machine, now: now, calendar: calendar, incrementKg: { _ in 5 })
                        .first?.trend == .flat, "One rung on a five-kilo stack must read as flat")

        // Too little history gets no tag at all.
        precondition(trends(series("few", loads: [60, 70, 80])).isEmpty, "Three sessions are not a trend")
        let stale = series("stale", loads: [60, 60, 80, 80], gap: 30)
        precondition(trends(stale).isEmpty, "Sessions older than the window do not count towards the four")
        let crammed = series("block", loads: [60, 62.5, 65, 67.5], gap: 3)
        precondition(trends(crammed).isEmpty, "Four sessions in nine days are a block, not a trend")
        precondition(trends([]).isEmpty)

        // A drop's rows are lifted pre-fatigued and are not the lift.
        let held: [Double] = [100, 100, 100, 100, 100]
        let withDrops = held.enumerated().map { index, kg in
            session((held.count - 1 - index) * 7, [
                Work(id: "curl", kg: kg, reps: 5),
                Work(id: "curl", kg: index >= 3 ? 130 : 60, reps: 5, drop: true),
            ])
        }
        precondition(trend("curl", withDrops) == .flat, "Continuation rows must not count as the best set")

        // Nothing to compare: no load, or no reps to estimate from.
        let bodyweight = (0..<6).map { session($0 * 7, [Work(id: "pullup", kg: 0, reps: 10 + (5 - $0), tracking: .bodyweightReps)]) }
        let timed = (0..<6).map { session($0 * 7, [Work(id: "plank", kg: 0, reps: 0, tracking: .duration, seconds: 30 + (5 - $0) * 5)]) }
        let unloaded = (0..<6).map { session($0 * 7, [Work(id: "dip", kg: 0, reps: 8)]) }
        precondition(trends(bodyweight + timed + unloaded).isEmpty, "Reps-only and timed work is never tagged")

        // An unfinished session is not history yet.
        var active = series("live", loads: [60, 60, 60])
        let live = session(1, [Work(id: "live", kg: 90, reps: 5)])
        live.endedAt = nil
        active.append(live)
        precondition(trends(active).isEmpty, "The session in progress must not make a fourth session")

        // Most recently trained first, and only a handful of rows.
        var many: [WorkoutSession] = []
        for n in 0..<7 {
            many += series("lift\(n)", loads: [60, 60, 70, 70], newest: n)
        }
        let listed = trends(many)
        precondition(listed.count == LiftTrends.maximumRows, "The card is capped at \(LiftTrends.maximumRows) rows")
        precondition(listed.map(\.catalogID) == (0..<LiftTrends.maximumRows).map { "lift\($0)" },
                     "Rows run from the most recently trained")
        precondition(trends(many, limit: 2).count == 2 && trends(many, limit: 0).isEmpty)

        print("Lift trends tests passed")
    }
}
