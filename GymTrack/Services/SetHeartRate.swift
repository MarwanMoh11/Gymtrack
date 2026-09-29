import Foundation
import SwiftData

// MARK: - What a set's heart rate was read off

/// Where a set's heart rate window came from.
///
/// The distinction is the whole reason this type exists. A set whose start was
/// announced has a real window and the numbers over it are a measurement; a set
/// without one has a window this app worked out, and a reader who can't tell
/// the two apart will treat both as fact. Worked out comes in two grades — read
/// off this set's own climb in heart rate, or assumed from its rep count — and
/// those are kept apart for the same reason. Carried beside every attributed
/// number, all the way into the backup.
enum HeartRateWindowSource: String, Sendable {
    /// `startedAt` to `completedAt` — both ends are moments somebody marked.
    case measured
    /// From where the heart rate climbed out of the rest to where it levelled
    /// off. Nobody marked either end; the trace drew them, which is more than a
    /// rep count can say and less than a tap. See `SetEffortDetection`.
    case detected
    /// The tail of the gap before the set was logged. See
    /// `SetTiming.assumedDuration`.
    case inferred
}

/// One heart-rate reading, as plain values.
///
/// Deliberately not an `HKQuantitySample`: the windowing below is the part of
/// this feature most likely to be wrong, and keeping it over ordinary structs
/// means it can be exercised with made-up samples on any machine, without
/// HealthKit, a watch, or a granted permission.
struct HeartRateSample: Equatable, Sendable {
    let start: Date
    let end: Date
    let bpm: Double

    init(start: Date, end: Date, bpm: Double) {
        self.start = start
        self.end = end
        self.bpm = bpm
    }

    /// Most watch readings are a single instant.
    init(at moment: Date, bpm: Double) {
        self.init(start: moment, end: moment, bpm: bpm)
    }
}

/// The stretch of time a set's heart rate is read from.
struct HeartRateWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    let source: HeartRateWindowSource

    /// Whether a reading falls in this window.
    ///
    /// A sample counts when its own interval touches the window at all. Watch
    /// heart-rate samples are almost always instantaneous, so this is usually
    /// just "is this moment inside" — but a sample recorded across a short
    /// interval that begins in the rest and ends inside the set is still
    /// evidence about the set, and dropping it because one end fell outside
    /// would quietly thin out exactly the short windows that can least afford
    /// it. Both ends are inclusive, so a reading landing precisely on the
    /// boundary between two sets is credited to both rather than to neither.
    func contains(_ sample: HeartRateSample) -> Bool {
        sample.end >= start && sample.start <= end
    }
}

/// What a set's heart rate turned out to be.
struct SetHeartRate: Equatable, Sendable {
    let average: Double
    let peak: Double
    let source: HeartRateWindowSource
}

/// One set reduced to the facts that decide its window.
struct SetTiming: Equatable, Sendable {
    let id: UUID
    /// When the lifter said they were starting, if they said so.
    let startedAt: Date?
    /// When the set was logged. A set without this has no window at all and
    /// never reaches here.
    let completedAt: Date
    let reps: Int
    /// The hold, for a duration-tracked set. Zero for everything else.
    let heldSeconds: Int
    /// Where the heart rate showed this set began and ended, where an earlier
    /// pass read one off the trace. Believed after an announced start and
    /// before the assumed tail — see `SetHeartRateAttribution.window(for:after:)`.
    let detected: DetectedSetWindow?

    init(id: UUID, startedAt: Date?, completedAt: Date, reps: Int, heldSeconds: Int,
         detected: DetectedSetWindow? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.reps = reps
        self.heldSeconds = heldSeconds
        self.detected = detected
    }

    /// How long this set probably lasted, for the case where nobody said.
    ///
    /// A duration-tracked set already carries its own length — the lifter typed
    /// how long they held it — so that number is used as it stands. Everything
    /// else is estimated at three seconds a rep, which is a rep at an ordinary
    /// tempo, and then held between fifteen seconds and a minute and a half:
    /// below that a heavy single would get a window too short to catch a single
    /// reading, and above it the "set" would be long enough to be mostly rest
    /// again, which is the thing this whole approach exists to avoid.
    ///
    /// It is an estimate and it is wrong. It is allowed to be, because nothing
    /// derived from it is ever reported as measured.
    var assumedDuration: TimeInterval {
        if heldSeconds > 0 { return TimeInterval(heldSeconds) }
        return min(90, max(15, TimeInterval(reps) * 3))
    }
}

// MARK: - Reading the set off the heart rate

/// Where a set began and ended, as the heart rate told it.
///
/// A reading and not a stamp: nobody marked either end. That is why it is its
/// own type rather than a `startedAt` — the one field a reader is entitled to
/// treat as somebody having said so — and why everything read through it is
/// labelled `.detected`.
struct DetectedSetWindow: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Finding the set inside the gap before it was logged.
///
/// Most sets are never announced, so the gap from the previous set being logged
/// to this one is rest and set run together. The heart rate usually draws the
/// line between them plainly: flat or falling through the rest, then one climb
/// that starts within a beat or two of the first rep and levels off as the bar
/// goes back. This reads that climb, after the session, from the trace the
/// watch already recorded — the lifter is asked for nothing.
///
/// It reads it only where there is exactly one. Every rule below that gives up
/// is a trace that could be read two ways, and a window placed confidently on
/// the wrong effort is worse than the tail estimate it would replace, because
/// it would travel into the record labelled as read off this set.
enum SetEffortDetection {

