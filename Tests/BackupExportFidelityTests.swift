import Foundation
import SwiftData

/// Run with scripts/test-backup-export-fidelity.sh; no simulator is needed.
///
/// The export is read by an AI coach that has to cite sets, take "the row
/// above" literally, hash the file, place a session in the lifter's own week,
/// and propose loads the equipment can be set to. Each of those needs
/// something the file used to leave to chance: set IDs, a defined order, a
/// time zone, and a rung for every exercise rather than only the corrected ones.
@main
struct BackupExportFidelityTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    /// 22:30 UTC on the 22nd, which is already the 23rd in Cairo.
    static let stamp = BackupService.ExportStamp(
        exportedAt: Date(timeIntervalSince1970: 1_790_116_200),
        timeZone: TimeZone(identifier: "Africa/Cairo")!, appVersion: "1.4", appBuild: "27")

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    static func decode(_ data: Data) throws -> BackupService.Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupService.Archive.self, from: data)
    }

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A store filled in the order least likely to come back sorted: everything
    /// is inserted newest-first, highest-order-first, or largest-ID-first.
    @MainActor static func fill(_ context: ModelContext) throws -> (plannedDay: UUID, sessionIDs: [UUID]) {
        func plan(_ name: String, createdAt: TimeInterval, items: [(String, String)]) -> PlanDay {
            let plan = Plan(name: name, isActive: name == "A")
            plan.createdAt = base.addingTimeInterval(createdAt)
            context.insert(plan)
            var firstDay: PlanDay?
            for order in [2, 0, 1] {
                let day = PlanDay(name: "\(name) day \(order)", order: order, weekday: order + 2)
                day.plan = plan
                context.insert(day)
                if order == 0 { firstDay = day }
                for (position, item) in items.enumerated().reversed() {
                    let slot = PlanItem(catalogID: item.0, name: item.1, order: position)
                    slot.day = day
                    context.insert(slot)
                }
            }
            return firstDay!
        }
        _ = plan("B", createdAt: 100, items: [("cable-crossover", "Cable Crossover")])
        let plannedDay = plan("A", createdAt: 0, items: [
            ("barbell-bench-press", "Barbell Bench Press"), ("dumbbell-curl", "Dumbbell Curl"),
            ("leg-press", "Leg Press")])

        // Two sessions share a start, so the ID has to settle them.
        var sessionIDs: [UUID] = []
        for (n, offset) in [(3, 3000.0), (0xA2, 2000), (0xA1, 2000), (1, 1000)] {
            let session = WorkoutSession(title: "Session \(n)", planDayID: n == 3 ? plannedDay.id : nil,
                                         startedAt: base.addingTimeInterval(offset))
            session.id = uuid(n)
            session.endedAt = session.startedAt.addingTimeInterval(3_000)
            context.insert(session)
            sessionIDs.append(session.id)

            // Rows inserted out of order, one of them a drop set.
            let rows: [(String, String, Int, Int, Double)] = [
                ("dumbbell-curl", "Dumbbell Curl", 1, 0, 12),
                ("barbell-bench-press", "Barbell Bench Press", 0, 2, 60),
                ("barbell-bench-press", "Barbell Bench Press", 0, 1, 50),
                ("barbell-bench-press", "Barbell Bench Press", 0, 0, 80),
                ("dumbbell-lateral-raise", "Lateral Raise", 2, 0, 8),
                ("gone-custom-exercise", "Gone", 3, 0, 20)]
            for (index, row) in rows.enumerated() {
                let set = SetLog(catalogID: row.0, exerciseName: row.1, exerciseOrder: row.2,
                                 setIndex: row.3, weightKg: row.4, reps: 8, tracking: .weightReps)
                set.id = uuid(n * 100 + 99 - index)
                set.isCompleted = true
                set.completedAt = session.startedAt.addingTimeInterval(Double(60 * (index + 1)))
                if row.0 == "barbell-bench-press" && row.3 == 1 { set.continuesPreviousSet = true }
                set.session = session
                context.insert(set)
            }
            for (catalogID, name) in [("dumbbell-curl", "Dumbbell Curl"), ("barbell-bench-press", "Bench")] {
                let note = ExerciseNote(catalogID: catalogID, exerciseName: name)
                note.text = "Felt fine on \(name)"
                note.session = session
                context.insert(note)
            }
        }

        for offset in [500.0, 100, 300] {
            let metric = BodyMetric(date: base.addingTimeInterval(offset), weightKg: 80 + offset / 100)
            context.insert(metric)
        }
        for id in ["zz-custom", "aa-custom"] {
            let record = CustomExerciseRecord(name: id, muscles: [], equipment: ["Dumbbell"], tracking: .weightReps)
            record.id = id
            context.insert(record)
        }
        for id in ["b-hidden", "a-hidden"] { context.insert(HiddenExerciseRecord(catalogID: id)) }
        // One correction on a referenced exercise, one on an exercise nothing refers to.
        context.insert(ExerciseLoadPreference(catalogID: "dumbbell-curl", scale: LoadScale(unit: .kg, increment: 1)))
        context.insert(ExerciseLoadPreference(catalogID: "dumbbell-pullover", scale: LoadScale(unit: .lb, increment: 5)))
        try context.save()
        return (plannedDay.id, sessionIDs)
    }

    @MainActor static func main() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let made = try fill(context)
        AppSettings.shared.weightUnit = .kg

        // Two exports of one store are the same bytes.
        let first = try BackupService.exportData(context: context, stamp: stamp)
        let second = try BackupService.exportData(context: context, stamp: stamp)
        check(first == second, "Two exports of the same store must be byte-identical")
        let fileA = try BackupService.export(context: context, stamp: stamp)
        let fileB = try BackupService.export(context: context, stamp: stamp)
        defer { try? FileManager.default.removeItem(at: fileA); try? FileManager.default.removeItem(at: fileB) }
        check(try Data(contentsOf: fileA) == first && fileA.lastPathComponent == "GymTrack-2026-09-23.json",
              "The exported file must hold the same bytes, named for the day in the stamp's zone")

        let archive = try decode(first)
        let text = String(decoding: first, as: UTF8.self)
        check(archive.version == 2, "The backup version must stay 2")

        // Top-level provenance.
        check(archive.timeZone == "Africa/Cairo", "timeZone must be the IANA identifier, got \(archive.timeZone ?? "nil")")
        check(archive.appVersion == "1.4" && archive.appBuild == "27", "appVersion and appBuild must be written")
        check(abs(archive.exportedAt.timeIntervalSince(stamp.exportedAt)) < 1, "exportedAt must be the stamp's moment")
        let bare = BackupService.ExportStamp(exportedAt: stamp.exportedAt, timeZone: stamp.timeZone,
                                             appVersion: nil, appBuild: nil)
        let bareText = String(decoding: try BackupService.exportData(context: context, stamp: bare), as: UTF8.self)
        check(!bareText.contains("\"appVersion\"") && !bareText.contains("\"appBuild\""),
              "A build with no version must write no key, not an empty one")
        check(BackupService.ExportStamp.current().timeZone == .current, "The default stamp must name this phone's zone")

        // Order: plans by createdAt, days and slots by order, sessions by
        // start then ID, sets as the app groups them.
        check(archive.plans.map(\.name) == ["A", "B"], "Plans must be ordered by createdAt")
        check(archive.plans.allSatisfy { $0.days.map(\.order) == [0, 1, 2] }, "Days must be ordered by order")
        check(archive.plans[0].days.allSatisfy { $0.items.map(\.order) == [0, 1, 2] }, "Slots must be ordered by order")
        check(archive.sessions.map(\.id) == [uuid(1), uuid(0xA1), uuid(0xA2), uuid(3)],
              "Sessions must be ordered by startedAt, then id: \(archive.sessions.map(\.title))")
        for session in archive.sessions {
            let positions = session.sets.map { [$0.exerciseOrder, $0.setIndex] }
            check(positions == [[0, 0], [0, 1], [0, 2], [1, 0], [2, 0], [3, 0]],
                  "Sets must run in exercise then set order, got \(positions)")
            let drop = session.sets[1]
            check(drop.continues != nil && session.sets[0].weightKg > drop.weightKg,
                  "The row above a continuation must be the set it continues")
            check(session.exerciseNotes?.map(\.catalogID) == ["barbell-bench-press", "dumbbell-curl"],
                  "Exercise notes must follow the order the exercises were trained")
        }
        check(archive.bodyMetrics?.map(\.date) == archive.bodyMetrics?.map(\.date).sorted(),
              "Body metrics must be ordered by date")
        check(archive.customExercises.map(\.id) == ["aa-custom", "zz-custom"], "Custom exercises must be ordered by id")
        check(archive.hiddenExercises == ["a-hidden", "b-hidden"], "Hidden exercises must be ordered")
        let catalogIDs = archive.exerciseCatalog?.map(\.catalogID) ?? []
        check(catalogIDs == catalogIDs.sorted(), "The exercise catalog must be ordered by id")

        // IDs: sets carry theirs, a session carries its plan day, and only
        // where it has one.
        let exportedSetIDs = archive.sessions.flatMap(\.sets).map(\.id)
        check(exportedSetIDs.allSatisfy { $0 != nil } && Set(exportedSetIDs).count == exportedSetIDs.count,
              "Every set must carry a unique id")
        let storedSetIDs = Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id))
        check(Set(exportedSetIDs.compactMap { $0 }) == storedSetIDs, "The exported set IDs must be the stored ones")
        let planDayIDs = archive.sessions.compactMap(\.planDayID)
        check(planDayIDs == [made.plannedDay], "Only the session started from a plan day carries planDayID")
        check(text.components(separatedBy: "\"planDayID\"").count == 2,
              "A session with no plan day must have no planDayID key at all")
        check(archive.plans.flatMap(\.days).contains { $0.id == made.plannedDay },
              "The session's planDayID must be a day in the file's plans")

        // Effective load scales: every resolvable exercise in the plans or
        // sessions, with a derived default and the correction marked.
        let referenced = Set(archive.plans.flatMap(\.days).flatMap(\.items).map(\.catalogID))
            .union(archive.sessions.flatMap(\.sets).map(\.catalogID))
        let effective = archive.effectiveLoadScales ?? []
        let byID = Dictionary(effective.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        check(effective.map(\.catalogID) == effective.map(\.catalogID).sorted(), "Effective scales must be ordered by id")
        check(Set(byID.keys) == referenced.subtracting(["gone-custom-exercise"]),
              "Every resolvable exercise in the plans or sessions, and only those, must have a rung: \(byID.keys.sorted())")
        func expect(_ id: String, _ unit: String, _ increment: Double, _ source: String) {
            let row = byID[id]
            check(row?.unit == unit && row?.increment == increment && row?.source == source,
                  "\(id) should step \(increment) \(unit) from \(source), got \(String(describing: row))")
        }
        expect("barbell-bench-press", "kg", 2.5, "derived")
        expect("leg-press", "kg", 5, "derived")
        expect("cable-crossover", "kg", 2.5, "derived")
        expect("dumbbell-lateral-raise", "kg", 2, "derived")
        expect("dumbbell-curl", "kg", 1, "correction")
        check(byID["dumbbell-pullover"] == nil, "A correction on an exercise nothing refers to stays out of the rungs")
        let corrections = archive.loadScales ?? []
        check(corrections.map(\.catalogID).sorted() == ["dumbbell-curl", "dumbbell-pullover"].map(ExerciseCatalog.canonicalID(for:)).sorted(),
              "loadScales must keep listing corrections only")

        AppSettings.shared.weightUnit = .lb
        let pounds = Dictionary(uniqueKeysWithValues: (try decode(BackupService.exportData(context: context, stamp: stamp))
            .effectiveLoadScales ?? []).map { ($0.catalogID, $0) })
        check(pounds["barbell-bench-press"]?.unit == "lb" && pounds["barbell-bench-press"]?.increment == 5,
              "A derived rung follows the app-wide unit")
        check(pounds["dumbbell-curl"]?.unit == "kg" && pounds["dumbbell-curl"]?.source == "correction",
              "A correction keeps the unit the lifter marked it in")
        AppSettings.shared.weightUnit = .kg

        // Round trip: restore keeps the set IDs and the plan links, and the
        // next export is the same bytes.
        try BackupService.restore(data: first, context: context)
        let restoredIDs = Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id))
        check(restoredIDs == storedSetIDs, "Restore must keep the file's set IDs")
        let restoredSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        check(restoredSessions.compactMap(\.planDayID) == [made.plannedDay], "Restore must keep planDayID")
        let third = try BackupService.exportData(context: context, stamp: stamp)
        check(third == first, "Export, restore, export must give the same bytes")

        // A duplicate set ID is turned away, with the store untouched.
        var duplicated = archive
        duplicated.sessions[1].sets[0].id = duplicated.sessions[0].sets[0].id
        do {
            try BackupService.restore(data: try BackupService.encoded(duplicated), context: context)
            check(false, "A file repeating a set ID must not restore")
        } catch let BackupService.RestoreError.invalidValue(field, _, _, _) {
            check(field == "set ID", "The rejection must name the set ID, got \(field)")
        }
        check(Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id)) == storedSetIDs,
              "A rejected restore must leave the store as it was")
        var sameSession = archive
        sameSession.sessions[0].sets[1].id = sameSession.sessions[0].sets[0].id
        do {
            try BackupService.restore(data: try BackupService.encoded(sameSession), context: context)
            check(false, "A repeated set ID inside one session must not restore")
        } catch BackupService.RestoreError.invalidValue {}
        // A warm-up is never stored, so it cannot make a stored ID repeat.
        var warmup = archive
        warmup.sessions[1].sets[0].id = warmup.sessions[0].sets[0].id
        warmup.sessions[1].sets[0].isWarmup = true
        try BackupService.restore(data: try BackupService.encoded(warmup), context: context)

        // An old file, from before any of this: no key, and it still restores.
        var object = try JSONSerialization.jsonObject(with: first) as! [String: Any]
        for key in ["timeZone", "appVersion", "appBuild", "effectiveLoadScales"] { object[key] = nil }
        var oldSessions = object["sessions"] as! [[String: Any]]
        for index in oldSessions.indices {
            oldSessions[index]["planDayID"] = nil
            oldSessions[index]["sets"] = (oldSessions[index]["sets"] as! [[String: Any]]).map {
                var set = $0
                set["id"] = nil
                return set
            }
        }
        object["sessions"] = oldSessions
        let old = try JSONSerialization.data(withJSONObject: object)
        let decodedOld = try decode(old)
        check(decodedOld.timeZone == nil && decodedOld.appVersion == nil && decodedOld.effectiveLoadScales == nil,
              "An old file must decode with the new top-level keys absent")
        check(decodedOld.sessions.allSatisfy { $0.planDayID == nil && $0.sets.allSatisfy { $0.id == nil } },
              "An old file must decode with no set IDs and no plan day")
        try BackupService.restore(data: old, context: context)
        let regenerated = try context.fetch(FetchDescriptor<SetLog>()).map(\.id)
        check(regenerated.count == exportedSetIDs.count && Set(regenerated).count == regenerated.count,
              "Sets restored from an old file must each get their own new ID")
        check(Set(regenerated).isDisjoint(with: storedSetIDs), "An old file has no IDs to keep, so none may reappear")
        check(try context.fetch(FetchDescriptor<WorkoutSession>()).allSatisfy { $0.planDayID == nil },
              "An old file has no plan days to restore")

        guard failures == 0 else {
            print("\(failures) backup export fidelity check(s) failed")
            exit(1)
        }
        print("Backup export fidelity tests passed")
    }
}
