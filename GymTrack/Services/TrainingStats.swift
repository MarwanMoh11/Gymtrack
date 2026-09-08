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

    /// A streak counts consecutive *calendar days* with at least one finished
    /// session. Today not being trained yet doesn't break the streak — the
    /// streak only dies once yesterday is also missed.
    static func streak(from sessions: [WorkoutSession], calendar: Calendar = .current) -> Streak {
        let days = Set(sessions.filter { !$0.isActive }.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return Streak(current: 0, longest: 0) }

        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for i in 1..<max(sorted.count, 1) where sorted.count > 1 {
            let gap = calendar.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            run = gap == 1 ? run + 1 : 1
            longest = max(longest, run)
        }

        // Walk backwards from today (or yesterday) while days are present.
        let today = calendar.startOfDay(for: .now)
        var cursor = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        var current = 0
        while days.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }

        return Streak(current: current, longest: max(longest, current))
    }

    // MARK: - Volume

    static func sessions(in sessions: [WorkoutSession], days: Int, calendar: Calendar = .current) -> [WorkoutSession] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) else { return [] }
        return sessions.filter { !$0.isActive && $0.startedAt >= cutoff }
    }

    /// Hard sets per muscle over a window. A set credits its exercise's first
    /// two muscles — direct work counts fully, the secondary at half.
    static func setsPerMuscle(_ sessions: [WorkoutSession]) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for session in sessions {
            for set in session.completedSets where !set.isWarmup {
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

    /// Volume per calendar day over the last `days` days, oldest first.
    static func dailyVolume(_ sessions: [WorkoutSession], days: Int, calendar: Calendar = .current) -> [(date: Date, volume: Double)] {
        let today = calendar.startOfDay(for: .now)
        var buckets: [Date: Double] = [:]
        for session in sessions where !session.isActive {
            let day = calendar.startOfDay(for: session.startedAt)
            buckets[day, default: 0] += session.totalVolumeKg
        }
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, buckets[date] ?? 0)
        }
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
        sessions
            .filter { !$0.isActive }
            .compactMap { session -> ExerciseSessionSummary? in
                let sets = session.completedSets
                    .filter { $0.catalogID == catalogID && !$0.isWarmup }
                    .sorted { $0.setIndex < $1.setIndex }
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
                    bestEstimatedOneRepMax: sets.map(\.estimatedOneRepMax).max() ?? 0,
                    totalReps: sets.reduce(0) { $0 + $1.reps }
                )
            }
            .sorted { $0.date > $1.date }
    }

    /// The most recent completed sets for an exercise, used to prefill the
    /// logger and to show "last time" next to each set.
    static func lastPerformance(of catalogID: String,
                                in sessions: [WorkoutSession],
                                excluding sessionID: UUID? = nil) -> [SetLog] {
        let candidates = sessions
            .filter { $0.id != sessionID && !$0.isActive }
            .sorted { $0.startedAt > $1.startedAt }
        for session in candidates {
            let sets = session.completedSets
                .filter { $0.catalogID == catalogID && !$0.isWarmup }
                .sorted { $0.setIndex < $1.setIndex }
            if !sets.isEmpty { return sets }
        }
        return []
    }

    // MARK: - Records

    struct PersonalRecord: Identifiable {
        let catalogID: String
        let exerciseName: String
        let heaviestKg: Double
        let bestReps: Int
        let bestEstimatedOneRepMax: Double
        let bestVolumeKg: Double
        let achievedAt: Date
        var id: String { catalogID }
    }

    static func records(in sessions: [WorkoutSession]) -> [PersonalRecord] {
        var byExercise: [String: [SetLog]] = [:]
        for session in sessions where !session.isActive {
            for set in session.completedSets where !set.isWarmup {
                byExercise[set.catalogID, default: []].append(set)
            }
        }

        return byExercise.compactMap { catalogID, sets in
            guard let bestE1RM = sets.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) else { return nil }
            let heaviest = sets.map(\.weightKg).max() ?? 0
            let bestReps = sets.filter { $0.weightKg == heaviest }.map(\.reps).max() ?? 0
            return PersonalRecord(
                catalogID: catalogID,
                exerciseName: sets.first?.exerciseName ?? catalogID,
                heaviestKg: heaviest,
                bestReps: bestReps,
                bestEstimatedOneRepMax: bestE1RM.estimatedOneRepMax,
                bestVolumeKg: sets.map(\.volumeKg).max() ?? 0,
                achievedAt: bestE1RM.completedAt ?? bestE1RM.session?.startedAt ?? .distantPast
            )
        }
        .sorted { $0.bestEstimatedOneRepMax > $1.bestEstimatedOneRepMax }
    }

    /// Whether `set` beats everything logged for that exercise before it.
    /// Compared on estimated 1RM so heavier-for-fewer and lighter-for-more are
    /// both recognised.
    ///
    /// The first set of an exercise you've never done is not a record — with no
    /// baseline there's nothing to beat, and celebrating it would fire on every
    /// new movement.
    static func isPersonalRecord(_ set: SetLog, in sessions: [WorkoutSession]) -> Bool {
        guard set.isCompleted, !set.isWarmup else { return false }

        let previous = allSets(for: set.catalogID, in: sessions, before: set)
        guard !previous.isEmpty else { return false }

        switch set.tracking {
        case .duration:
            let best = previous.map(\.seconds).max() ?? 0
            return set.seconds > best && set.seconds > 0
        case .weightReps, .bodyweightReps:
            if set.tracking == .bodyweightReps && set.weightKg == 0 {
                let best = previous.filter { $0.weightKg == 0 }.map(\.reps).max() ?? 0
                return set.reps > best && set.reps > 0
            }
            let best = previous.map(\.estimatedOneRepMax).max() ?? 0
            return set.estimatedOneRepMax > best && set.estimatedOneRepMax > 0
        }
    }

    private static func allSets(for catalogID: String,
                                in sessions: [WorkoutSession],
                                before set: SetLog) -> [SetLog] {
        let boundary = set.completedAt ?? .now
        return sessions.flatMap(\.sets).filter {
            $0.catalogID == catalogID
            && $0.isCompleted
            && !$0.isWarmup
            && $0.id != set.id
            && (($0.completedAt ?? .distantPast) < boundary)
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

    /// Double progression: work up the rep range at a fixed load, then add
    /// weight and drop back to the bottom of the range.
    static func suggestion(for item: PlanItem, lastSets: [SetLog]) -> OverloadSuggestion {
        let increment = weightIncrement(for: item)

        guard !lastSets.isEmpty else {
            return OverloadSuggestion(
                action: .firstTime,
                weightKg: item.targetWeightKg,
                reps: item.targetRepsLow,
                message: "First time logging this — set a baseline you can repeat."
            )
        }

        let workingWeight = lastSets.map(\.weightKg).max() ?? item.targetWeightKg
        let setsAtWeight = lastSets.filter { $0.weightKg == workingWeight }
        let allHitTop = !setsAtWeight.isEmpty && setsAtWeight.allSatisfy { $0.reps >= item.targetRepsHigh }
        let minReps = setsAtWeight.map(\.reps).min() ?? 0

        if item.tracking == .duration {
            let best = lastSets.map(\.seconds).max() ?? item.targetSeconds
            return OverloadSuggestion(
                action: .addReps, weightKg: 0, reps: 0,
                message: "Last time you held \(best)s. Aim for \(best + 5)s."
            )
        }

        // Unloaded bodyweight work has no weight to add — the progression is
        // reps, then eventually a belt or a vest.
        let isUnloadedBodyweight = item.tracking == .bodyweightReps && workingWeight == 0

        if allHitTop {
            if isUnloadedBodyweight {
                return OverloadSuggestion(
                    action: .addReps, weightKg: 0, reps: item.targetRepsHigh + 1,
                    message: "You cleared \(item.targetRepsHigh) reps on every set. Push past it, or start adding weight."
                )
            }
            return OverloadSuggestion(
                action: .increaseWeight,
                weightKg: workingWeight + increment,
                reps: item.targetRepsLow,
                message: "You cleared \(item.targetRepsHigh) reps on every set. Add \(AppSettings.shared.weight(increment)) and reset to \(item.targetRepsLow) reps."
            )
        }

        if minReps < item.targetRepsLow - 2 && workingWeight > increment && !isUnloadedBodyweight {
            return OverloadSuggestion(
                action: .deload,
                weightKg: max(0, workingWeight - increment),
                reps: item.targetRepsLow,
                message: "Reps fell below the range last time. Back off to \(AppSettings.shared.weight(max(0, workingWeight - increment))) and rebuild."
            )
        }

        let goal = min(item.targetRepsHigh, minReps + 1)
        return OverloadSuggestion(
            action: .addReps,
            weightKg: workingWeight,
            reps: goal,
            message: isUnloadedBodyweight
                ? "Chase \(goal) reps on every set."
                : "Stay at \(AppSettings.shared.weight(workingWeight)) and chase \(goal) reps on every set."
        )
    }

    /// Smallest jump that's actually loadable for the equipment in question.
    static func weightIncrement(for item: PlanItem) -> Double {
        guard let equipment = item.catalog?.equipment else { return 2.5 }
        if equipment.contains("Dumbbell") || equipment.contains("Kettlebell") { return 2.0 }
        if equipment.contains("Cable") || equipment.contains("Machine") { return 2.5 }
        if equipment.contains("Band") { return 1.0 }
        return 2.5   // barbell: 1.25 kg plates a side
    }
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
            case .volume: AppSettings.shared.weightUnit.fromKg(session.totalVolumeKg)
            case .sets: Double(session.completedSets.count)
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
                      calendar: Calendar = .current) -> [DayPoint] {
        let today = calendar.startOfDay(for: .now)
        var buckets: [Date: Double] = [:]
        for session in sessions where !session.isActive {
            buckets[calendar.startOfDay(for: session.startedAt), default: 0] += metric.value(of: session)
        }
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
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
                               calendar: Calendar = .current) -> [WorkoutSession] {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days * 2, to: today),
              let end = calendar.date(byAdding: .day, value: -days, to: today)
        else { return [] }
        return sessions.filter { !$0.isActive && $0.startedAt >= start && $0.startedAt < end }
    }

    /// Percentage change, or nil when there is no baseline to compare against.
    static func change(from previous: Double, to current: Double) -> Double? {
        guard previous > 0 else { return nil }
        return (current - previous) / previous
    }

    static func total(_ metric: Metric, _ sessions: [WorkoutSession]) -> Double {
        sessions.reduce(0) { $0 + metric.value(of: $1) }
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

    static func lastTrained(_ muscle: Muscle, in sessions: [WorkoutSession]) -> Date? {
        sessions
            .filter { session in
                session.completedSets.contains { set in
                    guard let exercise = ExerciseCatalog.shared.exercise(id: set.catalogID) else { return false }
                    return !set.isWarmup && exercise.muscles.prefix(2).contains(muscle)
                }
            }
            .map(\.startedAt)
            .max()
    }

    /// Which movements are actually feeding a muscle, heaviest contributor
    /// first — the answer to "why is this still cold?".
    static func topExercises(for muscle: Muscle,
                             in sessions: [WorkoutSession],
                             limit: Int = 3) -> [(name: String, sets: Double)] {
        var tally: [String: Double] = [:]
        for session in sessions {
            for set in session.completedSets where !set.isWarmup {
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
