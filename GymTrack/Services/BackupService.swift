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
        var customExercises: [CustomExerciseDTO]
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
        var restSeconds: Int
        var notes: String
    }

    struct SessionDTO: Codable {
        var id: UUID
        var title: String
        var startedAt: Date
        var endedAt: Date?
        var notes: String
        var planName: String
        var sets: [SetDTO]
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
        var isWarmup: Bool
        var completedAt: Date?
        var targetRepsLow: Int
        var targetRepsHigh: Int
    }

    struct CustomExerciseDTO: Codable {
        var id: String
        var name: String
        var category: String
        var muscleRaw: [String]
        var equipment: [String]
        var trackingRaw: String
    }

    // MARK: - Export

    static func export(context: ModelContext) throws -> URL {
        let plans = try context.fetch(FetchDescriptor<Plan>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let custom = try context.fetch(FetchDescriptor<CustomExerciseRecord>())

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
            sessions: sessions.filter { !$0.isActive }.map { session in
                SessionDTO(id: session.id, title: session.title, startedAt: session.startedAt,
                           endedAt: session.endedAt, notes: session.notes, planName: session.planName,
                           sets: session.sets.map { set in
                               SetDTO(catalogID: set.catalogID, exerciseName: set.exerciseName,
                                      exerciseOrder: set.exerciseOrder, setIndex: set.setIndex,
                                      weightKg: set.weightKg, reps: set.reps, seconds: set.seconds,
                                      isCompleted: set.isCompleted, isWarmup: set.isWarmup,
                                      completedAt: set.completedAt,
                                      targetRepsLow: set.targetRepsLow, targetRepsHigh: set.targetRepsHigh)
                           })
            },
            customExercises: custom.map {
                CustomExerciseDTO(id: $0.id, name: $0.name, category: $0.category,
                                  muscleRaw: $0.muscleRaw, equipment: $0.equipment, trackingRaw: $0.trackingRaw)
            }
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
            context.insert(session)

            for setDTO in dto.sets {
                let set = SetLog(catalogID: setDTO.catalogID, exerciseName: setDTO.exerciseName,
                                 exerciseOrder: setDTO.exerciseOrder, setIndex: setDTO.setIndex,
                                 weightKg: setDTO.weightKg, reps: setDTO.reps, seconds: setDTO.seconds,
                                 targetRepsLow: setDTO.targetRepsLow, targetRepsHigh: setDTO.targetRepsHigh,
                                 isWarmup: setDTO.isWarmup)
                set.isCompleted = setDTO.isCompleted
                set.completedAt = setDTO.completedAt
                set.session = session
                context.insert(set)
            }
        }

        AppSettings.shared.weightUnit = WeightUnit(rawValue: archive.settings.weightUnit) ?? .kg
        AppSettings.shared.userName = archive.settings.userName
        AppSettings.shared.defaultRestSeconds = archive.settings.defaultRestSeconds

        try context.save()
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
        for record in try context.fetch(FetchDescriptor<CustomExerciseRecord>()) { context.delete(record) }
        for metric in try context.fetch(FetchDescriptor<BodyMetric>()) { context.delete(metric) }

        // Sweep anything the cascade missed (orphans from an interrupted write).
        for item in try context.fetch(FetchDescriptor<PlanItem>()) { context.delete(item) }
        for day in try context.fetch(FetchDescriptor<PlanDay>()) { context.delete(day) }
        for set in try context.fetch(FetchDescriptor<SetLog>()) { context.delete(set) }

        try context.save()
    }
}
