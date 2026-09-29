import Foundation
import SwiftData

/// Run with scripts/test-backup-archive-integrity.sh. Covers what a backup
/// file says and what a restore accepts: honest absence on export, older
/// files still restoring, warm-ups left out, and a bad file turned away
/// before it can replace good data.
@main
struct BackupArchiveIntegrityTests {
    @MainActor static func main() async throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        try checkWeekdayAccessorsDoNotTrap()
        try checkOlderFileRestoresWithoutWarmups(context: context)
        try checkExportOmitsWhatNobodyMeasured(context: context)
        try checkBadFilesAreRefusedBeforeTheWipe(context: context)

        print("Backup honest-absence, warm-up, validation and weekday checks passed")
    }

    // MARK: - XC-03: the accessors a bad store used to crash on

    private static func checkWeekdayAccessorsDoNotTrap() throws {
        for bad in [0, 8, -1, Int.min, Int.max] {
            let day = PlanDay(name: "Bad", order: 0, weekday: bad)
            precondition(day.weekdayName == nil && day.weekdayShortName == nil,
                         "Weekday \(bad) must read as unpinned rather than trap")
        }
        let sunday = PlanDay(name: "Sunday", order: 0, weekday: 1)
        precondition(sunday.weekdayName == Calendar.current.weekdaySymbols[0])
        let saturday = PlanDay(name: "Saturday", order: 0, weekday: 7)
        precondition(saturday.weekdayShortName == Calendar.current.shortWeekdaySymbols[6])
        precondition(PlanDay(name: "Floating", order: 0).weekdayName == nil)
    }

    // MARK: - DATA-03 and old-file decoding

    /// Written the way a build from the warm-up era wrote a file: every key
    /// present, empty notes, a hold time on a squat and two warm-up rows.
    static let olderFile = """
    {
      "version": 2,
      "exportedAt": "2026-09-18T10:00:00Z",
      "settings": { "weightUnit": "kg", "userName": "Warm-up era", "defaultRestSeconds": 90 },
      "customExercises": [],
      "plans": [{
        "id": "5B1D0C8E-8A0B-4E7C-9C4A-1F6B2D3E4A01", "name": "Old plan", "summary": "",
        "isActive": true, "createdAt": "2026-09-01T10:00:00Z",
        "days": [{
          "id": "5B1D0C8E-8A0B-4E7C-9C4A-1F6B2D3E4A02", "name": "Legs", "order": 0,
          "weekday": 2, "isRest": false, "notes": "",
          "items": [{
            "catalogID": "test-squat", "name": "Squat", "order": 0, "targetSets": 3,
            "targetRepsLow": 5, "targetRepsHigh": 8, "targetWeightKg": 0,
            "targetSeconds": 45, "notes": ""
          }]
        }]
      }],
      "sessions": [{
        "id": "5B1D0C8E-8A0B-4E7C-9C4A-1F6B2D3E4A03", "title": "Legs",
        "startedAt": "2026-09-17T17:00:00Z", "endedAt": "2026-09-17T18:00:00Z",
        "notes": "", "planName": "Old plan",
        "sets": [
          { "catalogID": "test-squat", "exerciseName": "Squat", "exerciseOrder": 0, "setIndex": 0,
            "weightKg": 40, "reps": 10, "seconds": 45, "isCompleted": true, "isWarmup": true,
            "completedAt": "2026-09-17T17:05:00Z", "targetRepsLow": 5, "targetRepsHigh": 8 },
          { "catalogID": "test-squat", "exerciseName": "Squat", "exerciseOrder": 0, "setIndex": 1,
            "weightKg": 60, "reps": 5, "seconds": 45, "isCompleted": true, "isWarmup": true,
            "completedAt": "2026-09-17T17:08:00Z", "targetRepsLow": 5, "targetRepsHigh": 8 },
          { "catalogID": "test-squat", "exerciseName": "Squat", "exerciseOrder": 0, "setIndex": 2,
            "weightKg": 100, "reps": 5, "seconds": 45, "isCompleted": true, "isWarmup": false,
            "completedAt": "2026-09-17T17:12:00Z", "targetRepsLow": 5, "targetRepsHigh": 8 }
        ]
      }]
    }
    """

    @MainActor
    private static func checkOlderFileRestoresWithoutWarmups(context: ModelContext) throws {
        try BackupService.restore(data: Data(olderFile.utf8), context: context)

        let sets = try context.fetch(FetchDescriptor<SetLog>())
        precondition(sets.count == 1, "Warm-up rows must be left out of the restore, found \(sets.count) sets")
        precondition(sets[0].weightKg == 100 && sets[0].reps == 5,
                     "The working set must be the one that survives")
        // An older file's keys are taken at their word, as they always were.
        precondition(sets[0].seconds == 45 && sets[0].targetRepsLow == 5 && sets[0].targetRepsHigh == 8)

        let items = try context.fetch(FetchDescriptor<PlanItem>())
        precondition(items.count == 1 && items[0].targetSeconds == 45 && items[0].targetRepsLow == 5
                     && items[0].notes.isEmpty)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(sessions.count == 1 && sessions[0].notes.isEmpty)
        let days = try context.fetch(FetchDescriptor<PlanDay>())
        precondition(days.count == 1 && days[0].weekday == 2 && days[0].notes.isEmpty)
    }

    // MARK: - DATA-04: export writes only what somebody measured or set

    @MainActor
    private static func checkExportOmitsWhatNobodyMeasured(context: ModelContext) throws {
        let session = WorkoutSession(title: "Mixed", startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        session.endedAt = session.startedAt.addingTimeInterval(3_600)
        context.insert(session)

        // A reps set still carrying the plan's hold time underneath.
        let squat = SetLog(catalogID: "test-squat", exerciseName: "Squat", exerciseOrder: 0, setIndex: 0,
                           weightKg: 100, reps: 5, seconds: 45, targetRepsLow: 5, targetRepsHigh: 8,
                           tracking: .weightReps)
        // A continuation row, whose zeros stand for "no target".
        let drop = SetLog(catalogID: "test-squat", exerciseName: "Squat", exerciseOrder: 0, setIndex: 1,
                          weightKg: 80, reps: 4, seconds: 45, tracking: .weightReps)
        // A timed set seeded with a rep count and an off-plan rep range.
        let plank = SetLog(catalogID: "test-plank", exerciseName: "Plank", exerciseOrder: 1, setIndex: 0,
                           reps: 10, seconds: 60, targetRepsLow: 8, targetRepsHigh: 12, tracking: .duration)
        for set in [squat, drop, plank] {
            set.isCompleted = true
            set.completedAt = session.startedAt.addingTimeInterval(600)
            set.session = session
            context.insert(set)
        }

        let plan = try context.fetch(FetchDescriptor<Plan>())[0]
        let day = plan.orderedDays[0]
        let timed = PlanItem(catalogID: "test-plank", name: "Plank", order: 1,
                             targetRepsLow: 0, targetRepsHigh: 0, targetSeconds: 60)
        timed.trackingRaw = TrackingMode.duration.rawValue
        timed.day = day
        context.insert(timed)
        let weighted = try context.fetch(FetchDescriptor<PlanItem>()).first { $0.catalogID == "test-squat" }!
        weighted.trackingRaw = TrackingMode.weightReps.rawValue
        weighted.notes = "  "
        try context.save()

        let url = try BackupService.export(context: context)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let sessions = root["sessions"] as! [[String: Any]]
        let mixed = sessions.first { $0["title"] as? String == "Mixed" }!
        precondition(mixed["notes"] == nil, "A session nobody wrote about must carry no notes key")
        let setRows = mixed["sets"] as! [[String: Any]]
        func row(_ name: String, _ index: Int) -> [String: Any] {
            setRows.first { $0["exerciseName"] as? String == name && $0["setIndex"] as? Int == index }!
        }
        let squatRow = row("Squat", 0), dropRow = row("Squat", 1), plankRow = row("Plank", 0)
        precondition(squatRow["seconds"] == nil, "A reps set must not carry a hold time nobody timed")
        precondition(squatRow["reps"] as? Int == 5)
        precondition(squatRow["targetRepsLow"] as? Int == 5 && squatRow["targetRepsHigh"] as? Int == 8)
        precondition(dropRow["targetRepsLow"] == nil && dropRow["targetRepsHigh"] == nil,
                     "A continuation's zero targets must not be written as targets")
        precondition(plankRow["reps"] == nil, "A timed set must not carry a rep count nobody counted")
        precondition(plankRow["seconds"] as? Int == 60)
        precondition(plankRow["targetRepsLow"] == nil && plankRow["targetRepsHigh"] == nil,
                     "A timed set must not carry a rep range")

        let plans = root["plans"] as! [[String: Any]]
        let days = plans[0]["days"] as! [[String: Any]]
        precondition(days[0]["notes"] == nil, "A day without a note must carry no notes key")
        let itemRows = days[0]["items"] as! [[String: Any]]
        let squatItem = itemRows.first { $0["name"] as? String == "Squat" }!
        let plankItem = itemRows.first { $0["name"] as? String == "Plank" }!
        precondition(squatItem["targetSeconds"] == nil, "A reps slot must not carry a hold target")
        precondition(squatItem["targetWeightKg"] == nil, "No starting weight must mean no key")
        precondition(squatItem["notes"] == nil, "A note of spaces is no note")
        precondition(squatItem["targetRepsLow"] as? Int == 5 && squatItem["targetRepsHigh"] as? Int == 8)
        precondition(plankItem["targetRepsLow"] == nil && plankItem["targetRepsHigh"] == nil,
                     "A timed slot's zero range must not be written")
        precondition(plankItem["targetSeconds"] as? Int == 60)

        // The new shape restores: absent reps, seconds and targets come back
        // as the zeros they stood for, and a reps slot keeps the default hold.
        try BackupService.restore(data: data, context: context)
        let restoredSets = try context.fetch(FetchDescriptor<SetLog>())
        let restoredPlank = restoredSets.first { $0.exerciseName == "Plank" }!
        precondition(restoredPlank.reps == 0 && restoredPlank.seconds == 60 && restoredPlank.targetRepsHigh == 0)
        let restoredSquat = restoredSets.first { $0.exerciseName == "Squat" && $0.setIndex == 0 && $0.session?.title == "Mixed" }!
        precondition(restoredSquat.seconds == 0 && restoredSquat.reps == 5 && restoredSquat.targetRepsLow == 5)
        let restoredItems = try context.fetch(FetchDescriptor<PlanItem>())
        precondition(restoredItems.first { $0.name == "Squat" }?.targetSeconds == 45)
        precondition(restoredItems.first { $0.name == "Plank" }?.targetSeconds == 60)
        precondition(restoredItems.first { $0.name == "Plank" }?.targetRepsLow == 0)
    }

    // MARK: - XC-03: a bad file never replaces good data

    @MainActor
    private static func checkBadFilesAreRefusedBeforeTheWipe(context: ModelContext) throws {
        try BackupService.restore(data: Data(olderFile.utf8), context: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var good = try decoder.decode(BackupService.Archive.self, from: Data(olderFile.utf8))
        // A file that did get through would be seen: these differ from the store.
        good.sessions[0].title = "Replacement"
        good.settings.userName = "Replacement"
        AppSettings.shared.userName = "Kept"

        let cases: [(field: String, change: (inout BackupService.Archive) -> Void)] = [
            ("weekday", { $0.plans[0].days[0].weekday = 0 }),
            ("weekday", { $0.plans[0].days[0].weekday = 8 }),
            ("rep range", { $0.plans[0].days[0].items[0].targetRepsLow = 70
                            $0.plans[0].days[0].items[0].targetRepsHigh = 70 }),
            ("rep range", { $0.plans[0].days[0].items[0].targetRepsLow = -1 }),
            ("rep range", { $0.plans[0].days[0].items[0].targetRepsHigh = 500 }),
            ("rep range", { $0.sessions[0].sets[2].targetRepsLow = 61 }),
            ("starting weight", { $0.plans[0].days[0].items[0].targetWeightKg = -2.5 }),
            ("hold time", { $0.plans[0].days[0].items[0].targetSeconds = -5 }),
            ("rest", { $0.plans[0].days[0].items[0].restSeconds = -30 }),
            ("weight", { $0.sessions[0].sets[2].weightKg = -5 }),
            ("time", { $0.sessions[0].sets[2].seconds = -10 }),
            ("default rest", { $0.settings.defaultRestSeconds = -1 }),
            ("body weight", { $0.bodyMetrics = [.init(id: UUID(), date: .now, weightKg: -80, source: "manual")] }),
        ]
        for (field, change) in cases {
            var bad = good
            change(&bad)
            do {
                try BackupService.restore(data: encode(bad), context: context)
                preconditionFailure("A file with a bad \(field) must be refused")
            } catch let BackupService.RestoreError.invalidValue(refused, _, _, _) {
                precondition(refused == field, "Expected the \(field) to be named, got \(refused)")
            }
            try assertStoreUntouched(context: context)
        }

        // Non-finite numbers can't be encoded, so they are checked directly,
        // and through a file whose number overflows a Double.
        for nonFinite in [Double.infinity, -Double.infinity, Double.nan] {
            var bad = good
            bad.sessions[0].sets[2].weightKg = nonFinite
            do {
                try BackupService.validate(bad)
                preconditionFailure("A weight of \(nonFinite) must be refused")
            } catch BackupService.RestoreError.invalidValue {}
        }
        let overflowing = String(decoding: try encode(good), as: UTF8.self)
            .replacingOccurrences(of: "\"weightKg\":100", with: "\"weightKg\":1e999")
        precondition(overflowing.contains("1e999"))
        do {
            try BackupService.restore(data: Data(overflowing.utf8), context: context)
            preconditionFailure("A weight that overflows a Double must be refused")
        } catch {}
        try assertStoreUntouched(context: context)

        // A warm-up is never stored, so nothing in one can turn a file away.
        var warmupOnlyBad = good
        warmupOnlyBad.sessions[0].sets[0].weightKg = -40
        try BackupService.validate(warmupOnlyBad)

        // A range that runs backwards restores: this app wrote them itself
        // once, and nothing traps on one.
        var backwards = good
        backwards.plans[0].days[0].items[0].targetRepsLow = 12
        backwards.plans[0].days[0].items[0].targetRepsHigh = 8
        backwards.sessions[0].sets[2].targetRepsLow = 9
        try BackupService.validate(backwards)

        // The edges of every range are accepted, weekday absent included.
        var edges = good
        edges.plans[0].days[0].weekday = nil
        edges.plans[0].days[0].items[0].targetRepsLow = 0
        edges.plans[0].days[0].items[0].targetRepsHigh = 60
        edges.sessions[0].sets[2].targetRepsLow = nil
        edges.sessions[0].sets[2].targetRepsHigh = nil
        edges.sessions[0].sets[2].weightKg = 0
        try BackupService.validate(edges)
        var sunday = good
        sunday.plans[0].days[0].weekday = 7
        try BackupService.validate(sunday)
    }

    @MainActor
    private static func assertStoreUntouched(context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(sessions.map(\.title) == ["Legs"], "A refused file must leave the sessions as they were")
        let sets = try context.fetch(FetchDescriptor<SetLog>())
        precondition(sets.count == 1 && sets[0].weightKg == 100)
        let days = try context.fetch(FetchDescriptor<PlanDay>())
        precondition(days.count == 1 && days[0].weekday == 2 && days[0].items.count == 1)
        precondition(days[0].items[0].targetRepsLow == 5 && days[0].items[0].targetRepsHigh == 8)
        precondition(AppSettings.shared.userName == "Kept", "A refused file must not reach the settings")
    }

    private static func encode(_ archive: BackupService.Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }
}
