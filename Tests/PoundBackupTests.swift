import Foundation
import SwiftData

/// Run with scripts/test-pound-backup.sh; no simulator is needed.
///
/// XC-08: the backup is written for a reader that never sees the phone's
/// setting, so the unit a lifter reads their screen in must change nothing the
/// file says about what was lifted. Every measured weight is kilograms, the
/// setting is only a label, and the one section that does follow the unit, the
/// rungs derived from equipment, says which unit it is in. Restoring the file
/// puts the label back, and never scales a weight a second time.
@main
struct PoundBackupTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let stamp = BackupService.ExportStamp(
        exportedAt: Date(timeIntervalSince1970: 1_790_116_200),
        timeZone: TimeZone(identifier: "Africa/Cairo")!, appVersion: "1.4", appBuild: "27")

    @MainActor static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// One finished session with loads chosen so a stray conversion can't
    /// land on another valid-looking number: 62.5 kg is 137.79 lb.
    @MainActor static func fill(_ context: ModelContext) {
        let session = WorkoutSession(title: "Push", startedAt: Date(timeIntervalSince1970: 1_790_000_000))
        session.endedAt = session.startedAt.addingTimeInterval(3_000)
        context.insert(session)
        for (index, load) in [60.0, 62.5, 65.0].enumerated() {
            let set = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press",
                             exerciseOrder: 0, setIndex: index, weightKg: load, reps: 8,
                             targetRepsLow: 8, targetRepsHigh: 12, tracking: .weightReps)
            set.isCompleted = true
            set.session = session
            context.insert(set)
        }
        context.insert(BodyMetric(date: Date(timeIntervalSince1970: 1_789_900_000), weightKg: 81.5))
    }

    static func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    /// The measured part of a document: everything but the settings label and
    /// the rungs, which are the two places the unit is allowed to show.
    static func measured(_ document: [String: Any]) -> NSDictionary {
        var copy = document
        copy["settings"] = nil
        copy["effectiveLoadScales"] = nil
        return copy as NSDictionary
    }

    static func setWeights(_ document: [String: Any]) -> [Double] {
        let sessions = document["sessions"] as? [[String: Any]] ?? []
        let sets = sessions.flatMap { $0["sets"] as? [[String: Any]] ?? [] }
        return sets.compactMap { $0["weightKg"] as? Double }.sorted()
    }

    @MainActor static func main() throws {
        defer { AppSettings.shared.weightUnit = .kg }
        let context = try makeContext()
        fill(context)

        AppSettings.shared.weightUnit = .kg
        let kilos = try object(BackupService.exportData(context: context, stamp: stamp))
        AppSettings.shared.weightUnit = .lb
        let pounds = try object(BackupService.exportData(context: context, stamp: stamp))

        let label = { (document: [String: Any]) in (document["settings"] as? [String: Any])?["weightUnit"] as? String }
        check(label(kilos) == "kg", "A kilogram phone must say so in the file, got \(String(describing: label(kilos)))")
        check(label(pounds) == "lb", "A pound phone must say so in the file, got \(String(describing: label(pounds)))")

        check(setWeights(pounds) == [60, 62.5, 65],
              "Set loads are kilograms whatever the phone shows, got \(setWeights(pounds))")
        check(setWeights(kilos) == setWeights(pounds), "The unit must not change a logged load")
        let weighIns = (pounds["bodyMetrics"] as? [[String: Any]])?.compactMap { $0["weightKg"] as? Double }
        check(weighIns == [81.5], "Body weight is kilograms too, got \(String(describing: weighIns))")
        check(measured(kilos) == measured(pounds),
              "Nothing outside the settings label and the derived rungs may follow the unit")

        // The derived rung is the one section that follows the unit, and it
        // has to name the unit it is in or 5 reads as kilograms.
        func bench(_ document: [String: Any]) -> [String: Any]? {
            (document["effectiveLoadScales"] as? [[String: Any]])?
                .first { $0["catalogID"] as? String == "barbell-bench-press" }
        }
        check(bench(kilos)?["unit"] as? String == "kg" && bench(kilos)?["increment"] as? Double == 2.5,
              "Barbell rung in kilograms is 2.5, got \(String(describing: bench(kilos)))")
        check(bench(pounds)?["unit"] as? String == "lb" && bench(pounds)?["increment"] as? Double == 5,
              "Barbell rung in pounds is 5 lb, got \(String(describing: bench(pounds)))")
        check(bench(pounds)?["source"] as? String == "derived", "No correction was saved, so the rung is derived")

        // Restore brings the label back and does not touch a weight.
        for (writtenIn, restoredOver) in [(WeightUnit.lb, WeightUnit.kg), (.kg, .lb)] {
            AppSettings.shared.weightUnit = writtenIn
            let file = try BackupService.exportData(context: context, stamp: stamp)
            AppSettings.shared.weightUnit = restoredOver
            let fresh = try makeContext()
            try BackupService.restore(data: file, context: fresh)
            check(AppSettings.shared.weightUnit == writtenIn,
                  "Restoring a \(writtenIn.rawValue) file over a \(restoredOver.rawValue) phone must bring the unit back")
            let loads = try fresh.fetch(FetchDescriptor<SetLog>()).map(\.weightKg).sorted()
            check(loads == [60, 62.5, 65],
                  "A \(writtenIn.rawValue) file must restore the same kilograms, got \(loads)")
            let bodyWeights = try fresh.fetch(FetchDescriptor<BodyMetric>()).map(\.weightKg)
            check(bodyWeights == [81.5], "Restore must not scale body weight, got \(bodyWeights)")
        }

        fflush(stdout)
        guard failures == 0 else { preconditionFailure("\(failures) pound backup check(s) failed") }
        print("Pound backup tests passed")
    }
}
