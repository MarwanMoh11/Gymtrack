import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What `BackupService` accepts and what it writes, key by key: older version-2
/// files that predate the optional fields, malformed and hostile files turned
/// away before anything is wiped, and the rule that a field with no data is
/// absent from the file rather than null, zero or a sentinel.
///
/// Complements `Tests/BackupArchiveIntegrityTests.swift` and
/// `Tests/BackupIDsTrackingTests.swift`, which cover the same rules through
/// stubs. Whole-store round trips are in `BackupRestoreTests`.
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
        withKnownIssue("validate does not check SetDTO.reps, so a negative rep count restores") {
            #expect(throws: BackupService.RestoreError.self) {
                try BackupService.restore(data: data, context: context)
            }
        }
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

    // MARK: - What restore keeps and what it will not store

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
    case weekdayNine, weekdayZero, slotRepRangeTooHigh, setRepRangeTooHigh, negativeStartingWeight,
         negativeSetWeight, negativeHoldTime, negativeSlotRest, negativeDefaultRest, negativeSetSeconds,
         negativeOfferedWeight, negativeBodyWeight, zeroGirth, duplicatePlanID, duplicateDayID,
         duplicateSessionID, duplicateSetID, duplicateCustomExerciseID

    var field: String {
        switch self {
        case .weekdayNine, .weekdayZero: "weekday"
        case .slotRepRangeTooHigh, .setRepRangeTooHigh: "rep range"
        case .negativeStartingWeight: "starting weight"
        case .negativeSetWeight: "weight"
        case .negativeHoldTime: "hold time"
        case .negativeSlotRest: "rest"
        case .negativeDefaultRest: "default rest"
        case .negativeSetSeconds: "time"
        case .negativeOfferedWeight: "offered weight"
        case .negativeBodyWeight: "body weight"
        case .zeroGirth: "waist"
        case .duplicatePlanID: "plan ID"
        case .duplicateDayID: "day ID"
        case .duplicateSessionID: "session ID"
        case .duplicateSetID: "set ID"
        case .duplicateCustomExerciseID: "custom exercise ID"
        }
    }

    func apply(to archive: inout BackupService.Archive) {
        let moment = TestClock.reference
        switch self {
        case .weekdayNine: archive.plans[0].days[0].weekday = 9
        case .weekdayZero: archive.plans[0].days[0].weekday = 0
        case .slotRepRangeTooHigh: archive.plans[0].days[0].items[0].targetRepsLow = 70
        case .setRepRangeTooHigh: archive.sessions[0].sets[0].targetRepsHigh = 61
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
        case .duplicatePlanID: archive.plans.append(archive.plans[0])
        case .duplicateDayID: archive.plans[0].days.append(archive.plans[0].days[0])
        case .duplicateSessionID: archive.sessions.append(archive.sessions[0])
        case .duplicateSetID: archive.sessions[0].sets.append(archive.sessions[0].sets[0])
        case .duplicateCustomExerciseID:
            let custom = BackupService.CustomExerciseDTO(id: "custom-1", name: "Press", category: "strength",
                                                         muscleRaw: [], equipment: [], trackingRaw: "weightReps")
            archive.customExercises = [custom, custom]
        }
    }
}
