import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// Two things the export used to state more confidently than it knew. An effort
/// answer was written as a point RPE, so "Easy" (three or more reps left) read
/// as four in reserve; and a session's heart rate and energy carried no hint of
/// whether a workout's worth of readings stood behind them or two background
/// ones.
///
/// Nothing here touches HealthKit: the decision the backfill makes,
/// `VitalsEvidence.judge`, is a pure function of the samples and is tested as
/// one. Which stored number is which answer is in `UnitsTests`; the keys the
/// rest of a session writes or leaves out are in `BackupDecodingTests`.
@MainActor @Suite(.serialized)
struct SessionProvenanceTests {

    private let base = TestClock.at("2026-03-10T18:00:00")

    private var hour: DateInterval { DateInterval(start: base, duration: 3_600) }

    /// A finished hour-long session, `offset` seconds after `base`.
    private func session(_ title: String, at offset: TimeInterval, in context: ModelContext) -> WorkoutSession {
        let start = base.addingTimeInterval(offset)
        return PersistenceFixtures.session(title, startedAt: start, endedAt: start.addingTimeInterval(3_600),
                                           in: context)
    }

    /// The exported file as loose JSON, so a test can say a key is absent
    /// rather than merely nil.
    private func exported(_ context: ModelContext) throws -> [String: Any] {
        try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp()))
    }

    /// Every exported session, by title.
    private func sessionsByTitle(_ context: ModelContext) throws -> [String: [String: Any]] {
        let rows = try PersistenceFixtures.sessions(in: exported(context))
        return Dictionary(uniqueKeysWithValues: rows.map { ($0["title"] as? String ?? "", $0) })
    }

    private func reading(at seconds: TimeInterval, _ bpm: Double, wrist: Bool = true) -> VitalsSample {
        let at = base.addingTimeInterval(seconds)
        return VitalsSample(start: at, end: at, value: bpm, isFromWrist: wrist)
    }

    private func slice(from start: TimeInterval, for length: TimeInterval, kcal: Double,
                       wrist: Bool) -> VitalsSample {
        VitalsSample(start: base.addingTimeInterval(start), end: base.addingTimeInterval(start + length),
                     value: kcal, isFromWrist: wrist)
    }

    private static let provenanceKeys = ["heartRateSource", "heartRateReadings", "energySource"]

    // MARK: - Effort words (DATA-08)

    @Test func aSetExportsTheAnswerItWasGivenAndAnOldStripNumberGetsNoWord() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let workout = session("Effort", at: 0, in: context)
        for (index, rpe) in [6.0, 8, 9, 10, 7, 8.5].enumerated() {
            let set = PersistenceFixtures.set(setIndex: index, completedAt: workout.startedAt.addingTimeInterval(Double(60 * (index + 1))))
            set.rpe = rpe
            PersistenceFixtures.add(set, to: workout, in: context)
        }
        let unrated = PersistenceFixtures.set(setIndex: 6, completedAt: workout.startedAt.addingTimeInterval(500))
        PersistenceFixtures.add(unrated, to: workout, in: context)

        let sets = try PersistenceFixtures.sets(in: exported(context), sessionIndex: 0)
        let byIndex = Dictionary(uniqueKeysWithValues: sets.map { ($0["setIndex"] as? Int ?? -1, $0) })

        #expect(byIndex[0]?["effort"] as? String == "easy")
        #expect(byIndex[1]?["effort"] as? String == "solid")
        #expect(byIndex[2]?["effort"] as? String == "hard")
        #expect(byIndex[3]?["effort"] as? String == "allOut")
        // The number stays beside the word, so restore and older readers are unchanged.
        #expect(byIndex[0]?["rpe"] as? Double == 6)
        // A 7 or an 8.5 from the old five-number strip is a number the lifter
        // chose. Calling it a word would put one in their mouth.
        #expect(byIndex[4]?["rpe"] as? Double == 7)
        #expect(byIndex[4]?.keys.contains("effort") == false)
        #expect(byIndex[5]?["rpe"] as? Double == 8.5)
        #expect(byIndex[5]?.keys.contains("effort") == false)
        // Nobody rated it, so neither key.
        #expect(byIndex[6]?.keys.contains("rpe") == false)
        #expect(byIndex[6]?.keys.contains("effort") == false)
    }

    @Test func theFileSaysRpeIsABucketCodeAndSpellsOutTheFourAnswers() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()

        let scale = try #require(exported(context)["effortScale"] as? [String: Any])

        #expect(scale["rpe"] as? String == "bucketCode")
        let buckets = try #require(scale["buckets"] as? [[String: Any]])
        // Button order, each with its code.
        #expect(buckets.map { $0["effort"] as? String } == ["easy", "solid", "hard", "allOut"])
        #expect(buckets.map { $0["rpe"] as? Double } == [6, 8, 9, 10])
        #expect(buckets.first?["meaning"] as? String == "Three or more reps left")
    }

    /// Off is an answer too: left out, a reader could not tell a lifter who
    /// switched the question off from a file written before it existed.
    @Test(arguments: [true, false])
    func trackRPEIsExportedAsItIsSetAndOffIsWrittenNotLeftOut(_ on: Bool) throws {
        let saved = PersistenceFixtures.pin()
        let savedTrackRPE = AppSettings.shared.trackRPE
        defer {
            AppSettings.shared.trackRPE = savedTrackRPE
            saved.restore()
        }
        AppSettings.shared.trackRPE = on
        let context = try TestStore.context()

        let settings = try #require(exported(context)["settings"] as? [String: Any])

        #expect(settings["trackRPE"] as? Bool == on)
    }

    // MARK: - Where a session's vitals came from (DATA-10)

    @Test func aSessionsProvenanceIsExportedOnlyBesideNumbersItDescribesAndCanName() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()

        // Stored before provenance existed: numbers, and no way to say where
        // they came from.
        let old = session("Old", at: 0, in: context)
        old.averageHeartRate = 118
        old.maxHeartRate = 151
        old.activeEnergyKcal = 320

        let stamped = session("Stamped", at: 10_000, in: context)
        stamped.averageHeartRate = 131
        stamped.maxHeartRate = 166
        stamped.activeEnergyKcal = 410
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

        let rows = try sessionsByTitle(context)

        for key in Self.provenanceKeys {
            #expect(rows["Old"]?.keys.contains(key) == false, "a session stored before provenance wrote \(key)")
            #expect(rows["Cleared"]?.keys.contains(key) == false, "a cleared session wrote \(key)")
        }
        #expect(rows["Old"]?["averageHeartRate"] as? Double == 118)
        #expect(rows["Old"]?["activeEnergyKcal"] as? Double == 320)

        #expect(rows["Stamped"]?["heartRateSource"] as? String == "healthSamples")
        #expect(rows["Stamped"]?["heartRateReadings"] as? Int == 640)
        #expect(rows["Stamped"]?["energySource"] as? String == "watchWorkout")

        #expect(rows["Trace"]?.keys.contains("activeEnergyKcal") == false)
        #expect(rows["Trace"]?.keys.contains("energySource") == false)
        // Left out, not echoed; and a count with no source says nothing.
        #expect(rows["Unknown"]?.keys.contains("heartRateSource") == false)
        #expect(rows["Unknown"]?.keys.contains("heartRateReadings") == false)
    }

    @Test func aFileWrittenBeforeProvenanceDecodesRestoresAndExportsWithoutInventingAny() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let source = try TestStore.context()
        session("Legacy", at: 0, in: source).averageHeartRate = 120
        try source.save()

        // The file as an earlier build wrote it: none of the new keys anywhere.
        var file = try exported(source)
        file.removeValue(forKey: "effortScale")
        var settings = try #require(file["settings"] as? [String: Any])
        settings.removeValue(forKey: "trackRPE")
        file["settings"] = settings
        var rows = try PersistenceFixtures.sessions(in: file)
        for key in Self.provenanceKeys { rows[0].removeValue(forKey: key) }
        file["sessions"] = rows
        let data = try JSONSerialization.data(withJSONObject: file)

        let archive = try BackupService.decodedArchive(from: data)
        #expect(archive.version == 2)
        #expect(archive.effortScale == nil)
        #expect(archive.settings.trackRPE == nil)
        #expect(archive.sessions.first?.heartRateSource == nil)

        let fresh = try TestStore.context()
        try BackupService.restore(data: data, context: fresh)
        let restored = try fresh.fetch(FetchDescriptor<WorkoutSession>())
        #expect(restored.count == 1)
        #expect(restored.first?.averageHeartRate == 120)
        #expect(restored.first?.heartRateSource == nil)
        let again = try #require(PersistenceFixtures.sessions(in: exported(fresh)).first)
        #expect(!again.keys.contains("heartRateSource"))
        #expect(!again.keys.contains("energySource"))
    }

    @Test func eachSourceAndTheReadingCountSurviveARestore() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let source = try TestStore.context()
        let workout = session("Round trip", at: 0, in: source)
        workout.averageHeartRate = 131
        workout.maxHeartRate = 166
        workout.activeEnergyKcal = 410
        workout.heartRateSourceRaw = VitalsSource.healthSamples.rawValue
        workout.heartRateReadings = 640
        workout.energySourceRaw = VitalsSource.watchWorkout.rawValue
        try source.save()

        let target = try TestStore.context()
        try BackupService.restore(data: BackupService.exportData(context: source, stamp: PersistenceFixtures.stamp()),
                                  context: target)

        let row = try #require(PersistenceFixtures.sessions(in: exported(target)).first)
        #expect(row["heartRateSource"] as? String == "healthSamples")
        #expect(row["heartRateReadings"] as? Int == 640)
        #expect(row["energySource"] as? String == "watchWorkout")
    }

    @Test func theWatchsReportStampsOnlyWhatItCarried() {
        let workout = WorkoutSession(title: "Watch", startedAt: base)

        // Health filled the energy in first; the watch's report then carries
        // heart rate only. The energy must not be relabelled as the wrist's.
        workout.activeEnergyKcal = 300
        workout.energySourceRaw = VitalsSource.healthSamples.rawValue
        workout.averageHeartRate = 140
        workout.maxHeartRate = 170
        workout.heartRateSourceRaw = VitalsSource.healthSamples.rawValue
        workout.heartRateReadings = 500

        workout.stampWatchVitals(average: 141, max: 171, energy: nil)
        #expect(workout.heartRateSourceRaw == VitalsSource.watchWorkout.rawValue)
        // A count from the Health read the watch's numbers replaced.
        #expect(workout.heartRateReadings == nil)
        #expect(workout.energySourceRaw == VitalsSource.healthSamples.rawValue)

        // A zero is a watch with nothing to report yet.
        workout.stampWatchVitals(average: nil, max: nil, energy: 0)
        #expect(workout.energySourceRaw == VitalsSource.healthSamples.rawValue)
        workout.stampWatchVitals(average: 0, max: 0, energy: 350)
        #expect(workout.heartRateSourceRaw == VitalsSource.watchWorkout.rawValue)
        #expect(workout.energySourceRaw == VitalsSource.watchWorkout.rawValue)
    }

    // MARK: - What the backfill may keep

    @Test func onlyADenseEvenTraceOfHeartRateStandsForTheSession() {
        // Two background readings across an hour.
        let sparse = VitalsEvidence.judge(heartRate: [reading(at: 300, 88), reading(at: 3_000, 92)],
                                          energy: [], window: hour)
        #expect(sparse.averageHeartRate == nil)
        #expect(sparse.maxHeartRate == nil)
        #expect(sparse.heartRateReadings == nil)

        // A workout's worth: one every five seconds.
        let dense = (0..<720).map { reading(at: Double($0) * 5, 100 + Double($0 % 60)) }
        let workout = VitalsEvidence.judge(heartRate: dense, energy: [], window: hour)
        #expect(workout.heartRateReadings == 720)
        #expect(workout.maxHeartRate == 159)
        #expect(abs((workout.averageHeartRate ?? 0) - 129.5) < 0.001)

        // Plenty of readings, all in the first five minutes.
        let clustered = (0..<300).map { reading(at: Double($0), 120) }
        #expect(VitalsEvidence.judge(heartRate: clustered, energy: [], window: hour).averageHeartRate == nil)

        // Spread across the hour, but one every 90 seconds is too thin and one a
        // minute is the least that will do.
        let slow = (0..<40).map { reading(at: Double($0) * 90, 110) }
        #expect(VitalsEvidence.judge(heartRate: slow, energy: [], window: hour).averageHeartRate == nil)
        let minute = (0..<60).map { reading(at: Double($0) * 60, 110) }
        #expect(VitalsEvidence.judge(heartRate: minute, energy: [], window: hour).averageHeartRate == 110)

        // A chest strap on a phone app is a measurement too.
        let strap = (0..<720).map { reading(at: Double($0) * 5, 120, wrist: false) }
        #expect(VitalsEvidence.judge(heartRate: strap, energy: [], window: hour).averageHeartRate == 120)

        // Zeros are a query with nothing to say.
        let zeros = (0..<720).map { reading(at: Double($0) * 5, 0) }
        #expect(VitalsEvidence.judge(heartRate: zeros, energy: [], window: hour).averageHeartRate == nil)
    }

    @Test(arguments: [(count: 11, accepted: false), (count: 12, accepted: true)])
    func aShortSessionStillNeedsADozenReadings(count: Int, accepted: Bool) {
        let fiveMinutes = DateInterval(start: base, duration: 300)
        let readings = (0..<count).map { reading(at: Double($0) * 25, 110) }

        let judged = VitalsEvidence.judge(heartRate: readings, energy: [], window: fiveMinutes)

        #expect(judged.averageHeartRate == (accepted ? 110 : nil))
    }

    @Test func onlyTheWristsEnergyAcrossTheSessionCountsAndARefusalCostsTheHeartRateNothing() {
        let pedometer = [slice(from: 0, for: 3_600, kcal: 200, wrist: false)]
        #expect(VitalsEvidence.judge(heartRate: [], energy: pedometer, window: hour).activeEnergyKcal == nil)

        let wrist = [slice(from: 0, for: 900, kcal: 90, wrist: true), slice(from: 900, for: 900, kcal: 110, wrist: true),
                     slice(from: 1_800, for: 900, kcal: 100, wrist: true)]
        #expect(VitalsEvidence.judge(heartRate: [], energy: wrist + pedometer, window: hour).activeEnergyKcal == 300)

        // Two minutes of energy don't stand for an hour.
        let brief = [slice(from: 0, for: 120, kcal: 12, wrist: true)]
        #expect(VitalsEvidence.judge(heartRate: [], energy: brief, window: hour).activeEnergyKcal == nil)

        let trace = [slice(from: 0, for: 3_600, kcal: 0.6, wrist: true)]
        #expect(VitalsEvidence.judge(heartRate: [], energy: trace, window: hour).activeEnergyKcal == nil)

        let dense = (0..<720).map { reading(at: Double($0) * 5, 100 + Double($0 % 60)) }
        #expect(VitalsEvidence.judge(heartRate: dense, energy: pedometer, window: hour).averageHeartRate != nil)
        #expect(VitalsEvidence.judge(heartRate: dense, energy: [], window: DateInterval(start: base, duration: 0))
                == VitalsEvidence())
    }
}