    /// Fewer readings than this can't show a rest and a climb out of it: two
    /// for the floor, two for the rise, and any fewer leaves a single noisy
    /// beat carrying the whole story.
    static let minimumSamples = 4

    /// The smallest climb read as an effort, in beats per minute. A wrist
    /// reading wanders by a handful of beats standing still, and walking to the
    /// water or loading plates moves it more; twelve clears both and is still
    /// below what a light set of curls costs. The same number decides whether
    /// the gap holds a second effort, because a swing big enough to count as
    /// this set is, by the same measure, big enough to count as another one.
    static let minimumRise: Double = 12

    /// How far up the climb the set is taken to have already begun, as a share
    /// of the climb. Heart rate answers the first rep within a beat or two, so
    /// the last reading still near the floor of the rest is the last one from
    /// before the set. A fifth steps over the rest's wander without reaching
    /// into the set.
    static let onsetFraction = 0.2

    /// How near the top the climb counts as finished — a tenth of the climb,
    /// never less than `plateauLeeway`. Heart rate keeps creeping for a few
    /// seconds after the bar is racked, so the literal highest reading lands
    /// after the set; the first reading on the plateau is nearer the moment
    /// the work stopped.
    static let plateauFraction = 0.1

    /// The least room given to "near the top", in beats per minute, so a small
    /// climb doesn't demand its exact peak back beat for beat before it counts
    /// as levelled off.
    static let plateauLeeway: Double = 2

    /// The shortest window believed. Under five seconds is a single rep at
    /// best, and a climb that steep between two readings is likelier a sensor
    /// glitch than a set.
    static let shortestSet: TimeInterval = 5

    /// The longest window believed. Three minutes covers a long hold or a set
    /// of twenty; a climb slower than that is a warm-up walk, a drift through a
    /// long rest, or two sets run together, and none of those is this set.
    static let longestSet: TimeInterval = 180

    /// The longest silence tolerated between readings across the climb. A
    /// watch in a workout reads every few seconds; a longer gap means it
    /// dropped readings there, and the moment the climb began could be
    /// anywhere inside it — the midpoint would be a guess dressed as a reading.
    static let longestSampleGap: TimeInterval = 15

    /// How long after the previous set was logged its own climb may still be
    /// going. A lifter who logs as the bar goes back logs before their heart
    /// rate has peaked — it goes on rising for several seconds, easily by more
    /// than `minimumRise` after a hard set — so the top of nearly every gap is
    /// the last set still climbing. Read as it stands, that climb is a second
    /// effort beside this set's, and the gap would be given up as ambiguous on
    /// exactly the sessions where the lifter logs promptly.
    static let previousSetSettling: TimeInterval = 30

    /// The set inside the gap from `lowerBound` to `completedAt`, or `nil`
    /// wherever the trace doesn't show one effort plainly.
    ///
    /// The effort is the largest climb in the gap, from the lowest point of the
    /// rest to the highest the set reached. It is refused when the gap holds
    /// another climb of the same size before or after it, or a fall of that
    /// size inside it: those are two efforts, which is what batch-logging three
    /// sets at the end looks like, and handing the first set the biggest of
    /// them would give it somebody else's work.
    ///
    /// The start is placed between the last reading still near the floor and
    /// the first one clear of it, since the set began somewhere in between. The
    /// end is the first reading on the plateau, not the log — a set logged a
    /// minute after it was racked still ended when it was racked.
    static func window(in samples: [HeartRateSample],
                       after lowerBound: Date,
                       loggedAt completedAt: Date) -> DetectedSetWindow? {
        guard lowerBound < completedAt else { return nil }
        // A heart rate of zero is a dropped reading, and would read as the
        // deepest floor of any rest in the gap.
        let gap = samples
            .filter { $0.bpm > 0 && $0.start >= lowerBound && $0.start <= completedAt }
            .sorted { $0.start < $1.start }
        // The gap is read from the top of the previous set's climb, wherever
        // that landed in its first seconds. See `previousSetSettling`.
        let settled = lowerBound.addingTimeInterval(previousSetSettling)
        let settlingPeak = gap.indices
            .filter { gap[$0].start <= settled }
            .max { gap[$0].bpm < gap[$1].bpm } ?? gap.startIndex
        let trace = Array(gap[settlingPeak...])
        guard trace.count >= minimumSamples else { return nil }
        let beats = trace.map(\.bpm)

        guard let climb = largestRise(in: beats[...]), climb.rise >= minimumRise else { return nil }
        // Read from a peak, a gap holds a rest only if the heart rate came down
        // off it before climbing again. A climb straight out of the first
        // reading is a set begun inside the previous one's settling, and the
        // highest of those seconds is already partway up this set — its start
        // would land late, with nothing in the trace to say so.
        guard climb.trough > 0 else { return nil }
        let isOnlyEffort = (largestRise(in: beats[...climb.trough])?.rise ?? 0) < minimumRise
            && (largestRise(in: beats[climb.peak...])?.rise ?? 0) < minimumRise
            && largestFall(in: beats[climb.trough...climb.peak]) < minimumRise
        guard isOnlyEffort else { return nil }

        let floor = beats[climb.trough] + climb.rise * onsetFraction
        guard let onset = (climb.trough..<climb.peak).last(where: { beats[$0] <= floor }) else { return nil }
        let start = midpoint(trace[onset].start, trace[onset + 1].start)

        let plateau = beats[climb.peak] - max(plateauLeeway, climb.rise * plateauFraction)
        guard let finish = ((onset + 1)...climb.peak).first(where: { beats[$0] >= plateau }) else { return nil }
        let end = min(trace[finish].start, completedAt)

        let length = end.timeIntervalSince(start)
        guard length >= shortestSet, length <= longestSet else { return nil }
        let isContinuous = (onset..<finish).allSatisfy {
            trace[$0 + 1].start.timeIntervalSince(trace[$0].start) <= longestSampleGap
        }
        guard isContinuous else { return nil }

        return DetectedSetWindow(start: start, end: end)
    }

