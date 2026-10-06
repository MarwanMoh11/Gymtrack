import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

/// JSON export/import of everything the app stores. With no account and no
/// server, this is the user's way to move devices or keep a copy.
enum BackupService {

    struct Archive: Codable {
        var version = 2
        /// The one thing that differs between two exports of an unchanged
        /// store, so anything hashing the file for "has this changed" has to
        /// look past this key. Every other byte is a function of the data.
        var exportedAt = Date()
        /// The IANA identifier of the zone the phone was in when this was
        /// written, such as `Africa/Cairo`. Every date in the file is UTC while
        /// a plan day's `weekday` is the lifter's own local one, so without
        /// this a 01:30 Tuesday session reads as 22:30 Monday and lands on the
        /// wrong plan day. Optional so older files, which never said, still
        /// decode; nothing reads it back.
        var timeZone: String?
        /// The app's marketing version and build number, from its bundle, so a
        /// reader can tell which build's rules wrote the file. Absent rather
        /// than empty wherever the bundle has none, and optional like the rest.
        var appVersion: String?
        var appBuild: String?
        var settings: Settings
        var plans: [PlanDTO]
        var sessions: [SessionDTO]
        /// Optional for the same reason — weigh-ins arrived later than the
        /// first backup format.
        var bodyMetrics: [BodyMetricDTO]?
        /// Tape-measure check-ins, oldest first. Absent rather than empty when
        /// there are none, so a reader can tell a lifter who never measured
        /// from one whose measurements were all taken back. Optional like the
        /// rest: a backup written before this existed still restores.
        var bodyMeasurements: [BodyMeasurementDTO]?
        var customExercises: [CustomExerciseDTO]
        /// How individual machines are marked. Optional for the same reason as
        /// the rest — a backup written before this existed still restores, and
        /// every exercise in it falls back to its equipment default.
        var loadScales: [LoadScaleDTO]?
        /// Which library exercises the user has put away. Optional like the
        /// rest — an older backup simply restores with nothing hidden.
        var hiddenExercises: [String]?
        /// What the bundled library knows about the exercises this file names,
        /// so the file explains itself to whatever reads it — a backup handed
        /// to an AI coach otherwise has to guess from "Front Squat" that the
        /// set was quads and a barbell. Optional like the rest: a backup
        /// written before this existed still restores, and restore ignores the
        /// section either way.
        var exerciseCatalog: [CatalogExerciseDTO]?
        /// The rung each exercise in this file is actually loaded on, whether
        /// the lifter corrected it or the app worked it out from the equipment.
        /// `loadScales` above lists corrections only, so on its own it can't
        /// tell a reader what the other machines step by, and a proposal has to
        /// name a load the equipment can really be set to. Kept as its own key
        /// rather than folded into `loadScales`, so a reader written against
        /// that list sees exactly what it always saw. Restore never reads it.
        var effectiveLoadScales: [EffectiveLoadScaleDTO]?
        /// What the numbers under each set's `rpe` mean. Present on every file
        /// this build writes, so a reader can tell a file that says so from an
        /// older one that never did. Restore never reads it.
        var effortScale: EffortScaleDTO?
    }

    struct Settings: Codable {
        var weightUnit: String
        var userName: String
        var defaultRestSeconds: Int
        /// Whether the app was asking how each set felt when this file was
        /// written. The setting as it stands at export, not a history of it: a
        /// month of sets without an `effort` may be a month the question was
        /// off or a month it went unanswered, and this can't say which. Left to
        /// a reader as one more reason not to read a missing answer as a low
        /// one. Optional so older files decode, and never restored, because the
        /// setting stays per device.
        var trackRPE: Bool?
    }

    /// The scale behind a set's `rpe`, spelled out so the file doesn't depend
    /// on a reader having read the coaching notes.
    ///
    /// The four effort answers are buckets, not a point RPE: "Easy" is three or
    /// more reps left, which `rpe: 6` (four in reserve) only stands in for.
    /// `rpe` keeps those stand-in numbers so an older reader and restore see
    /// what they always saw, and `effort` beside it is the answer itself.
    struct EffortScaleDTO: Codable {
        /// `bucketCode`: `rpe` is the code for the answer given, not a
        /// measurement of proximity to failure.
        var rpe: String
        var buckets: [EffortBucketDTO]
    }

    struct EffortBucketDTO: Codable {
        var effort: String
        var rpe: Double
        var meaning: String
    }

    struct PlanDTO: Codable {
        var id: UUID
        var name: String
        var summary: String
        var isActive: Bool
        var createdAt: Date
        var days: [DayDTO]
    }

    struct DayDTO: Codable {
        var id: UUID
        var name: String
        var order: Int
        var weekday: Int?
        var isRest: Bool
        /// Absent when the day has no note. Optional so older files, which
        /// wrote an empty string on every day, still decode.
        var notes: String?
        var items: [ItemDTO]
    }

    struct ItemDTO: Codable, Equatable {
        /// The slot's own identity, so a coach's proposal can name the exact
        /// slot it means. Matching on the exercise instead is wrong the day a
        /// plan holds the same lift twice, and on position is wrong the moment
        /// a slot is added above it. Optional so older files, which carried
        /// none, still decode; absent restores as a new ID, and so does one
        /// the file repeats, because a slot is found by this alone.
        var id: UUID?
        var catalogID: String
        var name: String
        var order: Int
        var targetSets: Int
        /// The rep range, written only for a reps slot and only where it is
        /// above zero. A timed slot's range is a zero standing for "none", and
        /// written out it reads as a prescription of nothing. Optional so older
        /// files still decode; absent restores as zero, the value it stood for.
        var targetRepsLow: Int?
        var targetRepsHigh: Int?
        /// Absent where no starting weight was set, rather than a zero.
        var targetWeightKg: Double?
        /// The hold time, written only for a timed slot. Every slot carries
        /// one in the store, a squat's included, and a 45 s target on a squat
        /// is a prescription nobody made. Absent restores as the store's own
        /// default.
        var targetSeconds: Int?
        /// Kept for a plan slot whose custom exercise was deleted. Older
        /// backups use the exercise catalog when this is absent.
        var tracking: String?
        /// Absent/null means the exercise follows the app-wide default rest.
        var restSeconds: Int?
        /// Absent when the slot has no note, like the day's.
        var notes: String?
    }

    struct SessionDTO: Codable {
        var id: UUID
        var title: String
        var startedAt: Date
        /// Absent on a session logged afterwards, which had no clock running.
        var endedAt: Date?
        /// `true` on a session written down after the workout rather than
        /// logged during it. Only the day of `startedAt` is meant; its hour is
        /// a placeholder, and the session has no `endedAt`, no set times and
        /// no heart rate. Its sets are what the lifter entered as done. Absent
        /// on every session logged as it happened, and on older files.
        var loggedAfterwards: Bool?
        /// What the lifter said about the whole session. Absent on a session
        /// nobody wrote about; older files wrote an empty string on every
        /// session, so it stays optional for them.
        var notes: String?
        var planName: String
        /// The plan day this session was started from, where it was started from
        /// one. `title` and `planName` are free-text copies taken at the time,
        /// and plans are edited in place, so once a day is renamed or two plans
        /// both have a "Day 1" they can't say which day was trained. This is
        /// the same ID `DayDTO.id` carries. It can name a day that has since
        /// been deleted, which is a fact about the session and stays. Absent on
        /// a session started without a plan day, and on older files.
        var planDayID: UUID?
        /// What that plan day prescribed when the session began, slot by slot,
        /// in the same shape and by the same rules as `DayDTO.items`, minus
        /// starting weights and notes. Plans are edited in place, so this is
        /// the only record of what a session was measured against: compare it
        /// with the sets to see what was skipped or done instead. Absent on a
        /// session started without a plan day and on sessions stored before
        /// it existed.
        var plannedItems: [ItemDTO]?
        // Optional so backups written before Health support still restore.
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var activeEnergyKcal: Double?
        /// The Health workout this session was saved as. Optional so backups
        /// written before Health linkage still restore without inventing one.
        var healthWorkoutID: UUID?
        var wasWatchDriven: Bool?
        /// Where `averageHeartRate` and `maxHeartRate` came from — `watchWorkout`
        /// where the watch app recorded the workout, `healthSamples` where the
        /// numbers were read back from Health and enough readings covered
        /// enough of the session. Absent, the whole key, on a session stored
        /// before this existed and wherever nothing could vouch for the
        /// numbers, so a missing source reads as "unknown", never as "phone".
        var heartRateSource: String?
        /// Individual readings behind the average and the peak, where this app
        /// counted them.
        var heartRateReadings: Int?
        /// The same as `heartRateSource`, for `activeEnergyKcal`.
        var energySource: String?
        /// The session note's tags — `NoteTag` raw values. Optional like the
        /// rest, and absent rather than empty on a session nobody tagged, so
        /// the file doesn't carry a line of nothing per session.
        var noteTags: [String]?
        /// What was said about individual exercises. Absent when nothing was.
        var exerciseNotes: [ExerciseNoteDTO]?
        var sets: [SetDTO]
    }

    /// One exercise's note from one session — the tags and the sentence, which
    /// are independent of each other and of the sets around them.
    ///
    /// Carries the exercise's name as well as its ID, the way `SetDTO` does, so
    /// a reader can follow the note without resolving anything: a note is the
    /// part of this file a person wrote on purpose, and it should be legible on
    /// its own.
    struct ExerciseNoteDTO: Codable {
        var catalogID: String
        var exerciseName: String
        var text: String
        var tags: [String]
    }

