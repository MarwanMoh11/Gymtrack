import Foundation

// MARK: - What a set's heart rate was read off

/// Where a set's heart rate window came from.
///
/// The distinction is the whole reason this type exists. A set whose start was
/// announced has a real window and the numbers over it are a measurement; a set
/// without one has a window this app worked out, and a reader who can't tell
/// the two apart will treat both as fact. Carried beside every attributed
/// number, all the way into the backup.
enum HeartRateWindowSource: String, Sendable {
    /// `startedAt` to `completedAt` — both ends are moments somebody marked.
    case measured
    /// The tail of the gap before the set was logged. See `SetTiming.window`.
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

    init(id: UUID, startedAt: Date?, completedAt: Date, reps: Int, heldSeconds: Int) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.reps = reps
        self.heldSeconds = heldSeconds
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

// MARK: - Attribution

/// Splitting a session's heart-rate samples across its sets.
///
/// Every number here is derived from stamps the sets already carried and
/// samples the watch already recorded. The lifter is asked for nothing: this
/// runs when a session is written to Health and again when its summary opens,
/// and a session where nobody touched anything still comes out with a heart
/// rate on every set.
enum SetHeartRateAttribution {

    /// The window a set's heart rate should be read from, or `nil` when there
    /// isn't one worth reading.
    ///
    /// Two cases, and the difference between them is the point:
    ///
    /// * **Announced.** `startedAt` to `completedAt` is the set and only the
    ///   set. A start is believed only where it falls inside the interval it
    ///   claims to split — not before the previous set was logged, and before
    ///   this one was — the rule `WorkoutSession.gapsWithProvenance` already
    ///   applies to the same stamp for the same reason. A stamp
    ///   outside that is a clock moved or a backup carried across timezones,
    ///   and a window running backwards would attribute somebody else's beats
    ///   with total confidence.
    /// * **Not announced.** All that is known is the gap from the previous set
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
    /// with the numbers into the record and the file: an inferred window is
    /// never presented, drawn or exported as a measured one.
    static func window(for set: SetTiming, after previous: Date?) -> HeartRateWindow? {
        let lowerBound = previous ?? .distantPast

        if let announced = set.startedAt,
           announced < set.completedAt,
           announced >= lowerBound {
            return HeartRateWindow(start: announced, end: set.completedAt, source: .measured)
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
        let ordered = sets.sorted { $0.completedAt < $1.completedAt }
        var previous = sessionStart
        var result: [(id: UUID, window: HeartRateWindow)] = []
        for set in ordered {
            if let window = window(for: set, after: previous) {
                result.append((set.id, window))
            }
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
        // A heart rate of zero is a dropped reading, not a stopped heart. Left
        // in it would drag an average down to a number no one's chest ever did.
        let usable = samples.filter { $0.bpm > 0 }.sorted { $0.start < $1.start }
        guard !usable.isEmpty else { return [:] }

        var result: [UUID: SetHeartRate] = [:]
        for (id, window) in windows(for: sets, sessionStart: sessionStart) {
            let inWindow = usable.filter(window.contains)
            guard !inWindow.isEmpty else { continue }
            let beats = inWindow.map(\.bpm)
            result[id] = SetHeartRate(
                average: beats.reduce(0, +) / Double(beats.count),
                peak: beats.max() ?? 0,
                source: window.source
            )
        }
        return result
    }
}