    /// The biggest climb in `beats`: the earlier and later index with the most
    /// gained between them, and how much. `nil` where nothing climbs at all.
    private static func largestRise(in beats: ArraySlice<Double>) -> (trough: Int, peak: Int, rise: Double)? {
        guard var low = beats.indices.first else { return nil }
        var best: (trough: Int, peak: Int, rise: Double)?
        for index in beats.indices.dropFirst() {
            let rise = beats[index] - beats[low]
            if rise > (best?.rise ?? 0) { best = (low, index, rise) }
            if beats[index] < beats[low] { low = index }
        }
        return best
    }

    /// The biggest fall in `beats`, from any reading to a later one.
    private static func largestFall(in beats: ArraySlice<Double>) -> Double {
        guard var high = beats.first else { return 0 }
        var fall = 0.0
        for bpm in beats {
            fall = max(fall, high - bpm)
            high = max(high, bpm)
        }
        return fall
    }

    private static func midpoint(_ a: Date, _ b: Date) -> Date {
        a.addingTimeInterval(b.timeIntervalSince(a) / 2)
    }
}

// MARK: - Attribution

/// Splitting a session's heart-rate samples across its sets.
///
/// Every number here is derived from stamps the sets already carried and
/// samples the watch already recorded. The lifter is asked for nothing: this
/// runs when a session is written to Health and again whenever it is opened,
/// and a session where nobody touched anything still comes out with a heart
/// rate on every set.
enum SetHeartRateAttribution {

    /// The window a set's heart rate should be read from, or `nil` when there
    /// isn't one worth reading.
    ///
    /// Three cases, believed in this order, and the difference between them is
    /// the point:
    ///
    /// * **Announced.** `startedAt` to `completedAt` is the set and only the
    ///   set. A start is believed only where it falls inside the interval it
    ///   claims to split — not before the previous set was logged, and before
    ///   this one was — the rule `WorkoutSession.gapsWithProvenance` already
    ///   applies to the same stamp for the same reason. A stamp
    ///   outside that is a clock moved or a backup carried across timezones,
    ///   and a window running backwards would attribute somebody else's beats
    ///   with total confidence.
    /// * **Detected.** Nobody announced a start, but the heart rate showed one:
    ///   a single climb out of the rest, read off the trace by
    ///   `SetEffortDetection` and kept on the set. The window is that climb,
    ///   from where it left the rest to where it levelled off, so a set logged
    ///   a minute after it was racked doesn't average that minute of recovery
    ///   in. It is held to the announced start's rule — inside the gap it
    ///   claims to split or not at all. Better than the estimate below because
    ///   it was read off this set rather than off sets in general; not a
    ///   measurement, because nobody marked either end.
    /// * **Neither.** All that is known is the gap from the previous set
    ///   being logged, and that gap is the rest *plus* the set. Handing the
    ///   whole of it to the set would average two minutes of standing around
    ///   into a number labelled "this set", and on a normal session the rest is
    ///   the larger half — the reported heart rate would mostly describe
    ///   recovery. So the window is the *tail* of the gap: the assumed length
    ///   of the set, ending at the moment it was logged, since a set finishes
    ///   when it is logged and not before. It never reaches back past the
    ///   previous set, so a drop set logged twenty seconds apart gets a
    ///   twenty-second window rather than one overlapping the set before it.
    ///
    /// Refusing to attribute anything without an announced start was the other
    /// candidate, and it is the more conservative one. It was not taken because
    /// it would make per-set heart rate cost a tap per set, and a feature in
    /// this app that costs taps is a feature nobody has. The honesty that
    /// refusal buys is bought instead by `HeartRateWindowSource`, which travels
    /// with the numbers into the record and the file: neither kind of window
    /// this app worked out is ever presented, drawn or exported as a measured
    /// one, or as each other.
    static func window(for set: SetTiming, after previous: Date?) -> HeartRateWindow? {
        let lowerBound = previous ?? .distantPast

        if let announced = set.startedAt,
           announced < set.completedAt,
           announced >= lowerBound {
            return HeartRateWindow(start: announced, end: set.completedAt, source: .measured)
        }

        if let detected = set.detected,
           detected.start >= lowerBound,
           detected.start < detected.end,
           detected.end <= set.completedAt {
            return HeartRateWindow(start: detected.start, end: detected.end, source: .detected)
        }

        let assumedStart = set.completedAt.addingTimeInterval(-set.assumedDuration)
        let start = max(assumedStart, lowerBound)
        // A set logged at the same instant as the one before it — a double tap,
        // a restored backup with duplicated stamps — has no window at all, and
        // an empty one would read every sample on its boundary as this set's.
        guard start < set.completedAt else { return nil }
        return HeartRateWindow(start: start, end: set.completedAt, source: .inferred)
    }

