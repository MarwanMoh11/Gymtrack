import Foundation
import SwiftData

// MARK: - Plan

@Model
final class Plan {

    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var isActive: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PlanDay.plan)
    var days: [PlanDay] = []

    init(name: String, summary: String = "", isActive: Bool = false) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.isActive = isActive
        self.createdAt = .now
    }

    /// Days in display order.
    var orderedDays: [PlanDay] { days.sorted { $0.order < $1.order } }

    var trainingDayCount: Int { days.filter { !$0.isRest }.count }

    /// The day scheduled for a given date, if any.
    func day(for date: Date) -> PlanDay? {
        let weekday = Calendar.current.component(.weekday, from: date)   // 1 = Sunday
        return orderedDays.first { $0.weekday == weekday && !$0.isRest }
    }
}

// MARK: - Plan day

@Model
final class PlanDay {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    /// 1 = Sunday … 7 = Saturday. `nil` means the day isn't pinned to a weekday.
    var weekday: Int?
    var isRest: Bool = false
    var notes: String = ""

    var plan: Plan?

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.day)
    var items: [PlanItem] = []

    init(name: String, order: Int, weekday: Int? = nil, isRest: Bool = false, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.order = order
        self.weekday = weekday
        self.isRest = isRest
        self.notes = notes
    }

    var orderedItems: [PlanItem] { items.sorted { $0.order < $1.order } }

    var totalSets: Int { items.reduce(0) { $0 + $1.targetSets } }

    var weekdayName: String? {
        guard let weekday else { return nil }
        return Calendar.current.weekdaySymbols[weekday - 1]
    }

    var weekdayShortName: String? {
        guard let weekday else { return nil }
        return Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    /// The muscles this day trains, ordered by how many sets hit each.
    var targetedMuscles: [Muscle] {
        var counts: [Muscle: Int] = [:]
        for item in items {
            guard let ex = ExerciseCatalog.shared.exercise(id: item.catalogID) else { continue }
            for muscle in ex.muscles.prefix(2) {
                counts[muscle, default: 0] += item.targetSets
            }
        }
        // Break ties by name so the pill order doesn't shuffle between renders.
        return counts
            .sorted { $0.value == $1.value ? $0.key.name < $1.key.name : $0.value > $1.value }
            .map(\.key)
    }
}

// MARK: - Plan item (an exercise slot inside a day)

@Model
final class PlanItem {
    var id: UUID = UUID()
    var catalogID: String = ""
    /// Denormalised so a plan still reads correctly if a custom exercise is deleted.
    var name: String = ""
    var order: Int = 0
    var targetSets: Int = 3
    var targetRepsLow: Int = 8
    var targetRepsHigh: Int = 12
    /// Always stored in kilograms; converted for display.
    var targetWeightKg: Double = 0
    /// Target hold/work time for duration-tracked exercises.
    var targetSeconds: Int = 45
    var restSeconds: Int = 90
    var notes: String = ""

    var day: PlanDay?

    init(catalogID: String,
         name: String,
         order: Int,
         targetSets: Int = 3,
         targetRepsLow: Int = 8,
         targetRepsHigh: Int = 12,
         targetWeightKg: Double = 0,
         targetSeconds: Int = 45,
         restSeconds: Int = 90) {
        self.id = UUID()
        self.catalogID = catalogID
        self.name = name
        self.order = order
        self.targetSets = targetSets
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.targetWeightKg = targetWeightKg
        self.targetSeconds = targetSeconds
        self.restSeconds = restSeconds
    }

    var catalog: CatalogExercise? { ExerciseCatalog.shared.exercise(id: catalogID) }
    var tracking: TrackingMode { catalog?.tracking ?? .weightReps }

    var repRangeLabel: String {
        targetRepsLow == targetRepsHigh ? "\(targetRepsLow)" : "\(targetRepsLow)–\(targetRepsHigh)"
    }
}

// MARK: - Session

@Model
final class WorkoutSession {

    var id: UUID = UUID()
    var title: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var notes: String = ""
    var planDayID: UUID?
    var planName: String = ""

    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var sets: [SetLog] = []