    struct SetDTO: Codable {
        /// What a reader cites when it points at this set. Restore keeps it, so
        /// a citation made against one export still resolves against the file
        /// written after a restore; a file without one, from before sets were
        /// numbered, gets a fresh ID per set. Optional for exactly that reason.
        var id: UUID?
        var catalogID: String
        var exerciseName: String
        var exerciseOrder: Int
        var setIndex: Int
        var weightKg: Double
        /// Written only for a set counted in reps. A timed set still carries
        /// whatever count it was seeded with, and nobody did those reps.
        /// Optional so older files, which wrote both keys on every set, still
        /// decode; absent restores as zero.
        var reps: Int?
        /// Written only for a timed set. Every other set carries its plan
        /// slot's hold target underneath, so a squat went out as 45 seconds
        /// long, which a coach reading time under tension would believe.
        var seconds: Int?
        /// How this set was measured when logged. Absent on older backups;
        /// the exercise catalog remains their best available description.
        var tracking: String?
        var isCompleted: Bool
        /// Written by versions that had a warm-up flag. Decoded so those
        /// backups still restore, and a set carrying it is left out of the
        /// restore: see `insertArchive`.
        var isWarmup: Bool?
        var completedAt: Date?
        /// The moment the lifter said the set was beginning, where they said
        /// so. Optional like the rest — a backup written before this existed
        /// still restores, and a set nobody announced is absent here rather
        /// than carrying a stamp copied off `completedAt`: the whole point of
        /// the field is that the reader can tell the two apart. With both, a
        /// coach reading this file gets the set's own length and the real rest
        /// before it; with only `completedAt`, the gap to the previous set is
        /// rest and set together and can't be pulled apart.
        var startedAt: Date?
        /// Where the set began and ended by the heart rate's account, for a set
        /// whose start nobody announced: the climb out of the rest before it,
        /// read off the watch's trace after the session. Both present or both
        /// absent, and absent on most sets — wherever a start was announced,
        /// wherever the watch wasn't there, and wherever the trace could have
        /// been read two ways.
        ///
        /// Deliberately not `startedAt`. That key means the lifter said so;
        /// these mean this app read it off a heart rate, and a coach can only
        /// weigh the two differently if the file keeps them apart. With them the
        /// gap before the set splits into rest and set much as an announced
        /// start splits it, at the lower grade of certainty the names state.
        /// Optional like the rest, so older backups still decode.
        var detectedStartedAt: Date?
        var detectedEndedAt: Date?
        /// The range this set was aimed at, on a reps set that had one. A
        /// continuation row's zeros mean "no target" and are left out, as is
        /// any range on a timed set. Optional so older files still decode.
        var targetRepsLow: Int?
        var targetRepsHigh: Int?
        /// Optional so a backup written before effort tracking still restores —
        /// and so a set that was never rated round-trips as unrated rather than
        /// as an RPE of zero.
        var rpe: Double?
        /// The answer to "how did that set feel", as the lifter gave it: `easy`
        /// (three or more reps left), `solid` (two), `hard` (one) or `allOut`.
        /// Written only where the stored `rpe` is exactly one of the four
        /// answers' codes. A 7 or an 8.5 left by the old five-number strip
        /// keeps its `rpe` and gets no word, since nobody pressed one.
        /// Derived, so restore never reads it and older files decode without.
        var effort: String?
        /// What the watch read during this set. Both absent on a set the watch
        /// wasn't there for, which is most of them — an average of zero would
        /// tell a coach the set was easy, and a null written as a value would
        /// tell them it was measured as nothing.
        ///
        /// This is the field per-set detail exists for: a session average of
        /// 132 says a workout happened, while a heavy triple at 168 beside
        /// accessory work at 110 says which part of it was the work.
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        /// How the window those two were read over was arrived at —
        /// `measured` where the lifter announced the set's start and the window
        /// is the set itself, `detected` where the window is the set as the
        /// heart rate showed it (`detectedStartedAt` to `detectedEndedAt`), and
        /// `inferred` where the app assumed the likely last seconds before the
        /// set was logged. Written whenever there is a heart rate and never
        /// otherwise, so a reader is never left deciding for themselves how
        /// much to trust a number this file handed them.
        var heartRateWindow: String?
        /// The load the app offered off the back of this set's rating, and what
        /// the lifter did with it. Absent — the whole key — on every set that
        /// was never offered anything, which is nearly all of them, and absent
        /// again wherever an offer was taken and then undone. Optional like the
        /// rest, so a backup written before this existed still restores.
        var loadNudge: LoadNudgeDTO?
        /// Present only where this row and the one above it were one effort,
        /// taken without putting the weight down — the second and third rows of
        /// a drop set, the clusters after a myo-rep activation set.
        ///
        /// This is the fact the file was missing. Three rows at 62.5, 50 and 40
        /// with nothing joining them read as a lifter falling apart across
        /// three working sets; the same three rows with this key are one
        /// working set deliberately taken twice further, which is a lifter
        /// doing well. Identical numbers, opposite conclusions, and nothing
        /// else here can separate them — a drop leaves the same falling weights
        /// as a collapse, and the seconds between its rows are the same short
        /// gap as a lifter who doesn't rest enough.
        ///
        /// The key's **presence** is that fact, and it is the only part
        /// restored. Its **value** — `drop` where the load came down between
        /// the rows, `cluster` where it didn't — is this app's reading of the
        /// two weights, written out so the file explains itself instead of
        /// making a reader fetch the row above to classify this one. It is
        /// never stored and never read back, so it cannot drift from the
        /// weights it describes, and a word some later version writes that this
        /// one has never heard of still says "one effort" simply by being here.
        ///
        /// Absent on every ordinary set, which is nearly all of them, and
        /// optional like the rest so older backups still decode.
        var continues: String?
    }

    /// One load offer and what became of it.
    ///
    /// This is the autoregulation signal in the file: whether the lifter pushes
    /// when told there is room, or holds. `outcome` is `taken` or `declined` —
    /// declining covers the cross and simply lifting the next set at the weight
    /// that stood, which the app can't tell apart and doesn't pretend to.
    ///
    /// The rung travels with the outcome because neither is worth anything
    /// alone: turning down 62.5 → 65 on a squat and turning down 20 → 25 on a
    /// curl are different decisions. The other end of it is the set's own
    /// `weightKg` — every offer is computed from it — so it isn't copied here,
    /// where a reader would have two numbers that could disagree.
    struct LoadNudgeDTO: Codable {
        /// `taken` or `declined`.
        var outcome: String
        /// The weight the offer moved the remaining sets to, in kilograms.
        var toKg: Double
    }

    struct BodyMetricDTO: Codable {
        var id: UUID
        var date: Date
        var weightKg: Double
        var source: String
    }

    /// One check-in. A part that wasn't measured has no key at all, never a
    /// zero and never a null, so a reader can't mistake a skipped tape for a
    /// girth that fell to nothing.
    struct BodyMeasurementDTO: Codable {
        var id: UUID
        var date: Date
        var armCm: Double?
        var chestCm: Double?
        var shouldersCm: Double?
        var waistCm: Double?
        var thighCm: Double?
    }

    struct LoadScaleDTO: Codable {
        var catalogID: String
        var unit: String
        var increment: Double
    }

    /// One exercise's rung as the logger uses it, and where that rung came from.
    ///
    /// `source` is `correction` where the lifter marked the machine themselves
    /// (the same row `loadScales` carries) and `derived` where the app worked it
    /// out from the exercise's equipment and the app-wide unit. The two are
    /// kept apart because they carry different weight: a correction is what
    /// this gym's machine is, a derived rung is a good guess at it.
    struct EffectiveLoadScaleDTO: Codable {
        /// Spelled as the plans and sets in this file spell it.
        var catalogID: String
        var unit: String
        var increment: Double
        /// `correction` or `derived`.
        var source: String
    }

    struct CustomExerciseDTO: Codable {
        var id: String
        var name: String
        var category: String
        var muscleRaw: [String]
        var equipment: [String]
        var trackingRaw: String
    }

    /// A bundled library exercise that something in this file refers to,
    /// flattened into the archive. Shaped after `CustomExerciseDTO`, which has
    /// always carried these same facts about the user's own exercises.
    ///
    /// Custom exercises stay out of here even when they were trained, because
    /// `customExercises` already describes them in full: copying one into both
    /// sections would give a reader two records for the same exercise with no
    /// rule for which wins, and would tempt a future restore into inserting it
    /// twice. Resolving an ID means checking both sections.
    ///
    /// Nothing reads this back. The bundled library is the source of truth at
    /// runtime, and seeding exercises from a backup would let a file written by
    /// an older build shadow an entry the app has since corrected or merged.
    struct CatalogExerciseDTO: Codable {
        /// Spelled as the sets and plan items in this file spell it, which
        /// isn't always the ID the app resolved it to — a set logged under an
        /// exercise that has since been merged into another keeps the old ID,
        /// and that's the one a reader has to be able to look up.
        var catalogID: String
        var name: String
        var category: String
        /// The library's own wording, which runs to dozens of free-text labels.
        var muscleRaw: [String]
        /// The same muscles folded into the canonical groups the app credits
        /// work to — the list worth counting sets against.
        var muscles: [String]
        var equipment: [String]
        var trackingRaw: String
    }

    // MARK: - Export

    /// Where, when and by which build a file was written.
    ///
    /// Handed to the export rather than read inside it, so a test can hold all
    /// of it still. Two exports of one store are the same bytes only while the
    /// clock is, and `exportedAt` is the one key that would otherwise differ.
    struct ExportStamp {
        var exportedAt: Date
        var timeZone: TimeZone
        var appVersion: String?
        var appBuild: String?

        /// The moment of the call, on this phone, from this build.
        static func current(now: Date = .now, timeZone: TimeZone = .current,
                            bundle: Bundle = .main) -> ExportStamp {
            ExportStamp(exportedAt: now, timeZone: timeZone,
                        appVersion: bundle.infoString("CFBundleShortVersionString"),
                        appBuild: bundle.infoString("CFBundleVersion"))
        }
    }