    /// Every set's window, in the order the sets were logged.
    ///
    /// Computed together rather than one set at a time because each window
    /// needs to know where the one before it ended, and because the samples are
    /// fetched once for the whole session and partitioned — one HealthKit query
    /// per set would be dozens of round trips for a record that arrives all at
    /// once anyway.
    static func windows(for sets: [SetTiming], sessionStart: Date?) -> [(id: UUID, window: HeartRateWindow)] {
        gaps(of: sets, sessionStart: sessionStart).compactMap { set, previous in
            window(for: set, after: previous).map { (set.id, $0) }
        }
    }

    /// Where the heart rate shows each of `candidates` began and ended, for
    /// the ones whose trace shows it plainly.
    ///
    /// Which sets are owed a reading is the caller's to say — the stored ones
    /// know whether a start was announced and whether they continue the row
    /// above — but every set bounds the gap of the one after it, so all of
    /// them are walked.
    static func detectedWindows(samples: [HeartRateSample],
                                for sets: [SetTiming],
                                sessionStart: Date?,
                                candidates: Set<UUID>) -> [UUID: DetectedSetWindow] {
        guard !candidates.isEmpty else { return [:] }
        var result: [UUID: DetectedSetWindow] = [:]
        for (set, previous) in gaps(of: sets, sessionStart: sessionStart) where candidates.contains(set.id) {
            let found = SetEffortDetection.window(in: samples,
                                                  after: previous ?? .distantPast,
                                                  loggedAt: set.completedAt)
            if let found { result[set.id] = found }
        }
        return result
    }

    /// Each set in the order it was logged, beside the moment its gap opened:
    /// the latest log before it, or the session's start for the first.
    ///
    /// One walk shared by the windows and the detection, so the two can't
    /// disagree about where a set's gap begins.
    private static func gaps(of sets: [SetTiming], sessionStart: Date?) -> [(set: SetTiming, previous: Date?)] {
        var previous = sessionStart
        var result: [(set: SetTiming, previous: Date?)] = []
        for set in sets.sorted(by: { $0.completedAt < $1.completedAt }) {
            result.append((set, previous))
            previous = max(previous ?? set.completedAt, set.completedAt)
        }
        return result
    }

    /// The heart rate of each set, for the sets that have one.
    ///
    /// A set with no readings in its window is simply absent from the result.
    /// Nothing is written for it — not a zero, not a null with a number's
    /// shape. A set the watch wasn't there for has to be indistinguishable from
    /// a set logged before this feature existed, because that is what it is.
    static func attribute(samples: [HeartRateSample],
                          to sets: [SetTiming],
                          sessionStart: Date?) -> [UUID: SetHeartRate] {
        readings(samples: samples, to: sets, sessionStart: sessionStart).mapValues { $0.heartRate }
    }

    /// `attribute`, with how many readings each set's numbers were read from.
    /// The count is what decides whether a later pass may replace them; see
    /// `updates(samples:sets:sessionStart:)`.
    static func readings(samples: [HeartRateSample],
                         to sets: [SetTiming],
                         sessionStart: Date?) -> [UUID: (heartRate: SetHeartRate, samples: Int)] {
        // A heart rate of zero is a dropped reading, not a stopped heart. Left
        // in it would drag an average down to a number no one's chest ever did.
        let usable = samples.filter { $0.bpm > 0 }.sorted { $0.start < $1.start }
        guard !usable.isEmpty else { return [:] }

        var result: [UUID: (heartRate: SetHeartRate, samples: Int)] = [:]
        for (id, window) in windows(for: sets, sessionStart: sessionStart) {
            let inWindow = usable.filter(window.contains)
            guard !inWindow.isEmpty else { continue }
            let beats = inWindow.map(\.bpm)
            let heartRate = SetHeartRate(
                average: beats.reduce(0, +) / Double(beats.count),
                peak: beats.max() ?? 0,
                source: window.source
            )
            result[id] = (heartRate, beats.count)
        }
        return result
    }

