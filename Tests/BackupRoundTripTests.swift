import Foundation
import SwiftData

/// Run with scripts/test-backup-round-trip.sh; no simulator is needed.
///
/// XC-10: export, restore into a container that has never held any of it,
/// export again, and compare the two JSON documents key by key. The existing
/// fidelity test restores into the store it exported from, which proves the
/// wipe-and-reinsert path is stable but not that a fresh device ends up with
/// the same record. It also fills only weight and reps; the fields that were
/// most recently added (effort, heart rate, detected windows, load offers,
/// continuations, Health provenance) are the ones a restore is likeliest to
/// drop, so this fills every one of them.
///
/// The only fields allowed to differ are the export stamp the caller supplies
/// each time: `exportedAt`, `timeZone`, `appVersion` and `appBuild`. Those are
/// regenerated from the moment and the device on every export by design. The
/// test uses two different stamps so an accidental copy of them cannot pass.
@main
struct BackupRoundTripTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }

    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// The export stamp is the one part of the document that is meant to change.
    static let regenerated: Set<String> = ["exportedAt", "timeZone", "appVersion", "appBuild"]

    static let stampA = BackupService.ExportStamp(
        exportedAt: Date(timeIntervalSince1970: 1_790_116_200),
        timeZone: TimeZone(identifier: "Africa/Cairo")!, appVersion: "1.4", appBuild: "27")
    static let stampB = BackupService.ExportStamp(
        exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
        timeZone: TimeZone(identifier: "America/New_York")!, appVersion: "9.9", appBuild: "999")

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    @MainActor static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A store in which every optional thing a set or session can carry is
    /// present on at least one row, and absent on another, so a restore that
    /// invents a value for a missing key is caught as well as one that drops one.
    @MainActor static func fill(_ context: ModelContext) throws -> UUID {
        let plan = Plan(name: "Push Pull", summary: "Two days", isActive: true)
        plan.createdAt = base
        context.insert(plan)
        let day = PlanDay(name: "Push", order: 0, weekday: 2, notes: "Arrive warm")
        day.plan = plan
        context.insert(day)
        let rest = PlanDay(name: "Rest", order: 1, weekday: 3, isRest: true)
        rest.plan = plan
        context.insert(rest)
        for (position, id, name, tracking) in [
            (0, "barbell-bench-press", "Barbell Bench Press", TrackingMode.weightReps),
            (1, "plank", "Plank", TrackingMode.duration),
            (2, "pull-up", "Pull-Up", TrackingMode.bodyweightReps)] {
            let item = PlanItem(catalogID: id, name: name, order: position, targetSets: 3,
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

        func set(_ n: Int, _ id: String, _ name: String, order: Int, index: Int, weight: Double,
                 reps: Int, seconds: Int = 0, tracking: TrackingMode, in session: WorkoutSession,
                 done: Bool = true, offset: Double) -> SetLog {
            let row = SetLog(catalogID: id, exerciseName: name, exerciseOrder: order, setIndex: index,
                             weightKg: weight, reps: reps, seconds: seconds,
                             targetRepsLow: 6, targetRepsHigh: 10, tracking: tracking)
            row.id = uuid(n)
            row.session = session
            context.insert(row)
            if done {
                row.isCompleted = true
                row.completedAt = session.startedAt.addingTimeInterval(offset)
            }
            return row
        }

        let a = set(0x101, "barbell-bench-press", "Barbell Bench Press", order: 0, index: 0, weight: 62.5,
                    reps: 8, tracking: .weightReps, in: full, offset: 120)
        a.startedAt = a.completedAt!.addingTimeInterval(-40)
        a.rpe = Double(SetFeel.hard.rawValue)
        a.apply(SetHeartRate(average: 131, peak: 149, source: .measured))
        a.recordLoadNudge(.taken, toKg: 65)

        let b = set(0x102, "barbell-bench-press", "Barbell Bench Press", order: 0, index: 1, weight: 60,
                    reps: 6, tracking: .weightReps, in: full, offset: 300)
        b.continuesPreviousSet = true
        b.recordDetectedWindow(DetectedSetWindow(start: b.completedAt!.addingTimeInterval(-35),
                                                 end: b.completedAt!.addingTimeInterval(-3)))
        b.apply(SetHeartRate(average: 128, peak: 140, source: .detected))
        b.rpe = Double(SetFeel.solid.rawValue)
        b.recordLoadNudge(.declined, toKg: 62.5)

        // A set that carries nothing but what was lifted: no key may appear for the rest.
        _ = set(0x103, "barbell-bench-press", "Barbell Bench Press", order: 0, index: 2, weight: 60,
                reps: 5, tracking: .weightReps, in: full, offset: 480)
        _ = set(0x104, "plank", "Plank", order: 1, index: 0, weight: 0, reps: 0, seconds: 75,
                tracking: .duration, in: full, offset: 700)
        _ = set(0x105, "pull-up", "Pull-Up", order: 2, index: 0, weight: 0, reps: 9,
                tracking: .bodyweightReps, in: full, offset: 900)
        // Planned and never done.
        _ = set(0x106, "pull-up", "Pull-Up", order: 2, index: 1, weight: 0, reps: 9,
                tracking: .bodyweightReps, in: full, done: false, offset: 0)

        for (catalogID, name, text, tags) in [
            ("barbell-bench-press", "Barbell Bench Press", "Left shoulder pinched", [NoteTag.allCases[0].rawValue]),
            ("plank", "Plank", "", [NoteTag.allCases[1].rawValue])] {
            let note = ExerciseNote(catalogID: catalogID, exerciseName: name)
            note.text = text
            note.tagsRaw = tags
            note.session = full
            context.insert(note)
        }

        // A bare session: nothing recorded beyond its sets.
        let bare = WorkoutSession(title: "Quick", startedAt: base.addingTimeInterval(9_000))
        bare.id = uuid(2)
        bare.endedAt = bare.startedAt.addingTimeInterval(1_800)
        context.insert(bare)
        _ = set(0x201, "dumbbell-curl", "Dumbbell Curl", order: 0, index: 0, weight: 14, reps: 12,
                tracking: .weightReps, in: bare, offset: 60)

        for (offset, kg) in [(100.0, 80.2), (200, 79.9)] {
            context.insert(BodyMetric(date: base.addingTimeInterval(offset), weightKg: kg))
        }
        let custom = CustomExerciseRecord(name: "Sled Drag", muscles: [], equipment: ["Sled"], tracking: .weightReps)
        custom.id = "custom-sled-drag"
        context.insert(custom)
        context.insert(HiddenExerciseRecord(catalogID: "cable-crossover"))
        context.insert(ExerciseLoadPreference(catalogID: "barbell-bench-press",
                                              scale: LoadScale(unit: .lb, increment: 5)))
        context.insert(ExerciseLoadPreference(catalogID: "dumbbell-curl",
                                              scale: LoadScale(unit: .kg, increment: 1)))
        try context.save()
        return full.id
    }

    // MARK: - JSON comparison

    static func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    /// Every path at which two documents differ, so a failure names the field
    /// rather than saying two blobs are unequal.
    static func differences(_ lhs: Any?, _ rhs: Any?, path: String = "$") -> [String] {
        switch (lhs, rhs) {
        case let (l as [String: Any], r as [String: Any]):
            var out: [String] = []
            for key in Set(l.keys).union(r.keys).sorted() {
                out += differences(l[key], r[key], path: "\(path).\(key)")
            }
            return out
        case let (l as [Any], r as [Any]):
            if l.count != r.count { return ["\(path): \(l.count) elements became \(r.count)"] }
            return l.indices.flatMap { differences(l[$0], r[$0], path: "\(path)[\($0)]") }
        case (nil, nil):
            return []
        case (nil, _?):
            return ["\(path): absent before, present after (\(rhs!))"]
        case (_?, nil):
            return ["\(path): present before (\(lhs!)), absent after"]
        default:
            return (lhs as? NSObject)?.isEqual(rhs) == true ? [] : ["\(path): \(lhs!) became \(rhs!)"]
        }
    }

    static func stripped(_ document: [String: Any]) -> [String: Any] {
        document.filter { !regenerated.contains($0.key) }
    }

    /// Every key that occurs on any dictionary in `rows`.
    static func keys(in rows: [[String: Any]]) -> Set<String> { Set(rows.flatMap(\.keys)) }

    @MainActor static func main() throws {
        for unit in [WeightUnit.kg, .lb] {
            AppSettings.shared.weightUnit = unit
            try roundTrip(displayUnit: unit)
        }
        guard failures == 0 else { preconditionFailure("\(failures) round-trip check(s) failed") }
        print("Export, restore into a fresh store, export: identical documents")
    }

    @MainActor static func roundTrip(displayUnit: WeightUnit) throws {
        let tag = "(display unit \(displayUnit.rawValue))"
        let source = try makeContext()
        _ = try fill(source)
        let first = try BackupService.exportData(context: source, stamp: stampA)

        // The document must actually contain what the round trip is meant to protect.
        let document = try object(first)
        let sessions = document["sessions"] as! [[String: Any]]
        let sets = sessions.flatMap { $0["sets"] as! [[String: Any]] }
        let setKeys = keys(in: sets)
        for key in ["id", "startedAt", "completedAt", "detectedStartedAt", "detectedEndedAt", "rpe", "effort",
                    "averageHeartRate", "maxHeartRate", "heartRateWindow", "loadNudge", "continues",
                    "seconds", "reps", "targetRepsLow", "targetRepsHigh", "tracking"] {
            check(setKeys.contains(key), "Fixture never exercises set field \(key) \(tag)")
        }
        let sessionKeys = keys(in: sessions)
        for key in ["planDayID", "averageHeartRate", "maxHeartRate", "activeEnergyKcal", "healthWorkoutID",
                    "wasWatchDriven", "heartRateSource", "energySource", "heartRateReadings", "noteTags",
                    "exerciseNotes", "notes", "endedAt"] {
            check(sessionKeys.contains(key), "Fixture never exercises session field \(key) \(tag)")
        }
        for key in ["bodyMetrics", "customExercises", "loadScales", "hiddenExercises", "exerciseCatalog",
                    "effectiveLoadScales", "effortScale", "timeZone", "appVersion", "appBuild"] {
            check(document[key] != nil, "Fixture never exercises top-level field \(key) \(tag)")
        }

        let fresh = try makeContext()
        try BackupService.restore(data: first, context: fresh)
        let second = try BackupService.exportData(context: fresh, stamp: stampB)

        let changed = differences(stripped(document), stripped(try object(second)))
        check(changed.isEmpty,
              "Export, restore into a fresh store, export changed \(changed.count) field(s) \(tag): "
              + changed.prefix(12).joined(separator: "; "))

        // The stamp is the only thing that should have moved, and it must have moved
        // for a reason: it is regenerated, not copied through the restore.
        let secondDocument = try object(second)
        for key in regenerated {
            check(document[key] != nil && secondDocument[key] != nil
                  && (document[key] as? NSObject)?.isEqual(secondDocument[key]) == false,
                  "\(key) is regenerated by each export, not carried through a restore \(tag)")
        }

        // Absence stays absence. A set that carried nothing must still carry no
        // optional key after a restore, not a null, a zero or an empty string.
        let restored = try object(second)["sessions"] as! [[String: Any]]
        let restoredSets = restored.flatMap { $0["sets"] as! [[String: Any]] }
        let bareSet = restoredSets.first { ($0["id"] as? String) == uuid(0x103).uuidString }
        let optional: Set<String> = ["startedAt", "detectedStartedAt", "detectedEndedAt", "rpe", "effort",
                                     "averageHeartRate", "maxHeartRate", "heartRateWindow", "loadNudge",
                                     "continues", "isWarmup"]
        check(bareSet != nil && Set(bareSet!.keys).isDisjoint(with: optional),
              "A set with nothing recorded gained keys through the round trip: "
              + "\(bareSet.map { Set($0.keys).intersection(optional).sorted() } ?? [])  \(tag)")

        // A second restore of the second export changes nothing either.
        let third = try BackupService.exportData(context: fresh, stamp: stampB)
        check(third == second, "Exporting twice from the restored store gave different bytes \(tag)")
    }
}