    /// Writes the export to a temporary file and returns it.
    ///
    /// The file's order is defined, so two exports of an unchanged store differ
    /// only in `exportedAt`: sessions by `startedAt`, sets as the app groups
    /// them (`SetLog.precedesInSession`), plans by `createdAt`, days and slots
    /// by `order`, and everything else by a stable key, with the ID breaking any
    /// tie. `continues` reads "the row above", and that is only true if the
    /// rows are where a reader will look for them.
    static func export(context: ModelContext, stamp: ExportStamp = .current()) throws -> URL {
        try writeExport(try exportData(context: context, stamp: stamp), stamp: stamp)
    }

    /// The same file as `export`, with only the part that has to touch the
    /// store left on the main actor. The archive is a value snapshot, so the
    /// pretty-printing and the disk write, which are most of the time on a
    /// year of history, run on a background thread and the sheet stays live.
    /// Byte-identical to `export`: both call the same `encoded`.
    ///
    /// The snapshot stays on the main context, cut into slices with the main
    /// actor handed back between them (`makeArchivePaced`).
    /// Read through a second context it worked until a restore had run in the
    /// same session, and then trapped inside SwiftData (DATA-14).
    ///
    /// `progress` runs on the main actor with a fraction from 0 to 1. The
    /// snapshot is the first 60 per cent, and the encode and write, which have
    /// no steps to count, fill the rest at once.
    @MainActor
    static func exportOffMain(context: ModelContext, stamp: ExportStamp = .current(),
                              sliceMilliseconds: Double = Pacer.defaultSliceMilliseconds,
                              progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> URL {
        let archive = try await makeArchivePaced(context: context, stamp: stamp,
                                                 sliceMilliseconds: sliceMilliseconds,
                                                 progress: { progress($0 * 0.6) })
        progress(0.6)
        let url = try await Task.detached(priority: .userInitiated) {
            try writeExport(try encoded(archive), stamp: stamp)
        }.value
        progress(1)
        return url
    }

    /// Hands the main actor back once a slice of work has used up its share.
    ///
    /// The snapshot and the restore are loops over sessions, and each pass is
    /// cheap; it is 300 of them in a row that froze the sheet. Checking the
    /// clock after each pass, rather than counting a fixed number of sessions,
    /// keeps a slice short whether a session holds 5 sets or 80, and on a slow
    /// phone as well as a fast one.
    ///
    /// The pause is a short sleep rather than a bare `Task.yield()`. A yielded
    /// task goes straight back on the main queue, where it can run again before
    /// the run loop has drawn a frame; a timer wakes the run loop, so the
    /// progress bar moves and touches are heard between slices.
    @MainActor
    struct Pacer {
        nonisolated static let defaultSliceMilliseconds = 16.0

        /// A restore never pauses; see `restoreOffMain`. Tests pass a slice of
        /// their own to exercise the paced path.
        nonisolated static let restoreSliceMilliseconds = Double.infinity

        private let sliceNanoseconds: UInt64
        private let report: @MainActor (Double) -> Void
        private var sliceStart = DispatchTime.now().uptimeNanoseconds

        init(sliceMilliseconds: Double, report: @escaping @MainActor (Double) -> Void) {
            sliceNanoseconds = sliceMilliseconds.isFinite
                ? UInt64(max(0, sliceMilliseconds) * 1_000_000)
                : .max
            self.report = report
        }

        /// Pauses, and reports `fraction`, only when the slice is used up.
        mutating func pauseIfDue(fraction: Double) async {
            guard DispatchTime.now().uptimeNanoseconds &- sliceStart >= sliceNanoseconds else { return }
            report(min(1, max(0, fraction)))
            try? await Task.sleep(nanoseconds: 1_000_000)
            sliceStart = DispatchTime.now().uptimeNanoseconds
        }
    }

    /// Puts the bytes in a temporary file named for the export's day.
    static func writeExport(_ data: Data, stamp: ExportStamp) throws -> URL {
        // `.iso8601` formats in UTC, which names a late-evening export with the
        // wrong day. Stamp the file in the user's own timezone.
        let name = DateFormatter()
        name.dateFormat = "yyyy-MM-dd"
        name.timeZone = stamp.timeZone
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymTrack-\(name.string(from: stamp.exportedAt)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The bytes of the file, without writing it anywhere.
    static func exportData(context: ModelContext, stamp: ExportStamp = .current()) throws -> Data {
        try encoded(makeArchive(context: context, stamp: stamp))
    }

    /// Sorted keys, so the same archive is the same bytes however the encoder
    /// happens to walk a dictionary.
    static func encoded(_ archive: Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// What the archive is made of, read from the store: models for the plans
    /// and the sessions (whose sets the snapshot turns into value types), and
    /// plain rows for the rest. Split from the assembly so the synchronous and
    /// the chunked snapshot can't drift apart.
    private struct SnapshotInputs {
        var plans: [Plan]
        var finished: [WorkoutSession]
        var custom: [CustomExerciseRecord]
        var bodyMetrics: [BodyMetric]
        var bodyMeasurements: [BodyMeasurement]
        var loadScales: [ExerciseLoadPreference]
        var hidden: [HiddenExerciseRecord]
    }

    private static func fetchInputs(_ context: ModelContext) throws -> SnapshotInputs {
        let plans = plansInOrder(try context.fetch(FetchDescriptor<Plan>()))
        let sessions = sessionsInOrder(try context.fetch(FetchDescriptor<WorkoutSession>()))
        return SnapshotInputs(
            plans: plans,
            finished: sessions.filter { !$0.isActive },
            custom: try context.fetch(FetchDescriptor<CustomExerciseRecord>()).sorted { $0.id < $1.id },
            bodyMetrics: try context.fetch(FetchDescriptor<BodyMetric>())
                .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) },
            bodyMeasurements: try context.fetch(FetchDescriptor<BodyMeasurement>())
                .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) },
            loadScales: try context.fetch(FetchDescriptor<ExerciseLoadPreference>()),
            hidden: try context.fetch(FetchDescriptor<HiddenExerciseRecord>())
        )
    }

    static func makeArchive(context: ModelContext, stamp: ExportStamp = .current()) throws -> Archive {
        let inputs = try fetchInputs(context)
        return assemble(inputs, sessions: inputs.finished.map(sessionDTO), stamp: stamp)
    }