    /// What one pass over `samples` should write, set by set.
    ///
    /// A pass runs when the session is written to Health and again whenever
    /// it is opened, because the watch's samples reach the phone late: a
    /// minute late in the ordinary case, and not until the phone is next
    /// unlocked when it finished the session in a bag. So a pass can find a
    /// set it already read off a trace that stopped partway through it: a
    /// detected window that ends where the synced data happened to end, or an
    /// average over the one early beat that had arrived. Filling a set once and
    /// never again froze those.
    ///
    /// A reading is replaced only by one read from strictly more samples, and
    /// only where this phone remembers how many the first was read from (see
    /// `SetHeartRateLedger`). More of the set's own beats is the one thing that
    /// makes a second reading better than the first. A different window over
    /// the same number of beats is just a second opinion, and letting it win
    /// would make the record depend on how often somebody opened the session.
    /// A reading with no remembered count came from a backup, an older build
    /// or a pass long enough ago that everything had synced, and is left
    /// alone because there is nothing to beat.
    ///
    /// A detected window travels with the reading taken through it and is
    /// never written without one, so the window on a set is always the one its
    /// numbers describe.
    static func updates(samples: [HeartRateSample],
                        sets: [StoredSetHeartRate],
                        sessionStart: Date?) -> [SetHeartRateUpdate] {
        let open = sets.filter(\.isOpen)
        guard !open.isEmpty else { return [] }

        let found = detectedWindows(samples: samples, for: sets.map(\.timing), sessionStart: sessionStart,
                                    candidates: Set(open.filter(\.mayDetect).map(\.timing.id)))
        // A trace that no longer shows one plain effort keeps the window an
        // earlier pass read, rather than dropping to the assumed tail and
        // trading a reading for a guess on the strength of a count.
        let proposed = sets.map { stored in
            found[stored.timing.id].map { stored.timing.reading(through: $0) } ?? stored.timing
        }
        let read = readings(samples: samples, to: proposed, sessionStart: sessionStart)

        return open.compactMap { stored in
            let id = stored.timing.id
            guard let reading = read[id],
                  mayReplace(hasReading: stored.hasReading, readFrom: stored.readFrom, samples: reading.samples)
            else { return nil }
            let window = reading.heartRate.source == .detected ? found[id] : nil
            return SetHeartRateUpdate(id: id, heartRate: reading.heartRate, detected: window,
                                      samples: reading.samples)
        }
    }

    /// Whether a reading from `samples` readings may be written over what a
    /// set carries. Always, on a set with none; on a set with one, only where
    /// its count is remembered and beaten outright.
    static func mayReplace(hasReading: Bool, readFrom: Int?, samples: Int) -> Bool {
        guard hasReading else { return true }
        guard let readFrom else { return false }
        return samples > readFrom
    }
}

// MARK: - Coming back for more

/// A set as a later pass finds it: its timing, and what it already carries.
struct StoredSetHeartRate: Equatable, Sendable {
    let timing: SetTiming
    let hasReading: Bool
    /// How many readings its heart rate was read from, where a pass on this
    /// phone wrote it recently enough to remember. `nil` everywhere else.
    let readFrom: Int?
    /// Whether its window may be looked for in the trace: nobody announced its
    /// start and it continues no row above it. The seconds into a drop's
    /// back-off row are plates coming off mid-effort, with no rest for the
    /// heart rate to climb out of.
    let mayDetect: Bool

    /// Whether a pass may write to it at all: it has no reading yet, or one
    /// this phone read and could still improve on.
    var isOpen: Bool { !hasReading || readFrom != nil }
}

/// What one pass writes to one set.
struct SetHeartRateUpdate: Equatable, Sendable {
    let id: UUID
    let heartRate: SetHeartRate
    /// The window read off the trace in this pass, where the reading was taken
    /// through it. `nil` when the reading used whatever window the set had.
    let detected: DetectedSetWindow?
    /// How many readings `heartRate` was read from.
    let samples: Int
}

extension SetTiming {
    /// The same set, read through a window found in the trace.
    func reading(through detected: DetectedSetWindow) -> SetTiming {
        SetTiming(id: id, startedAt: startedAt, completedAt: completedAt, reps: reps,
                  heldSeconds: heldSeconds, detected: detected)
    }
}

/// How many readings each recent set's heart rate was read from, on this phone.
///
/// The count decides whether a later pass may replace a reading, and it is
/// not kept on the set: there it would travel into the export as though it
/// described the lift, when it describes one pass on one phone. It is held for
/// two days, long after a watch's samples have all reached the phone, and then
/// forgotten, which closes the sets it covered to any further pass.
struct SetHeartRateLedger {
    private struct Entry: Codable {
        var set: UUID
        var samples: Int
        var at: Date
    }

    static let key = "health.setHeartRateSamples"
    static let keptFor: TimeInterval = 2 * 24 * 60 * 60
    /// A heavy week of long sessions, several times over.
    static let limit = 600

    let defaults: UserDefaults

