import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

/// JSON export/import of everything the app stores. With no account and no
/// server, this is the user's way to move devices or keep a copy.
enum BackupService {

    struct Archive: Codable {
        var version = 2
        var exportedAt = Date()
        var settings: Settings
        var plans: [PlanDTO]
        var sessions: [SessionDTO]
        /// Optional for the same reason — weigh-ins arrived later than the
        /// first backup format.
        var bodyMetrics: [BodyMetricDTO]?
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
    }

    struct Settings: Codable {
        var weightUnit: String
        var userName: String
        var defaultRestSeconds: Int
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
        var notes: String
        var items: [ItemDTO]
    }

    struct ItemDTO: Codable {
        var catalogID: String
        var name: String
        var order: Int
        var targetSets: Int
        var targetRepsLow: Int
        var targetRepsHigh: Int
        var targetWeightKg: Double
        var targetSeconds: Int
        /// Absent/null means the exercise follows the app-wide default rest.
        var restSeconds: Int?
        var notes: String
    }

    struct SessionDTO: Codable {
        var id: UUID
        var title: String
        var startedAt: Date
        var endedAt: Date?
        /// What the lifter said about the whole session. Has always been in the
        /// file; until recently nothing in the app could write to it.
        var notes: String
        var planName: String
        // Optional so backups written before Health support still restore.
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var activeEnergyKcal: Double?
        var wasWatchDriven: Bool?
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
        var catalogID: String
        var exerciseName: String
        var exerciseOrder: Int
        var setIndex: Int
        var weightKg: Double
        var reps: Int
        var seconds: Int
        var isCompleted: Bool
        /// Written by versions that had a warm-up flag. Decoded so those
        /// backups still restore, and ignored — a set is a set now.
        var isWarmup: Bool?
        var completedAt: Date?
        var targetRepsLow: Int
        var targetRepsHigh: Int
        /// Optional so a backup written before effort tracking still restores —
        /// and so a set that was never rated round-trips as unrated rather than
        /// as an RPE of zero.
        var rpe: Double?
    }

    struct BodyMetricDTO: Codable {
        var id: UUID
        var date: Date
        var weightKg: Double
        var source: String
    }

    struct LoadScaleDTO: Codable {
        var catalogID: String
        var unit: String
        var increment: Double
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