    init(title: String, planDayID: UUID? = nil, planName: String = "", startedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.planDayID = planDayID
        self.planName = planName
        self.startedAt = startedAt
    }

    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }

    var completedSets: [SetLog] { sets.filter(\.isCompleted) }

    var totalVolumeKg: Double {
        completedSets.reduce(0) { $0 + $1.volumeKg }
    }

    var totalReps: Int { completedSets.reduce(0) { $0 + $1.reps } }

    /// Exercises in the order they appear in the session.
    var exerciseGroups: [SessionExerciseGroup] {
        let grouped = Dictionary(grouping: sets) { $0.catalogID }
        return grouped.map { key, value in
            SessionExerciseGroup(
                catalogID: key,
                name: value.first?.exerciseName ?? key,
                order: value.map(\.exerciseOrder).min() ?? 0,
                sets: value.sorted { $0.setIndex < $1.setIndex }
            )
        }
        .sorted { $0.order < $1.order }
    }

    var day: String {
        startedAt.formatted(.dateTime.weekday(.wide))
    }
}

struct SessionExerciseGroup: Identifiable {
    let catalogID: String
    let name: String
    let order: Int
    let sets: [SetLog]

    var id: String { catalogID }
    var completedCount: Int { sets.filter(\.isCompleted).count }
    var isComplete: Bool { !sets.isEmpty && completedCount == sets.count }
    var catalog: CatalogExercise? { ExerciseCatalog.shared.exercise(id: catalogID) }
}

// MARK: - Set log

@Model
final class SetLog {

    var id: UUID = UUID()
    var catalogID: String = ""
    var exerciseName: String = ""
    /// Position of the parent exercise within the session.
    var exerciseOrder: Int = 0
    /// Position of this set within its exercise, 0-based.
    var setIndex: Int = 0

    var weightKg: Double = 0
    var reps: Int = 0
    var seconds: Int = 0
    var rpe: Double?

    var targetRepsLow: Int = 0
    var targetRepsHigh: Int = 0

    var isCompleted: Bool = false
    var isWarmup: Bool = false
    var completedAt: Date?

    var session: WorkoutSession?

    init(catalogID: String,
         exerciseName: String,
         exerciseOrder: Int,
         setIndex: Int,
         weightKg: Double = 0,
         reps: Int = 0,
         seconds: Int = 0,
         targetRepsLow: Int = 0,
         targetRepsHigh: Int = 0,
         isWarmup: Bool = false) {
        self.id = UUID()
        self.catalogID = catalogID
        self.exerciseName = exerciseName
        self.exerciseOrder = exerciseOrder
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
        self.seconds = seconds
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.isWarmup = isWarmup
    }

    var catalog: CatalogExercise? { ExerciseCatalog.shared.exercise(id: catalogID) }
    var tracking: TrackingMode { catalog?.tracking ?? .weightReps }

    /// Volume load. Bodyweight work counts reps only so it can't silently
    /// vanish from the totals.
    var volumeKg: Double {
        switch tracking {
        case .weightReps: weightKg * Double(reps)
        case .bodyweightReps: weightKg > 0 ? weightKg * Double(reps) : 0
        case .duration: 0
        }
    }

    /// Epley estimated 1-rep max — the comparable strength number across
    /// different rep schemes.
    var estimatedOneRepMax: Double {
        guard tracking != .duration, reps > 0, weightKg > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30.0)
    }

    var hitTopOfRange: Bool {
        targetRepsHigh > 0 && reps >= targetRepsHigh
    }
}

// MARK: - Custom exercise

@Model
final class CustomExerciseRecord {
    var id: String = ""
    var name: String = ""
    var category: String = "strength"
    var muscleRaw: [String] = []
    var equipment: [String] = []
    var trackingRaw: String = TrackingMode.weightReps.rawValue
    var createdAt: Date = Date()

    init(name: String, muscles: [Muscle], equipment: [String], tracking: TrackingMode) {
        self.id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        self.name = name
        self.muscleRaw = muscles.map(\.name)
        self.equipment = equipment
        self.trackingRaw = tracking.rawValue
        self.createdAt = .now
    }

    var asCatalogExercise: CatalogExercise {
        CatalogExercise(
            id: id,
            name: name,
            category: category,
            muscleGroups: muscleRaw,
            equipment: equipment,
            details: nil,
            difficulty: nil,
            tracking: TrackingMode(rawValue: trackingRaw) ?? .weightReps,
            isCustom: true
        )
    }
}

// MARK: - Body weight entry

@Model
final class BodyMetric {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0

    init(date: Date = .now, weightKg: Double) {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
    }
}
