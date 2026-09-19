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
    /// Per-exercise rest override. `nil` means "follow the app-wide default",
    /// so changing that setting reaches every exercise that hasn't been tuned.
    var restSeconds: Int?
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
         restSeconds: Int? = nil) {
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

    /// The rest actually used for this exercise — its own override, or the
    /// app-wide default when it has none.
    var resolvedRestSeconds: Int { restSeconds ?? AppSettings.shared.defaultRestSeconds }

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
    /// What the lifter had to say about the session as a whole, in their own
    /// words. Written on the summary and still editable from history — never
    /// asked for, and empty is the normal state.
    var notes: String = ""
    /// The same note's tags, as `NoteTag` raw values. Kept beside the sentence
    /// rather than inside it so a reader can count the flat weeks without
    /// parsing anybody's prose; either half works with the other missing.
    var noteTagsRaw: [String] = []
    var planDayID: UUID?
    var planName: String = ""
    /// An exercise being worked out of turn — chosen from the watch, or by
    /// jumping around the logger. `nil` means "whatever comes next".
    var preferredExerciseID: String?

    // MARK: Health

    /// The `HKWorkout` this session was saved as — by the phone when it
    /// finished, or by the watch if it drove the session. Its presence is also
    /// what stops a second copy being written.
    var healthWorkoutID: UUID?
    /// Beats per minute over the session, from the watch. `nil` when nothing
    /// was recorded — a zero would read as a measurement.
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKcal: Double?
    /// True when an Apple Watch was logging alongside the phone.
    var wasWatchDriven: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var sets: [SetLog] = []

    /// What was said about individual exercises today. A row exists only where
    /// something was actually written — see `ExerciseNote`.
    @Relationship(deleteRule: .cascade, inverse: \ExerciseNote.session)
    var exerciseNotes: [ExerciseNote] = []

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

    /// The gaps between consecutive logged sets, in seconds. What you actually
    /// took between sets — including the set itself, because the only two
    /// timestamps a set has are the one it was logged at and the one before it.
    ///
    /// Nothing is asked for here: the numbers were already being written every
    /// time a set was logged.
    var setGaps: [TimeInterval] {
        let stamps = completedSets.compactMap(\.completedAt).sorted()
        guard stamps.count > 1 else { return [] }
        return zip(stamps, stamps.dropFirst()).map { $1.timeIntervalSince($0) }
    }

    /// The rest you typically take. Median rather than mean, so the one set you
    /// spent ten minutes waiting for a rack doesn't become "your" rest.
    var typicalRestSeconds: Int? {
        let gaps = setGaps.sorted()
        guard !gaps.isEmpty else { return nil }
        return Int(gaps[gaps.count / 2].rounded())
    }

    /// Volume moved per minute of session — how hard the hour worked, which two
    /// sessions of identical volume can differ wildly on.
    var densityKgPerMinute: Double {
        let minutes = duration / 60
        guard minutes >= 1, totalVolumeKg > 0 else { return 0 }
        return totalVolumeKg / minutes
    }

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

    // MARK: Notes

    /// The session note's tags, as the words rather than the raw strings.
    var noteTags: [NoteTag] {
        get { NoteTag.resolve(noteTagsRaw) }
        set { noteTagsRaw = newValue.map(\.rawValue) }
    }

    /// The sentence with the whitespace taken off — what's left is what was
    /// actually said. A field opened, typed into and cleared again has to read
    /// as nothing written, not as a note made of spaces.
    var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether anything at all was said about the session as a whole.
    var hasSessionNote: Bool { !trimmedNotes.isEmpty || !noteTagsRaw.isEmpty }

    /// What was written about one exercise today, if anything was.
    func note(for catalogID: String) -> ExerciseNote? {
        exerciseNotes.first { $0.catalogID == catalogID }
    }

    /// Exercise notes in the order their exercises were trained, so the record
    /// reads down the session rather than in whatever order the rows come back.
    var orderedExerciseNotes: [ExerciseNote] {
        let order = Dictionary(sets.map { ($0.catalogID, $0.exerciseOrder) },
                               uniquingKeysWith: min)
        return exerciseNotes.sorted {
            let left = order[$0.catalogID] ?? .max
            let right = order[$1.catalogID] ?? .max
            return left == right ? $0.exerciseName < $1.exerciseName : left < right
        }
    }

    /// Whether there's anything from Health worth showing on the summary. A
    /// zero energy reading is nothing recorded, not a workout that cost
    /// nothing, so it doesn't count.
    var hasHealthMetrics: Bool {
        averageHeartRate != nil || maxHeartRate != nil || (activeEnergyKcal ?? 0) >= 1
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

    /// What a set is called on screen — 1, 2, 3 down the card.
    func label(for set: SetLog) -> String { "\(position(of: set) + 1)" }

    /// Position of a set within its exercise, which is also what lines it up
    /// with the same set last session.
    func position(of set: SetLog) -> Int {
        sets.firstIndex { $0.id == set.id } ?? 0
    }
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
    /// How hard the set was, on the 6–10 scale. Stored as the number it always
    /// was so the progression reads what it always read; asked for, and shown,
    /// as one of four words — see `feel`.
    var rpe: Double?

    var targetRepsLow: Int = 0
    var targetRepsHigh: Int = 0

    var isCompleted: Bool = false
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
         targetRepsHigh: Int = 0) {
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

    /// Whether the set came in under what was asked of it.
    var fellShortOfRange: Bool {
        targetRepsLow > 0 && reps < targetRepsLow
    }

    /// How the set felt, as one of the four words it was answered with. Ratings
    /// left over from the old 6–10 strip land on the nearest of them.
    var feel: SetFeel? {
        guard let rpe else { return nil }
        return SetFeel.nearest(to: rpe)
    }
}

// MARK: - Exercise note

/// What the lifter had to say about one exercise on one day — the pinched
/// shoulder, the machine that was taken, the day it all moved easily.
///
/// Its own model because there is nothing else to hang it on:
/// `SessionExerciseGroup` is computed out of the sets each time it's asked for,
/// and `PlanItem.notes` is a note on the *prescription* — it says what to do
/// every time, not what happened once.
///
/// A row exists only where something was written. Opening the field, typing and
/// clearing it again leaves no note at all, the same way an un-answered effort
/// question leaves no rating: a note that says nothing is indistinguishable
/// from a mis-tap, and a record whose value is that everything in it happened
/// can't afford rows that mean maybe.
@Model
final class ExerciseNote {
    var id: UUID = UUID()
    var catalogID: String = ""
    /// Denormalised like `SetLog.exerciseName`, so the note still says what
    /// it's about if a custom exercise is deleted out from under it.
    var exerciseName: String = ""
    var text: String = ""
    /// `NoteTag` raw values. Tags and sentence are independent: either can be
    /// the whole note.
    var tagsRaw: [String] = []
    var updatedAt: Date = Date()

    var session: WorkoutSession?

    init(catalogID: String, exerciseName: String) {
        self.id = UUID()
        self.catalogID = catalogID
        self.exerciseName = exerciseName
        self.updatedAt = .now
    }

    var tags: [NoteTag] {
        get { NoteTag.resolve(tagsRaw) }
        set {
            tagsRaw = newValue.map(\.rawValue)
            updatedAt = .now
        }
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nothing left to keep. Checked after every edit — this is what makes the
    /// row disappear rather than lingering as an empty one.
    var isEmpty: Bool { trimmedText.isEmpty && tagsRaw.isEmpty }
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

    /// Applies an edit in place. The ID is deliberately untouched: plans and
    /// logged sets reference it, and renaming an exercise shouldn't orphan the
    /// history that was built under the old name.
    func apply(name: String, muscles: [Muscle], equipment: [String], tracking: TrackingMode) {
        self.name = name
        self.muscleRaw = muscles.map(\.name)
        self.equipment = equipment
        self.trackingRaw = tracking.rawValue
    }

    /// The canonical muscles this was saved with, for re-opening the editor.
    var muscles: [Muscle] { muscleRaw.compactMap(Muscle.match) }

    var tracking: TrackingMode { TrackingMode(rawValue: trackingRaw) ?? .weightReps }

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
    /// Where the number came from, so an import from Health can tell itself
    /// apart from something the user typed.
    var source: String = Source.manual.rawValue

    init(date: Date = .now, weightKg: Double) {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
    }

    enum Source: String {
        case manual, health
    }

    var isFromHealth: Bool { source == Source.health.rawValue }
}

// MARK: - Per-exercise load scale

/// One exercise's machine, as the user corrected it: what the stack is marked
/// in and what one pin or one plate is worth.
///
/// Only exercises the user has actually put right get a row. Everything else
/// resolves from its equipment and the app-wide unit, so a new install and a
/// new exercise both behave sensibly with nothing stored at all.
@Model
final class ExerciseLoadPreference {
    /// The catalog exercise this corrects. Unique per exercise — the book
    /// upserts rather than accumulating rows.
    var catalogID: String = ""
    var unitRaw: String = WeightUnit.kg.rawValue
    /// The smallest jump, in `unitRaw`.
    var increment: Double = 2.5
    var updatedAt: Date = Date()

    init(catalogID: String, scale: LoadScale) {
        self.catalogID = catalogID
        self.unitRaw = scale.unit.rawValue
        self.increment = scale.increment
        self.updatedAt = .now
    }

    var scale: LoadScale {
        get { LoadScale(unit: WeightUnit(rawValue: unitRaw) ?? .kg, increment: increment) }
        set {
            unitRaw = newValue.unit.rawValue
            increment = newValue.increment
            updatedAt = .now
        }
    }
}

// MARK: - Hidden exercise

/// One exercise the user has put away.
///
/// Stored as a row per hidden exercise rather than as a filtered copy of the
/// library, so the bundled file stays the single source of what exists and an
/// app update that adds exercises can't silently resurrect the ones you trimmed.
@Model
final class HiddenExerciseRecord {
    /// The catalog exercise this hides. Unique per exercise.
    var catalogID: String = ""
    var hiddenAt: Date = Date()

    init(catalogID: String) {
        self.catalogID = catalogID
        self.hiddenAt = .now
    }
}
