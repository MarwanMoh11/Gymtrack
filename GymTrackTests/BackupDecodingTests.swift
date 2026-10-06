import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What `BackupService` accepts and what it writes, key by key: older version-2
/// files that predate the optional fields, malformed and hostile files turned
/// away before anything is wiped, and the rule that a field with no data is
/// absent from the file rather than null, zero or a sentinel.
///
/// Whole-store round trips are in `BackupRestoreTests`, the file's order and
/// provenance in `BackupExportFidelityTests`, and the sliced export and
/// restore in `BackupPacingTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BackupDecodingTests {

    private static let planID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let dayID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let sessionID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let setID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    private let start = TestClock.at("2026-03-10T18:00:00")

    // MARK: - Files with only what the first format had

    @Test func aFileWithOnlyTheRequiredKeysDecodesAndEveryLaterSectionIsNil() throws {
        let json = """
        {"version": 2, "exportedAt": "2026-03-11T12:00:00Z",
         "settings": {"weightUnit": "kg", "userName": "A", "defaultRestSeconds": 90},
         "plans": [], "sessions": [], "customExercises": []}
        """

        let archive = try BackupService.decodedArchive(from: Data(json.utf8))

        #expect(archive.version == 2)
        #expect(archive.exportedAt == TestClock.reference)
        #expect(archive.settings.userName == "A" && archive.settings.trackRPE == nil)
        // A file that never said where or by which build it was written.
        #expect(archive.timeZone == nil && archive.appVersion == nil && archive.appBuild == nil)
        #expect(archive.bodyMetrics == nil && archive.bodyMeasurements == nil)
        #expect(archive.loadScales == nil && archive.hiddenExercises == nil)
        #expect(archive.exerciseCatalog == nil && archive.effectiveLoadScales == nil && archive.effortScale == nil)
    }

    @Test func aMinimalFileRestoresAsAnEmptyPhoneWithTheFilesSettings() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try keepSomething(in: context)
        let json = """
        {"version": 2, "exportedAt": "2026-03-11T12:00:00Z",
         "settings": {"weightUnit": "lb", "userName": "Sam", "defaultRestSeconds": 75},
         "plans": [], "sessions": [], "customExercises": []}
        """

        try BackupService.restore(data: Data(json.utf8), context: context)

        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(AppSettings.shared.weightUnit == .lb)
        #expect(AppSettings.shared.userName == "Sam")
        #expect(AppSettings.shared.defaultRestSeconds == 75)
    }

    @Test func anOlderBackupWithNoneOfTheLaterFieldsRestoresWithTheStoresOwnDefaults() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        // Written before body metrics, Health, effort, set IDs, slot IDs and the
        // rest existed: empty strings on days and sessions, both a reps and a
        // seconds key on every set, and nothing else.
        let json = """
        {"version": 2, "exportedAt": "2025-11-02T09:00:00Z",
         "settings": {"weightUnit": "kg", "userName": "Sam", "defaultRestSeconds": 75},
         "plans": [{"id": "00000000-0000-4000-8000-0000000000A1", "name": "Old plan", "summary": "",
                    "isActive": true, "createdAt": "2025-10-01T08:00:00Z",
                    "days": [{"id": "00000000-0000-4000-8000-0000000000B1", "name": "Day 1", "order": 0,
                              "isRest": false, "notes": "",
                              "items": [{"catalogID": "barbell-bench-press", "name": "Barbell Bench Press",
                                         "order": 0, "targetSets": 3, "targetRepsLow": 8, "targetRepsHigh": 12}]}]}],
         "sessions": [{"id": "00000000-0000-4000-8000-0000000000C1", "title": "Day 1",
                       "startedAt": "2025-10-02T17:00:00Z", "endedAt": "2025-10-02T18:00:00Z",
                       "notes": "", "planName": "Old plan",
                       "sets": [{"catalogID": "barbell-bench-press", "exerciseName": "Barbell Bench Press",
                                 "exerciseOrder": 0, "setIndex": 0, "weightKg": 60, "reps": 8, "seconds": 45,
                                 "isCompleted": true, "isWarmup": false, "completedAt": "2025-10-02T17:10:00Z"}]}],
         "customExercises": []}
        """
        let context = try TestStore.context()

        try BackupService.restore(data: Data(json.utf8), context: context)

        let session = try #require(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(session.notes == "" && !session.isActive && !session.isLoggedAfterwards)
        #expect(session.planDayID == nil && session.plannedSlots == nil)
        #expect(session.healthWorkoutID == nil && !session.hasHealthMetrics && !session.wasWatchDriven)
        #expect(session.heartRateSource == nil && session.noteTags.isEmpty)
        let set = try #require(session.sets.first)
        #expect(set.weightKg == 60 && set.reps == 8 && set.isCompleted)
        #expect(set.completedAt == TestClock.at("2025-10-02T17:10:00"))
        #expect(set.rpe == nil && set.startedAt == nil && !set.hasHeartRate)
        #expect(set.loadNudgeOutcome == nil && !set.isContinuation && set.detectedWindow == nil)
        let item = try #require(context.fetch(FetchDescriptor<PlanItem>()).first)
        // Absent hold time comes back as the store's own default; absent
        // starting weight and rest as nothing set.
        #expect(item.targetSeconds == 45 && item.targetWeightKg == 0 && item.restSeconds == nil)
        #expect(item.notes == "" && item.trackingRaw == nil)
        #expect(try context.fetchCount(FetchDescriptor<BodyMetric>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLoadPreference>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HiddenExerciseRecord>()) == 0)
        #expect(AppSettings.shared.defaultRestSeconds == 75)
    }

    /// Written the way a build from the warm-up era wrote a file: every key
    /// present, empty notes, a hold time on a squat and two warm-up rows.
    private static let warmupEraFile = """
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

    @Test func aWarmupEraFileRestoresOnlyItsWorkingSetAndTakesItsKeysAtTheirWord() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()

        try BackupService.restore(data: Data(Self.warmupEraFile.utf8), context: context)

        // The two warm-ups would restore as ordinary working sets, which is false detail.
        let sets = try context.fetch(FetchDescriptor<SetLog>())
        #expect(sets.count == 1)
        let set = try #require(sets.first)
        #expect(set.weightKg == 100 && set.reps == 5)
        // An older file's keys are taken at their word, as they always were.
        #expect(set.seconds == 45 && set.targetRepsLow == 5 && set.targetRepsHigh == 8)
        let items = try context.fetch(FetchDescriptor<PlanItem>())
        #expect(items.count == 1)
        #expect(items.first?.targetSeconds == 45 && items.first?.targetRepsLow == 5 && items.first?.notes == "")
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1 && sessions.first?.notes == "")
        let days = try context.fetch(FetchDescriptor<PlanDay>())
        #expect(days.count == 1 && days.first?.weekday == 2 && days.first?.notes == "")
    }

    @Test func aFileFromBeforeSetIDsAndPlanDaysRestoresWithFreshIDsAndNoDay() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plan = PersistenceFixtures.plan("Plan", createdAt: start, active: true, in: context)
        let day = PersistenceFixtures.day("Push", order: 0, exercises: [PersistenceFixtures.bench], in: plan, context: context)
        for n in 0..<2 {
            let started = start.addingTimeInterval(Double(n) * 86_400)
            let session = PersistenceFixtures.session("Push \(n)", startedAt: started, endedAt: started.addingTimeInterval(3600),
                                                      planDayID: day.id, in: context)
            for index in 0..<3 {
                PersistenceFixtures.add(PersistenceFixtures.set(setIndex: index, completedAt: started.addingTimeInterval(Double(60 * (index + 1)))),
                                        to: session, in: context)
            }
        }
        try context.save()
        let storedIDs = Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id))
        // The same store as a build from before any of these keys would have written it.
        var root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))
        for key in ["timeZone", "appVersion", "appBuild", "effectiveLoadScales"] { root[key] = nil }
        root["sessions"] = try PersistenceFixtures.sessions(in: root).map { session in
            var session = session
            session["planDayID"] = nil
            session["sets"] = (session["sets"] as? [[String: Any]] ?? []).map { set in
                var set = set
                set["id"] = nil
                return set
            }
            return session
        }
        let old = try JSONSerialization.data(withJSONObject: root)

        let decoded = try BackupService.decodedArchive(from: old)
        #expect(decoded.timeZone == nil && decoded.appVersion == nil && decoded.appBuild == nil)
        #expect(decoded.effectiveLoadScales == nil)
        #expect(decoded.sessions.allSatisfy { $0.planDayID == nil && $0.sets.allSatisfy { $0.id == nil } })

        try BackupService.restore(data: old, context: context)

        let fresh = try context.fetch(FetchDescriptor<SetLog>()).map(\.id)
        #expect(fresh.count == storedIDs.count && Set(fresh).count == fresh.count, "Each set gets its own new ID")
        // An old file has no IDs to keep, so none of the ones it replaced may come back.
        #expect(Set(fresh).isDisjoint(with: storedIDs))
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).allSatisfy { $0.planDayID == nil })
    }

    @Test func keysThisBuildHasNeverHeardOfAreIgnoredAtEveryLevel() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var root = try PersistenceFixtures.object(BackupService.encoded(archive()))
        root["futureTopLevel"] = ["a": 1]
        var settings = try #require(root["settings"] as? [String: Any])
        settings["futureSetting"] = true
        root["settings"] = settings
        editFirst(&root, "sessions") { session in
            session["futureSessionKey"] = "x"
            editFirst(&session, "sets") { $0["futureSetKey"] = [1, 2, 3] }
        }
        editFirst(&root, "plans") { plan in
            plan["futurePlanKey"] = NSNull()
        }
        let context = try TestStore.context()

        try BackupService.restore(data: JSONSerialization.data(withJSONObject: root), context: context)

        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 1)
    }

    // MARK: - Malformed files change nothing

    @Test(arguments: [0.0, 0.1, 0.5, 0.97])
    func aTruncatedFileThrowsAndLeavesThePhoneAsItWas(_ fraction: Double) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let whole = try BackupService.encoded(archive())
        let cut = whole.prefix(Int(Double(whole.count) * fraction))
        let context = try TestStore.context()
        try keepSomething(in: context)

        #expect(throws: DecodingError.self) {
            try BackupService.restore(data: Data(cut), context: context)
        }

        try expectUntouched(context)
    }

    @Test(arguments: WrongType.allCases)
    func aValueOfTheWrongTypeThrowsAndLeavesThePhoneAsItWas(_ wrong: WrongType) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var root = try PersistenceFixtures.object(BackupService.encoded(archive()))
        wrong.apply(to: &root)
        let data = try JSONSerialization.data(withJSONObject: root)
        let context = try TestStore.context()
        try keepSomething(in: context)

        #expect(throws: DecodingError.self) {
            try BackupService.restore(data: data, context: context)
        }

        try expectUntouched(context)
    }

    @Test(arguments: InvalidValue.allCases)
    func aValueNoVersionOfTheAppWritesIsRefusedBeforeAnythingIsWiped(_ invalid: InvalidValue) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var broken = archive()
        invalid.apply(to: &broken)
        let data = try BackupService.encoded(broken)
        let context = try TestStore.context()
        try keepSomething(in: context)

        do {
            try BackupService.restore(data: data, context: context)
            Issue.record("\(invalid) was accepted")
        } catch let error as BackupService.RestoreError {
            guard case let .invalidValue(field, _, _, _) = error else {
                Issue.record("\(invalid) was refused for the wrong reason: \(error)")
                return
            }
            #expect(field == invalid.field)
        }

        try expectUntouched(context)
    }

    @Test func aNegativeRepCountIsRefusedLikeEveryOtherMeasurement() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var broken = archive()
        broken.sessions[0].sets[0].reps = -5
        let data = try BackupService.encoded(broken)
        let context = try TestStore.context()
        try keepSomething(in: context)

        // `validate` turns away a negative weight and a negative time, and a
        // rep count is the one measurement of the three it lets through. A
        // negative count restores as negative volume and negative total reps.
        withKnownIssue("validate does not check SetDTO.reps, so a negative rep count restores (#5)") {
            #expect(throws: BackupService.RestoreError.self) {
                try BackupService.restore(data: data, context: context)
            }
        }
    }

    @Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
    func aWeightThatIsNotARealNumberIsRefused(_ weight: Double) throws {
        var broken = archive()
        broken.sessions[0].sets[0].weightKg = weight

        // JSON has no spelling for these, so the archive is checked directly.
        do {
            try BackupService.validate(broken)
            Issue.record("A weight of \(weight) was accepted")
        } catch BackupService.RestoreError.invalidValue(let field, _, _, _) {
            #expect(field == "weight")
        }
    }

    @Test func aWeightThatOverflowsADoubleIsRefusedAndTouchesNothing() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let overflowing = String(decoding: try encoder.encode(archive()), as: UTF8.self)
            .replacingOccurrences(of: "\"weightKg\":100", with: "\"weightKg\":1e999")
        try #require(overflowing.contains("1e999"))
        let context = try TestStore.context()
        try keepSomething(in: context)

        #expect(throws: (any Error).self) {
            try BackupService.restore(data: Data(overflowing.utf8), context: context)
        }

        try expectUntouched(context)
    }

    @Test func aRepeatedCustomExerciseIDIsRefusedByBothRestoresAndNamed() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var file = archive()
        file.customExercises = [
            BackupService.CustomExerciseDTO(id: "custom-sled", name: "Sled Push", category: "strength",
                                            muscleRaw: [], equipment: ["Sled"], trackingRaw: "weightReps"),
            BackupService.CustomExerciseDTO(id: "custom-hold", name: "Sled Hold", category: "strength",
                                            muscleRaw: [], equipment: ["Sled"], trackingRaw: "duration"),
        ]
        var repeated = file
        repeated.customExercises[1].id = repeated.customExercises[0].id
        let bad = try BackupService.encoded(repeated)
        let context = try TestStore.context()
        try keepSomething(in: context)
        let before = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp())

        func expectNamed(_ error: any Error, by path: String) {
            guard case let BackupService.RestoreError.invalidValue(field, value, _, _) = error else {
                Issue.record("\(path) refused for the wrong reason: \(error)")
                return
            }
            #expect(field == "custom exercise ID", "\(path) names the field")
            #expect(value == "custom-sled", "\(path) names the repeated ID")
        }
        do {
            try BackupService.restore(data: bad, context: context)
            Issue.record("restore accepted a repeated custom exercise ID")
        } catch {
            expectNamed(error, by: "restore")
        }
        do {
            try await BackupService.restoreOffMain(data: bad, context: context)
            Issue.record("restoreOffMain accepted a repeated custom exercise ID")
        } catch {
            expectNamed(error, by: "restoreOffMain")
        }

        try expectUntouched(context)
        #expect(try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()) == before)

        // Distinct IDs are all the check asks for.
        try await BackupService.restoreOffMain(data: BackupService.encoded(file), context: context)
        #expect(try context.fetchCount(FetchDescriptor<CustomExerciseRecord>()) == 2)
    }

    @Test(arguments: AcceptedValue.allCases)
    func aValueThisAppHasWrittenOrNeverStoresRestores(_ accepted: AcceptedValue) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var file = archive()
        accepted.apply(to: &file)
        let context = try TestStore.context()

        try BackupService.restore(data: BackupService.encoded(file), context: context)

        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == file.plans.count)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == file.sessions.count)
        let working = file.sessions.flatMap(\.sets).filter { $0.isWarmup != true }
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == working.count)
    }

    // MARK: - Dates

    @Test(arguments: [
        DateCase(text: "2026-03-11T12:00:00Z", decodes: true),
        DateCase(text: "2026-03-11T14:00:00+02:00", decodes: true),
        DateCase(text: "2026-03-11T00:00:00-12:00", decodes: true),
        DateCase(text: "2026-03-11", decodes: false),
        DateCase(text: "2026-03-11 12:00:00", decodes: false),
        DateCase(text: "yesterday", decodes: false),
    ])
    func datesReadAsISO8601WithAnOffsetOrNotAtAll(_ date: DateCase) throws {
        let json = """
        {"version": 2, "exportedAt": "\(date.text)",
         "settings": {"weightUnit": "kg", "userName": "A", "defaultRestSeconds": 90},
         "plans": [], "sessions": [], "customExercises": []}
        """

        if date.decodes {
            let archive = try BackupService.decodedArchive(from: Data(json.utf8))
            // Every accepted spelling is the same instant.
            #expect(archive.exportedAt == TestClock.reference)
        } else {
            #expect(throws: DecodingError.self) { try BackupService.decodedArchive(from: Data(json.utf8)) }
        }
    }

    // MARK: - Weekdays

    @Test(arguments: [0, 8, -1, Int.min, Int.max])
    func aWeekdayOutsideTheWeekReadsAsUnpinnedRatherThanTrapping(_ weekday: Int) {
        let day = PlanDay(name: "Bad", order: 0, weekday: weekday)

        #expect(day.weekdayName == nil && day.weekdayShortName == nil)
    }

    @Test func weekdaysOneAndSevenAreSundayAndSaturdayAndNoWeekdayIsUnpinned() {
        #expect(PlanDay(name: "Sunday", order: 0, weekday: 1).weekdayName == Calendar.current.weekdaySymbols[0])
        #expect(PlanDay(name: "Saturday", order: 0, weekday: 7).weekdayShortName
                == Calendar.current.shortWeekdaySymbols[6])
        #expect(PlanDay(name: "Floating", order: 0).weekdayName == nil)
    }

    // MARK: - What restore keeps and what it will not store

    @Test func aRestoredSlotForTheLiftersOwnExerciseCarriesItsTrackingPastTheExercisesDeletion() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var file = archive()
        file.customExercises = [
            BackupService.CustomExerciseDTO(id: "custom-aaaa0001", name: "Sled hold", category: "Strength",
                                            muscleRaw: [], equipment: [], trackingRaw: "duration"),
            BackupService.CustomExerciseDTO(id: "custom-aaaa0002", name: "Odd curl", category: "Strength",
                                            muscleRaw: [], equipment: [], trackingRaw: "weightReps"),
        ]
        func slot(_ catalogID: String, order: Int, tracking: String?) -> BackupService.ItemDTO {
            BackupService.ItemDTO(catalogID: catalogID, name: catalogID, order: order, targetSets: 3, tracking: tracking)
        }
        file.plans[0].days[0].items = [
            // An older file, which wrote no snapshot.
            slot("custom-aaaa0001", order: 0, tracking: nil),
            // A snapshot that contradicts the exercise it was written under.
            slot("custom-aaaa0002", order: 1, tracking: "duration"),
            // A bundled exercise, which has nothing to snapshot.
            slot(PersistenceFixtures.bench.id, order: 2, tracking: nil),
            // Its exercise was deleted before the export.
            slot("custom-gone0003", order: 3, tracking: "duration"),
        ]
        let context = try TestStore.context()

        try BackupService.restore(data: BackupService.encoded(file), context: context)

        let slots = try context.fetch(FetchDescriptor<PlanItem>()).sorted { $0.order < $1.order }
        #expect(slots.map(\.trackingRaw) == ["duration", "weightReps", nil, "duration"])

        // The point of the snapshot: the slot still reads as timed once the
        // exercise, and with it the catalog entry, is gone.
        for record in try context.fetch(FetchDescriptor<CustomExerciseRecord>()) { context.delete(record) }
        try context.save()
        context.refreshCustomExercises()
        let held = try #require(context.fetch(FetchDescriptor<PlanItem>()).first { $0.catalogID == "custom-aaaa0001" })
        #expect(held.tracking == .duration)
    }

    @Test func restoreStoresOnlyWhatItUnderstandsAndLeavesWarmupsOut() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var file = archive()
        var logged = file.sessions[0].sets[0]
        logged.id = nil
        logged.averageHeartRate = 150
        logged.heartRateWindow = "bogus"
        logged.loadNudge = BackupService.LoadNudgeDTO(outcome: "maybe", toKg: 102.5)
        logged.detectedStartedAt = start.addingTimeInterval(10)
        logged.continues = "drop"
        logged.completedAt = start.addingTimeInterval(60)
        var continuing = logged
        continuing.setIndex = 1
        continuing.weightKg = 80
        continuing.continues = "someFutureWord"
        continuing.completedAt = start.addingTimeInterval(120)
        var warmup = logged
        warmup.setIndex = 2
        warmup.isWarmup = true
        file.sessions[0].sets = [logged, continuing, warmup]
        file.sessions[0].noteTags = ["pain", "mystery"]
        file.sessions[0].exerciseNotes = [
            BackupService.ExerciseNoteDTO(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name,
                                          text: "  ", tags: ["mystery"]),
        ]
        let context = try TestStore.context()

        try BackupService.restore(data: BackupService.encoded(file), context: context)

        let session = try #require(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let sets = session.sets.sorted(by: SetLog.precedesInSession)
        // A warm-up would restore as an ordinary working set, which is false detail.
        #expect(sets.map(\.setIndex) == [0, 1])
        #expect(session.noteTags == [.pain])
        #expect(session.exerciseNotes.isEmpty)
        let first = sets[0]
        // The numbers survive the loss of their label; the label does not.
        #expect(first.averageHeartRate == 150 && first.heartRateWindowRaw == nil)
        #expect(first.loadNudgeOutcome == nil && first.loadNudgeToKg == nil)
        // Half a window is not a reading of the set.
        #expect(first.detectedWindow == nil && first.detectedStartedAt == nil)
        // Nothing sits above the first set of an exercise to continue.
        #expect(!first.isContinuation)
        #expect(sets[1].isContinuation && sets[1].continuation == .drop)
    }

    @Test func sectionsThatDescribeTheFileAreNeverReadBackAndAreWrittenAgainFresh() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        var file = archive()
        file.exerciseCatalog = [BackupService.CatalogExerciseDTO(
            catalogID: PersistenceFixtures.bench.id, name: "Renamed Press", category: "strength",
            muscleRaw: [], muscles: [], equipment: [], trackingRaw: TrackingMode.duration.rawValue)]
        file.effectiveLoadScales = [BackupService.EffectiveLoadScaleDTO(
            catalogID: PersistenceFixtures.bench.id, unit: "lb", increment: 5, source: "correction")]
        file.sessions[0].sets[0].rpe = 6
        file.sessions[0].sets[0].effort = "allOut"
        let context = try TestStore.context()

        try BackupService.restore(data: BackupService.encoded(file), context: context)

        // `rpe` is the stored answer; `effort` is derived from it and ignored.
        #expect(try context.fetch(FetchDescriptor<SetLog>()).first?.rpe == 6)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLoadPreference>()) == 0)
        #expect(ExerciseCatalog.shared.exercise(id: PersistenceFixtures.bench.id)?.name == PersistenceFixtures.bench.name)

        let again = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))
        let described = try #require(again["exerciseCatalog"] as? [[String: Any]])
        #expect(described.first?["name"] as? String == PersistenceFixtures.bench.name)
        let rungs = try #require(again["effectiveLoadScales"] as? [[String: Any]])
        #expect(rungs.first?["source"] as? String == "derived")
        #expect(try PersistenceFixtures.sets(in: again, sessionIndex: 0).first?["effort"] as? String == "easy")
    }

    // MARK: - A field with no data has no key

    @Test func aLoggedSetWithNoExtrasWritesNoKeysForThem() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, endedAt: start.addingTimeInterval(3600), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start.addingTimeInterval(60)), to: session, in: context)

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))
        let set = try #require(PersistenceFixtures.sets(in: root, sessionIndex: 0).first)

        for key in ["rpe", "effort", "startedAt", "averageHeartRate", "maxHeartRate", "heartRateWindow",
                    "detectedStartedAt", "detectedEndedAt", "loadNudge", "continues", "isWarmup",
                    "targetRepsLow", "targetRepsHigh", "seconds", "tracking"] {
            #expect(!set.keys.contains(key), "\(key) was written for a set with nothing to say")
        }
        #expect(set["reps"] as? Int == 5 && set["isCompleted"] as? Bool == true)
        // Not a single null anywhere in the file.
        #expect(!String(decoding: try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()), as: UTF8.self).contains("null"))
    }

    @Test func aSetCarriesOnlyTheMeasureItWasCountedIn() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, endedAt: start.addingTimeInterval(3600), in: context)
        // A hold still carries the reps and rep range it was seeded with, and a
        // reps set the hold time of the slot underneath.
        let hold = SetLog(catalogID: PersistenceFixtures.plank.id, exerciseName: PersistenceFixtures.plank.name,
                          exerciseOrder: 0, setIndex: 0, reps: 12, seconds: 45,
                          targetRepsLow: 8, targetRepsHigh: 12, tracking: .duration)
        hold.isCompleted = true
        let lift = SetLog(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name,
                          exerciseOrder: 1, setIndex: 0, weightKg: 100, reps: 5, seconds: 45,
                          targetRepsLow: 5, targetRepsHigh: 8, tracking: .weightReps)
        lift.isCompleted = true
        PersistenceFixtures.add(hold, to: session, in: context)
        PersistenceFixtures.add(lift, to: session, in: context)

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))
        let sets = try PersistenceFixtures.sets(in: root, sessionIndex: 0)

        #expect(sets[0]["seconds"] as? Int == 45)
        for key in ["reps", "targetRepsLow", "targetRepsHigh"] { #expect(!sets[0].keys.contains(key)) }
        #expect(sets[1]["reps"] as? Int == 5 && sets[1]["targetRepsLow"] as? Int == 5)
        #expect(!sets[1].keys.contains("seconds"))
    }

    @Test func aSessionWithNothingToSayWritesNoOptionalKeysAndNoNumbersItCannotVouchFor() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let bare = PersistenceFixtures.session("Bare", startedAt: start, endedAt: start.addingTimeInterval(3600), in: context)
        bare.notes = "   \n "
        // Left behind by numbers since cleared, or too small to be a reading.
        let leftovers = PersistenceFixtures.session("Leftovers", startedAt: start.addingTimeInterval(86_400),
                                                    endedAt: start.addingTimeInterval(90_000), in: context)
        leftovers.heartRateSourceRaw = VitalsSource.watchWorkout.rawValue
        leftovers.heartRateReadings = 600
        leftovers.energySourceRaw = VitalsSource.healthSamples.rawValue
        leftovers.activeEnergyKcal = 0.4

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))

        for session in try PersistenceFixtures.sessions(in: root) {
            for key in ["notes", "noteTags", "exerciseNotes", "planDayID", "plannedItems", "loggedAfterwards",
                        "averageHeartRate", "maxHeartRate", "activeEnergyKcal", "healthWorkoutID",
                        "heartRateSource", "heartRateReadings", "energySource"] {
                #expect(!session.keys.contains(key), "\(session["title"] ?? "?") wrote \(key)")
            }
            #expect(session["endedAt"] != nil)
        }
    }

    @Test func measurementsWriteOnlyThePartsTakenAndNoSectionWhenThereAreNone() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()

        let empty = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))
        #expect(!empty.keys.contains("bodyMeasurements"))
        #expect((empty["sessions"] as? [Any])?.isEmpty == true)

        // A check-in with no part measured is only a date, so it is left out.
        context.insert(BodyMeasurement(date: start))
        let tape = BodyMeasurement(date: start.addingTimeInterval(60))
        tape.set(38.5, for: .arm)
        tape.set(0, for: .chest)
        context.insert(tape)

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))
        let checks = try #require(root["bodyMeasurements"] as? [[String: Any]])
        #expect(checks.count == 1)
        #expect(checks[0]["armCm"] as? Double == 38.5)
        for key in ["chestCm", "shouldersCm", "waistCm", "thighCm"] { #expect(!checks[0].keys.contains(key)) }
    }

    @Test func aPlanAndSetsWriteOnlyWhatSomebodySetAndReadTheGapsBackAsTheZerosTheyWere() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try BackupService.restore(data: Data(Self.warmupEraFile.utf8), context: context)
        let mixed = PersistenceFixtures.session("Mixed", startedAt: start, endedAt: start.addingTimeInterval(3600), in: context)
        // A reps set still carrying the plan's hold time underneath.
        let squat = SetLog(catalogID: "test-squat", exerciseName: "Squat", exerciseOrder: 0, setIndex: 0,
                           weightKg: 100, reps: 5, seconds: 45, targetRepsLow: 5, targetRepsHigh: 8, tracking: .weightReps)
        // A row whose zero targets stand for "no target", as a continuation's do.
        let drop = SetLog(catalogID: "test-squat", exerciseName: "Squat", exerciseOrder: 0, setIndex: 1,
                          weightKg: 80, reps: 4, seconds: 45, tracking: .weightReps)
        // A timed set seeded with a rep count and an off-plan rep range.
        let plank = SetLog(catalogID: "test-plank", exerciseName: "Plank", exerciseOrder: 1, setIndex: 0,
                           reps: 10, seconds: 60, targetRepsLow: 8, targetRepsHigh: 12, tracking: .duration)
        for set in [squat, drop, plank] {
            set.isCompleted = true
            set.completedAt = start.addingTimeInterval(600)
            PersistenceFixtures.add(set, to: mixed, in: context)
        }
        let day = try #require(context.fetch(FetchDescriptor<PlanDay>()).first)
        let timed = PlanItem(catalogID: "test-plank", name: "Plank", order: 1, targetRepsLow: 0, targetRepsHigh: 0,
                             targetSeconds: 60)
        timed.trackingRaw = TrackingMode.duration.rawValue
        timed.day = day
        context.insert(timed)
        let weighted = try #require(context.fetch(FetchDescriptor<PlanItem>()).first { $0.catalogID == "test-squat" })
        weighted.trackingRaw = TrackingMode.weightReps.rawValue
        weighted.notes = "  "
        try context.save()

        let url = try BackupService.export(context: context, stamp: PersistenceFixtures.stamp())
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let root = try PersistenceFixtures.object(data)

        let session = try #require(PersistenceFixtures.sessions(in: root).first { $0["title"] as? String == "Mixed" })
        #expect(!session.keys.contains("notes"), "A session nobody wrote about carries no notes key")
        let rows = try #require(session["sets"] as? [[String: Any]])
        func row(_ name: String, _ index: Int) throws -> [String: Any] {
            try #require(rows.first { $0["exerciseName"] as? String == name && $0["setIndex"] as? Int == index })
        }
        let squatRow = try row("Squat", 0), dropRow = try row("Squat", 1), plankRow = try row("Plank", 0)
        #expect(!squatRow.keys.contains("seconds"), "A reps set carries no hold time nobody timed")
        #expect(squatRow["reps"] as? Int == 5)
        #expect(squatRow["targetRepsLow"] as? Int == 5 && squatRow["targetRepsHigh"] as? Int == 8)
        #expect(!dropRow.keys.contains("targetRepsLow") && !dropRow.keys.contains("targetRepsHigh"),
                "Zero targets are not written as targets")
        #expect(!plankRow.keys.contains("reps"), "A timed set carries no rep count nobody counted")
        #expect(plankRow["seconds"] as? Int == 60)
        #expect(!plankRow.keys.contains("targetRepsLow") && !plankRow.keys.contains("targetRepsHigh"),
                "A timed set carries no rep range")

        let plans = try #require(root["plans"] as? [[String: Any]])
        let days = try #require(plans.first?["days"] as? [[String: Any]])
        #expect(days.first?.keys.contains("notes") == false, "A day without a note carries no notes key")
        let items = try #require(days.first?["items"] as? [[String: Any]])
        let squatItem = try #require(items.first { $0["name"] as? String == "Squat" })
        let plankItem = try #require(items.first { $0["name"] as? String == "Plank" })
        #expect(!squatItem.keys.contains("targetSeconds"), "A reps slot carries no hold target")
        #expect(!squatItem.keys.contains("targetWeightKg"), "No starting weight means no key")
        #expect(!squatItem.keys.contains("notes"), "A note of spaces is no note")
        #expect(squatItem["targetRepsLow"] as? Int == 5 && squatItem["targetRepsHigh"] as? Int == 8)
        #expect(!plankItem.keys.contains("targetRepsLow") && !plankItem.keys.contains("targetRepsHigh"),
                "A timed slot's zero range is not written")
        #expect(plankItem["targetSeconds"] as? Int == 60)

        // That shape restores: absent reps, seconds and targets come back as
        // the zeros they stood for, and a reps slot keeps the default hold.
        try BackupService.restore(data: data, context: context)

        let sets = try context.fetch(FetchDescriptor<SetLog>())
        let restoredPlank = try #require(sets.first { $0.exerciseName == "Plank" })
        #expect(restoredPlank.reps == 0 && restoredPlank.seconds == 60 && restoredPlank.targetRepsHigh == 0)
        let restoredSquat = try #require(sets.first {
            $0.exerciseName == "Squat" && $0.setIndex == 0 && $0.session?.title == "Mixed"
        })
        #expect(restoredSquat.seconds == 0 && restoredSquat.reps == 5 && restoredSquat.targetRepsLow == 5)
        let slots = try context.fetch(FetchDescriptor<PlanItem>())
        #expect(slots.first { $0.name == "Squat" }?.targetSeconds == 45)
        #expect(slots.first { $0.name == "Plank" }?.targetSeconds == 60)
        #expect(slots.first { $0.name == "Plank" }?.targetRepsLow == 0)
    }

    // MARK: - Fixtures

    /// A valid one-plan, one-session archive built from the file's own types,
    /// for tests that break one thing in it.
    private func archive() -> BackupService.Archive {
        let bench = PersistenceFixtures.bench
        let item = BackupService.ItemDTO(catalogID: bench.id, name: bench.name, order: 0, targetSets: 3)
        let day = BackupService.DayDTO(id: Self.dayID, name: "Push", order: 0, isRest: false, items: [item])
        let plan = BackupService.PlanDTO(id: Self.planID, name: "Plan", summary: "", isActive: true,
                                         createdAt: start, days: [day])
        let set = BackupService.SetDTO(id: Self.setID, catalogID: bench.id, exerciseName: bench.name,
                                       exerciseOrder: 0, setIndex: 0, weightKg: 100, reps: 5, isCompleted: true)
        let session = BackupService.SessionDTO(id: Self.sessionID, title: "Push", startedAt: start,
                                               endedAt: start.addingTimeInterval(3600), planName: "Plan", sets: [set])
        return BackupService.Archive(
            exportedAt: TestClock.reference,
            settings: BackupService.Settings(weightUnit: "kg", userName: "Test Lifter", defaultRestSeconds: 90),
            plans: [plan], sessions: [session], customExercises: [])
    }

    /// Something on the phone that a refused restore must not disturb.
    private func keepSomething(in context: ModelContext) throws {
        PersistenceFixtures.plan("Keep", createdAt: start, active: true, in: context)
        let session = PersistenceFixtures.session("Keep session", startedAt: start, endedAt: start.addingTimeInterval(1800), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start), to: session, in: context)
        AppSettings.shared.userName = "Still me"
        try context.save()
    }

    private func expectUntouched(_ context: ModelContext) throws {
        #expect(try context.fetch(FetchDescriptor<Plan>()).map(\.name) == ["Keep"])
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.title) == ["Keep session"])
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 1)
        #expect(AppSettings.shared.userName == "Still me")
    }
}

/// Changes the first row under `key` in place, for editing nested JSON.
private func editFirst(_ root: inout [String: Any], _ key: String, _ change: (inout [String: Any]) -> Void) {
    var rows = root[key] as? [[String: Any]] ?? []
    guard !rows.isEmpty else { return }
    change(&rows[0])
    root[key] = rows
}

/// A date spelling and whether the decoder accepts it.
struct DateCase: Sendable {
    var text: String
    var decodes: Bool
}

/// One way to put the wrong type where the decoder expects another.
enum WrongType: CaseIterable, Sendable {
    case restSecondsIsAWord, settingsMissing, startedAtIsNotADate, completedFlagIsAWord, weekdayIsAWord,
         weightIsNull, sessionsIsAnObject

    func apply(to root: inout [String: Any]) {
        switch self {
        case .restSecondsIsAWord:
            var settings = root["settings"] as? [String: Any] ?? [:]
            settings["defaultRestSeconds"] = "ninety"
            root["settings"] = settings
        case .settingsMissing:
            root["settings"] = nil
        case .startedAtIsNotADate:
            editFirst(&root, "sessions") { $0["startedAt"] = "yesterday" }
        case .completedFlagIsAWord:
            editFirst(&root, "sessions") { session in editFirst(&session, "sets") { $0["isCompleted"] = "yes" } }
        case .weekdayIsAWord:
            editFirst(&root, "plans") { plan in editFirst(&plan, "days") { $0["weekday"] = "monday" } }
        case .weightIsNull:
            editFirst(&root, "sessions") { session in editFirst(&session, "sets") { $0["weightKg"] = NSNull() } }
        case .sessionsIsAnObject:
            root["sessions"] = ["title": "Push"]
        }
    }
}

/// One value no version of the app writes, and the field the refusal names.
enum InvalidValue: CaseIterable, Sendable {
    case weekdayNine, weekdayZero, weekdayEight, slotRepRangeTooHigh, slotRepRangeBothEndsTooHigh,
         slotRepRangeNegative, slotRepRangeTopTooHigh, setRepRangeTooHigh, setRepRangeBottomTooHigh,
         negativeStartingWeight, negativeSetWeight, negativeHoldTime, negativeSlotRest, negativeDefaultRest,
         negativeSetSeconds, negativeOfferedWeight, negativeBodyWeight, zeroGirth, zeroArm, duplicatePlanID,
         duplicateDayID, dayIDRepeatedAcrossPlans, duplicateSessionID, duplicateSetID,
         setIDRepeatedAcrossSessions, duplicateCustomExerciseID

    var field: String {
        switch self {
        case .weekdayNine, .weekdayZero, .weekdayEight: "weekday"
        case .slotRepRangeTooHigh, .slotRepRangeBothEndsTooHigh, .slotRepRangeNegative, .slotRepRangeTopTooHigh,
             .setRepRangeTooHigh, .setRepRangeBottomTooHigh: "rep range"
        case .negativeStartingWeight: "starting weight"
        case .negativeSetWeight: "weight"
        case .negativeHoldTime: "hold time"
        case .negativeSlotRest: "rest"
        case .negativeDefaultRest: "default rest"
        case .negativeSetSeconds: "time"
        case .negativeOfferedWeight: "offered weight"
        case .negativeBodyWeight: "body weight"
        case .zeroGirth: "waist"
        case .zeroArm: "arm"
        case .duplicatePlanID: "plan ID"
        case .duplicateDayID, .dayIDRepeatedAcrossPlans: "day ID"
        case .duplicateSessionID: "session ID"
        case .duplicateSetID, .setIDRepeatedAcrossSessions: "set ID"
        case .duplicateCustomExerciseID: "custom exercise ID"
        }
    }

    func apply(to archive: inout BackupService.Archive) {
        let moment = TestClock.reference
        switch self {
        case .weekdayNine: archive.plans[0].days[0].weekday = 9
        case .weekdayZero: archive.plans[0].days[0].weekday = 0
        case .weekdayEight: archive.plans[0].days[0].weekday = 8
        case .slotRepRangeTooHigh: archive.plans[0].days[0].items[0].targetRepsLow = 70
        case .slotRepRangeBothEndsTooHigh:
            archive.plans[0].days[0].items[0].targetRepsLow = 70
            archive.plans[0].days[0].items[0].targetRepsHigh = 70
        case .slotRepRangeNegative: archive.plans[0].days[0].items[0].targetRepsLow = -1
        case .slotRepRangeTopTooHigh: archive.plans[0].days[0].items[0].targetRepsHigh = 500
        case .setRepRangeTooHigh: archive.sessions[0].sets[0].targetRepsHigh = 61
        case .setRepRangeBottomTooHigh: archive.sessions[0].sets[0].targetRepsLow = 61
        case .negativeStartingWeight: archive.plans[0].days[0].items[0].targetWeightKg = -1
        case .negativeSetWeight: archive.sessions[0].sets[0].weightKg = -5
        case .negativeHoldTime: archive.plans[0].days[0].items[0].targetSeconds = -30
        case .negativeSlotRest: archive.plans[0].days[0].items[0].restSeconds = -1
        case .negativeDefaultRest: archive.settings.defaultRestSeconds = -1
        case .negativeSetSeconds: archive.sessions[0].sets[0].seconds = -10
        case .negativeOfferedWeight:
            archive.sessions[0].sets[0].loadNudge = BackupService.LoadNudgeDTO(outcome: "taken", toKg: -2.5)
        case .negativeBodyWeight:
            archive.bodyMetrics = [BackupService.BodyMetricDTO(id: UUID(), date: moment, weightKg: -1, source: "manual")]
        case .zeroGirth:
            archive.bodyMeasurements = [BackupService.BodyMeasurementDTO(id: UUID(), date: moment, waistCm: 0)]
        case .zeroArm:
            archive.bodyMeasurements = [BackupService.BodyMeasurementDTO(id: UUID(), date: moment, armCm: 0, waistCm: 80)]
        case .duplicatePlanID: archive.plans.append(archive.plans[0])
        case .duplicateDayID: archive.plans[0].days.append(archive.plans[0].days[0])
        case .dayIDRepeatedAcrossPlans:
            var other = archive.plans[0]
            other.id = UUID()
            other.isActive = false
            archive.plans.append(other)
        case .duplicateSessionID: archive.sessions.append(archive.sessions[0])
        case .duplicateSetID: archive.sessions[0].sets.append(archive.sessions[0].sets[0])
        case .setIDRepeatedAcrossSessions: archive.sessions.append(archive.sessions[0].nextDay())
        case .duplicateCustomExerciseID:
            let custom = BackupService.CustomExerciseDTO(id: "custom-1", name: "Press", category: "strength",
                                                         muscleRaw: [], equipment: [], trackingRaw: "weightReps")
            archive.customExercises = [custom, custom]
        }
    }
}

/// One value this app has written itself, or one restore never stores, so
/// nothing about it may turn a file away.
enum AcceptedValue: CaseIterable, Sendable {
    case warmupWithANegativeWeight, backwardsRepRanges, noWeekday, weekdaySeven, slotRepRangeAtItsEdges,
         noSetTargets, zeroWeight, warmupRepeatingASetID, distinctIDsAcrossTwoPlansAndSessions

    func apply(to archive: inout BackupService.Archive) {
        switch self {
        case .warmupWithANegativeWeight:
            var warmup = archive.sessions[0].sets[0]
            warmup.id = UUID()
            warmup.setIndex = 1
            warmup.isWarmup = true
            warmup.weightKg = -40
            archive.sessions[0].sets.append(warmup)
        case .backwardsRepRanges:
            // The day editor did not keep the ends in order once, so this
            // app's own older files hold ranges like these.
            archive.plans[0].days[0].items[0].targetRepsLow = 12
            archive.plans[0].days[0].items[0].targetRepsHigh = 8
            archive.sessions[0].sets[0].targetRepsLow = 9
        case .noWeekday: archive.plans[0].days[0].weekday = nil
        case .weekdaySeven: archive.plans[0].days[0].weekday = 7
        case .slotRepRangeAtItsEdges:
            archive.plans[0].days[0].items[0].targetRepsLow = 0
            archive.plans[0].days[0].items[0].targetRepsHigh = 60
        case .noSetTargets:
            archive.sessions[0].sets[0].targetRepsLow = nil
            archive.sessions[0].sets[0].targetRepsHigh = nil
        case .zeroWeight: archive.sessions[0].sets[0].weightKg = 0
        case .warmupRepeatingASetID:
            var again = archive.sessions[0].nextDay()
            again.sets[0].isWarmup = true
            archive.sessions.append(again)
        case .distinctIDsAcrossTwoPlansAndSessions:
            var other = archive.plans[0]
            other.id = UUID()
            other.isActive = false
            other.days[0].id = UUID()
            archive.plans.append(other)
            var again = archive.sessions[0].nextDay()
            again.sets[0].id = UUID()
            archive.sessions.append(again)
        }
    }
}

private extension BackupService.SessionDTO {
    /// The same session a day later under a new ID, its sets' IDs unchanged.
    func nextDay() -> Self {
        var copy = self
        copy.id = UUID()
        copy.startedAt = startedAt.addingTimeInterval(86_400)
        copy.endedAt = endedAt?.addingTimeInterval(86_400)
        return copy
    }
}
