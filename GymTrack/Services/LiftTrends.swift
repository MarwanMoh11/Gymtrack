import Foundation

/// Which way each lift has been heading, read from sets that are already
/// logged. The result is drawn on the Progress tab and never stored or
/// exported, so a tag can only ever be as wrong as the arithmetic below, and
/// the arithmetic declines to answer whenever the history is too thin to carry
/// one.
///
/// A tag is a claim about strength, so it is made from the same figure the
/// records use, `TrainingStats.standing(of:)`: an Epley one-rep-max estimate,
/// capped at twelve reps. A second formula here would let a lift be a record in
/// one place and "sliding" in another.
enum LiftTrends {

    enum Trend: Equatable {
        case moving, flat, sliding
    }

    struct Lift: Identifiable, Equatable {
        let catalogID: String
        let name: String
        let trend: Trend
        /// The sessions the tag was read from.
        let sessionCount: Int
        let lastTrained: Date
        var id: String { catalogID }
    }

    /// How far back a trend looks. Long enough for several sessions of a lift
    /// trained weekly, short enough that a lift left alone since spring is not
    /// judged on the spring.
    static let windowWeeks = 8

    /// Fewer sessions than this and two "halves" are one or two sets each, which
    /// is a coin toss rather than a trend.
    static let minimumSessions = 4

    /// Four sessions in a week are a block, not a trend: the halves would differ
    /// by day-to-day tiredness. The oldest and newest session must be at least
    /// this far apart.
    static let minimumSpanDays = 14

    /// The card is a glance, not a list of everything ever lifted.
    static let maximumRows = 5

    /// One session's best effort at one lift.
    private struct Point {
        let date: Date
        let estimate: Double
        let reps: Int
    }

    /// Tags for the lifts with enough recent history, most recently trained
    /// first. `incrementKg` answers what one step on that exercise's equipment
    /// is worth, so a single rung of noise is never read as progress.
    ///
    /// Only weighted-rep lifts are read. Reps-only and timed work have no load
    /// to compare, and an unloaded set logged in the middle of a weighted
    /// exercise would drop out of the average and bias it; neither is worth a
    /// guess.
    static func lifts(in sessions: [WorkoutSession],
                      now: Date,
                      calendar: Calendar,
                      incrementKg: (String) -> Double,
                      limit: Int = maximumRows) -> [Lift] {
        guard let start = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: now) else { return [] }

        var points: [String: [Point]] = [:]
        var names: [String: (name: String, date: Date)] = [:]
        for session in sessions where !session.isActive && session.startedAt >= start && session.startedAt <= now {
            var best: [String: Point] = [:]
            // `effortSets` leaves out the rows of a drop: they are lifted
            // pre-fatigued and would read as a collapse.
            for set in session.effortSets where set.tracking == .weightReps {
                guard let standing = TrainingStats.standing(of: set), standing.kind == .load else { continue }
                let id = ExerciseCatalog.canonicalID(for: set.catalogID)
                let point = Point(date: session.startedAt, estimate: standing.score.value, reps: set.reps)
                if let held = best[id], held.estimate >= point.estimate { continue }
                best[id] = point
                if names[id].map({ $0.date <= session.startedAt }) ?? true {
                    names[id] = (set.exerciseName, session.startedAt)
                }
            }
            for (id, point) in best { points[id, default: []].append(point) }
        }

        var lifts: [Lift] = []
        for (id, series) in points {
            let ordered = series.sorted { $0.date < $1.date }
            guard ordered.count >= minimumSessions,
                  let first = ordered.first, let last = ordered.last,
                  calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0 >= minimumSpanDays
            else { continue }

            let half = ordered.count / 2
            let earlier = mean(ordered.prefix(half).map(\.estimate))
            let recent = mean(ordered.suffix(half).map(\.estimate))
            let change = recent - earlier

            // What one rung of load is worth in one-rep-max terms, at the reps
            // of the latest session, since the estimate grows with reps.
            let rung = incrementKg(id) * (1 + Double(min(last.reps, TrainingStats.oneRepMaxRepCap)) / 30.0)
            guard rung > 0, rung.isFinite else { continue }

            let trend: Trend = abs(change) <= rung + 1e-9 ? .flat : (change > 0 ? .moving : .sliding)
            lifts.append(Lift(catalogID: id, name: names[id]?.name ?? id, trend: trend,
                              sessionCount: ordered.count, lastTrained: last.date))
        }
        return lifts
            .sorted { $0.lastTrained != $1.lastTrained ? $0.lastTrained > $1.lastTrained : $0.name < $1.name }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