    /// The remembered count for every set read in the last two days.
    func samples(now: Date = .now) -> [UUID: Int] {
        Dictionary(entries(now: now).map { ($0.set, $0.samples) }, uniquingKeysWith: { _, latest in latest })
    }

    func record(_ counts: [UUID: Int], now: Date = .now) {
        guard !counts.isEmpty else { return }
        var kept = entries(now: now).filter { counts[$0.set] == nil }
        kept += counts.map { Entry(set: $0.key, samples: $0.value, at: now) }
        guard let data = try? JSONEncoder().encode(Array(kept.suffix(Self.limit))) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private func entries(now: Date) -> [Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        let cutoff = now.addingTimeInterval(-Self.keptFor)
        return entries.filter { $0.at >= cutoff }
    }
}

// MARK: - The workout's activities, in the order they happened

/// One logged set, reduced to what places it in the workout's timeline.
struct ActivitySetStamp: Equatable, Sendable {
    let id: UUID
    /// The exercise's catalogue ID. Two sets belong to one activity only where
    /// this matches and nothing else was logged between them.
    let exercise: String
    let startedAt: Date?
    let completedAt: Date
}

/// A stretch of the workout spent on one exercise.
struct WorkoutActivityRun: Equatable, Sendable {
    let exercise: String
    /// The run's sets, in the order they were logged.
    let setIDs: [UUID]
    let start: Date
    let end: Date
}

/// Cutting a finished session into the activities Health shows inside it.
///
/// Read off when the sets were logged, not off the plan. A lifter who finds
/// the bench taken squats first, and one who goes back for a missed set at the
/// end, did the session in that order; walking the plan's order instead gave
/// the first exercise everything up to its last set and left no room for the
/// ones in between, which vanished from Health. Consecutive sets of one
/// exercise are one run, so a superset becomes an activity per round and a
/// make-up set its own short one at the end.
enum WorkoutActivitySegmentation {

    /// The runs, in order, never overlapping, all inside the session.
    ///
    /// A run ends when its last set was logged, which is measured. It begins
    /// where the run before it ended, since the only thing known about the
    /// time between two logs is that it went to the next set, rest included.
    /// An announced start is believed instead where it falls inside that gap,
    /// because then somebody said when the exercise began. A run with no length
    /// left, two exercises logged at the same instant, has no interval Health
    /// could show honestly and is left out; its sets still count in the
    /// workout's totals.
    static func runs(of sets: [ActivitySetStamp], sessionStart: Date, sessionEnd: Date) -> [WorkoutActivityRun] {
        // Ties keep the caller's order, which is the session's.
        let ordered = sets.enumerated()
            .sorted { ($0.element.completedAt, $0.offset) < ($1.element.completedAt, $1.offset) }
            .map(\.element)

        var groups: [[ActivitySetStamp]] = []
        for set in ordered {
            if let last = groups.last?.last, last.exercise == set.exercise {
                groups[groups.count - 1].append(set)
            } else {
                groups.append([set])
            }
        }

        var boundary = sessionStart
        var result: [WorkoutActivityRun] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let end = min(sessionEnd, last.completedAt)
            var start = boundary
            if let announced = first.startedAt, announced >= boundary, announced < first.completedAt {
                start = announced
            }
            boundary = max(boundary, end)
            guard end > start else { continue }
            result.append(WorkoutActivityRun(exercise: first.exercise, setIDs: group.map(\.id),
                                             start: start, end: end))
        }
        return result
    }
}

// MARK: - Deciding what to write and what to remove

/// The choices `HealthKitService` makes about duplicate workouts, held apart
/// from HealthKit so they can be checked without a Health store. The service
/// keeps every `HKHealthStore` call; it asks these what to do with the answers.
///
/// A second workout for one session inflates the lifter's Health totals and
/// double-counts the session for anything reading them, and a leftover after a
/// delete is a workout no screen in the app can find. Both were fixed once by
/// reading the service; nothing could hold the fix in place.
enum PhoneWorkoutWrite {

    /// Whether a session may be written to Health at all: not gone, and not
    /// already linked to a workout, since the watch's measured one is the
    /// record and a second would double it.
    static func shouldWrite(sessionGone: Bool, linkedWorkoutID: UUID?) -> Bool {
        !sessionGone && linkedWorkoutID == nil
    }

    /// What to do with a workout the phone has just finished writing.
    enum Outcome: Equatable {
        /// Health returned nothing to keep.
        case nothing
        /// The session was removed during the write, so no record points at the
        /// workout. It goes on the cleanup list, its own ID as the successor
        /// since there is no session to relink.
        case removeAsOrphan
        /// A watch workout linked itself while the phone was writing. The
        /// measured one stays and the phone's copy is queued for removal.
        case removeAsDuplicate(keeping: UUID)
        /// Nothing else claimed the session: the phone's workout becomes its link.
        case link
    }

    /// `linkedWorkoutID` is read after the last await, since that is when a
    /// watch can have landed. The session's absence is checked before the
    /// link, because a gone session cannot be relinked to anything.
    static func outcome(written: UUID?, sessionGone: Bool, linkedWorkoutID: UUID?) -> Outcome {
        guard written != nil else { return .nothing }
        if sessionGone { return .removeAsOrphan }
        if let linkedWorkoutID { return .removeAsDuplicate(keeping: linkedWorkoutID) }
        return .link
    }
}

