import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What the export promises a reader that has to cite sets, take "the row
/// above" literally, hash the file, place a session in the lifter's own week
/// and propose loads the equipment can be set to: set IDs, a defined order, the
/// zone and build it was written in, and a rung for every exercise rather than
/// only the corrected ones.
///
/// Round trips and restore's refusals are in `BackupRestoreTests` and
/// `BackupDecodingTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BackupExportFidelityTests {

    /// 22:30 UTC on the 22nd, which is already the 23rd in Cairo.
    private let stamp = PersistenceFixtures.stamp(at: TestClock.at("2026-09-22T22:30:00"), version: "1.4", build: "27")
    private let base = TestClock.at("2026-09-21T14:13:20")

    // MARK: - The same bytes, under the lifter's own date

    @Test func twoExportsOfOneStoreAreTheSameBytesInAFileNamedForTheLiftersDay() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try fill(context)

        let first = try BackupService.exportData(context: context, stamp: stamp)
        let second = try BackupService.exportData(context: context, stamp: stamp)
        let file = try BackupService.export(context: context, stamp: stamp)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(first == second)
        #expect(try Data(contentsOf: file) == first)
        #expect(file.lastPathComponent == "GymTrack-2026-09-23.json")
        #expect(try BackupService.decodedArchive(from: first).version == 2)
    }

    @Test func theFileSaysWhereWhenAndByWhichBuildItWasWritten() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try fill(context)

        let archive = try BackupService.decodedArchive(from: BackupService.exportData(context: context, stamp: stamp))

        #expect(archive.timeZone == "Africa/Cairo")
        #expect(archive.appVersion == "1.4" && archive.appBuild == "27")
        #expect(archive.exportedAt == stamp.exportedAt)
        // A build with no version writes no key, not an empty one.
        let bare = PersistenceFixtures.stamp(at: stamp.exportedAt, version: nil, build: nil)
        let bareText = String(decoding: try BackupService.exportData(context: context, stamp: bare), as: UTF8.self)
        #expect(!bareText.contains("\"appVersion\"") && !bareText.contains("\"appBuild\""))
        #expect(BackupService.ExportStamp.current().timeZone == .current)
    }

    // MARK: - Order

    @Test func everyListIsInADefinedOrderWhateverTheInsertOrder() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try fill(context)
        let uuid = PersistenceFixtures.uuid

        let archive = try BackupService.decodedArchive(from: BackupService.exportData(context: context, stamp: stamp))

        #expect(archive.plans.map(\.name) == ["A", "B"], "Plans by creation")
        #expect(archive.plans.allSatisfy { $0.days.map(\.order) == [0, 1, 2] }, "Days by order")
        #expect(archive.plans[0].days.allSatisfy { $0.items.map(\.order) == [0, 1, 2] }, "Slots by order")
        // Two sessions share a start, so their IDs settle it.
        #expect(archive.sessions.map(\.id) == [uuid(1), uuid(0xA1), uuid(0xA2), uuid(3)])
        for session in archive.sessions {
            let positions = session.sets.map { [$0.exerciseOrder, $0.setIndex] }
            #expect(positions == [[0, 0], [0, 1], [0, 2], [1, 0], [2, 0], [3, 0]], "Sets as the app groups them")
            try #require(session.sets.count == 6)
            // `continues` means the row above, so the row above has to be the set it continues.
            #expect(session.sets[1].continues != nil && session.sets[0].weightKg > session.sets[1].weightKg)
            #expect(session.exerciseNotes?.map(\.catalogID) == ["barbell-bench-press", "dumbbell-curl"],
                    "Notes in the order the exercises were trained")
        }
        let weighIns = (archive.bodyMetrics ?? []).map(\.date)
        #expect(weighIns.count == 3 && weighIns == weighIns.sorted())
        #expect(archive.bodyMeasurements?.map(\.id) == [uuid(0x701), uuid(0x702), uuid(0x703)])
        #expect(archive.customExercises.map(\.id) == ["aa-custom", "zz-custom"])
        #expect(archive.hiddenExercises == ["a-hidden", "b-hidden"])
        let catalogIDs = archive.exerciseCatalog?.map(\.catalogID) ?? []
        #expect(!catalogIDs.isEmpty && catalogIDs == catalogIDs.sorted())
    }

    // MARK: - Absence

    @Test func aCheckInWritesOnlyThePartsMeasuredAndAStoreWithoutOneWritesNoSection() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try fill(context)

        let data = try BackupService.exportData(context: context, stamp: stamp)

        let checks = try #require(PersistenceFixtures.object(data)["bodyMeasurements"] as? [[String: Any]])
        let expected: [Set<String>] = [["id", "date", "armCm", "waistCm"],
                                       ["id", "date", "chestCm", "shouldersCm", "thighCm"],
                                       ["id", "date", "waistCm"]]
        #expect(checks.map { Set($0.keys) } == expected, "A part that wasn't measured has no key")
        #expect(checks.first?["armCm"] as? Double == 36 && checks.last?["waistCm"] as? Double == 82.5,
                "Measured parts are written in centimetres")
        #expect(!String(decoding: data, as: UTF8.self).contains("null"))

        let empty = try BackupService.exportData(context: TestStore.context(), stamp: stamp)
        #expect(!String(decoding: empty, as: UTF8.self).contains("bodyMeasurements"))
    }

    // MARK: - What a reader can cite

    @Test func everySetCarriesItsStoredIDAndOnlyAPlannedSessionItsDay() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plannedDay = try fill(context)

        let data = try BackupService.exportData(context: context, stamp: stamp)
        let archive = try BackupService.decodedArchive(from: data)

        let exportedSetIDs = archive.sessions.flatMap(\.sets).map(\.id)
        #expect(exportedSetIDs.allSatisfy { $0 != nil } && Set(exportedSetIDs).count == exportedSetIDs.count)
        let storedSetIDs = Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id))
        #expect(Set(exportedSetIDs.compactMap { $0 }) == storedSetIDs)
        #expect(archive.sessions.compactMap(\.planDayID) == [plannedDay])
        // The other sessions have no key at all, not a null.
        #expect(String(decoding: data, as: UTF8.self).components(separatedBy: "\"planDayID\"").count == 2)
        let day = try #require(archive.plans.flatMap(\.days).first { $0.id == plannedDay })

        // The day as it stood at the start travels with the session opened
        // from it, in the day's order, and nothing is written for the others.
        let planned = archive.sessions.compactMap(\.plannedItems)
        #expect(planned.count == 1)
        #expect(planned.first?.map(\.catalogID) == day.items.map(\.catalogID))
        #expect(planned.first?.map(\.id) == day.items.map(\.id))
        #expect(planned.first?.map(\.order) == [0, 1, 2])
        #expect(planned.first?.allSatisfy { $0.targetWeightKg == nil && $0.notes == nil && $0.tracking != nil } == true,
                "A planned slot carries its tracking and no starting weight or note")
    }

    @Test func restoreKeepsTheSetIDsAndPlanDaysAndWritesTheSameBytesAgain() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plannedDay = try fill(context)
        let storedSetIDs = Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id))
        let first = try BackupService.exportData(context: context, stamp: stamp)

        try BackupService.restore(data: first, context: context)

        #expect(Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id)) == storedSetIDs)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).compactMap(\.planDayID) == [plannedDay])
        #expect(try BackupService.exportData(context: context, stamp: stamp) == first)
    }

    // MARK: - Rungs

    @Test func everyExerciseTheFileNamesHasARungAndLoadScalesListsOnlyCorrections() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try fill(context)

        let archive = try BackupService.decodedArchive(from: BackupService.exportData(context: context, stamp: stamp))

        let referenced = Set(archive.plans.flatMap(\.days).flatMap(\.items).map(\.catalogID))
            .union(archive.sessions.flatMap(\.sets).map(\.catalogID))
        let effective = archive.effectiveLoadScales ?? []
        let byID = Dictionary(effective.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(effective.map(\.catalogID) == effective.map(\.catalogID).sorted())
        // The deleted custom exercise has no equipment to derive a rung from.
        #expect(Set(byID.keys) == referenced.subtracting(["gone-custom-exercise"]))
        let rungs: [(id: String, unit: String, increment: Double, source: String)] = [
            ("barbell-bench-press", "kg", 2.5, "derived"),
            ("leg-press", "kg", 5, "derived"),
            ("cable-crossover", "kg", 2.5, "derived"),
            ("dumbbell-lateral-raise", "kg", 2, "derived"),
            ("dumbbell-curl", "kg", 1, "correction"),
        ]
        for rung in rungs {
            let row = byID[rung.id]
            #expect(row?.unit == rung.unit && row?.increment == rung.increment && row?.source == rung.source,
                    "\(rung.id) steps by \(String(describing: row))")
        }
        #expect(byID["dumbbell-pullover"] == nil, "A correction on an exercise nothing refers to has no rung")
        let corrections = (archive.loadScales ?? []).map(\.catalogID).sorted()
        #expect(corrections == ["dumbbell-curl", "dumbbell-pullover"].map(ExerciseCatalog.canonicalID(for:)).sorted())
    }

    @Test func aDerivedRungFollowsTheUnitAndACorrectionKeepsItsOwn() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try fill(context)
        AppSettings.shared.weightUnit = .lb

        let archive = try BackupService.decodedArchive(from: BackupService.exportData(context: context, stamp: stamp))

        let rungs = Dictionary((archive.effectiveLoadScales ?? []).map { ($0.catalogID, $0) },
                               uniquingKeysWith: { first, _ in first })
        #expect(rungs["barbell-bench-press"]?.unit == "lb" && rungs["barbell-bench-press"]?.increment == 5)
        #expect(rungs["dumbbell-curl"]?.unit == "kg" && rungs["dumbbell-curl"]?.source == "correction")
    }

    @Test func aCorrectionSavedUnderAMergedIDIsWrittenOnceUnderTheSurvivorAsTheLoggerReadsIt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        func store(_ id: String, _ scale: LoadScale, at offset: TimeInterval) {
            let row = ExerciseLoadPreference(catalogID: id, scale: scale)
            row.updatedAt = base.addingTimeInterval(offset)
            context.insert(row)
        }
        // The survivor saved after the losing ID: the survivor's answer.
        store("dumbbell-pullover-chest", LoadScale(unit: .lb, increment: 5), at: 100)
        store("dumbbell-pullover", LoadScale(unit: .kg, increment: 2), at: 200)
        // The losing ID saved after the survivor: its answer, under the survivor.
        store("unilateral-leg-extension", LoadScale(unit: .kg, increment: 5), at: 300)
        store("single-leg-leg-extension", LoadScale(unit: .lb, increment: 10), at: 400)
        // Only ever saved under the losing ID.
        store("scaption-dumbbell", LoadScale(unit: .lb, increment: 2.5), at: 500)
        // Saved in the same instant: the survivor's row, as the book decides.
        store("bicep-curl-band", LoadScale(unit: .lb, increment: 1), at: 600)
        store("banded-bicep-curl", LoadScale(unit: .kg, increment: 1.5), at: 600)
        // Nothing merged about it.
        store("barbell-bench-press", LoadScale(unit: .lb, increment: 5), at: 700)
        try context.save()

        let url = try BackupService.export(context: context, stamp: stamp)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try BackupService.decodedArchive(from: Data(contentsOf: url))

        #expect(archive.version == 2)
        let scales = archive.loadScales ?? []
        let ids = scales.map(\.catalogID)
        #expect(ids.count == Set(ids).count, "One correction per movement")
        #expect(ids.allSatisfy { ExerciseCatalog.canonicalID(for: $0) == $0 }, "Written under the survivor")
        #expect(ids == ids.sorted())
        let expected: [(id: String, unit: WeightUnit, increment: Double, why: String)] = [
            ("dumbbell-pullover", .kg, 2, "The newer survivor row wins"),
            ("unilateral-leg-extension", .lb, 10, "A newer row under the losing ID wins"),
            ("scaption", .lb, 2.5, "A row only under the losing ID is written under the survivor"),
            ("banded-bicep-curl", .kg, 1.5, "On an exact tie the survivor's row wins"),
            ("barbell-bench-press", .lb, 5, "An unmerged correction is written as stored"),
        ]
        for row in expected {
            let found = scales.first { $0.catalogID == row.id }
            #expect(found?.unit == row.unit.rawValue && found?.increment == row.increment, "\(row.why)")
        }
        #expect(scales.count == 5)

        // The book the logger reads gives the same answers. It has no way back
        // to unconfigured, so it is left on an empty store, which reads the
        // same: nothing corrected.
        let book = LoadScaleBook.shared
        let empty = try TestStore.context().container
        defer { book.configure(container: empty) }
        book.configure(container: context.container)
        for dto in scales {
            let scale = book.scale(for: dto.catalogID)
            #expect(scale.unit.rawValue == dto.unit && scale.increment == dto.increment,
                    "The file and the logger disagree about \(dto.catalogID)")
        }
    }

    // MARK: - Fixture

    /// A store filled in the order least likely to come back sorted: everything
    /// is inserted newest first, highest order first or largest ID first.
    /// Returns the plan day the one planned session was started from.
    private func fill(_ context: ModelContext) throws -> UUID {
        let uuid = PersistenceFixtures.uuid
        func plan(_ name: String, createdAt offset: TimeInterval, items: [(String, String)]) -> PlanDay? {
            let plan = PersistenceFixtures.plan(name, createdAt: base.addingTimeInterval(offset), active: name == "A",
                                                in: context)
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
            return firstDay
        }
        _ = plan("B", createdAt: 100, items: [("cable-crossover", "Cable Crossover")])
        let plannedDay = try #require(plan("A", createdAt: 0, items: [
            ("barbell-bench-press", "Barbell Bench Press"), ("dumbbell-curl", "Dumbbell Curl"),
            ("leg-press", "Leg Press"),
        ]))

        // Two sessions share a start, so the ID has to settle them.
        for (n, offset) in [(3, 3000.0), (0xA2, 2000), (0xA1, 2000), (1, 1000)] {
            let session = WorkoutSession(title: "Session \(n)", planDayID: n == 3 ? plannedDay.id : nil,
                                         startedAt: base.addingTimeInterval(offset))
            session.id = uuid(n)
            session.endedAt = session.startedAt.addingTimeInterval(3_000)
            if n == 3 { session.recordPlan(of: plannedDay) }
            context.insert(session)

            // Rows inserted out of order, one of them a drop set.
            let rows: [(String, String, Int, Int, Double)] = [
                ("dumbbell-curl", "Dumbbell Curl", 1, 0, 12),
                ("barbell-bench-press", "Barbell Bench Press", 0, 2, 60),
                ("barbell-bench-press", "Barbell Bench Press", 0, 1, 50),
                ("barbell-bench-press", "Barbell Bench Press", 0, 0, 80),
                ("dumbbell-lateral-raise", "Lateral Raise", 2, 0, 8),
                ("gone-custom-exercise", "Gone", 3, 0, 20),
            ]
            for (index, row) in rows.enumerated() {
                let set = SetLog(catalogID: row.0, exerciseName: row.1, exerciseOrder: row.2,
                                 setIndex: row.3, weightKg: row.4, reps: 8, tracking: .weightReps)
                set.id = uuid(n * 100 + 99 - index)
                set.isCompleted = true
                set.completedAt = session.startedAt.addingTimeInterval(Double(60 * (index + 1)))
                if row.0 == "barbell-bench-press" && row.3 == 1 { set.continuesPreviousSet = true }
                PersistenceFixtures.add(set, to: session, in: context)
            }
            for (catalogID, name) in [("dumbbell-curl", "Dumbbell Curl"), ("barbell-bench-press", "Bench")] {
                let note = ExerciseNote(catalogID: catalogID, exerciseName: name)
                note.text = "Felt fine on \(name)"
                note.session = session
                context.insert(note)
            }
        }

        for offset in [500.0, 100, 300] {
            context.insert(BodyMetric(date: base.addingTimeInterval(offset), weightKg: 80 + offset / 100))
        }
        // Out of date order, each measuring a different set of parts.
        let checkIns: [(TimeInterval, Int, [BodyMeasurement.Part: Double])] = [
            (500, 0x703, [.waist: 82.5]),
            (100, 0x701, [.arm: 36, .waist: 84]),
            (300, 0x702, [.chest: 101, .shoulders: 118, .thigh: 58.5]),
        ]
        for (offset, id, parts) in checkIns {
            let check = BodyMeasurement(date: base.addingTimeInterval(offset))
            check.id = uuid(id)
            for (part, cm) in parts { check.set(cm, for: part) }
            context.insert(check)
        }
        for id in ["zz-custom", "aa-custom"] {
            let record = CustomExerciseRecord(name: id, muscles: [], equipment: ["Dumbbell"], tracking: .weightReps)
            record.id = id
            context.insert(record)
        }
        for id in ["b-hidden", "a-hidden"] { context.insert(HiddenExerciseRecord(catalogID: id)) }
        // One correction on an exercise the file names, one on an exercise nothing refers to.
        context.insert(ExerciseLoadPreference(catalogID: "dumbbell-curl", scale: LoadScale(unit: .kg, increment: 1)))
        context.insert(ExerciseLoadPreference(catalogID: "dumbbell-pullover", scale: LoadScale(unit: .lb, increment: 5)))
        try context.save()
        return plannedDay.id
    }
}
