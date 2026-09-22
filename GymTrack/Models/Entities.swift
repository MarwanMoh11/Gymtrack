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
        day(onWeekday: Calendar.current.component(.weekday, from: date))
    }

    /// The day scheduled on a weekday, 1 = Sunday, if any.
    func day(onWeekday weekday: Int) -> PlanDay? {
        orderedDays.first { $0.weekday == weekday && !$0.isRest }
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

    /// One row per effort: every logged set except the rows that merely
    /// continued the one above them.
    ///
    /// This is the list for anything that counts sets as units of work — how
    /// many hard sets a muscle got, what beat what. A drop set is one hard set
    /// taken further, not two or three, and counting its rows would inflate
    /// weekly volume for a lifter whose only change was stripping a plate.
    ///
    /// Not the list for anything that counts the work itself — see
    /// `totalVolumeKg`.
    var effortSets: [SetLog] { completedSets.filter { !$0.isContinuation } }

    /// Every kilogram that actually moved, continuations included.
    ///
    /// Deliberately not `effortSets`: those reps happened and that weight was
    /// lifted. A session with a drop set did more work than the same session
    /// without one, and leaving the back-off rows out would report the opposite
    /// — the harder session as the lighter one.
    var totalVolumeKg: Double {
        completedSets.reduce(0) { $0 + $1.volumeKg }
    }

    var totalReps: Int { completedSets.reduce(0) { $0 + $1.reps } }

    /// One interval per pair of consecutive logged sets, each with whether it
    /// is a rest and nothing else.
    ///
    /// Where the lifter announced the start of a set — see `SetLog.startedAt` —
    /// the interval runs from the previous set being logged to this one being
    /// begun, which is the rest with the set taken out of it. Where nobody
    /// announced anything it falls back to the distance between the two logged
    /// stamps, which is rest *plus* the set that followed it and is the most
    /// those two stamps can say on their own.
    private var gapsWithProvenance: [(seconds: TimeInterval, isRest: Bool)] {
        let logged = completedSets
            .compactMap { set -> (begun: Date?, logged: Date, continues: Bool)? in
                guard let end = set.completedAt else { return nil }
                return (set.startedAt, end, set.isContinuation)
            }
            .sorted { $0.logged < $1.logged }
        guard logged.count > 1 else { return [] }

        // The interval into a continuation is not a rest — not a short one, not
        // a measured one, not one at all. It is the seconds spent stripping a
        // plate in the middle of a set the lifter never put down, and it is
        // there *because* they didn't rest. Counted, a lifter who takes one
        // drop a session would have their typical rest reported as half what
        // they actually take, and the number would look measured.
        return zip(logged, logged.dropFirst()).compactMap { previous, next in
            guard !next.continues else { return nil }
            // A start is only believed where it falls inside the gap it claims
            // to split. One outside it — a clock moved, a backup restored from
            // a device in another timezone — would report a negative rest, or
            // a rest longer than the interval containing it, and a confident
            // wrong number does more damage here than a coarse right one.
            if let begun = next.begun, begun > previous.logged, begun <= next.logged {
                return (begun.timeIntervalSince(previous.logged), true)
            }
            return (next.logged.timeIntervalSince(previous.logged), false)
        }
    }

    /// What you actually took between sets, in seconds — the real rest for
    /// every set whose start was announced, and the old gap arithmetic for the
    /// ones where it wasn't. The two kinds live in one list deliberately: a
    /// session with three announced starts and eight without still has to
    /// report a rest, and each number is the best one available for its own gap.
    ///
    /// Nothing is asked for either way. The fallback numbers were already being
    /// written every time a set was logged, and announcing a start is optional.
    var setGaps: [TimeInterval] { gapsWithProvenance.map(\.seconds) }

    /// The rest you typically take. Median rather than mean, so the one set you
    /// spent ten minutes waiting for a rack doesn't become "your" rest.
    ///
    /// Exact for the sets whose start was announced; for the others it still
    /// has the set inside it and so runs long — which is what this number
    /// always was, and why announcing a start exists.
    var typicalRestSeconds: Int? {
        let gaps = setGaps.sorted()
        guard !gaps.isEmpty else { return nil }
        return Int(gaps[gaps.count / 2].rounded())
    }

    /// Whether every interval behind `typicalRestSeconds` was a rest and only
    /// a rest. The summary says which it is, because a measured 1:30 and an
    /// inferred 1:30 are different claims about the same session.
    var restIsMeasured: Bool {
        let gaps = gapsWithProvenance
        return !gaps.isEmpty && gaps.allSatisfy(\.isRest)
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

    /// The set that took the most out of you, by the peak your heart reached
    /// during it. `nil` until something has been attributed — a session the
    /// watch sat out has no hardest set, only a hardest set nobody measured.
    ///
    /// One line on the summary rather than a number on every logged row: the
    /// question a per-set heart rate answers is which set was the hard one, and
    /// forty small numbers down a card answer it worse than naming it does.
    var hardestSet: SetLog? {
        completedSets
            .filter { $0.maxHeartRate != nil }
            .max { ($0.maxHeartRate ?? 0) < ($1.maxHeartRate ?? 0) }
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
    ///
    /// Efforts are counted, not rows. A drop taken after set 2 is still set 2,
    /// so it carries that number and the working set under it is 3 rather than
    /// 4. Numbering the rows instead would have the card claim a four-set
    /// exercise the moment somebody stripped a plate, and the number a set is
    /// called on screen is the number the record and the wrist use too.
    func label(for set: SetLog) -> String { "\(number(of: set))" }

    /// The same number, for the places that print "set 3 of 4" — the Lock
    /// Screen, the dock, the Today card. They used to count rows, so one drop
    /// had the card reading SET 3 while the Lock Screen underneath it said set
    /// 4 of 4, about the same set, at the same moment.
    func number(of set: SetLog) -> Int {
        max(1, effortsBefore(set) + (set.isContinuation ? 0 : 1))
    }

    /// How many sets the exercise holds, counted the way `number(of:)` counts
    /// them, so "set 3 of 3" is never followed by a fourth.
    var effortCount: Int { sets.filter { !$0.isContinuation }.count }

    /// Which of last session's sets this one is compared against — its position
    /// among the efforts.
    ///
    /// Nothing at all for a row that continues another. Those have no opposite
    /// number: "was 62.5 × 8" on a back-off row would be comparing a drop
    /// against a working set, and a drop that moved a row up or down between
    /// sessions would drag every hint under it out of line with the set it is
    /// supposed to be about.
    func pairingPosition(of set: SetLog) -> Int? {
        set.isContinuation ? nil : effortsBefore(set)
    }

    /// How many efforts started before this row.
    private func effortsBefore(_ set: SetLog) -> Int {
        sets.prefix { $0.id != set.id }.filter { !$0.isContinuation }.count
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
    /// When the lifter said they were about to start this set, if they said so
    /// — one tap on the expanded row, and nothing at all is the normal case.
    ///
    /// Never inferred. The moment a set is logged is measured; the moment it
    /// began is only known if somebody announced it, and writing a guess here
    /// would turn the one thing that separates rest from work into a number
    /// that looks measured and isn't.
    var startedAt: Date?

    // MARK: Health

    /// Beats per minute across this set, read off the samples an Apple Watch
    /// recorded while it was happening. `nil` — both of them — wherever the
    /// watch wasn't there, which is the normal state and has to stay
    /// indistinguishable from a set logged before any of this existed.
    ///
    /// Nothing is asked for. The watch is already recording, the stamps are
    /// already on the set, and `HealthKitService` puts the two together when
    /// the session is written to Health.
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    /// Which kind of window those two numbers were read from — a
    /// `HeartRateWindowSource` raw value. It is written together with them and
    /// is never absent while they are present, because a heart rate whose
    /// window nobody can characterise is a number pretending to be a
    /// measurement.
    var heartRateWindowRaw: String?

    // MARK: The offer this set's answer produced

    /// What the lifter did with the load offer this set's rating produced — a
    /// `LoadNudgeOutcome` raw value — and the rung that offer named.
    ///
    /// They are written and cleared together and neither means anything alone:
    /// "declined" says nothing without knowing what was declined, and a rung
    /// nobody acted on is not a decision. Both are absent on the great majority
    /// of sets, which are never offered anything, and absent again wherever an
    /// offer was taken and then undone — see `LoadNudgeOutcome`.
    ///
    /// The other half of the pair, what the offer was *from*, is this set's own
    /// `weightKg`: the offer is computed from it, and a logged set's weight
    /// can't change without the set being un-logged, which clears all of this.
    /// Copying it here would only let the two disagree.
    var loadNudgeOutcomeRaw: String?
    var loadNudgeToKg: Double?

    // MARK: One effort, spread over rows

    /// Set on the rows that were not a set of their own — the second and third
    /// rows of a drop set, the clusters after a myo-rep activation set. It says
    /// this row was taken on from the row above it in the same exercise without
    /// the effort being put down in between.
    ///
    /// `nil` on every ordinary set, which is nearly all of them. A `false` here
    /// would be a fact about 800 rows that don't need one, and a reader would
    /// have to be told that "not a continuation" is the normal state rather
    /// than simply not finding the field.
    ///
    /// The link is to the row above and is not named: which row that is falls
    /// out of `setIndex`, which is already the thing that orders a card and
    /// pairs a set with last week's. A stored parent ID would be a second
    /// answer to a question the ordering already answers, free to disagree with
    /// it the moment a set is inserted or removed. An effort is therefore a run
    /// of rows — one that carries nothing, then however many that do.
    var continuesPreviousSet: Bool?

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

    /// How long the set itself took: announced start to logged. `nil` wherever
    /// the start wasn't announced, and wherever the two stamps don't run
    /// forwards — a set logged before it began is a clock problem, not a set
    /// that took negative time.
    var timeUnderTension: TimeInterval? {
        guard let startedAt, let completedAt, completedAt > startedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    /// How the set felt, as one of the four words it was answered with. Ratings
    /// left over from the old 6–10 strip land on the nearest of them.
    var feel: SetFeel? {
        guard let rpe else { return nil }
        return SetFeel.nearest(to: rpe)
    }

    // MARK: Heart rate

    /// Where this set's heart rate was read from, as the word rather than the
    /// raw string. `nil` on a set that has none.
    var heartRateWindow: HeartRateWindowSource? {
        guard averageHeartRate != nil || maxHeartRate != nil else { return nil }
        return heartRateWindowRaw.flatMap(HeartRateWindowSource.init(rawValue:))
    }

    /// Whether the watch caught anything during this set.
    var hasHeartRate: Bool { averageHeartRate != nil || maxHeartRate != nil }

    /// Files what was read off the samples. Only ever called with a result the
    /// attribution actually produced, so there is no path here that writes a
    /// heart rate of zero onto a set the watch never saw.
    func apply(_ heartRate: SetHeartRate) {
        averageHeartRate = heartRate.average
        maxHeartRate = heartRate.peak
        heartRateWindowRaw = heartRate.source.rawValue
    }

    /// Forgets it. Un-logging a set takes its window away — the stamps that
    /// defined it are being cleared in the same breath — so the beats read
    /// through that window have to go with them rather than sitting on a set
    /// that will next be logged at some other time entirely.
    func clearHeartRate() {
        averageHeartRate = nil
        maxHeartRate = nil
        heartRateWindowRaw = nil
    }

    // MARK: The load offer

    /// What became of the offer this set's answer produced, as the word rather
    /// than the raw string. `nil` on a set that was never offered anything, or
    /// whose offer was never resolved.
    var loadNudgeOutcome: LoadNudgeOutcome? {
        guard loadNudgeToKg != nil else { return nil }
        return loadNudgeOutcomeRaw.flatMap(LoadNudgeOutcome.init(rawValue:))
    }

    /// Files an outcome and the rung it was about, together, because a reader
    /// can do nothing with either on its own.
    func recordLoadNudge(_ outcome: LoadNudgeOutcome, toKg: Double) {
        loadNudgeOutcomeRaw = outcome.rawValue
        loadNudgeToKg = toKg
    }

    /// Forgets the offer ever happened. Called where the record has to read as
    /// though the button was never pressed and the question never asked.
    func clearLoadNudge() {
        loadNudgeOutcomeRaw = nil
        loadNudgeToKg = nil
    }

    // MARK: One effort, spread over rows

    /// Whether this row was taken on from the one above it rather than being a
    /// set of its own.
    var isContinuation: Bool { continuesPreviousSet == true }

    /// The row it continues: the set of the same exercise immediately above it.
    ///
    /// `nil` where there isn't one. That should be impossible — a continuation
    /// is only ever built on top of a set that has already been logged, and
    /// `WorkoutSession.close` unlinks any row whose set didn't survive to the
    /// record — but it is checked rather than asserted, so a link with nothing
    /// on the other end reads as an ordinary set everywhere instead of drawing
    /// half a drop.
    var continuedSet: SetLog? {
        guard isContinuation, let session else { return nil }
        return session.sets
            .filter { $0.catalogID == catalogID && $0.setIndex < setIndex }
            .max { $0.setIndex < $1.setIndex }
    }

    /// Which kind of continuation this was, read off the two weights rather
    /// than stored — see `SetContinuation` for why.
    var continuation: SetContinuation? {
        guard let above = continuedSet else { return nil }
        return weightKg < above.weightKg ? .drop : .cluster
    }

    // MARK: Taking it back

    /// Puts the set back to never having been logged.
    ///
    /// Every field here was written by the act of logging, or read through the
    /// window logging defined, so all of it goes at once. A mis-tap is not
    /// data: this record exists to be read months later, and a set carrying an
    /// effort answer or a time under tension nobody spent is worse than a set
    /// carrying nothing.
    ///
    /// It lives on the set rather than in the logger because there are two ways
    /// a set gets un-logged. The phone has `ActiveWorkout.uncomplete`; the
    /// wrist can also un-log one with the phone asleep in a locker, and that
    /// message is applied straight to the store by `WatchCommandCenter` with no
    /// `ActiveWorkout` anywhere to route through. The two paths erasing
    /// different amounts is precisely how a set ends up half taken back.
    func unlog() {
        isCompleted = false
        completedAt = nil
        rpe = nil
        // Taking the set back takes back when it began as well. A start kept
        // here would pair with whatever timestamp the set is logged at next —
        // after however long the fixing took — and report a time under tension
        // nobody spent under a bar.
        startedAt = nil
        // And the heart rate read through that window. The beats were real, but
        // the window they were read through was this set's, and this set is
        // being taken back — kept, they would sit on whatever gets logged in
        // its place and describe minutes nobody spent doing it.
        clearHeartRate()
        // The offer came out of the rating being cleared two lines up. With the
        // answer gone there was never a reading of this set to act on, so what
        // was done about it stops being a fact about anything.
        clearLoadNudge()
        // `continuesPreviousSet` deliberately stays, along with `setIndex` and
        // for the same reason: it is not something the set gained by being
        // logged, it is what the row is. A drop's second row was created as a
        // continuation and is one whether or not it currently holds a lift.
        // Clearing it here would turn taking the reps back into silently
        // promoting a back-off row to an ordinary set sitting mid-exercise at
        // 40 kg — which is the lie this whole field exists to stop. The undo
        // for making the row is removing the row, and that is where it lives.
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