/// Whether the session an entry names still needs its link moved before the old
/// workout is removed. Nothing to move for an entry with no successor, a
/// session that is gone, or one already pointing somewhere else: rewriting
/// that link would undo a later, correct one.
enum CleanupRelink {
    static func isNeeded(preferredWorkoutID: UUID?, sessionFound: Bool,
                         sessionLink: UUID?, workoutID: UUID) -> Bool {
        guard preferredWorkoutID != nil, sessionFound else { return false }
        return sessionLink == workoutID
    }
}

/// How a request to work through the cleanup list is coalesced. A request that
/// arrives while a pass runs is not dropped, because it may be the entry that
/// pass has already read past, and it does not start a second pass on top of
/// the first, whose deletes could then race for one workout.
struct CleanupPassGate: Equatable {
    private(set) var inFlight = false
    private(set) var requested = false

    /// True when the caller should run a pass now. False records the request
    /// for the running pass to pick up.
    mutating func begin() -> Bool {
        guard !inFlight else {
            requested = true
            return false
        }
        inFlight = true
        return true
    }

    /// Called at the top of each pass. Only a request made after this point
    /// asks for another one.
    mutating func startPass() { requested = false }

    /// Whether a request arrived during the pass that just ran.
    var wantsAnotherPass: Bool { requested }

    mutating func end() { inFlight = false }
}

/// Which of a batch of workout IDs may be deleted, given what Health found.
enum WorkoutDeletionPlan: Equatable {

    /// One workout Health returned for the query.
    struct Found: Equatable {
        let id: UUID
        /// Written by this app or its watch app. Health fails a whole batch
        /// that holds one sample it refuses, and another app's workout is not
        /// ours to remove, so anything else stays out of the delete.
        let ours: Bool
    }

    /// `ids` once each, in the order first given.
    static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// The found workouts that go into the delete.
    static func toDelete(found: [Found]) -> [UUID] { found.filter(\.ours).map(\.id) }

    /// The IDs still in Health afterwards, in the order asked for. IDs the
    /// query could not find count as gone; a found workout that is not ours
    /// stays; and if the batch delete was refused nothing was removed, so
    /// every found ID stays.
    static func remaining(wanted: [UUID], found: [Found], deleteFailed: Bool) -> [UUID] {
        let stays = deleteFailed ? Set(found.map(\.id)) : Set(found.filter { !$0.ours }.map(\.id))
        return wanted.filter { stays.contains($0) }
    }
}

// MARK: - Giving up on a delete Health keeps refusing

/// How long the cleanup list keeps trying to remove a workout, and what it
/// remembers of the ones it stopped on.
///
/// A delete that failed used to be tried again at every foreground for as long
/// as the app stayed installed, silently. A workout Health will never let go
/// of, say one another app owns or one whose write permission was withdrawn,
/// is then asked about forever and nobody is told. The list now stops after
/// `cap` failures and keeps the IDs it stopped on, so Settings can say so and
/// offer to try again.
struct CleanupAttemptLedger: Codable, Equatable {
    /// Failed deletes, on separate occasions, before the list stops trying.
    static let cap = 5
    /// Passes arrive in bursts: an entry added, a foreground and a fresh
    /// authorization can land within the same minute. Failures closer together
    /// than this count once, so the cap measures occasions and not calls; five
    /// calls in a row would give up on a workout that had never had a real
    /// second chance.
    static let minimumSpacing: TimeInterval = 15 * 60
    /// The most given-up workouts kept. Older ones are forgotten, since an
    /// endless list is a notice nobody can act on.
    static let remembered = 50

    /// A workout with failed deletes that has not yet reached the cap.
    struct Struggling: Codable, Equatable {
        var workoutID: UUID
        var failures: Int
        var lastFailureAt: Date
    }

    /// A workout the list stopped trying to remove.
    struct GivenUp: Codable, Equatable {
        var workoutID: UUID
        var sessionID: UUID
        var at: Date
    }

    /// What one delete attempt came to.
    enum Outcome: Equatable {
        /// Health no longer holds the workout, whether this call removed it or
        /// it was not there.
        case gone
        /// Health, or the permission behind it, said no.
        case refused
        /// Health could not be asked, because a locked phone keeps its
        /// database closed. Not the workout's fault: it costs no attempt and
        /// is retried when the phone unlocks.
        case deferred
    }

    private(set) var struggling: [Struggling] = []
    private(set) var givenUp: [GivenUp] = []

