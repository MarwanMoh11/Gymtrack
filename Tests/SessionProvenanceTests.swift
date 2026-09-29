import Foundation
import SwiftData

/// Run with scripts/test-session-provenance.sh; no simulator is needed.
///
/// Two things the export used to state more confidently than it knew. An effort
/// answer was written as a point RPE, so "Easy" (three or more reps left) read
/// as four in reserve; and a session's heart rate and energy carried no hint of
/// whether a workout's worth of readings stood behind them or two background
/// ones. Nothing here touches HealthKit: the decision the backfill makes is a
/// pure function of the samples, and is tested as one.
@main
struct SessionProvenanceTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor static func session(_ title: String, at offset: TimeInterval,
                                   in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: title, startedAt: base.addingTimeInterval(offset))
        session.endedAt = session.startedAt.addingTimeInterval(3_600)
        context.insert(session)
        return session
    }

    /// The exported file as loose JSON, so a test can say a key is absent
    /// rather than merely nil.
    @MainActor static func exported(_ context: ModelContext) throws -> [String: Any] {
        let data = try BackupService.exportData(context: context)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static func sessions(_ file: [String: Any]) -> [[String: Any]] { file["sessions"] as! [[String: Any]] }

    static func reading(at seconds: TimeInterval, _ bpm: Double, wrist: Bool = true) -> VitalsSample {
        let at = base.addingTimeInterval(seconds)
        return VitalsSample(start: at, end: at, value: bpm, isFromWrist: wrist)
    }

    static func slice(from start: TimeInterval, for length: TimeInterval, kcal: Double,
                      wrist: Bool) -> VitalsSample {
        VitalsSample(start: base.addingTimeInterval(start), end: base.addingTimeInterval(start + length),
                     value: kcal, isFromWrist: wrist)
    }

    static let hour = DateInterval(start: base, duration: 3_600)

    @MainActor static func main() async throws {
        try effortAnswers()
        try provenanceExport()
        try oldFilesStillDecode()
        try roundTrip()
        try watchStamp()
        judging()
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("session provenance: all checks passed")
    }

    // MARK: DATA-08

    @MainActor static func effortAnswers() throws {
        check(SetFeel.answer(forStored: 6) == .easy, "6 is Easy")
        check(SetFeel.answer(forStored: 8) == .solid, "8 is Solid")
        check(SetFeel.answer(forStored: 9) == .hard, "9 is Hard")
        check(SetFeel.answer(forStored: 10) == .allOut, "10 is All out")
        check(SetFeel.answer(forStored: 7) == nil, "a 7 from the old strip is not an answer")
        check(SetFeel.answer(forStored: 8.5) == nil, "an 8.5 from the old strip is not an answer")
        check(SetFeel.answer(forStored: 0) == nil, "zero is not an answer")

        let container = try makeContainer()
        let context = container.mainContext
        let session = session("Effort", at: 0, in: context)
        for (index, rpe) in [6.0, 8, 9, 10, 7, 8.5].enumerated() {
            let set = SetLog(catalogID: "leg-press", exerciseName: "Leg Press", exerciseOrder: 0,
                             setIndex: index, weightKg: 100, reps: 8, tracking: .weightReps)
            set.isCompleted = true
            set.completedAt = session.startedAt.addingTimeInterval(Double(60 * (index + 1)))
            set.rpe = rpe
            set.session = session
            context.insert(set)
        }
        let unrated = SetLog(catalogID: "leg-press", exerciseName: "Leg Press", exerciseOrder: 0,
                             setIndex: 6, weightKg: 100, reps: 8, tracking: .weightReps)
        unrated.isCompleted = true
        unrated.completedAt = session.startedAt.addingTimeInterval(500)
        unrated.session = session
        context.insert(unrated)
        try context.save()

        let file = try exported(context)
        let sets = sessions(file)[0]["sets"] as! [[String: Any]]
        let byIndex = Dictionary(uniqueKeysWithValues: sets.map { ($0["setIndex"] as! Int, $0) })
        check(byIndex[0]?["effort"] as? String == "easy", "6 exports effort easy")
        check(byIndex[1]?["effort"] as? String == "solid", "8 exports effort solid")
        check(byIndex[2]?["effort"] as? String == "hard", "9 exports effort hard")
        check(byIndex[3]?["effort"] as? String == "allOut", "10 exports effort allOut")
        check(byIndex[0]?["rpe"] as? Double == 6, "rpe stays beside the word, so restore and old readers are unchanged")
        check(byIndex[4]?["rpe"] as? Double == 7 && byIndex[4]?["effort"] == nil,
              "an old-strip 7 keeps its rpe and gets no effort key")
        check(byIndex[5]?["rpe"] as? Double == 8.5 && byIndex[5]?["effort"] == nil,
              "an old-strip 8.5 keeps its rpe and gets no effort key")
        check(byIndex[6]?["rpe"] == nil && byIndex[6]?["effort"] == nil,
              "a set nobody rated writes neither key")

        let scale = file["effortScale"] as? [String: Any]
        check(scale?["rpe"] as? String == "bucketCode", "the file says rpe is a bucket code")
        let buckets = scale?["buckets"] as? [[String: Any]] ?? []
        check(buckets.map { $0["effort"] as? String } == ["easy", "solid", "hard", "allOut"],
              "the scale lists the four answers in button order")
        check(buckets.map { $0["rpe"] as? Double } == [6, 8, 9, 10], "the scale carries each answer's code")
        check(buckets.first?["meaning"] as? String == "Three or more reps left", "Easy is spelled out as three or more")

        let settings = file["settings"] as? [String: Any]
        check(settings?["trackRPE"] as? Bool == true, "trackRPE is exported")
        AppSettings.shared.trackRPE = false
        defer { AppSettings.shared.trackRPE = true }
        check((try exported(context)["settings"] as? [String: Any])?["trackRPE"] as? Bool == false,
              "trackRPE off is exported as false, not left out")
    }

    // MARK: DATA-10

    @MainActor static func provenanceExport() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Stored before provenance existed: numbers, and no way to say where
        // they came from.
        let old = session("Old", at: 0, in: context)
        old.averageHeartRate = 118; old.maxHeartRate = 151; old.activeEnergyKcal = 320

        let stamped = session("Stamped", at: 10_000, in: context)
        stamped.averageHeartRate = 131; stamped.maxHeartRate = 166; stamped.activeEnergyKcal = 410
        stamped.heartRateSourceRaw = VitalsSource.healthSamples.rawValue
        stamped.heartRateReadings = 640
        stamped.energySourceRaw = VitalsSource.watchWorkout.rawValue

        // A provenance whose numbers have since gone must not describe them.
        let cleared = session("Cleared", at: 20_000, in: context)
        cleared.heartRateSourceRaw = VitalsSource.healthSamples.rawValue
        cleared.heartRateReadings = 640
        cleared.energySourceRaw = VitalsSource.healthSamples.rawValue

        // Under a kilocalorie is a sensor waking up.
        let trace = session("Trace", at: 30_000, in: context)
        trace.activeEnergyKcal = 0.4
        trace.energySourceRaw = VitalsSource.watchWorkout.rawValue

        // A source no build knows.
        let unknown = session("Unknown", at: 40_000, in: context)
        unknown.averageHeartRate = 100
        unknown.heartRateSourceRaw = "somethingLater"
        try context.save()

        let rows = Dictionary(uniqueKeysWithValues: sessions(try exported(context)).map { ($0["title"] as! String, $0) })
        let provenanceKeys = ["heartRateSource", "heartRateReadings", "energySource"]

        for key in provenanceKeys {
            check(rows["Old"]?[key] == nil, "a session stored before provenance writes no \(key)")
        }
        check(rows["Old"]?["averageHeartRate"] as? Double == 118, "the old session's numbers still export")
        check(rows["Old"]?["activeEnergyKcal"] as? Double == 320, "the old session's energy still exports")

        check(rows["Stamped"]?["heartRateSource"] as? String == "healthSamples", "heart-rate source exports")
        check(rows["Stamped"]?["heartRateReadings"] as? Int == 640, "reading count exports")
        check(rows["Stamped"]?["energySource"] as? String == "watchWorkout", "energy source exports separately")

        for key in provenanceKeys {
            check(rows["Cleared"]?[key] == nil, "a cleared session writes no \(key)")
        }
        check(rows["Trace"]?["activeEnergyKcal"] == nil, "0.4 kcal is not exported as energy")
        check(rows["Trace"]?["energySource"] == nil, "and its source is not exported either")
        check(rows["Unknown"]?["heartRateSource"] == nil, "a source this build can't name is left out, not echoed")
        check(rows["Unknown"]?["heartRateReadings"] == nil, "a count with no source is left out")
    }

    @MainActor static func oldFilesStillDecode() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = session("Legacy", at: 0, in: context)
        session.averageHeartRate = 120
        try context.save()

        // A file as an earlier build wrote it: none of the new keys anywhere.
        var file = try exported(context)
        file.removeValue(forKey: "effortScale")
        var settings = file["settings"] as! [String: Any]
        settings.removeValue(forKey: "trackRPE")
        file["settings"] = settings
        var rows = sessions(file)
        for key in ["heartRateSource", "heartRateReadings", "energySource"] { rows[0].removeValue(forKey: key) }
        file["sessions"] = rows
        let data = try JSONSerialization.data(withJSONObject: file)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(BackupService.Archive.self, from: data)
        check(archive.version == 2, "the version stays 2")
        check(archive.effortScale == nil && archive.settings.trackRPE == nil, "absent top-level keys decode as nil")
        check(archive.sessions[0].heartRateSource == nil, "absent provenance decodes as nil")

        let freshContainer = try makeContainer()
        let fresh = freshContainer.mainContext
        try BackupService.restore(data: data, context: fresh)
        let restored = try fresh.fetch(FetchDescriptor<WorkoutSession>())
        check(restored.count == 1 && restored[0].averageHeartRate == 120, "the old file restores its numbers")
        check(restored[0].heartRateSource == nil, "and invents no provenance for them")
        let again = sessions(try exported(fresh))[0]
        check(again["heartRateSource"] == nil && again["energySource"] == nil, "re-exporting still writes no key")
    }

    @MainActor static func roundTrip() throws {
        let sourceContainer = try makeContainer()
        let source = sourceContainer.mainContext
        let session = session("Round trip", at: 0, in: source)
        session.averageHeartRate = 131; session.maxHeartRate = 166; session.activeEnergyKcal = 410
        session.heartRateSourceRaw = VitalsSource.healthSamples.rawValue
        session.heartRateReadings = 640
        session.energySourceRaw = VitalsSource.watchWorkout.rawValue
        try source.save()

        let data = try BackupService.exportData(context: source)
        let targetContainer = try makeContainer()
        let target = targetContainer.mainContext
        try BackupService.restore(data: data, context: target)
        let row = sessions(try exported(target))[0]
        check(row["heartRateSource"] as? String == "healthSamples", "heart-rate source survives a restore")
        check(row["heartRateReadings"] as? Int == 640, "reading count survives a restore")
        check(row["energySource"] as? String == "watchWorkout", "energy source survives a restore")
    }

    @MainActor static func watchStamp() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = session("Watch", at: 0, in: context)

        // Health filled the energy in first; the watch's report then carries
        // heart rate only. The energy must not be re-labelled as the wrist's.
        session.activeEnergyKcal = 300
        session.energySourceRaw = VitalsSource.healthSamples.rawValue
        session.averageHeartRate = 140; session.maxHeartRate = 170
        session.heartRateSourceRaw = VitalsSource.healthSamples.rawValue
        session.heartRateReadings = 500
        session.stampWatchVitals(average: 141, max: 171, energy: nil)
        check(session.heartRateSourceRaw == VitalsSource.watchWorkout.rawValue, "watch heart rate is stamped as the watch's")
        check(session.heartRateReadings == nil, "a count from the replaced Health read is dropped")
        check(session.energySourceRaw == VitalsSource.healthSamples.rawValue,
              "energy the report didn't carry keeps the source it had")

        session.stampWatchVitals(average: nil, max: nil, energy: 0)
        check(session.energySourceRaw == VitalsSource.healthSamples.rawValue, "a zero reading stamps nothing")
        session.stampWatchVitals(average: 0, max: 0, energy: 350)
        check(session.heartRateSourceRaw == VitalsSource.watchWorkout.rawValue, "a zero heart rate leaves the source alone")
        check(session.energySourceRaw == VitalsSource.watchWorkout.rawValue, "watch energy is stamped as the watch's")
    }

    // MARK: The backfill's decision

    @MainActor static func judging() {
        // Two background readings across an hour.
        let sparse = VitalsEvidence.judge(heartRate: [reading(at: 300, 88), reading(at: 3_000, 92)],
                                          energy: [], window: hour)
        check(sparse.averageHeartRate == nil && sparse.maxHeartRate == nil && sparse.heartRateReadings == nil,
              "two background readings are no session heart rate")

        // A workout's worth: one every five seconds.
        let dense = (0..<720).map { reading(at: Double($0) * 5, 100 + Double($0 % 60)) }
        let workout = VitalsEvidence.judge(heartRate: dense, energy: [], window: hour)
        check(workout.heartRateReadings == 720, "a dense trace is accepted and counted")
        check(workout.maxHeartRate == 159, "the peak comes from the readings")
        check(abs((workout.averageHeartRate ?? 0) - 129.5) < 0.001, "the average comes from the readings")

        // Plenty of readings, all in the first five minutes.
        let clustered = (0..<300).map { reading(at: Double($0), 120) }
        check(VitalsEvidence.judge(heartRate: clustered, energy: [], window: hour).averageHeartRate == nil,
              "readings covering a fraction of the session are refused")

        // Spread across the hour but too far apart.
        let slow = (0..<40).map { reading(at: Double($0) * 90, 110) }
        check(VitalsEvidence.judge(heartRate: slow, energy: [], window: hour).averageHeartRate == nil,
              "a reading every 90 seconds is too thin")
        let minute = (0..<60).map { reading(at: Double($0) * 60, 110) }
        check(VitalsEvidence.judge(heartRate: minute, energy: [], window: hour).averageHeartRate == 110,
              "a reading a minute is the least accepted")

        // A short session still needs a dozen readings.
        let fiveMinutes = DateInterval(start: base, duration: 300)
        let eleven = (0..<11).map { reading(at: Double($0) * 25, 110) }
        let twelve = (0..<12).map { reading(at: Double($0) * 25, 110) }
        check(VitalsEvidence.judge(heartRate: eleven, energy: [], window: fiveMinutes).averageHeartRate == nil,
              "eleven readings are not enough however short the session")
        check(VitalsEvidence.judge(heartRate: twelve, energy: [], window: fiveMinutes).averageHeartRate == 110,
              "twelve readings across a short session are enough")

        // A chest strap on a phone app is a measurement too.
        let strap = (0..<720).map { reading(at: Double($0) * 5, 120, wrist: false) }
        check(VitalsEvidence.judge(heartRate: strap, energy: [], window: hour).averageHeartRate == 120,
              "dense heart rate is accepted whatever wrote it")

        // Zeros are a query with nothing to say.
        let zeros = (0..<720).map { reading(at: Double($0) * 5, 0) }
        check(VitalsEvidence.judge(heartRate: zeros, energy: [], window: hour).averageHeartRate == nil,
              "zero readings are not readings")

        // Energy.
        let pedometer = [slice(from: 0, for: 3_600, kcal: 200, wrist: false)]
        check(VitalsEvidence.judge(heartRate: [], energy: pedometer, window: hour).activeEnergyKcal == nil,
              "phone-estimated energy is no workout energy")
        let wrist = [slice(from: 0, for: 900, kcal: 90, wrist: true), slice(from: 900, for: 900, kcal: 110, wrist: true),
                     slice(from: 1_800, for: 900, kcal: 100, wrist: true)]
        check(VitalsEvidence.judge(heartRate: [], energy: wrist + pedometer, window: hour).activeEnergyKcal == 300,
              "only the wrist's slices are summed")
        let brief = [slice(from: 0, for: 120, kcal: 12, wrist: true)]
        check(VitalsEvidence.judge(heartRate: [], energy: brief, window: hour).activeEnergyKcal == nil,
              "two minutes of energy don't stand for an hour")
        let trace = [slice(from: 0, for: 3_600, kcal: 0.6, wrist: true)]
        check(VitalsEvidence.judge(heartRate: [], energy: trace, window: hour).activeEnergyKcal == nil,
              "under a kilocalorie is nothing")
        check(VitalsEvidence.judge(heartRate: dense, energy: pedometer, window: hour).averageHeartRate != nil,
              "energy refused doesn't cost the heart rate")
        check(VitalsEvidence.judge(heartRate: dense, energy: [], window: DateInterval(start: base, duration: 0)) == VitalsEvidence(),
              "an empty window vouches for nothing")
    }
}