    /// The same archive as `makeArchive`, with the walk over the sessions, which
    /// is nearly all of the time, cut into slices. The main actor is given back
    /// between them (see `Pacer`), so a year of history holds it for a slice at
    /// a time rather than for most of a second, and `progress` can move.
    ///
    /// Still on the main context: the same reads on a second one trapped inside
    /// SwiftData once a restore had run, so the store is only ever read here.
    @MainActor
    static func makeArchivePaced(context: ModelContext, stamp: ExportStamp = .current(),
                                 sliceMilliseconds: Double = Pacer.defaultSliceMilliseconds,
                                 progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> Archive {
        let inputs = try fetchInputs(context)
        var pacer = Pacer(sliceMilliseconds: sliceMilliseconds, report: progress)
        var sessions: [SessionDTO] = []
        sessions.reserveCapacity(inputs.finished.count)
        for (done, session) in inputs.finished.enumerated() {
            sessions.append(sessionDTO(session))
            await pacer.pauseIfDue(fraction: Double(done + 1) / Double(inputs.finished.count))
        }
        return assemble(inputs, sessions: sessions, stamp: stamp)
    }

    private static func assemble(_ inputs: SnapshotInputs, sessions: [SessionDTO], stamp: ExportStamp) -> Archive {
        let plans = inputs.plans
        let corrections = loadScaleDTOs(inputs.loadScales)
        // Taken from the session values rather than the models, so this walk
        // over every set is not a second trip through the store.
        let referenced = referencedExerciseIDs(plans: plans, sessions: sessions)

        return Archive(
            exportedAt: stamp.exportedAt,
            timeZone: stamp.timeZone.identifier,
            appVersion: stamp.appVersion,
            appBuild: stamp.appBuild,
            settings: Settings(
                weightUnit: AppSettings.shared.weightUnit.rawValue,
                userName: AppSettings.shared.userName,
                defaultRestSeconds: AppSettings.shared.defaultRestSeconds,
                trackRPE: AppSettings.shared.trackRPE
            ),
            plans: plans.map { plan in
                PlanDTO(id: plan.id, name: plan.name, summary: plan.summary,
                        isActive: plan.isActive, createdAt: plan.createdAt,
                        days: daysInOrder(of: plan).map { day in
                            DayDTO(id: day.id, name: day.name, order: day.order,
                                   weekday: day.weekday, isRest: day.isRest, notes: written(day.notes),
                                   items: itemsInOrder(of: day).map(itemDTO))
                        })
            },
            sessions: sessions,
            bodyMetrics: inputs.bodyMetrics.map {
                BodyMetricDTO(id: $0.id, date: $0.date, weightKg: $0.weightKg, source: $0.source)
            },
            bodyMeasurements: measurementDTOs(inputs.bodyMeasurements),
            customExercises: inputs.custom.map {
                CustomExerciseDTO(id: $0.id, name: $0.name, category: $0.category,
                                  muscleRaw: $0.muscleRaw, equipment: $0.equipment, trackingRaw: $0.trackingRaw)
            },
            loadScales: corrections,
            hiddenExercises: inputs.hidden.map(\.catalogID).sorted(),
            exerciseCatalog: referencedCatalog(referenced),
            effectiveLoadScales: effectiveLoadScales(referenced, corrections: corrections),
            effortScale: effortScale
        )
    }

    /// Nil for no check-ins, so the key is left out of the file. A check-in
    /// with no part measured can't exist through the app, but one that did
    /// would only be a date with nothing on it, so it is left out too.
    private static func measurementDTOs(_ rows: [BodyMeasurement]) -> [BodyMeasurementDTO]? {
        let dtos = rows.filter(\.hasAnyPart).map {
            BodyMeasurementDTO(id: $0.id, date: $0.date, armCm: $0.armCm, chestCm: $0.chestCm,
                               shouldersCm: $0.shouldersCm, waistCm: $0.waistCm, thighCm: $0.thighCm)
        }
        return dtos.isEmpty ? nil : dtos
    }

    private static func sessionDTO(_ session: WorkoutSession) -> SessionDTO {
        return SessionDTO(id: session.id, title: session.title, startedAt: session.startedAt,
                          // The stored end is the start again, there only to
                          // close the session; written out, it would read as a
                          // workout that took no time.
                          endedAt: session.isLoggedAfterwards ? nil : session.endedAt,
                          loggedAfterwards: session.isLoggedAfterwards ? true : nil,
                          // Trimmed: a field that was opened and cleared again
                          // shouldn't reach the file as a note made of spaces.
                          notes: written(session.trimmedNotes), planName: session.planName,
                          planDayID: session.planDayID,
                          plannedItems: session.plannedSlots?.enumerated().map { plannedItemDTO($1, order: $0) },
                          averageHeartRate: session.averageHeartRate,
                          maxHeartRate: session.maxHeartRate,
                          // Under a kilocalorie is a sensor that woke up,
                          // not what the workout cost.
                          activeEnergyKcal: session.reportableEnergyKcal,
                          healthWorkoutID: session.healthWorkoutID,
                          wasWatchDriven: session.wasWatchDriven,
                          // Read through the session, so a source left behind
                          // by numbers since cleared can't describe values
                          // that aren't in the file.
                          heartRateSource: session.heartRateSource?.rawValue,
                          heartRateReadings: session.reportableHeartRateReadings,
                          energySource: session.energySource?.rawValue,
                          noteTags: session.noteTagsRaw.isEmpty ? nil : session.noteTags.map(\.rawValue),
                          exerciseNotes: exerciseNotes(of: session),
                          sets: setsInOrder(of: session).map { set in
                              SetDTO(id: set.id, catalogID: set.catalogID, exerciseName: set.exerciseName,
                                     exerciseOrder: set.exerciseOrder, setIndex: set.setIndex,
                                     weightKg: set.weightKg,
                                     reps: set.tracking == .duration ? nil : set.reps,
                                     seconds: set.tracking == .duration ? set.seconds : nil,
                                     tracking: set.trackingRaw,
                                     isCompleted: set.isCompleted,
                                     completedAt: set.completedAt,
                                     startedAt: set.startedAt,
                                     // Read through the set, so half a pair
                                     // or a window running backwards never
                                     // reaches a reader as a set's length.
                                     detectedStartedAt: set.detectedWindow?.start,
                                     detectedEndedAt: set.detectedWindow?.end,
                                     targetRepsLow: repTarget(set.targetRepsLow, tracking: set.tracking),
                                     targetRepsHigh: repTarget(set.targetRepsHigh, tracking: set.tracking),
                                     rpe: set.rpe,
                                     effort: set.rpe.flatMap(SetFeel.answer(forStored:))?.exportKey,
                                     averageHeartRate: set.averageHeartRate,
                                     maxHeartRate: set.maxHeartRate,
                                     // Read through the set rather than off
                                     // the stored string, so a provenance left
                                     // behind by a set whose heart rate has
                                     // since been cleared can't reach the file
                                     // on its own, describing a window over
                                     // numbers that aren't there.
                                     heartRateWindow: set.heartRateWindow?.rawValue,
                                     loadNudge: loadNudge(of: set),
                                     // Read through the set, so a link whose
                                     // set isn't in this file can't reach a
                                     // reader as half a drop set.
                                     continues: set.continuation?.rawValue)
                          })
    }

    /// The four effort answers and the code each is stored under, taken from
    /// `SetFeel` itself so a change to the buttons can't leave the file
    /// describing a scale the app no longer has.
    static var effortScale: EffortScaleDTO {
        EffortScaleDTO(rpe: "bucketCode", buckets: SetFeel.allCases.map {
            EffortBucketDTO(effort: $0.exportKey, rpe: $0.rawValue, meaning: $0.spokenDetail)
        })
    }

    // MARK: File order

    private static func plansInOrder(_ plans: [Plan]) -> [Plan] {
        plans.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    private static func sessionsInOrder(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
    }

    /// `Plan.orderedDays` and `PlanDay.orderedItems` sort on `order` alone, and
    /// two rows sharing one (an old file, a hand edit) then come out in
    /// whichever order the store returned them.
    private static func daysInOrder(of plan: Plan) -> [PlanDay] {
        plan.days.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    private static func itemsInOrder(of day: PlanDay) -> [PlanItem] {
        day.items.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    /// The app's own grouping, so the row above a continuation is the one it
    /// continues.
    private static func setsInOrder(of session: WorkoutSession) -> [SetLog] {
        session.sets.sorted(by: SetLog.precedesInSession)
    }

    /// One correction per movement, written under the survivor's ID.
    ///
    /// The store can hold a row under a merged, losing ID (saved before the
    /// merge, or brought back by a restore) next to a newer one under the
    /// survivor. Written as stored, the file carried both, and a reader had two
    /// answers for one machine with nothing to say which one the app uses. The
    /// winner is picked by `LoadScaleBook`'s own rule, the newest save and on an
    /// exact tie the row already under the survivor, so the file says what the
    /// logger shows. Sorted so two exports of the same store read the same.
    private static func loadScaleDTOs(_ rows: [ExerciseLoadPreference]) -> [LoadScaleDTO] {
        var newest: [String: ExerciseLoadPreference] = [:]
        for row in rows {
            let key = ExerciseCatalog.canonicalID(for: row.catalogID)
            if let held = newest[key] {
                let isNewer = row.updatedAt != held.updatedAt
                    ? row.updatedAt > held.updatedAt
                    : row.catalogID == key
                guard isNewer else { continue }
            }
            newest[key] = row
        }
        return newest
            .sorted { $0.key < $1.key }
            .map { LoadScaleDTO(catalogID: $0.key, unit: $0.value.unitRaw, increment: $0.value.increment) }
    }

    /// A plan slot as the file describes it: the targets that apply to how it
    /// is measured, and none that are only a default or a zero standing in for
    /// "none". Read through `tracking`, the same answer the plan screen and
    /// the logger use, so the file prescribes what the app shows.
    static func itemDTO(_ item: PlanItem) -> ItemDTO {
        let timed = item.tracking == .duration
        return ItemDTO(id: item.id, catalogID: item.catalogID, name: item.name, order: item.order,
                       targetSets: item.targetSets,
                       targetRepsLow: repTarget(item.targetRepsLow, tracking: item.tracking),
                       targetRepsHigh: repTarget(item.targetRepsHigh, tracking: item.tracking),
                       targetWeightKg: item.targetWeightKg > 0 ? item.targetWeightKg : nil,
                       targetSeconds: timed && item.targetSeconds > 0 ? item.targetSeconds : nil,
                       tracking: item.trackingRaw,
                       restSeconds: item.restSeconds,
                       notes: written(item.notes))
    }

    /// A slot a session was opened against, by `itemDTO`'s rules.
    private static func plannedItemDTO(_ slot: PlannedSlot, order: Int) -> ItemDTO {
        let timed = slot.tracking == .duration
        return ItemDTO(id: slot.itemID, catalogID: slot.catalogID, name: slot.name, order: order,
                       targetSets: slot.targetSets,
                       targetRepsLow: repTarget(slot.targetRepsLow, tracking: slot.tracking),
                       targetRepsHigh: repTarget(slot.targetRepsHigh, tracking: slot.tracking),
                       targetWeightKg: nil,
                       targetSeconds: timed && slot.targetSeconds > 0 ? slot.targetSeconds : nil,
                       tracking: slot.trackingRaw,
                       restSeconds: slot.restSeconds,
                       notes: nil)
    }

    /// A rep target worth writing: one above zero, on something counted in
    /// reps. Zero is how a continuation row and a timed slot say "no target",
    /// and a reader can't tell that from a target of nothing.
    private static func repTarget(_ value: Int, tracking: TrackingMode) -> Int? {
        tracking != .duration && value > 0 ? value : nil
    }

    /// A note worth a key. An empty string on every day, slot and session was
    /// a line of nothing per record, and a reader parsing it can't tell that
    /// from a note somebody cleared on purpose.
    private static func written(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The notes kept on individual exercises in one session, in the order they
    /// were trained. Nothing is written for a session nobody wrote about.
    ///
    /// An empty note can't normally survive the end of a session, but the check
    /// is here too: this file is the one thing that outlives the app, and a
    /// note that says nothing would read to anything parsing it as a lifter who
    /// had something to report and didn't say what.
    private static func exerciseNotes(of session: WorkoutSession) -> [ExerciseNoteDTO]? {
        let notes = notesInOrder(of: session).filter { !$0.isEmpty }
        guard !notes.isEmpty else { return nil }
        return notes.map {
            ExerciseNoteDTO(catalogID: $0.catalogID, exerciseName: $0.exerciseName,
                            text: $0.trimmedText, tags: $0.tags.map(\.rawValue))
        }
    }

    /// `WorkoutSession.orderedExerciseNotes` with the ties settled: it ranks by
    /// the exercise's place in the session and then its name, which leaves two
    /// notes on one exercise in whatever order the store returned them.
    private static func notesInOrder(of session: WorkoutSession) -> [ExerciseNote] {
        let trained = Dictionary(session.sets.map { ($0.catalogID, $0.exerciseOrder) }, uniquingKeysWith: min)
        func key(_ note: ExerciseNote) -> (Int, String, String, String) {
            (trained[note.catalogID] ?? .max, note.exerciseName, note.catalogID, note.id.uuidString)
        }
        return session.exerciseNotes.sorted { key($0) < key($1) }
    }

    /// What the app offered this set's rating and what came of it, where an
    /// offer was both made and resolved. Nothing is written otherwise: a set
    /// nobody was offered a rung on has to stay indistinguishable from a set
    /// logged before any of this existed, which is what a null or a "none"
    /// would quietly break.
    private static func loadNudge(of set: SetLog) -> LoadNudgeDTO? {
        guard let outcome = set.loadNudgeOutcome, let toKg = set.loadNudgeToKg else { return nil }
        return LoadNudgeDTO(outcome: outcome.rawValue, toKg: toKg)
    }

    /// The library definitions behind the exercises the archive's plans and
    /// sessions name, and only those — the bundled library runs to hundreds of
    /// entries, and a backup is a file the user opens and sends on, not a copy
    /// of the app's resources.
    ///
    /// Load scales and the hidden list are read as settings rather than as
    /// training, so the IDs in them don't pull an exercise in: hiding is how
    /// the library gets trimmed down to one gym, and following that list would
    /// put most of the library back in the file it was kept out of.
    private static func referencedCatalog(_ referenced: Set<String>) -> [CatalogExerciseDTO] {
        // Sorted so two exports of unchanged data are the same bytes, which is
        // what `.sortedKeys` buys everywhere else in the file.
        referenced.sorted().compactMap { id in
            // A custom exercise is left to `customExercises`, and an ID that
            // resolves to nothing at all — a custom exercise deleted out from
            // under its own history — has nothing to say. The set still
            // carries the name it was logged under.
            guard let exercise = ExerciseCatalog.shared.exercise(id: id), !exercise.isCustom else { return nil }
            return CatalogExerciseDTO(
                catalogID: id,
                name: exercise.name,
                category: exercise.category,
                muscleRaw: exercise.muscleGroups,
                muscles: exercise.muscles.map(\.name),
                equipment: exercise.equipment,
                trackingRaw: exercise.tracking.rawValue
            )
        }
    }

    /// Every exercise ID the plans and sessions in this file spell, as they
    /// spell it.
    private static func referencedExerciseIDs(plans: [Plan], sessions: [SessionDTO]) -> Set<String> {
        var ids: Set<String> = []
        for plan in plans {
            for day in plan.days {
                for item in day.items { ids.insert(item.catalogID) }
            }
        }
        for session in sessions {
            for set in session.sets { ids.insert(set.catalogID) }
        }
        return ids
    }

    /// The rung of every exercise the plans and sessions name, with whether the
    /// lifter set it or the app worked it out.
    ///
    /// A correction is read off the rows already resolved for `loadScales`, so
    /// the two sections of one file can't disagree about a machine. Everything
    /// else takes `LoadScaleBook.derived`, the rule the logger falls back to,
    /// in the app-wide unit this file's `settings` states. An ID that resolves
    /// to no exercise and has no correction is left out: a custom exercise
    /// deleted under its own history has no equipment to derive a rung from, and
    /// the fallback for "unknown" would be a rung nobody chose.
    private static func effectiveLoadScales(_ referenced: Set<String>,
                                            corrections: [LoadScaleDTO]) -> [EffectiveLoadScaleDTO] {
        let unit = AppSettings.shared.weightUnit
        let corrected = Dictionary(corrections.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        return referenced.sorted().compactMap { id in
            if let row = corrected[ExerciseCatalog.canonicalID(for: id)] {
                return EffectiveLoadScaleDTO(catalogID: id, unit: row.unit, increment: row.increment,
                                             source: "correction")
            }
            guard let exercise = ExerciseCatalog.shared.exercise(id: id) else { return nil }
            let scale = LoadScaleBook.derived(for: exercise, unit: unit)
            return EffectiveLoadScaleDTO(catalogID: id, unit: scale.unit.rawValue,
                                         increment: scale.increment, source: "derived")
        }
    }

    // MARK: - Import

    enum RestoreError: LocalizedError {
        case workoutInProgress
        /// A second restore started while one was still working through its
        /// slices. Two would wipe and insert into the same context together.
        case alreadyRunning
        /// A value no version of this app writes, found before anything on
        /// the phone was touched. It names the record, the field and the value
        /// so the file can be put right by hand, which matters most for a file
        /// the app didn't write, such as a plan an AI coach drew up.
        case invalidValue(field: String, value: String, record: String, allowed: String)

        var errorDescription: String? {
            switch self {
            case .workoutInProgress:
                "Finish or discard the workout that's running first. Restoring replaces everything on this phone, and a workout still in progress isn't in any backup to bring it back."
            case .alreadyRunning:
                "A restore is already running. Wait for it to finish."
            case let .invalidValue(field, value, record, allowed):
                "This backup can't be restored: \(record) has a \(field) of \(value), which has to be \(allowed). Nothing on this phone was changed."
            }
        }
    }

    enum WipeError: LocalizedError {
        case workoutInProgress

        var errorDescription: String? {
            switch self {
            case .workoutInProgress:
                "Finish or discard the workout that's running first. Erasing now would remove it from under the logger and the watch."
            }
        }
    }

    /// What became of an erase that was asked to remove workouts from Health.
    /// Local data is committed even if Health refuses a workout deletion.
    /// Keeping the failed IDs visible lets the caller report that partial result.
    struct HealthCleanupResult {
        var failedIDs: [UUID]
        var isComplete: Bool { failedIDs.isEmpty }
    }

    /// Replaces everything currently stored with the archive's contents.
    ///
    /// Refused while a workout is open. Export leaves the running session out,
    /// so no file can hold it, and the wipe would delete it from under the
    /// logger, the dock, the Live Activity and the wrist, all of which are
    /// still reading it. Nothing is touched before this check. The old records
    /// and their replacements share one save; a failed import rolls both back.
    ///
    /// Apple Health is never touched. A session the file doesn't hold leaves
    /// GymTrack, and its workout stays in Health: a deletion there reaches
    /// every device on the account and nothing brings it back, which is not
    /// something to do as a side effect of picking a file.
    @MainActor
    static func restore(from url: URL, context: ModelContext, beforeCommit: () throws -> Void = {}) throws {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        try restore(data: data, context: context, beforeCommit: beforeCommit)
    }

    /// The importer reads the security-scoped file while its callback is live,
    /// then hands these bytes to the restore.
    @MainActor
    static func restore(data: Data, context: ModelContext, beforeCommit: () throws -> Void = {}) throws {
        try requireNoOpenWorkout(context)
        try apply(try decodedArchive(from: data), context: context, beforeCommit: beforeCommit)
    }

    /// `restore(from:)` with the reading, decoding and validating moved off
    /// the main actor. Validation still finishes before anything is deleted, so
    /// a bad file leaves the phone as it was.
    ///
    /// The wipe and the inserts can be cut into slices, but by default they
    /// are not (`Pacer.restoreSliceMilliseconds`). Between the wipe and the one
    /// save, a pause would let a watch command or a Health backfill run on the
    /// same main context and save it, committing half a restore. Holding the
    /// main actor for the second or two the apply takes is the smaller cost for
    /// something done this rarely.
    ///
    /// The store is still written on the main context, and there is still one
    /// save, at the end: nothing reaches the store until every insert has been
    /// made, so a failure part-way, whether in an insert, in `beforeCommit` or
    /// in the save itself, rolls back to exactly what was there. Autosave is
    /// switched off for the duration, or a slice boundary could commit half a
    /// restore. A second context over the same store trapped inside SwiftData
    /// in testing (see `exportOffMain`), so it is not used.
    ///
    /// `progress` runs on the main actor with a fraction from 0 to 1.
    @MainActor
    static func restoreOffMain(from url: URL, context: ModelContext,
                               beforeCommit: () throws -> Void = {},
                               sliceMilliseconds: Double = Pacer.restoreSliceMilliseconds,
                               progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        try requireNoOpenWorkout(context)
        let archive = try await Task.detached(priority: .userInitiated) {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            return try decodedArchive(from: try Data(contentsOf: url))
        }.value
        try await applyPaced(archive, context: context, beforeCommit: beforeCommit,
                             sliceMilliseconds: sliceMilliseconds, progress: progress)
    }

    /// The same, for bytes already in memory.
    @MainActor
    static func restoreOffMain(data: Data, context: ModelContext,
                               beforeCommit: () throws -> Void = {},
                               sliceMilliseconds: Double = Pacer.restoreSliceMilliseconds,
                               progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws {
        try requireNoOpenWorkout(context)
        let archive = try await Task.detached(priority: .userInitiated) {
            try decodedArchive(from: data)
        }.value
        try await applyPaced(archive, context: context, beforeCommit: beforeCommit,
                             sliceMilliseconds: sliceMilliseconds, progress: progress)
    }

    /// Decoded and validated, and nothing more: no store, so it may run on any
    /// thread. Validation belongs here because it has to finish before the
    /// wipe, and every caller that reaches the wipe goes through it.
    static func decodedArchive(from data: Data) throws -> Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Archive.self, from: data)
        // Before the wipe, so a file that would crash the plan screens on
        // every launch is turned away with the old data still in place.
        try validate(archive)
        return archive
    }

    @MainActor
    private static func requireNoOpenWorkout(_ context: ModelContext) throws {
        let open = try context.fetchCount(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil }))
        guard open == 0 else { throw RestoreError.workoutInProgress }
    }

    /// The wipe and the inserts on the main context.
    @MainActor
    private static func apply(_ archive: Archive, context: ModelContext,
                              beforeCommit: () throws -> Void) throws {
        try applyStore(archive, context: context, beforeCommit: beforeCommit)
        finishRestore(archive, context: context)
    }

    /// True while a paced restore is between its first delete and its save.
    @MainActor private static var pacedRestoreRunning = false

    /// `apply`, in slices. The fraction reported counts one unit for each
    /// session deleted, one for each restored and one for the save, since the
    /// sessions are where the time goes.
    @MainActor
    private static func applyPaced(_ archive: Archive, context: ModelContext,
                                   beforeCommit: () throws -> Void, sliceMilliseconds: Double,
                                   progress: @escaping @MainActor (Double) -> Void) async throws {
        guard !pacedRestoreRunning else { throw RestoreError.alreadyRunning }
        pacedRestoreRunning = true
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer {
            context.autosaveEnabled = autosave
            pacedRestoreRunning = false
        }

        // The workout check again, because the decode above awaited and a
        // workout started in that gap would be deleted from under the logger.
        try requireNoOpenWorkout(context)
        var pacer = Pacer(sliceMilliseconds: sliceMilliseconds, report: progress)
        do {
            let oldSessions = try context.fetchCount(FetchDescriptor<WorkoutSession>())
            let total = Double(oldSessions + archive.sessions.count + 1)

            let localLinks = try await deleteStoredRecords(context: context, pacer: &pacer, total: total)
            let links = linksBySession(localLinks)

            insertExercisesAndPlans(archive, context: context)
            for (n, dto) in archive.sessions.enumerated() {
                insertSession(dto, keepingLinks: links, context: context)
                await pacer.pauseIfDue(fraction: Double(oldSessions + n + 1) / total)
            }
            insertRemainder(archive, context: context)

            try beforeCommit()
            progress((total - 1) / total)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        finishRestore(archive, context: context)
        progress(1)
    }

    /// Checks for an open workout again, because the off-main restore awaits
    /// between its first check and here, and a workout started in that gap
    /// would be deleted from under the logger. Then the wipe and the inserts,
    /// under one save; a failure rolls the lot back.
    @MainActor
    private static func applyStore(_ archive: Archive, context: ModelContext,
                                   beforeCommit: () throws -> Void) throws {
        try requireNoOpenWorkout(context)
        do {
            let localLinks = try deleteStoredRecords(context: context)

            insertArchive(archive, keepingLinks: linksBySession(localLinks), context: context)

            try beforeCommit()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// What follows a committed restore, and needs the main actor: the
    /// settings the file carries and the caches built from the store.
    @MainActor
    private static func finishRestore(_ archive: Archive, context: ModelContext) {
        AppSettings.shared.weightUnit = WeightUnit(rawValue: archive.settings.weightUnit) ?? .kg
        AppSettings.shared.userName = archive.settings.userName
        AppSettings.shared.defaultRestSeconds = archive.settings.defaultRestSeconds

        LoadScaleBook.shared.reload()
        ExerciseVisibility.reload(context: context)
        // Told directly rather than left to the root view, which only
        // re-reads the user's exercises when their count changes. A backup
        // from another phone with as many custom exercises as this one left
        // the library listing the ones just wiped and missing the ones just
        // restored, and their sets resolving to nothing, until a relaunch.
        context.refreshCustomExercises()
    }

    /// A session's link to its Health workout, remembered across the wipe so a
    /// restore can tell which session each workout belonged to.
    private struct HealthLink {
        let session: UUID
        let workout: UUID
    }

    /// `id` carries no uniqueness constraint. Should two rows ever share one,
    /// the first link is carried over and the other is dropped with its row.
    private static func linksBySession(_ links: [HealthLink]) -> [UUID: UUID] {
        Dictionary(links.map { ($0.session, $0.workout) }, uniquingKeysWith: { first, _ in first })
    }

    /// The restored session's Health link, decided by session identity.
    ///
    /// A file written before linkage has no `healthWorkoutID` at all, so
    /// taking its word would unlink every session it restores, and nothing
    /// writes the link back once a session has finished. A file taken between
    /// the phone's fallback save and the watch's own names a workout this
    /// device has since replaced. In both cases the link already on this
    /// device is the current one, so it wins whenever there is one.
    private static func restoredHealthLink(for dto: SessionDTO, keeping localLinks: [UUID: UUID]) -> UUID? {
        localLinks[dto.id] ?? dto.healthWorkoutID
    }

    /// The highest rep target the day editor has ever offered. No file this
    /// app wrote goes past it, and the editor can't show a range that does.
    private static let maxRepTarget = 60

    /// Turns away a file holding values no version of this app writes, before
    /// anything on the phone is touched.
    ///
    /// A hand-edited or foreign file, such as a plan an AI coach drew up,
    /// restored cleanly with a weekday of 0 or a low rep target of 70, and the
    /// plan screens then trapped on every launch with the bad row still in the
    /// store. Nothing is clamped into range instead: a clamped value is one
    /// this app made up and stored as though the file had said it. Warm-ups
    /// are passed over, because the restore never stores them.
    static func validate(_ archive: Archive) throws {
        try requireSeconds(archive.settings.defaultRestSeconds, field: "default rest", record: "the settings")
        // Restore keeps every ID the file carries, and a session finds its day
        // by `planDayID`. Two days under one ID would have the second silently
        // stand in for the first wherever a session is matched to its plan, and
        // a repeated plan or session ID does the same to whatever cites it. A
        // hand-edited file or a copy-pasted block is how it happens. Plan slots
        // are not compared: their ID is optional, and a repeated one is
        // replaced by a new one on restore rather than refused, since nothing
        // in the file cites a slot.
        var seenPlanIDs: Set<UUID> = []
        var seenDayIDs: Set<UUID> = []
        // A custom exercise is looked up by its ID, from a set, a plan slot and
        // a note alike, so two under one ID would have every one of those
        // resolve to whichever the store returned first, and its name, muscle
        // and tracking would be the other's.
        var seenExerciseIDs: Set<String> = []
        for exercise in archive.customExercises where !seenExerciseIDs.insert(exercise.id).inserted {
            throw RestoreError.invalidValue(field: "custom exercise ID", value: exercise.id,
                                           record: "\"\(exercise.name)\"",
                                           allowed: "different from every other custom exercise's ID in this file")
        }
        for plan in archive.plans {
            if !seenPlanIDs.insert(plan.id).inserted {
                throw RestoreError.invalidValue(field: "plan ID", value: plan.id.uuidString,
                                               record: "the plan \"\(plan.name)\"",
                                               allowed: "different from every other plan's ID in this file")
            }
            for day in plan.days {
                let dayRecord = "the day \"\(day.name)\" in \"\(plan.name)\""
                if !seenDayIDs.insert(day.id).inserted {
                    throw RestoreError.invalidValue(field: "day ID", value: day.id.uuidString, record: dayRecord,
                                                   allowed: "different from every other day's ID in this file")
                }
                if let weekday = day.weekday, !(1...7).contains(weekday) {
                    throw RestoreError.invalidValue(field: "weekday", value: "\(weekday)", record: dayRecord,
                                                   allowed: "1 (Sunday) to 7 (Saturday), or left out")
                }
                for item in day.items {
                    let record = "\"\(item.name)\" on \(dayRecord)"
                    try requireRepTargets(low: item.targetRepsLow, high: item.targetRepsHigh, record: record)
                    try requireWeight(item.targetWeightKg, field: "starting weight", record: record)
                    try requireSeconds(item.targetSeconds, field: "hold time", record: record)
                    try requireSeconds(item.restSeconds, field: "rest", record: record)
                }
            }
        }
        var seenSetIDs: Set<UUID> = []
        var seenSessionIDs: Set<UUID> = []
        for session in archive.sessions {
            let date = session.startedAt.formatted(date: .abbreviated, time: .omitted)
            if !seenSessionIDs.insert(session.id).inserted {
                throw RestoreError.invalidValue(field: "session ID", value: session.id.uuidString,
                                               record: "the session \"\(session.title)\" on \(date)",
                                               allowed: "different from every other session's ID in this file")
            }
            for set in session.sets where set.isWarmup != true {
                let record = "a set of \"\(set.exerciseName)\" on \(date)"
                // Restore keeps the file's set IDs, so a repeated one would put
                // two sets under one ID, and a coach citing that ID would be
                // pointing at whichever the store returned first. A hand-edited
                // file or a copy-pasted block of sets is how it happens.
                if let id = set.id, !seenSetIDs.insert(id).inserted {
                    throw RestoreError.invalidValue(field: "set ID", value: id.uuidString, record: record,
                                                   allowed: "different from every other set's ID in this file")
                }
                try requireRepTargets(low: set.targetRepsLow, high: set.targetRepsHigh, record: record)
                try requireWeight(set.weightKg, field: "weight", record: record)
                try requireReps(set.reps, record: record)
                try requireSeconds(set.seconds, field: "time", record: record)
                try requireWeight(set.loadNudge?.toKg, field: "offered weight", record: record)
            }
        }
        for metric in archive.bodyMetrics ?? [] {
            let date = metric.date.formatted(date: .abbreviated, time: .omitted)
            try requireWeight(metric.weightKg, field: "body weight", record: "the weigh-in on \(date)")
        }
        for check in archive.bodyMeasurements ?? [] {
            let date = check.date.formatted(date: .abbreviated, time: .omitted)
            let parts = [("arm", check.armCm), ("chest", check.chestCm), ("shoulders", check.shouldersCm),
                         ("waist", check.waistCm), ("thigh", check.thighCm)]
            for (name, cm) in parts {
                try requireLength(cm, field: name, record: "the measurements on \(date)")
            }
        }
    }

    /// An absent target is a zero, the value export leaves out.
    ///
    /// A range that runs backwards is let through. Nothing traps on one, and
    /// this app wrote them itself before the day editor kept the ends in
    /// order, so refusing one would turn away the user's own older backups.
    private static func requireRepTargets(low: Int?, high: Int?, record: String) throws {
        let low = low ?? 0, high = high ?? 0
        guard (0...maxRepTarget).contains(low) && (0...maxRepTarget).contains(high) else {
            throw RestoreError.invalidValue(field: "rep range", value: "\(low)–\(high)", record: record,
                                           allowed: "between 0 and \(maxRepTarget)")
        }
    }

    private static func requireWeight(_ kg: Double?, field: String, record: String) throws {
        guard let kg, !kg.isFinite || kg < 0 else { return }
        throw RestoreError.invalidValue(field: field, value: "\(kg) kg", record: record,
                                       allowed: "a real number of kilograms, zero or more")
    }

    /// A girth that is there is a real length above zero. Zero is refused, not
    /// let through like a weight, because a skipped part has no key to begin
    /// with, so a zero in a file was never written by this app.
    private static func requireLength(_ cm: Double?, field: String, record: String) throws {
        guard let cm, !cm.isFinite || cm <= 0 else { return }
        throw RestoreError.invalidValue(field: field, value: "\(cm) cm", record: record,
                                       allowed: "a real number of centimetres, above zero")
    }

    /// A negative count restored cleanly and History then showed negative
    /// reps and negative volume for the set. Zero is let through: a set
    /// counted in time has no reps key, which restores as zero, and an older
    /// file wrote that zero out.
    private static func requireReps(_ reps: Int?, record: String) throws {
        guard let reps, reps < 0 else { return }
        throw RestoreError.invalidValue(field: "rep count", value: "\(reps)", record: record,
                                       allowed: "zero or more")
    }

    private static func requireSeconds(_ seconds: Int?, field: String, record: String) throws {
        guard let seconds, seconds < 0 else { return }
        throw RestoreError.invalidValue(field: field, value: "\(seconds) s", record: record,
                                       allowed: "zero seconds or more")
    }

    /// The tracking a restored plan slot carries in `trackingRaw`.
    ///
    /// A slot for one of the user's own exercises takes that exercise's
    /// tracking, the snapshot the day editor stamps on a new one
    /// (`slotTrackingSnapshot`). The snapshot is what keeps the slot in reps or
    /// in time once the exercise is deleted and the catalog lookup misses; a
    /// slot restored without one would fall to weight-and-reps then, under
    /// targets written for a hold. It follows the exercise rather than the
    /// file's own value because the file's targets were written under the
    /// exercise's tracking, and a stale snapshot would contradict them.
    ///
    /// Any other slot keeps what the file says, which is nothing for a bundled
    /// exercise, and a snapshot the file carries for one whose custom exercise
    /// was already deleted when it was exported.
    private static func slotTracking(of item: ItemDTO, customTracking: [String: TrackingMode]) -> TrackingMode? {
        customTracking[item.catalogID] ?? item.tracking.flatMap(TrackingMode.init(rawValue:))
    }

    private static func insertArchive(_ archive: Archive, keepingLinks localLinks: [UUID: UUID],
                                      context: ModelContext) {
        insertExercisesAndPlans(archive, context: context)
        for dto in archive.sessions { insertSession(dto, keepingLinks: localLinks, context: context) }
        insertRemainder(archive, context: context)
    }

    /// The user's own exercises and the plans, the small part of a restore.
    private static func insertExercisesAndPlans(_ archive: Archive, context: ModelContext) {
        let customTracking = Dictionary(
            archive.customExercises.map { ($0.id, TrackingMode(rawValue: $0.trackingRaw) ?? .weightReps) },
            uniquingKeysWith: { first, _ in first })

        for dto in archive.customExercises {
            let record = CustomExerciseRecord(name: dto.name, muscles: [], equipment: dto.equipment,
                                              tracking: TrackingMode(rawValue: dto.trackingRaw) ?? .weightReps)
            record.id = dto.id
            record.category = dto.category
            record.muscleRaw = dto.muscleRaw
            context.insert(record)
        }

        var takenItemIDs: Set<UUID> = []
        for dto in archive.plans {
            let plan = Plan(name: dto.name, summary: dto.summary, isActive: dto.isActive)
            plan.id = dto.id
            plan.createdAt = dto.createdAt
            context.insert(plan)

            for dayDTO in dto.days {
                let day = PlanDay(name: dayDTO.name, order: dayDTO.order, weekday: dayDTO.weekday,
                                  isRest: dayDTO.isRest, notes: dayDTO.notes ?? "")
                day.id = dayDTO.id
                day.plan = plan
                context.insert(day)

                for itemDTO in dayDTO.items {
                    // An absent target is one the file left out for being
                    // zero or not applying, so it comes back as the zero it
                    // was. An absent hold time comes back as the store's own
                    // default, which is what a reps slot held before export.
                    let item = PlanItem(catalogID: itemDTO.catalogID, name: itemDTO.name, order: itemDTO.order,
                                        targetSets: itemDTO.targetSets, targetRepsLow: itemDTO.targetRepsLow ?? 0,
                                        targetRepsHigh: itemDTO.targetRepsHigh ?? 0,
                                        targetWeightKg: itemDTO.targetWeightKg ?? 0,
                                        restSeconds: itemDTO.restSeconds)
                    if let seconds = itemDTO.targetSeconds { item.targetSeconds = seconds }
                    // Kept so a proposal written against the exported plan
                    // still finds its slot after a restore. One the file
                    // repeats keeps its first owner; the rest stay as new.
                    if let id = itemDTO.id, !takenItemIDs.contains(id) { item.id = id }
                    takenItemIDs.insert(item.id)
                    item.notes = itemDTO.notes ?? ""
                    item.trackingRaw = slotTracking(of: itemDTO, customTracking: customTracking)?.rawValue
                    item.day = day
                    context.insert(item)
                }
            }
        }
    }

    /// One session with its notes and sets. The unit the chunked restore paces
    /// itself by, and the same body the synchronous one loops over.
    private static func insertSession(_ dto: SessionDTO, keepingLinks localLinks: [UUID: UUID],
                                      context: ModelContext) {
        let session = WorkoutSession(title: dto.title, planName: dto.planName, startedAt: dto.startedAt)
        session.id = dto.id
        session.isLoggedAfterwards = dto.loggedAfterwards == true
        // Closed at its own start, as the past-workout sheet closes it. Left
        // open, it would come back as a workout in progress.
        session.endedAt = dto.endedAt ?? (session.isLoggedAfterwards ? dto.startedAt : nil)
        session.planDayID = dto.planDayID
        session.plannedSlots = dto.plannedItems?.map { item in
            PlannedSlot(itemID: item.id, catalogID: item.catalogID, name: item.name,
                        targetSets: item.targetSets, targetRepsLow: item.targetRepsLow ?? 0,
                        targetRepsHigh: item.targetRepsHigh ?? 0, targetSeconds: item.targetSeconds ?? 0,
                        restSeconds: item.restSeconds,
                        trackingRaw: item.tracking ?? TrackingMode.weightReps.rawValue)
        }
        session.notes = dto.notes ?? ""
        session.averageHeartRate = dto.averageHeartRate
        session.maxHeartRate = dto.maxHeartRate
        session.activeEnergyKcal = dto.activeEnergyKcal
        session.healthWorkoutID = restoredHealthLink(for: dto, keeping: localLinks)
        session.wasWatchDriven = dto.wasWatchDriven ?? false
        session.heartRateSourceRaw = dto.heartRateSource
        session.heartRateReadings = dto.heartRateReadings
        session.energySourceRaw = dto.energySource
        // Tags the app doesn't know are dropped rather than stored: a value
        // nothing can draw would sit in the record unreadable and be
        // written back out as though it had been understood.
        session.noteTagsRaw = NoteTag.resolve(dto.noteTags ?? []).map(\.rawValue)
        context.insert(session)

        for noteDTO in dto.exerciseNotes ?? [] {
            let tags = NoteTag.resolve(noteDTO.tags)
            let text = noteDTO.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty || !tags.isEmpty else { continue }
            let note = ExerciseNote(catalogID: noteDTO.catalogID, exerciseName: noteDTO.exerciseName)
            note.text = text
            note.tags = tags
            note.session = session
            context.insert(note)
        }

        // A warm-up from a file written before warm-ups were removed is
        // left out, the rule the store migration (`dropWarmupSets`)
        // applied to the phone's own rows. Nothing marks a warm-up any
        // more, so stored it would become an ordinary working set: a
        // 40 kg ramp-up counted as training, inflating volume and pairing
        // the next session's first set against it. That is false detail.
        for setDTO in dto.sets where setDTO.isWarmup != true {
            let set = SetLog(catalogID: setDTO.catalogID, exerciseName: setDTO.exerciseName,
                             exerciseOrder: setDTO.exerciseOrder, setIndex: setDTO.setIndex,
                             weightKg: setDTO.weightKg, reps: setDTO.reps ?? 0, seconds: setDTO.seconds ?? 0,
                             targetRepsLow: setDTO.targetRepsLow ?? 0, targetRepsHigh: setDTO.targetRepsHigh ?? 0,
                             tracking: setDTO.tracking.flatMap(TrackingMode.init(rawValue:)))
            // Kept where the file has one, so a citation of this set still
            // resolves after a restore. A file from before sets were
            // numbered keeps the fresh one the initializer just made.
            if let id = setDTO.id { set.id = id }
            set.isCompleted = setDTO.isCompleted
            set.completedAt = setDTO.completedAt
            set.startedAt = setDTO.startedAt
            // Only a whole window, running forwards and over by the time
            // the set was logged. Anything less is not a reading of this
            // set, and stored it would be exported again as though it were.
            if let start = setDTO.detectedStartedAt, let end = setDTO.detectedEndedAt,
               let logged = setDTO.completedAt, start < end, end <= logged {
                set.recordDetectedWindow(DetectedSetWindow(start: start, end: end))
            }
            set.rpe = setDTO.rpe
            set.averageHeartRate = setDTO.averageHeartRate
            set.maxHeartRate = setDTO.maxHeartRate
            // A window the app doesn't recognise is dropped rather than
            // stored, the way an unknown note tag is: a provenance nothing
            // can read would still be written back out on the next export
            // as though it had been understood. The numbers survive it and
            // read as a heart rate of unstated provenance, which is the
            // truth about them once their label is unreadable.
            set.heartRateWindowRaw = setDTO.heartRateWindow
                .flatMap(HeartRateWindowSource.init(rawValue:))?.rawValue
            // An outcome the app can't read is dropped whole, rung and all.
            // Unlike a heart rate, whose numbers survive losing their
            // label, there is nothing left here once the word goes: a rung
            // on its own doesn't say whether anybody took it.
            if let nudge = setDTO.loadNudge, let outcome = LoadNudgeOutcome(rawValue: nudge.outcome) {
                set.recordLoadNudge(outcome, toKg: nudge.toKg)
            }
            // The key being there is the whole of what's restored — which
            // kind of continuation it was gets read back off the weights,
            // so an unfamiliar word costs nothing here, unlike an unknown
            // heart-rate window or a load outcome. What it can't survive is
            // having nothing above it to continue: the first set of an
            // exercise continues the end of the exercise before it, or
            // nothing at all, and a file claiming otherwise would put a
            // dangling link into the record that no reader could resolve.
            if setDTO.continues != nil && setDTO.setIndex > 0 {
                set.continuesPreviousSet = true
            }
            set.session = session
            context.insert(set)
        }
    }

    /// Body weights, tape measurements, load corrections and hidden exercises.
    private static func insertRemainder(_ archive: Archive, context: ModelContext) {
        for dto in archive.bodyMetrics ?? [] {
            let metric = BodyMetric(date: dto.date, weightKg: dto.weightKg)
            metric.id = dto.id
            metric.source = dto.source
            context.insert(metric)
        }

        for dto in archive.bodyMeasurements ?? [] {
            let check = BodyMeasurement(date: dto.date)
            check.id = dto.id
            check.set(dto.armCm, for: .arm)
            check.set(dto.chestCm, for: .chest)
            check.set(dto.shouldersCm, for: .shoulders)
            check.set(dto.waistCm, for: .waist)
            check.set(dto.thighCm, for: .thigh)
            // An empty one is dropped for the reason export drops it.
            if check.hasAnyPart { context.insert(check) }
        }

        for dto in archive.loadScales ?? [] {
            let scale = LoadScale(unit: WeightUnit(rawValue: dto.unit) ?? .kg, increment: dto.increment)
            context.insert(ExerciseLoadPreference(catalogID: dto.catalogID, scale: scale))
        }

        for catalogID in archive.hiddenExercises ?? [] {
            context.insert(HiddenExerciseRecord(catalogID: catalogID))
        }
    }

    /// Deletes every record, and removes the linked workouts from Health only
    /// when the lifter chose that separately.
    ///
    /// Health is left alone by default because a deletion there is not "on
    /// this device": it reaches every device on the iCloud account, and a
    /// backup holds only each workout's ID, so the Export the erase dialog
    /// recommends can't bring one back. Returns `nil` when Health wasn't asked
    /// to do anything, so nobody can read a cleanup that never ran as one that
    /// succeeded. Health permission can fail after the local erase succeeds,
    /// so a cleanup that did run says which part remains in Health.
    ///
    /// The workouts go to Health as one batch, in a defined order, each ID
    /// once. One query and one delete replace a round trip per session, which
    /// held the sheet on an empty store for as long as the history was long.
    /// `deletingHealthWorkouts` returns the IDs it could not remove; the
    /// per-ID closure remains for callers that only know one at a time.
    @MainActor
    @discardableResult
    static func wipe(
        context: ModelContext,
        removingHealthWorkouts: Bool = false,
        deletingHealthWorkout: ((UUID) async -> Bool)? = nil,
        deletingHealthWorkouts: (([UUID]) async -> [UUID])? = nil
    ) async throws -> HealthCleanupResult? {
        let open = try context.fetchCount(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil }))
        guard open == 0 else { throw WipeError.workoutInProgress }

        let healthIDs: Set<UUID>
        do {
            healthIDs = Set(try deleteStoredRecords(context: context).map(\.workout))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        LoadScaleBook.shared.reload()
        ExerciseVisibility.reload(context: context)
        context.refreshCustomExercises()
        guard removingHealthWorkouts else { return nil }
        let ids = healthIDs.sorted(by: { $0.uuidString < $1.uuidString })
        if let deletingHealthWorkouts {
            return HealthCleanupResult(failedIDs: await deletingHealthWorkouts(ids))
        }
        if let deletingHealthWorkout {
            return await deleteHealthWorkouts(healthIDs, using: deletingHealthWorkout)
        }
        return HealthCleanupResult(failedIDs: await HealthKitService.shared.deleteWorkouts(ids: ids))
    }

    /// How many Health workouts an erase could remove, for the erase dialog to
    /// name. Counted by workout rather than by session, which is what the
    /// erase itself deletes.
    @MainActor
    static func linkedHealthWorkoutCount(context: ModelContext) -> Int {
        let linked = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.healthWorkoutID != nil })
        let sessions = (try? context.fetch(linked)) ?? []
        return Set(sessions.compactMap(\.healthWorkoutID)).count
    }

    /// Deletes instances rather than using `context.delete(model:)`: that issues
    /// a batch delete, which can't satisfy `PlanItem`'s mandatory inverse to
    /// `PlanDay` and fails with a constraint trigger violation. Removing the
    /// roots lets the cascade rules do the work.
    ///
    /// Returns each deleted session's Health link with the session's `id`,
    /// because a restore has to know which session a link belonged to, not
    /// just that it existed.
    @MainActor
    private static func deleteStoredRecords(context: ModelContext) throws -> [HealthLink] {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let healthLinks = sessions.compactMap { session in
            session.healthWorkoutID.map { HealthLink(session: session.id, workout: $0) }
        }
        for plan in try context.fetch(FetchDescriptor<Plan>()) { context.delete(plan) }
        for session in sessions { context.delete(session) }
        for metric in try context.fetch(FetchDescriptor<BodyMetric>()) { context.delete(metric) }
        for check in try context.fetch(FetchDescriptor<BodyMeasurement>()) { context.delete(check) }
        for record in try context.fetch(FetchDescriptor<CustomExerciseRecord>()) { context.delete(record) }

        // Sweep anything the cascade missed (orphans from an interrupted write).
        for item in try context.fetch(FetchDescriptor<PlanItem>()) { context.delete(item) }
        for day in try context.fetch(FetchDescriptor<PlanDay>()) { context.delete(day) }
        for set in try context.fetch(FetchDescriptor<SetLog>()) { context.delete(set) }
        for note in try context.fetch(FetchDescriptor<ExerciseNote>()) { context.delete(note) }
        for scale in try context.fetch(FetchDescriptor<ExerciseLoadPreference>()) { context.delete(scale) }
        for hidden in try context.fetch(FetchDescriptor<HiddenExerciseRecord>()) { context.delete(hidden) }

        return healthLinks
    }

    /// `deleteStoredRecords` in slices, in the same order and over the same
    /// rows. Only the deletes of sessions and the sweeps, which is where the
    /// time is, give the main actor back; the deletes are still unsaved.
    @MainActor
    private static func deleteStoredRecords(context: ModelContext, pacer: inout Pacer,
                                            total: Double) async throws -> [HealthLink] {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let healthLinks = sessions.compactMap { session in
            session.healthWorkoutID.map { HealthLink(session: session.id, workout: $0) }
        }
        for plan in try context.fetch(FetchDescriptor<Plan>()) { context.delete(plan) }
        for (n, session) in sessions.enumerated() {
            context.delete(session)
            await pacer.pauseIfDue(fraction: Double(n + 1) / total)
        }
        let deleted = Double(sessions.count) / total
        for metric in try context.fetch(FetchDescriptor<BodyMetric>()) {
            context.delete(metric)
            await pacer.pauseIfDue(fraction: deleted)
        }
        for check in try context.fetch(FetchDescriptor<BodyMeasurement>()) { context.delete(check) }
        for record in try context.fetch(FetchDescriptor<CustomExerciseRecord>()) { context.delete(record) }

        // Sweep anything the cascade missed (orphans from an interrupted write).
        for item in try context.fetch(FetchDescriptor<PlanItem>()) {
            context.delete(item)
            await pacer.pauseIfDue(fraction: deleted)
        }
        for day in try context.fetch(FetchDescriptor<PlanDay>()) { context.delete(day) }
        for set in try context.fetch(FetchDescriptor<SetLog>()) {
            context.delete(set)
            await pacer.pauseIfDue(fraction: deleted)
        }
        for note in try context.fetch(FetchDescriptor<ExerciseNote>()) { context.delete(note) }
        for scale in try context.fetch(FetchDescriptor<ExerciseLoadPreference>()) { context.delete(scale) }
        for hidden in try context.fetch(FetchDescriptor<HiddenExerciseRecord>()) { context.delete(hidden) }

        return healthLinks
    }

    @MainActor
    private static func deleteHealthWorkouts(
        _ ids: Set<UUID>, using delete: (UUID) async -> Bool
    ) async -> HealthCleanupResult {
        var failed: [UUID] = []
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            if !(await delete(id)) { failed.append(id) }
        }
        return HealthCleanupResult(failedIDs: failed)
    }
}

private extension Bundle {
    /// An Info.plist string, or nil where it is missing or blank, so an export
    /// from a build with no version writes no key rather than an empty one.
    func infoString(_ key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }
}