    static func export(context: ModelContext) throws -> URL {
        let plans = try context.fetch(FetchDescriptor<Plan>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let custom = try context.fetch(FetchDescriptor<CustomExerciseRecord>())
        let bodyMetrics = try context.fetch(FetchDescriptor<BodyMetric>())
        let loadScales = try context.fetch(FetchDescriptor<ExerciseLoadPreference>())
        let hidden = try context.fetch(FetchDescriptor<HiddenExerciseRecord>())
        let finished = sessions.filter { !$0.isActive }

        let archive = Archive(
            settings: Settings(
                weightUnit: AppSettings.shared.weightUnit.rawValue,
                userName: AppSettings.shared.userName,
                defaultRestSeconds: AppSettings.shared.defaultRestSeconds
            ),
            plans: plans.map { plan in
                PlanDTO(id: plan.id, name: plan.name, summary: plan.summary,
                        isActive: plan.isActive, createdAt: plan.createdAt,
                        days: plan.orderedDays.map { day in
                            DayDTO(id: day.id, name: day.name, order: day.order,
                                   weekday: day.weekday, isRest: day.isRest, notes: day.notes,
                                   items: day.orderedItems.map { item in
                                       ItemDTO(catalogID: item.catalogID, name: item.name, order: item.order,
                                               targetSets: item.targetSets, targetRepsLow: item.targetRepsLow,
                                               targetRepsHigh: item.targetRepsHigh, targetWeightKg: item.targetWeightKg,
                                               targetSeconds: item.targetSeconds, restSeconds: item.restSeconds,
                                               notes: item.notes)
                                   })
                        })
            },
            sessions: finished.map { session in
                SessionDTO(id: session.id, title: session.title, startedAt: session.startedAt,
                           endedAt: session.endedAt,
                           // Trimmed: a field that was opened and cleared again
                           // shouldn't reach the file as a note made of spaces.
                           notes: session.trimmedNotes, planName: session.planName,
                           averageHeartRate: session.averageHeartRate,
                           maxHeartRate: session.maxHeartRate,
                           activeEnergyKcal: session.activeEnergyKcal,
                           wasWatchDriven: session.wasWatchDriven,
                           noteTags: session.noteTagsRaw.isEmpty ? nil : session.noteTags.map(\.rawValue),
                           exerciseNotes: exerciseNotes(of: session),
                           sets: session.sets.map { set in
                               SetDTO(catalogID: set.catalogID, exerciseName: set.exerciseName,
                                      exerciseOrder: set.exerciseOrder, setIndex: set.setIndex,
                                      weightKg: set.weightKg, reps: set.reps, seconds: set.seconds,
                                      isCompleted: set.isCompleted,
                                      completedAt: set.completedAt,
                                      targetRepsLow: set.targetRepsLow, targetRepsHigh: set.targetRepsHigh,
                                      rpe: set.rpe)
                           })
            },
            bodyMetrics: bodyMetrics.map {
                BodyMetricDTO(id: $0.id, date: $0.date, weightKg: $0.weightKg, source: $0.source)
            },
            customExercises: custom.map {
                CustomExerciseDTO(id: $0.id, name: $0.name, category: $0.category,
                                  muscleRaw: $0.muscleRaw, equipment: $0.equipment, trackingRaw: $0.trackingRaw)
            },
            loadScales: loadScales.map {
                LoadScaleDTO(catalogID: $0.catalogID, unit: $0.unitRaw, increment: $0.increment)
            },
            hiddenExercises: hidden.map(\.catalogID),
            exerciseCatalog: referencedCatalog(plans: plans, sessions: finished)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        // `.iso8601` formats in UTC, which names a late-evening export with the
        // wrong day. Stamp the file in the user's own timezone.
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        stamp.timeZone = .current
        let name = "GymTrack-\(stamp.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The notes kept on individual exercises in one session, in the order they
    /// were trained. Nothing is written for a session nobody wrote about.
    ///
    /// An empty note can't normally survive the end of a session, but the check
    /// is here too: this file is the one thing that outlives the app, and a
    /// note that says nothing would read to anything parsing it as a lifter who
    /// had something to report and didn't say what.
    private static func exerciseNotes(of session: WorkoutSession) -> [ExerciseNoteDTO]? {
        let notes = session.orderedExerciseNotes.filter { !$0.isEmpty }
        guard !notes.isEmpty else { return nil }
        return notes.map {
            ExerciseNoteDTO(catalogID: $0.catalogID, exerciseName: $0.exerciseName,
                            text: $0.trimmedText, tags: $0.tags.map(\.rawValue))
        }
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
    private static func referencedCatalog(plans: [Plan], sessions: [WorkoutSession]) -> [CatalogExerciseDTO] {
        var ids: Set<String> = []
        for plan in plans {
            for day in plan.days {
                for item in day.items { ids.insert(item.catalogID) }
            }
        }
        for session in sessions {
            for set in session.sets { ids.insert(set.catalogID) }
        }

        // Sorted so two exports of unchanged data are the same bytes, which is
        // what `.sortedKeys` buys everywhere else in the file.
        return ids.sorted().compactMap { id in
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

    // MARK: - Import

    /// Replaces everything currently stored with the archive's contents.
    static func restore(from url: URL, context: ModelContext) throws {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Archive.self, from: data)

        try wipe(context: context)

        for dto in archive.customExercises {
            let record = CustomExerciseRecord(name: dto.name, muscles: [], equipment: dto.equipment,
                                              tracking: TrackingMode(rawValue: dto.trackingRaw) ?? .weightReps)
            record.id = dto.id
            record.category = dto.category
            record.muscleRaw = dto.muscleRaw
            context.insert(record)
        }

        for dto in archive.plans {
            let plan = Plan(name: dto.name, summary: dto.summary, isActive: dto.isActive)
            plan.id = dto.id
            plan.createdAt = dto.createdAt
            context.insert(plan)

            for dayDTO in dto.days {
                let day = PlanDay(name: dayDTO.name, order: dayDTO.order, weekday: dayDTO.weekday,
                                  isRest: dayDTO.isRest, notes: dayDTO.notes)
                day.id = dayDTO.id
                day.plan = plan
                context.insert(day)

                for itemDTO in dayDTO.items {
                    let item = PlanItem(catalogID: itemDTO.catalogID, name: itemDTO.name, order: itemDTO.order,
                                        targetSets: itemDTO.targetSets, targetRepsLow: itemDTO.targetRepsLow,
                                        targetRepsHigh: itemDTO.targetRepsHigh, targetWeightKg: itemDTO.targetWeightKg,
                                        targetSeconds: itemDTO.targetSeconds, restSeconds: itemDTO.restSeconds)
                    item.notes = itemDTO.notes
                    item.day = day
                    context.insert(item)
                }
            }
        }

        for dto in archive.sessions {
            let session = WorkoutSession(title: dto.title, planName: dto.planName, startedAt: dto.startedAt)
            session.id = dto.id
            session.endedAt = dto.endedAt
            session.notes = dto.notes
            session.averageHeartRate = dto.averageHeartRate
            session.maxHeartRate = dto.maxHeartRate
            session.activeEnergyKcal = dto.activeEnergyKcal
            session.wasWatchDriven = dto.wasWatchDriven ?? false
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

            for setDTO in dto.sets {
                let set = SetLog(catalogID: setDTO.catalogID, exerciseName: setDTO.exerciseName,
                                 exerciseOrder: setDTO.exerciseOrder, setIndex: setDTO.setIndex,
                                 weightKg: setDTO.weightKg, reps: setDTO.reps, seconds: setDTO.seconds,
                                 targetRepsLow: setDTO.targetRepsLow, targetRepsHigh: setDTO.targetRepsHigh)
                set.isCompleted = setDTO.isCompleted
                set.completedAt = setDTO.completedAt
                set.rpe = setDTO.rpe
                set.session = session
                context.insert(set)
            }
        }

        for dto in archive.bodyMetrics ?? [] {
            let metric = BodyMetric(date: dto.date, weightKg: dto.weightKg)
            metric.id = dto.id
            metric.source = dto.source
            context.insert(metric)
        }

        for dto in archive.loadScales ?? [] {
            let scale = LoadScale(unit: WeightUnit(rawValue: dto.unit) ?? .kg, increment: dto.increment)
            context.insert(ExerciseLoadPreference(catalogID: dto.catalogID, scale: scale))
        }

        for catalogID in archive.hiddenExercises ?? [] {
            context.insert(HiddenExerciseRecord(catalogID: catalogID))
        }

        AppSettings.shared.weightUnit = WeightUnit(rawValue: archive.settings.weightUnit) ?? .kg
        AppSettings.shared.userName = archive.settings.userName
        AppSettings.shared.defaultRestSeconds = archive.settings.defaultRestSeconds

        try context.save()
        LoadScaleBook.shared.reload()
        ExerciseVisibility.reload(context: context)
    }

    /// Deletes every record. Used by restore and by "erase all data".
    ///
    /// Deletes instances rather than using `context.delete(model:)`: that issues
    /// a batch delete, which can't satisfy `PlanItem`'s mandatory inverse to
    /// `PlanDay` and fails with a constraint trigger violation. Removing the
    /// roots lets the cascade rules do the work.
    static func wipe(context: ModelContext) throws {
        for plan in try context.fetch(FetchDescriptor<Plan>()) { context.delete(plan) }
        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) { context.delete(session) }
        for metric in try context.fetch(FetchDescriptor<BodyMetric>()) { context.delete(metric) }
        for record in try context.fetch(FetchDescriptor<CustomExerciseRecord>()) { context.delete(record) }
        for metric in try context.fetch(FetchDescriptor<BodyMetric>()) { context.delete(metric) }

        // Sweep anything the cascade missed (orphans from an interrupted write).
        for item in try context.fetch(FetchDescriptor<PlanItem>()) { context.delete(item) }
        for day in try context.fetch(FetchDescriptor<PlanDay>()) { context.delete(day) }
        for set in try context.fetch(FetchDescriptor<SetLog>()) { context.delete(set) }
        for note in try context.fetch(FetchDescriptor<ExerciseNote>()) { context.delete(note) }
        for scale in try context.fetch(FetchDescriptor<ExerciseLoadPreference>()) { context.delete(scale) }
        for hidden in try context.fetch(FetchDescriptor<HiddenExerciseRecord>()) { context.delete(hidden) }

        try context.save()
        LoadScaleBook.shared.reload()
        ExerciseVisibility.reload(context: context)
    }
}
