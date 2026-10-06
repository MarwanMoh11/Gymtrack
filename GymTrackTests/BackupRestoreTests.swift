import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// `BackupService` export and restore against the real schema: the file is the
/// same bytes for the same store, restoring it and exporting again gives that
/// file back, and a restore that is refused leaves the phone as it was.
///
/// Decoding of older and malformed files is in `BackupDecodingTests`, the
/// file's order and provenance in `BackupExportFidelityTests`, and the sliced
/// export and restore in `BackupPacingTests`. That restore never asks Health
/// to delete anything is still checked by `scripts/test-backup-service.sh`:
/// `restore` takes no Health seam, so only a stubbed `HealthKitService` can
/// see that no call was made.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BackupRestoreTests {

    private let stamp = PersistenceFixtures.stamp()

    // MARK: - Export

    @Test func twoExportsOfOneStoreWithOneStampAreTheSameBytes() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try populate(context)

        let first = try BackupService.exportData(context: context, stamp: stamp)
        let second = try BackupService.exportData(context: context, stamp: stamp)

        #expect(first == second)
    }

    @Test func exportsMadeAtDifferentMomentsDifferOnlyInExportedAt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try populate(context)

        let earlier = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(at: TestClock.reference))
        let later = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(at: TestClock.reference.addingTimeInterval(86_400)))

        #expect(earlier != later)
        var first = try PersistenceFixtures.object(earlier)
        var second = try PersistenceFixtures.object(later)
        #expect(first["exportedAt"] as? String == "2026-03-11T12:00:00Z")
        #expect(second["exportedAt"] as? String == "2026-03-12T12:00:00Z")
        first["exportedAt"] = nil
        second["exportedAt"] = nil
        #expect(NSDictionary(dictionary: first).isEqual(to: second))
    }

    @Test func exportCarriesVersionTwoAndTheStampsZoneAndBuild() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()

        let stamped = try PersistenceFixtures.object(
            BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(version: "1.4.2", build: "57")))
        #expect(stamped["version"] as? Int == 2)
        #expect(stamped["timeZone"] as? String == "Africa/Cairo")
        #expect(stamped["appVersion"] as? String == "1.4.2")
        #expect(stamped["appBuild"] as? String == "57")

        // A bundle with neither writes no key, rather than an empty string.
        let bare = try PersistenceFixtures.object(
            BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(version: nil, build: nil)))
        #expect(!bare.keys.contains("appVersion"))
        #expect(!bare.keys.contains("appBuild"))
        #expect(bare["timeZone"] as? String == "Africa/Cairo")
    }

    @Test func fileOrderFollowsStartDateCreationDateAndOrderNotInsertOrder() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-02T18:00:00")
        // Everything inserted newest and last-numbered first.
        let lateSession = PersistenceFixtures.session("Late", startedAt: t.addingTimeInterval(2 * 86_400),
                                                      endedAt: t.addingTimeInterval(2 * 86_400 + 3600), in: context)
        let earlySession = PersistenceFixtures.session("Early", startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 1, completedAt: t), to: earlySession, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(PersistenceFixtures.squat, order: 1, setIndex: 0, completedAt: t), to: earlySession, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t), to: earlySession, in: context)
        _ = lateSession
        let newPlan = PersistenceFixtures.plan("Newer", createdAt: t.addingTimeInterval(60), active: false, in: context)
        let oldPlan = PersistenceFixtures.plan("Older", createdAt: t, active: true, in: context)
        _ = PersistenceFixtures.day("Second", order: 1, exercises: [], in: oldPlan, context: context)
        _ = PersistenceFixtures.day("First", order: 0, exercises: [], in: oldPlan, context: context)
        _ = newPlan

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: stamp))

        let sessions = try PersistenceFixtures.sessions(in: root)
        #expect(sessions.map { $0["title"] as? String } == ["Early", "Late"])
        let sets = try PersistenceFixtures.sets(in: root, sessionIndex: 0)
        #expect(sets.map { "\($0["exerciseOrder"] as? Int ?? -1).\($0["setIndex"] as? Int ?? -1)" } == ["0.0", "0.1", "1.0"])
        let plans = try #require(root["plans"] as? [[String: Any]])
        #expect(plans.map { $0["name"] as? String } == ["Older", "Newer"])
        let days = try #require(plans[0]["days"] as? [[String: Any]])
        #expect(days.map { $0["name"] as? String } == ["First", "Second"])
    }

    @Test func aWorkoutStillInProgressIsLeftOutOfTheFile() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        PersistenceFixtures.session("Done", startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        let open = PersistenceFixtures.session("Running", startedAt: t.addingTimeInterval(7200), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t.addingTimeInterval(7300)), to: open, in: context)

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: stamp))

        #expect(try PersistenceFixtures.sessions(in: root).map { $0["title"] as? String } == ["Done"])
    }

    @Test func exportingToAFileNamesItByTheLifterOwnDayAndHoldsTheSameBytes() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        // 23:30 UTC on the 10th is 01:30 on the 11th in Cairo.
        let late = PersistenceFixtures.stamp(at: TestClock.at("2026-03-10T23:30:00"))

        let url = try BackupService.export(context: context, stamp: late)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == "GymTrack-2026-03-11.json")
        #expect(try Data(contentsOf: url) == BackupService.exportData(context: context, stamp: late))
    }

    // MARK: - Round trips

    @Test func restoringAnExportAndExportingAgainGivesTheSameFileBack() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let source = try TestStore.context()
        let ids = try populate(source)
        let original = try BackupService.exportData(context: source, stamp: stamp)

        // A different phone: its settings differ until the file says otherwise.
        AppSettings.shared.userName = "Someone else"
        AppSettings.shared.defaultRestSeconds = 45
        let target = try TestStore.context()
        try BackupService.restore(data: original, context: target)

        #expect(AppSettings.shared.userName == "Test Lifter")
        #expect(AppSettings.shared.defaultRestSeconds == 90)
        #expect(try target.fetchCount(FetchDescriptor<Plan>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<PlanDay>()) == 3)
        #expect(try target.fetchCount(FetchDescriptor<PlanItem>()) == 3)
        #expect(try target.fetchCount(FetchDescriptor<WorkoutSession>()) == 2)
        #expect(try target.fetchCount(FetchDescriptor<SetLog>()) == 5)
        #expect(try target.fetchCount(FetchDescriptor<ExerciseNote>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<BodyMetric>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<BodyMeasurement>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<ExerciseLoadPreference>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<HiddenExerciseRecord>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<CustomExerciseRecord>()) == 1)

        let sessions = try target.fetch(FetchDescriptor<WorkoutSession>())
        let push = try #require(sessions.first { $0.id == ids.pushSession })
        #expect(push.title == "Push")
        #expect(push.notes == "Felt strong")
        #expect(push.noteTags == [.feltStrong])
        #expect(push.averageHeartRate == 118 && push.maxHeartRate == 171 && push.activeEnergyKcal == 240)
        #expect(push.heartRateSource == .watchWorkout && push.heartRateReadings == 600)
        #expect(push.healthWorkoutID == ids.healthWorkout)
        #expect(push.wasWatchDriven)
        #expect(push.planDayID == ids.pushDay)
        #expect(push.plannedSlots?.map(\.catalogID) == [PersistenceFixtures.bench.id, PersistenceFixtures.plank.id])
        #expect(push.exerciseNotes.first?.text == "Left shoulder pinched")
        #expect(push.exerciseNotes.first?.tags == [.pain])
        let drop = try #require(push.sets.first { $0.id == ids.dropSet })
        #expect(drop.isContinuation && drop.continuation == .drop)
        #expect(drop.weightKg == 80 && drop.reps == 6)
        let hard = try #require(push.sets.first { $0.id == ids.hardSet })
        #expect(hard.rpe == 9 && hard.averageHeartRate == 150 && hard.heartRateWindow == .measured)
        #expect(hard.loadNudgeOutcome == .taken && hard.loadNudgeToKg == 102.5)
        #expect(hard.detectedWindow != nil)
        let timed = try #require(push.sets.first { $0.catalogID == PersistenceFixtures.plank.id })
        #expect(timed.seconds == 60 && timed.tracking == .duration)

        let afterwards = try #require(sessions.first { $0.id == ids.afterwardsSession })
        #expect(afterwards.isLoggedAfterwards && !afterwards.isActive)
        #expect(afterwards.sets.first?.completedAt == nil && afterwards.sets.first?.isCompleted == true)

        let day = try #require(target.fetch(FetchDescriptor<PlanDay>()).first { $0.id == ids.pushDay })
        #expect(day.weekday == 2 && day.notes == "Bar path straight")
        let bench = try #require(day.orderedItems.first)
        #expect(bench.targetSets == 4 && bench.targetRepsLow == 5 && bench.targetRepsHigh == 8)
        #expect(bench.targetWeightKg == 80 && bench.restSeconds == 120 && bench.notes == "Pause the first rep")

        // The file is a function of the data, so the restored store writes it again.
        #expect(try BackupService.exportData(context: target, stamp: stamp) == original)
    }

    @Test func aPoundsLifterStoresKilogramsAndGetsPoundsBack() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        AppSettings.shared.weightUnit = .lb
        let source = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        let session = PersistenceFixtures.session(startedAt: t, endedAt: t.addingTimeInterval(3600), in: source)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, kg: 102.5, completedAt: t), to: session, in: source)
        source.insert(BodyMetric(date: t, weightKg: 82.5))

        let data = try BackupService.exportData(context: source, stamp: stamp)

        let root = try PersistenceFixtures.object(data)
        #expect((root["settings"] as? [String: Any])?["weightUnit"] as? String == "lb")
        // Pounds are display only: the file holds the kilograms that were stored.
        #expect(try PersistenceFixtures.sets(in: root, sessionIndex: 0).first?["weightKg"] as? Double == 102.5)
        #expect((root["bodyMetrics"] as? [[String: Any]])?.first?["weightKg"] as? Double == 82.5)

        AppSettings.shared.weightUnit = .kg
        let target = try TestStore.context()
        try BackupService.restore(data: data, context: target)

        #expect(AppSettings.shared.weightUnit == .lb)
        #expect(try target.fetch(FetchDescriptor<SetLog>()).first?.weightKg == 102.5)
        #expect(try target.fetch(FetchDescriptor<BodyMetric>()).first?.weightKg == 82.5)
    }

    @Test(arguments: [WeightUnit.kg, .lb])
    func everyFieldSurvivesARestoreIntoAFreshStoreAndOnlyTheStampIsWrittenAgain(_ unit: WeightUnit) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        AppSettings.shared.weightUnit = unit
        let source = try TestStore.context()
        try fillEveryField(source)
        let first = try BackupService.exportData(context: source, stamp: stamp)

        // The file has to hold what the round trip is meant to protect.
        let document = try PersistenceFixtures.object(first)
        let sessions = try PersistenceFixtures.sessions(in: document)
        let setKeys = Set(sessions.flatMap { ($0["sets"] as? [[String: Any]] ?? []).flatMap(\.keys) })
        for key in ["id", "startedAt", "completedAt", "detectedStartedAt", "detectedEndedAt", "rpe", "effort",
                    "averageHeartRate", "maxHeartRate", "heartRateWindow", "loadNudge", "continues",
                    "seconds", "reps", "targetRepsLow", "targetRepsHigh", "tracking"] {
            #expect(setKeys.contains(key), "The fixture never writes the set field \(key)")
        }
        let sessionKeys = Set(sessions.flatMap(\.keys))
        for key in ["planDayID", "averageHeartRate", "maxHeartRate", "activeEnergyKcal", "healthWorkoutID",
                    "wasWatchDriven", "heartRateSource", "energySource", "heartRateReadings", "noteTags",
                    "exerciseNotes", "notes", "endedAt", "loggedAfterwards", "plannedItems"] {
            #expect(sessionKeys.contains(key), "The fixture never writes the session field \(key)")
        }
        for key in ["bodyMetrics", "bodyMeasurements", "customExercises", "loadScales", "hiddenExercises",
                    "exerciseCatalog", "effectiveLoadScales", "effortScale", "timeZone", "appVersion", "appBuild"] {
            #expect(document[key] != nil, "The fixture never writes the top-level field \(key)")
        }

        // Another phone, at another moment, in another zone, on another build,
        // so a stamp copied through the restore can't pass for a fresh one.
        let fresh = try TestStore.context()
        try BackupService.restore(data: first, context: fresh)
        let later = PersistenceFixtures.stamp(at: TestClock.at("2027-01-15T08:00:00"), zone: "America/New_York",
                                              version: "9.9", build: "999")
        let second = try BackupService.exportData(context: fresh, stamp: later)
        let again = try PersistenceFixtures.object(second)

        let changed = Self.differences(document.filter { !Self.regenerated.contains($0.key) },
                                       again.filter { !Self.regenerated.contains($0.key) })
        #expect(changed.isEmpty, "\(changed.count) field(s) changed: \(changed.prefix(12).joined(separator: "; "))")
        // The comparison does see a change where there is one: the stamp's four keys.
        #expect(Self.differences(document, again).count == Self.regenerated.count)
        for key in Self.regenerated {
            #expect(document[key] != nil && again[key] != nil && (document[key] as? NSObject)?.isEqual(again[key]) == false,
                    "\(key) is written by each export, not carried through a restore")
        }

        // Absence stays absence: a set that carried nothing gains no key, not
        // a null, a zero or an empty string.
        let restoredSets = try PersistenceFixtures.sessions(in: again).flatMap { $0["sets"] as? [[String: Any]] ?? [] }
        let bare = try #require(restoredSets.first { $0["id"] as? String == PersistenceFixtures.uuid(0x103).uuidString })
        let optional: Set<String> = ["startedAt", "detectedStartedAt", "detectedEndedAt", "rpe", "effort",
                                     "averageHeartRate", "maxHeartRate", "heartRateWindow", "loadNudge",
                                     "continues", "isWarmup"]
        #expect(Set(bare.keys).isDisjoint(with: optional), "Gained \(Set(bare.keys).intersection(optional).sorted())")

        // A session logged afterwards goes out with no end, which would read as
        // a workout that took no time, and comes back closed rather than open.
        let afterwardsID = PersistenceFixtures.uuid(3).uuidString
        let afterwardsOut = try #require(sessions.first { $0["id"] as? String == afterwardsID })
        #expect(!afterwardsOut.keys.contains("endedAt") && afterwardsOut["loggedAfterwards"] as? Bool == true)
        #expect(sessions.allSatisfy { $0["id"] as? String == afterwardsID || !$0.keys.contains("loggedAfterwards") })
        let afterwardsIn = try #require(fresh.fetch(FetchDescriptor<WorkoutSession>()).first {
            $0.id == PersistenceFixtures.uuid(3)
        })
        #expect(afterwardsIn.isLoggedAfterwards && afterwardsIn.endedAt == afterwardsIn.startedAt)

        #expect(try BackupService.exportData(context: fresh, stamp: later) == second)
    }

    @Test func theUnitOnScreenChangesOnlyTheLabelAndTheDerivedRungs() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try fillPressDay(context)

        AppSettings.shared.weightUnit = .kg
        let kilos = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: stamp))
        AppSettings.shared.weightUnit = .lb
        let pounds = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: stamp))

        #expect((kilos["settings"] as? [String: Any])?["weightUnit"] as? String == "kg")
        #expect((pounds["settings"] as? [String: Any])?["weightUnit"] as? String == "lb")
        // Pounds are a label: every measured weight in the file is kilograms.
        #expect(try Self.setWeights(in: pounds) == [60, 62.5, 65])
        #expect(try Self.setWeights(in: kilos) == Self.setWeights(in: pounds))
        #expect((pounds["bodyMetrics"] as? [[String: Any]])?.compactMap { $0["weightKg"] as? Double } == [81.5])
        #expect(NSDictionary(dictionary: Self.measured(kilos)).isEqual(to: Self.measured(pounds)),
                "Nothing outside the settings label and the derived rungs may follow the unit")

        // The derived rung is the one section that follows the unit, and it
        // names the unit it is in, or 5 would read as kilograms.
        let benchInKilos = try #require(Self.rung(of: PersistenceFixtures.bench.id, in: kilos))
        #expect(benchInKilos["unit"] as? String == "kg" && benchInKilos["increment"] as? Double == 2.5)
        let benchInPounds = try #require(Self.rung(of: PersistenceFixtures.bench.id, in: pounds))
        #expect(benchInPounds["unit"] as? String == "lb" && benchInPounds["increment"] as? Double == 5)
        #expect(benchInPounds["source"] as? String == "derived")
    }

    @Test(arguments: [WeightUnit.lb, .kg])
    func restoreBringsTheUnitBackAndNeverScalesAWeight(_ writtenIn: WeightUnit) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let restoredOver: WeightUnit = writtenIn == .lb ? .kg : .lb
        let context = try TestStore.context()
        try fillPressDay(context)
        AppSettings.shared.weightUnit = writtenIn
        let file = try BackupService.exportData(context: context, stamp: stamp)
        AppSettings.shared.weightUnit = restoredOver
        let fresh = try TestStore.context()

        try BackupService.restore(data: file, context: fresh)

        #expect(AppSettings.shared.weightUnit == writtenIn)
        #expect(try fresh.fetch(FetchDescriptor<SetLog>()).map(\.weightKg).sorted() == [60, 62.5, 65])
        #expect(try fresh.fetch(FetchDescriptor<BodyMetric>()).map(\.weightKg) == [81.5])
    }

    @Test func aSessionKeepsItsInstantWhateverZoneTheFileWasWrittenIn() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let instant = TestClock.at("2026-03-10T22:30:00")
        let plan = PersistenceFixtures.plan("Week", createdAt: instant, active: true, in: context)
        PersistenceFixtures.day("Tuesday", order: 0, weekday: 3, exercises: [PersistenceFixtures.bench], in: plan, context: context)
        PersistenceFixtures.session("Late", startedAt: instant, endedAt: instant.addingTimeInterval(3600), in: context)

        let cairo = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(zone: "Africa/Cairo"))
        let kiritimati = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(zone: "Pacific/Kiritimati"))

        // Dates are UTC in the file whoever wrote it; only the zone key differs.
        #expect(try PersistenceFixtures.sessions(in: PersistenceFixtures.object(cairo)).first?["startedAt"] as? String == "2026-03-10T22:30:00Z")
        var first = try PersistenceFixtures.object(cairo)
        var second = try PersistenceFixtures.object(kiritimati)
        #expect(first["timeZone"] as? String == "Africa/Cairo")
        #expect(second["timeZone"] as? String == "Pacific/Kiritimati")
        first["timeZone"] = nil
        second["timeZone"] = nil
        #expect(NSDictionary(dictionary: first).isEqual(to: second))

        let target = try TestStore.context()
        try BackupService.restore(data: kiritimati, context: target)
        let restored = try #require(target.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(restored.startedAt == instant)
        // The same instant is Tuesday night in UTC and already Wednesday in Cairo, which is
        // why the weekday on a plan day is read back as the lifter's, never converted.
        #expect(TestClock.calendar.component(.weekday, from: restored.startedAt) == 3)
        #expect(TestClock.calendar(in: "Africa/Cairo").component(.weekday, from: restored.startedAt) == 4)
        #expect(try target.fetch(FetchDescriptor<PlanDay>()).first?.weekday == 3)
    }

    @Test func restoreKeepsTheHealthLinkAlreadyOnThisPhone() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        let session = PersistenceFixtures.session(startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t), to: session, in: context)
        let file = try BackupService.exportData(context: context, stamp: stamp)
        #expect(!(try PersistenceFixtures.sessions(in: PersistenceFixtures.object(file))[0]).keys.contains("healthWorkoutID"))
        // The workout was saved to Health after the file was taken.
        let linked = UUID(uuidString: "5A3D1C20-0000-4000-8000-000000000042")!
        session.healthWorkoutID = linked
        try context.save()

        try BackupService.restore(data: file, context: context)

        let restored = try #require(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(restored.id == session.id)
        #expect(restored.healthWorkoutID == linked)
    }

    @Test(arguments: FileLink.allCases)
    func restoreKeepsThisPhonesHealthLinkWhateverTheFileSays(_ link: FileLink) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let linked = try linkedStore(context)
        var file = try BackupService.decodedArchive(from: BackupService.exportData(context: context, stamp: stamp))
        #expect(file.version == 2)
        #expect(file.sessions.first?.healthWorkoutID == linked.workout)
        file.sessions[0].title = "Replacement"
        file.settings.userName = "After restore"
        switch link {
        case .same: break
        // Every file written before linkage looks like this.
        case .absent: file.sessions[0].healthWorkoutID = nil
        // Taken between the phone's fallback save and the watch's own, so it
        // names a workout this phone has since replaced.
        case .other: file.sessions[0].healthWorkoutID = UUID()
        }
        let data = try BackupService.encoded(file)
        if link == .absent {
            // No key at all, not a null.
            #expect(!String(decoding: data, as: UTF8.self).contains("healthWorkoutID"))
            #expect(try BackupService.decodedArchive(from: data).sessions[0].healthWorkoutID == nil)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try BackupService.restore(from: url, context: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.map(\.title) == ["Replacement"])
        #expect(sessions.first?.healthWorkoutID == linked.workout)
        let plans = try context.fetch(FetchDescriptor<Plan>())
        #expect(plans.count == 1 && plans.first?.orderedDays.first?.orderedItems.count == 1)
        #expect(AppSettings.shared.userName == "After restore")
    }

    @Test func aSessionTheFileDoesNotHoldLeavesAndTheOneItHoldsKeepsItsLink() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let linked = try linkedStore(context)
        var file = try BackupService.decodedArchive(from: BackupService.exportData(context: context, stamp: stamp))
        file.sessions[0].healthWorkoutID = nil
        let later = PersistenceFixtures.session("Later", startedAt: linked.start.addingTimeInterval(86_400),
                                                endedAt: linked.start.addingTimeInterval(86_460), in: context)
        later.healthWorkoutID = PersistenceFixtures.uuid(0xB2)
        try context.save()

        try BackupService.restore(data: BackupService.encoded(file), context: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.map(\.title) == ["Original"])
        #expect(sessions.first?.healthWorkoutID == linked.workout)
    }

    // MARK: - Restore replaces, refuses and rolls back

    @Test func restoreReplacesWhatIsOnThePhoneInsteadOfMergingIt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        let oldPlan = PersistenceFixtures.plan("Old plan", createdAt: t, active: true, in: context)
        PersistenceFixtures.day("Old day", order: 0, weekday: 2, exercises: [PersistenceFixtures.squat], in: oldPlan, context: context)
        let oldSession = PersistenceFixtures.session("Old session", startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        context.insert(BodyMetric(date: t, weightKg: 90))
        context.insert(HiddenExerciseRecord(catalogID: "deadlift"))
        try context.save()
        let donor = try donorBackup()

        try BackupService.restore(data: donor.data, context: context)

        let plans = try context.fetch(FetchDescriptor<Plan>())
        #expect(plans.map(\.name) == ["Donor plan"])
        #expect(plans.first?.id != oldPlan.id)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.map(\.title) == ["Donor session"])
        #expect(sessions.first?.id != oldSession.id)
        #expect(try context.fetchCount(FetchDescriptor<PlanDay>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlanItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMetric>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HiddenExerciseRecord>()) == 0)
        #expect(!ExerciseCatalog.shared.isHidden("deadlift"))
    }

    @Test func restoreRefusesWhileAWorkoutIsOpenAndTouchesNothing() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        PersistenceFixtures.plan("Keep", createdAt: t, active: true, in: context)
        let open = PersistenceFixtures.session("Running", startedAt: t, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t), to: open, in: context)
        try context.save()
        AppSettings.shared.userName = "Still me"
        let donor = try donorBackup()

        do {
            try BackupService.restore(data: donor.data, context: context)
            Issue.record("A restore over a running workout was accepted")
        } catch let error as BackupService.RestoreError {
            guard case .workoutInProgress = error else {
                Issue.record("Wrong refusal: \(error)")
                return
            }
        }

        #expect(try context.fetch(FetchDescriptor<Plan>()).map(\.name) == ["Keep"])
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(open.isActive && open.sets.count == 1)
        #expect(AppSettings.shared.userName == "Still me")
    }

    @Test func aRestoreThatFailsBeforeItsSaveLeavesSessionsPlansAndSettingsAsTheyWere() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try expectRollback(in: context, withSlot: false)
    }

    @Test(.disabled("""
        Traps inside ModelContext.rollback() (Unexpected backing data for snapshot creation: \
        _FullFutureBackingData<PlanItem>) once a restore has wiped and reinserted a plan slot, \
        which kills the test process before withKnownIssue can catch it. \
        scripts/test-backup-service.sh still checks this case on macOS.
        """))
    func aRestoreThatFailsBeforeItsSaveRollsBackAPlansSlotsToo() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try expectRollback(in: context, withSlot: true)
    }

    // MARK: - Erase

    @Test func eraseRemovesEverythingAndNeverTouchesHealthUnlessAsked() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try populate(context)
        try context.save()

        let result = try await BackupService.wipe(context: context)

        #expect(result == nil)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanDay>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseNote>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMetric>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMeasurement>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLoadPreference>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HiddenExerciseRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CustomExerciseRecord>()) == 0)
    }

    @Test func eraseRefusesWhileAWorkoutIsOpen() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        PersistenceFixtures.plan("Keep", createdAt: t, active: true, in: context)
        PersistenceFixtures.session("Running", startedAt: t, in: context)
        try context.save()

        do {
            try await BackupService.wipe(context: context)
            Issue.record("An erase over a running workout was accepted")
        } catch is BackupService.WipeError {
        }

        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    @Test func eraseHandsHealthEveryLinkedWorkoutOnceInOneSortedBatch() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let workouts = try fillLinkedSessions(context)
        var calls: [[UUID]] = []

        let result = try await BackupService.wipe(context: context, removingHealthWorkouts: true,
                                                  deletingHealthWorkouts: { ids in
            calls.append(ids)
            return []
        })

        // One call, not a round trip per session.
        #expect(calls.count == 1)
        let received = calls.first ?? []
        #expect(received.count == workouts.count && Set(received) == workouts)
        #expect(received == received.sorted { $0.uuidString < $1.uuidString })
        #expect(result?.isComplete == true)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 0)
    }

    @Test func eraseAsksHealthNothingUnlessTheLifterChoseIt() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try fillLinkedSessions(context)

        let result = try await BackupService.wipe(
            context: context,
            deletingHealthWorkout: { _ in
                Issue.record("Health was asked about one workout without being chosen")
                return true
            },
            deletingHealthWorkouts: { _ in
                Issue.record("Health was asked about a batch without being chosen")
                return []
            })

        // Nil rather than an empty result, so a cleanup that never ran can't
        // read as one that succeeded.
        #expect(result == nil)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
    }

    @Test func theEraseDialogCountsLinkedWorkoutsAndAPlainEraseReportsNoCleanup() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try linkedStore(context)
        #expect(BackupService.linkedHealthWorkoutCount(context: context) == 1)

        let result = try await BackupService.wipe(context: context)

        #expect(result == nil)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(BackupService.linkedHealthWorkoutCount(context: context) == 0)
    }

    @Test func aWorkoutHealthKeptIsReportedOverALocalEraseThatStays() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let batched = try TestStore.context()
        _ = try fillLinkedSessions(batched)

        let partial = try await BackupService.wipe(context: batched, removingHealthWorkouts: true,
                                                   deletingHealthWorkouts: { ids in [ids[0]] })

        #expect(partial?.failedIDs.count == 1)
        #expect(partial?.isComplete == false)
        #expect(try batched.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)

        // The same through the per-workout path some callers still use.
        let single = try TestStore.context()
        let linked = try linkedStore(single)

        let refused = try await BackupService.wipe(context: single, removingHealthWorkouts: true,
                                                   deletingHealthWorkout: { _ in false })

        #expect(refused?.failedIDs == [linked.workout])
        #expect(try single.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
    }

    @Test(.enabled("Needs a host without Health write access, which the unit-test host is", {
        await MainActor.run { !HealthKitService.shared.canWriteWorkouts }
    }))
    func theDefaultEraseHandsTheHealthServiceEveryLinkedWorkoutOnce() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let linked = try linkedStore(context)
        let second = PersistenceFixtures.session("Second", startedAt: linked.start.addingTimeInterval(172_800),
                                                 endedAt: linked.start.addingTimeInterval(172_860), in: context)
        second.healthWorkoutID = PersistenceFixtures.uuid(0xB2)
        try context.save()
        #expect(BackupService.linkedHealthWorkoutCount(context: context) == 2)

        let result = try await BackupService.wipe(context: context, removingHealthWorkouts: true)

        // Without write access the real service removes nothing and hands back
        // every ID it was given, so what it reports is what it was asked: both
        // workouts, once each, in the batch's order.
        let asked = [linked.workout, PersistenceFixtures.uuid(0xB2)].sorted { $0.uuidString < $1.uuidString }
        #expect(result?.failedIDs == asked)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
    }

    // MARK: - Fixtures

    private struct Populated {
        var pushDay: UUID
        var pushSession: UUID
        var afterwardsSession: UUID
        var dropSet: UUID
        var hardSet: UUID
        var healthWorkout: UUID
    }

    /// A store using every table and most of what a set can carry.
    private func populate(_ context: ModelContext) throws -> Populated {
        let bench = PersistenceFixtures.bench, plank = PersistenceFixtures.plank
        let plan = PersistenceFixtures.plan("Push Pull", createdAt: TestClock.at("2026-02-20T09:00:00"), active: true, in: context)
        plan.summary = "Two days a week"
        let push = PersistenceFixtures.day("Push", order: 0, weekday: 2, exercises: [bench, plank], in: plan, context: context)
        push.notes = "Bar path straight"
        let slot = try #require(push.orderedItems.first)
        slot.targetSets = 4
        slot.targetRepsLow = 5
        slot.targetRepsHigh = 8
        slot.targetWeightKg = 80
        slot.restSeconds = 120
        slot.notes = "Pause the first rep"
        try #require(push.orderedItems.last).targetSeconds = 60
        PersistenceFixtures.day("Rest", order: 1, weekday: 3, isRest: true, exercises: [], in: plan, context: context)
        PersistenceFixtures.day("Pull", order: 2, exercises: [PersistenceFixtures.pullUp], in: plan, context: context)

        let t = TestClock.at("2026-03-02T18:00:00")
        let health = UUID(uuidString: "5A3D1C20-0000-4000-8000-0000000000A1")!
        let session = PersistenceFixtures.session("Push", startedAt: t, endedAt: t.addingTimeInterval(3600),
                                                  planName: "Push Pull", planDayID: push.id, in: context)
        session.recordPlan(of: push)
        session.notes = "Felt strong"
        session.noteTagsRaw = [NoteTag.feltStrong.rawValue]
        session.averageHeartRate = 118
        session.maxHeartRate = 171
        session.activeEnergyKcal = 240
        session.heartRateSourceRaw = VitalsSource.watchWorkout.rawValue
        session.energySourceRaw = VitalsSource.watchWorkout.rawValue
        session.heartRateReadings = 600
        session.wasWatchDriven = true
        session.healthWorkoutID = health

        let solid = PersistenceFixtures.set(setIndex: 0, kg: 100, reps: 5, completedAt: t.addingTimeInterval(120))
        solid.rpe = SetFeel.solid.rawValue
        solid.startedAt = t.addingTimeInterval(90)
        let hard = PersistenceFixtures.decoratedSet(at: t.addingTimeInterval(400), setIndex: 1)
        let drop = PersistenceFixtures.set(setIndex: 2, kg: 80, reps: 6, completedAt: t.addingTimeInterval(560))
        drop.continuesPreviousSet = true
        let hold = SetLog(catalogID: plank.id, exerciseName: plank.name, exerciseOrder: 1, setIndex: 0,
                          seconds: 60, tracking: .duration)
        hold.isCompleted = true
        hold.completedAt = t.addingTimeInterval(900)
        for set in [solid, hard, drop, hold] { PersistenceFixtures.add(set, to: session, in: context) }
        let note = ExerciseNote(catalogID: bench.id, exerciseName: bench.name)
        note.text = "Left shoulder pinched"
        note.tags = [.pain]
        note.session = session
        context.insert(note)

        let later = TestClock.at("2026-03-04T12:00:00")
        let afterwards = PersistenceFixtures.session("Pull", startedAt: later, endedAt: later, in: context)
        afterwards.isLoggedAfterwards = true
        let pulls = PersistenceFixtures.set(PersistenceFixtures.pullUp, setIndex: 0, kg: 0, reps: 8)
        pulls.isCompleted = true
        PersistenceFixtures.add(pulls, to: afterwards, in: context)

        context.insert(BodyMetric(date: TestClock.at("2026-03-05T07:30:00"), weightKg: 82.5))
        let tape = BodyMeasurement(date: TestClock.at("2026-03-05T07:35:00"))
        tape.set(38.5, for: .arm)
        tape.set(81, for: .waist)
        context.insert(tape)
        context.insert(ExerciseLoadPreference(catalogID: bench.id, scale: LoadScale(unit: .kg, increment: 1.25)))
        context.insert(HiddenExerciseRecord(catalogID: "deadlift"))
        context.insert(CustomExerciseRecord(name: "Landmine Press", muscles: [], equipment: ["Barbell"], tracking: .weightReps))
        try context.save()
        return Populated(pushDay: push.id, pushSession: session.id, afterwardsSession: afterwards.id,
                         dropSet: drop.id, hardSet: hard.id, healthWorkout: health)
    }

    /// A backup written by some other phone, with nothing in common with the
    /// store a test restores it into.
    private func donorBackup() throws -> (data: Data, planID: UUID) {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let donor = try TestStore.context()
        let t = TestClock.at("2026-02-01T18:00:00")
        let plan = PersistenceFixtures.plan("Donor plan", createdAt: t, active: true, in: donor)
        PersistenceFixtures.day("Donor day", order: 0, weekday: 4, exercises: [], in: plan, context: donor)
        PersistenceFixtures.session("Donor session", startedAt: t, endedAt: t.addingTimeInterval(1800), in: donor)
        return (try BackupService.exportData(context: donor, stamp: PersistenceFixtures.stamp()), plan.id)
    }

    /// A store in which every optional thing a set or session can carry is
    /// present on at least one row and absent on another, so a restore that
    /// invents a value for a missing key is caught as well as one that drops one.
    private func fillEveryField(_ context: ModelContext) throws {
        let base = TestClock.at("2026-09-21T14:13:20")
        let uuid = PersistenceFixtures.uuid
        let bench = PersistenceFixtures.bench, plank = PersistenceFixtures.plank, pullUp = PersistenceFixtures.pullUp
        let plan = Plan(name: "Push Pull", summary: "Two days", isActive: true)
        plan.createdAt = base
        context.insert(plan)
        let day = PlanDay(name: "Push", order: 0, weekday: 2, notes: "Arrive warm")
        day.plan = plan
        context.insert(day)
        let rest = PlanDay(name: "Rest", order: 1, weekday: 3, isRest: true)
        rest.plan = plan
        context.insert(rest)
        let slots: [(PersistenceFixtures.Exercise, TrackingMode)] = [
            (bench, .weightReps), (plank, .duration), (pullUp, .bodyweightReps),
        ]
        for (position, (exercise, tracking)) in slots.enumerated() {
            let item = PlanItem(catalogID: exercise.id, name: exercise.name, order: position, targetSets: 3,
                                targetRepsLow: tracking == .duration ? 0 : 6,
                                targetRepsHigh: tracking == .duration ? 0 : 10,
                                targetWeightKg: tracking == .weightReps ? 62.5 : 0,
                                targetSeconds: 60, restSeconds: position == 0 ? 150 : nil)
            item.notes = position == 0 ? "Pause on the chest" : ""
            item.day = day
            context.insert(item)
        }

        // A finished session with everything present.
        let full = WorkoutSession(title: "Push", planDayID: day.id, planName: plan.name,
                                  startedAt: base.addingTimeInterval(1_000))
        full.id = uuid(1)
        full.endedAt = full.startedAt.addingTimeInterval(3_600)
        full.recordPlan(of: day)
        full.notes = "Good day"
        full.noteTagsRaw = NoteTag.allCases.prefix(2).map(\.rawValue)
        full.averageHeartRate = 121
        full.maxHeartRate = 168
        full.activeEnergyKcal = 310
        full.healthWorkoutID = uuid(0xEE)
        full.wasWatchDriven = true
        full.heartRateSourceRaw = VitalsSource.watchWorkout.rawValue
        full.energySourceRaw = VitalsSource.watchWorkout.rawValue
        full.heartRateReadings = 412
        context.insert(full)

        func set(_ n: Int, _ exercise: PersistenceFixtures.Exercise, order: Int, index: Int, kg: Double, reps: Int,
                 seconds: Int = 0, tracking: TrackingMode, in session: WorkoutSession,
                 loggedAfter offset: TimeInterval?) -> SetLog {
            let row = SetLog(catalogID: exercise.id, exerciseName: exercise.name, exerciseOrder: order, setIndex: index,
                             weightKg: kg, reps: reps, seconds: seconds, targetRepsLow: 6, targetRepsHigh: 10,
                             tracking: tracking)
            row.id = uuid(n)
            if let offset {
                row.isCompleted = true
                row.completedAt = session.startedAt.addingTimeInterval(offset)
            }
            PersistenceFixtures.add(row, to: session, in: context)
            return row
        }

        let top = set(0x101, bench, order: 0, index: 0, kg: 62.5, reps: 8, tracking: .weightReps, in: full,
                      loggedAfter: 120)
        top.startedAt = full.startedAt.addingTimeInterval(80)
        top.rpe = SetFeel.hard.rawValue
        top.apply(SetHeartRate(average: 131, peak: 149, source: .measured))
        top.recordLoadNudge(.taken, toKg: 65)

        let drop = set(0x102, bench, order: 0, index: 1, kg: 60, reps: 6, tracking: .weightReps, in: full,
                       loggedAfter: 300)
        drop.continuesPreviousSet = true
        drop.recordDetectedWindow(DetectedSetWindow(start: full.startedAt.addingTimeInterval(265),
                                                    end: full.startedAt.addingTimeInterval(297)))
        drop.apply(SetHeartRate(average: 128, peak: 140, source: .detected))
        drop.rpe = SetFeel.solid.rawValue
        drop.recordLoadNudge(.declined, toKg: 62.5)

        // Nothing but what was lifted: no other key may appear for it.
        _ = set(0x103, bench, order: 0, index: 2, kg: 60, reps: 5, tracking: .weightReps, in: full, loggedAfter: 480)
        _ = set(0x104, plank, order: 1, index: 0, kg: 0, reps: 0, seconds: 75, tracking: .duration, in: full,
                loggedAfter: 700)
        _ = set(0x105, pullUp, order: 2, index: 0, kg: 0, reps: 9, tracking: .bodyweightReps, in: full,
                loggedAfter: 900)
        // Planned and never done.
        _ = set(0x106, pullUp, order: 2, index: 1, kg: 0, reps: 9, tracking: .bodyweightReps, in: full,
                loggedAfter: nil)

        for (exercise, text, tag) in [(bench, "Left shoulder pinched", NoteTag.allCases[0]),
                                      (plank, "", NoteTag.allCases[1])] {
            let note = ExerciseNote(catalogID: exercise.id, exerciseName: exercise.name)
            note.text = text
            note.tagsRaw = [tag.rawValue]
            note.session = full
            context.insert(note)
        }

        // Nothing recorded beyond its sets.
        let bare = WorkoutSession(title: "Quick", startedAt: base.addingTimeInterval(9_000))
        bare.id = uuid(2)
        bare.endedAt = bare.startedAt.addingTimeInterval(1_800)
        context.insert(bare)
        _ = set(0x201, PersistenceFixtures.Exercise(id: "dumbbell-curl", name: "Dumbbell Curl"), order: 0, index: 0,
                kg: 14, reps: 12, tracking: .weightReps, in: bare, loggedAfter: 60)

        // Written down afterwards: closed at its own start, sets done but never timed.
        let afterwards = WorkoutSession(title: "Push", planName: plan.name, startedAt: base.addingTimeInterval(20_000))
        afterwards.id = uuid(3)
        afterwards.endedAt = afterwards.startedAt
        afterwards.isLoggedAfterwards = true
        context.insert(afterwards)
        let recalled = SetLog(catalogID: bench.id, exerciseName: bench.name, exerciseOrder: 0, setIndex: 0,
                              weightKg: 62.5, reps: 8, tracking: .weightReps)
        recalled.id = uuid(0x301)
        recalled.isCompleted = true
        PersistenceFixtures.add(recalled, to: afterwards, in: context)

        for (offset, kg) in [(100.0, 80.2), (200, 79.9)] {
            context.insert(BodyMetric(date: base.addingTimeInterval(offset), weightKg: kg))
        }
        for (offset, id, parts) in [(150.0, 0x401, [BodyMeasurement.Part.arm: 36.5, .waist: 84]),
                                    (250, 0x402, [.chest: 101, .shoulders: 118, .thigh: 58.5])] {
            let check = BodyMeasurement(date: base.addingTimeInterval(offset))
            check.id = uuid(id)
            for (part, cm) in parts { check.set(cm, for: part) }
            context.insert(check)
        }
        let custom = CustomExerciseRecord(name: "Sled Drag", muscles: [], equipment: ["Sled"], tracking: .weightReps)
        custom.id = "custom-sled-drag"
        context.insert(custom)
        context.insert(HiddenExerciseRecord(catalogID: "cable-crossover"))
        context.insert(ExerciseLoadPreference(catalogID: bench.id, scale: LoadScale(unit: .lb, increment: 5)))
        context.insert(ExerciseLoadPreference(catalogID: "dumbbell-curl", scale: LoadScale(unit: .kg, increment: 1)))
        try context.save()
    }

    /// The keys each export writes from its own stamp, and so the only ones a
    /// round trip may change.
    private static let regenerated: Set<String> = ["exportedAt", "timeZone", "appVersion", "appBuild"]

    /// Every path at which two documents differ, so a failure names the field
    /// rather than saying two files are unequal.
    private static func differences(_ lhs: Any?, _ rhs: Any?, path: String = "$") -> [String] {
        switch (lhs, rhs) {
        case let (l as [String: Any], r as [String: Any]):
            return Set(l.keys).union(r.keys).sorted().flatMap { differences(l[$0], r[$0], path: "\(path).\($0)") }
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return ["\(path): \(l.count) elements became \(r.count)"] }
            return l.indices.flatMap { differences(l[$0], r[$0], path: "\(path)[\($0)]") }
        case (nil, nil):
            return []
        case (nil, let after?):
            return ["\(path): absent before, \(after) after"]
        case (let before?, nil):
            return ["\(path): \(before) before, absent after"]
        case let (before?, after?):
            return (before as? NSObject)?.isEqual(after) == true ? [] : ["\(path): \(before) became \(after)"]
        }
    }

    /// One finished session of three bench sets and a weigh-in, at loads a
    /// stray conversion can't land on: 62.5 kg is 137.79 lb.
    private func fillPressDay(_ context: ModelContext) throws {
        let t = TestClock.at("2026-09-21T14:13:20")
        let session = PersistenceFixtures.session(startedAt: t, endedAt: t.addingTimeInterval(3_000), in: context)
        for (index, load) in [60.0, 62.5, 65.0].enumerated() {
            let set = SetLog(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name,
                             exerciseOrder: 0, setIndex: index, weightKg: load, reps: 8,
                             targetRepsLow: 8, targetRepsHigh: 12, tracking: .weightReps)
            set.isCompleted = true
            PersistenceFixtures.add(set, to: session, in: context)
        }
        context.insert(BodyMetric(date: t.addingTimeInterval(-100_000), weightKg: 81.5))
        try context.save()
    }

    private static func setWeights(in document: [String: Any]) throws -> [Double] {
        try PersistenceFixtures.sessions(in: document)
            .flatMap { $0["sets"] as? [[String: Any]] ?? [] }
            .compactMap { $0["weightKg"] as? Double }
            .sorted()
    }

    /// Everything but the settings label and the derived rungs, the two places
    /// the unit is allowed to show.
    private static func measured(_ document: [String: Any]) -> [String: Any] {
        document.filter { $0.key != "settings" && $0.key != "effectiveLoadScales" }
    }

    private static func rung(of catalogID: String, in document: [String: Any]) -> [String: Any]? {
        (document["effectiveLoadScales"] as? [[String: Any]])?.first { $0["catalogID"] as? String == catalogID }
    }

    /// What a file can say about a session's Health workout, against the one
    /// this phone has.
    enum FileLink: CaseIterable, Sendable {
        case same, absent, other
    }

    /// One finished session linked to a Health workout, and a plan whose day
    /// holds one slot, with the name a restore would overwrite.
    @discardableResult
    private func linkedStore(_ context: ModelContext, withSlot: Bool = true) throws -> (start: Date, workout: UUID) {
        let start = TestClock.at("2023-11-14T22:13:20")
        let workout = PersistenceFixtures.uuid(0xB1)
        let original = PersistenceFixtures.session("Original", startedAt: start, endedAt: start.addingTimeInterval(60),
                                                   in: context)
        original.healthWorkoutID = workout
        let plan = PersistenceFixtures.plan("Original plan", createdAt: start, active: true, in: context)
        PersistenceFixtures.day("Day one", order: 0, exercises: withSlot ? [PersistenceFixtures.squat] : [],
                                in: plan, context: context)
        try context.save()
        AppSettings.shared.userName = "Before restore"
        return (start, workout)
    }

    /// Restores a changed copy of `linkedStore` with a `beforeCommit` that
    /// throws, and expects every part of the store and the settings unchanged.
    private func expectRollback(in context: ModelContext, withSlot: Bool) throws {
        try linkedStore(context, withSlot: withSlot)
        var file = try BackupService.decodedArchive(from: BackupService.exportData(context: context, stamp: stamp))
        file.sessions[0].title = "Replacement"
        file.settings.userName = "After restore"
        struct InjectedFailure: Error {}

        do {
            try BackupService.restore(data: BackupService.encoded(file), context: context,
                                      beforeCommit: { throw InjectedFailure() })
            Issue.record("A restore whose beforeCommit threw went through")
        } catch is InjectedFailure {
        }

        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.title) == ["Original"])
        let plans = try context.fetch(FetchDescriptor<Plan>())
        #expect(plans.count == 1 && plans.first?.orderedDays.count == 1)
        #expect(plans.first?.orderedDays.first?.orderedItems.count == (withSlot ? 1 : 0))
        #expect(AppSettings.shared.userName == "Before restore")
    }

    /// Thirty finished sessions of three sets, each linked to a Health
    /// workout except that the last two share one. Returns the workouts.
    private func fillLinkedSessions(_ context: ModelContext) throws -> Set<UUID> {
        let base = TestClock.at("2026-09-21T14:13:20")
        let count = 30
        var workouts: Set<UUID> = []
        for n in 0..<count {
            let started = base.addingTimeInterval(Double(n) * 86_400)
            let session = PersistenceFixtures.session("Session \(n)", startedAt: started,
                                                      endedAt: started.addingTimeInterval(3_000), in: context)
            let workout = PersistenceFixtures.uuid(0xB000 + min(n, count - 2))
            session.healthWorkoutID = workout
            workouts.insert(workout)
            for index in 0..<3 {
                PersistenceFixtures.add(PersistenceFixtures.set(setIndex: index, completedAt: started.addingTimeInterval(Double(60 * (index + 1)))),
                                        to: session, in: context)
            }
        }
        try context.save()
        return workouts
    }
}