    /// Notes one delete attempt, and returns whether the entry should now
    /// leave the cleanup list: because the workout is gone, or because the
    /// list has stopped trying and it is kept in `givenUp` instead.
    mutating func record(_ outcome: Outcome, workoutID: UUID, sessionID: UUID, at now: Date) -> Bool {
        switch outcome {
        case .gone:
            struggling.removeAll { $0.workoutID == workoutID }
            givenUp.removeAll { $0.workoutID == workoutID }
            return true
        case .deferred:
            return false
        case .refused:
            var entry = struggling.first { $0.workoutID == workoutID }
                ?? Struggling(workoutID: workoutID, failures: 0, lastFailureAt: .distantPast)
            if now.timeIntervalSince(entry.lastFailureAt) >= Self.minimumSpacing {
                entry.failures += 1
                entry.lastFailureAt = now
            }
            struggling.removeAll { $0.workoutID == workoutID }
            guard entry.failures >= Self.cap else {
                struggling.append(entry)
                return false
            }
            givenUp.removeAll { $0.workoutID == workoutID }
            givenUp.append(GivenUp(workoutID: workoutID, sessionID: sessionID, at: now))
            if givenUp.count > Self.remembered { givenUp.removeFirst(givenUp.count - Self.remembered) }
            return true
        }
    }

    /// Takes the given-up workouts back for one more attempt each, and returns
    /// them to be queued again.
    ///
    /// They come back one failure short of the cap. A single refusal then
    /// gives up on them again straight away, so a Retry that changes nothing
    /// leaves the notice standing instead of hiding it while the list quietly
    /// tries another five times.
    mutating func reopen() -> [GivenUp] {
        let reopened = givenUp
        givenUp = []
        for item in reopened {
            struggling.removeAll { $0.workoutID == item.workoutID }
            struggling.append(Struggling(workoutID: item.workoutID, failures: Self.cap - 1,
                                         lastFailureAt: .distantPast))
        }
        return reopened
    }
}

// MARK: - Energy the wrist recorded, counted once

/// One slice of active energy Health held inside a session's window, with
/// enough about its source to decide whether the wrist wrote it.
struct EnergySlice: Equatable, Sendable {
    var start: Date
    var end: Date
    var kilocalories: Double
    /// The bundle identifier of the app or device that wrote the slice.
    var sourceID: String
    var isFromWrist: Bool
}

/// The energy a session may keep from Health: the total and the stretch of
/// the window it was measured over.
struct WristEnergy: Equatable, Sendable {
    var start: Date
    var end: Date
    var kilocalories: Double
}

/// The pure part of reading a session's energy from Health.
///
/// The slices were once added up here, which counted twice whatever two watch
/// apps both wrote for the same minutes: the Workout app and a third-party one
/// running side by side. Health's cumulative-sum statistics de-duplicate
/// overlapping sources by the user's priority order, so the total comes from
/// there. What stays here is which sources that sum may draw on, because the
/// same query over every source would also include the energy an iPhone
/// estimates from its step count, and that is not a measurement of a workout.
enum WristEnergyRead {

    /// The sources whose slices were all written on the wrist. A source that
    /// also wrote a slice from something else is left out entirely: the sum
    /// can only be asked of whole sources, and a total that might include
    /// pedometer energy would be inferred data filed as measured.
    static func trustedSources(in slices: [EnergySlice]) -> Set<String> {
        let counted = slices.filter { $0.kilocalories > 0 }
        let wrist = Set(counted.filter(\.isFromWrist).map(\.sourceID))
        let other = Set(counted.filter { !$0.isFromWrist }.map(\.sourceID))
        return wrist.subtracting(other)
    }

    /// What to keep given the slices, the sources trusted, and the cumulative
    /// sum Health answered for them. Nil for no measurement: no trusted slice,
    /// no answer, or a total that is zero or worse. A session with nothing to
    /// report stores no key at all.
    static func result(slices: [EnergySlice], trusted: Set<String>, cumulativeSum: Double?) -> WristEnergy? {
        let kept = slices.filter { trusted.contains($0.sourceID) && $0.kilocalories > 0 }
        guard let sum = cumulativeSum, sum.isFinite, sum > 0,
              let first = kept.map(\.start).min(), let last = kept.map(\.end).max() else { return nil }
        return WristEnergy(start: first, end: last, kilocalories: sum)
    }
}

// MARK: - Holding a model across Health's awaits

extension PersistentModel {
    /// Whether a model read before an `await` is gone after it.
    ///
    /// Every Health call suspends, some for seconds, and a finished session
    /// can be deleted, erased with everything else or replaced by a restore
    /// meanwhile. Writing to it then leaves a Health workout or a heart rate
    /// on something that no longer exists, and reading a deleted model can
    /// trap. `isDeleted` alone can't tell: once the delete is saved it reads
    /// false again, and only the missing context says so.
    var isGoneFromStore: Bool { isDeleted || modelContext == nil }

    /// `isGoneFromStore`, and then the store asked through `descriptor`.
    ///
    /// A delete saved through another context leaves this instance looking
    /// alive, and so does a restore that put a new row with the same ID in
    /// its place; only a fetch finds either. A fetch that fails says nothing
    /// either way and is not read as gone.
    func isGone(fromStore descriptor: FetchDescriptor<Self>) -> Bool {
        guard !isGoneFromStore, let context = modelContext else { return true }
        guard let stored = try? context.fetch(descriptor) else { return false }
        return !stored.contains { $0.persistentModelID == persistentModelID }
    }
}
