import Foundation

/// One reading of the wrist's movement: how hard it was accelerating, in g,
/// with gravity taken out (the magnitude of `CMDeviceMotion.userAcceleration`).
struct MotionSample: Equatable, Sendable {
    let time: Date
    let magnitude: Double
}

/// A stretch of rep-like movement, from its first active second to its last.
struct MotionBout: Equatable, Sendable {
    let start: Date
    let end: Date
    /// How many swings of the acceleration were counted. Each rep's lift and
    /// lower both show as a swing, so this is not a rep count and is never
    /// reported as one.
    let swings: Int

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var window: WatchMotionWindow { WatchMotionWindow(start: start, end: end) }
}

/// Finding one set in the wrist's movement, for a set nobody announced.
///
/// The same stance as `SetEffortDetection` on the phone: a reading, never a
/// stamp, and refused whenever the trace could be read two ways. A set the
/// detector misses costs nothing (it is logged as it always was); a set it
/// invents, or a window it places wrongly, would sit in the record looking
/// like a measurement. So every rule below errs towards finding nothing.
enum MotionSetDetection {

    // MARK: Constants, each named by what it prevents

    /// The trace is judged a second at a time. Finer and a single pause at
    /// lockout splits a set in two; coarser and the ends of the set blur by
    /// more than the heart rate's would.
    static let slice: TimeInterval = 1
    /// Mean acceleration over a slice at or above which the wrist is moving.
    /// A wrist at rest, scrolling a phone or holding a bottle sits well under
    /// it, so rest is not read as work; a rep, even a slow one, is well over.
    static let activeLevel: Double = 0.04
    /// Fewer readings than this in a slice says nothing about it (the sensor
    /// paused, or the trace begins mid-slice), so it counts as quiet rather
    /// than as movement nobody saw.
    static let fewestReadingsPerSlice = 5
    /// Quiet up to this long inside a set does not end it: the breath at
    /// lockout between reps, the pause at the bottom of a rest-pause.
    static let joinGap: TimeInterval = 2.5
    /// How long the wrist must be still after the last rep before the set is
    /// taken to be over and offered. Shorter and the offer appears while the
    /// lifter is re-racking; it is also how close a further movement may come
    /// before the end can be read two ways (the last rep, or a re-rack), which
    /// is refused.
    static let settle: TimeInterval = 6
    /// Shortest bout taken for a set: about three reps at an ordinary tempo.
    /// Shorter movement is picking up a plate, fixing a pin or raising the
    /// wrist to look at it.
    static let shortestSet: TimeInterval = 6
    /// Longest bout taken for a set. Longer continuous movement is cardio, a
    /// walk or a long carry, and calling it one set would hand the set a
    /// length nobody spent under a bar.
    static let longestSet: TimeInterval = WatchMotionWindow.longestSet
    /// Fewest swings that make a set: two per rep, so about two reps' worth at
    /// the least. Fewer is one movement, not a repeated one.
    static let fewestSwings = 4
    /// The usual spacing between swings for reps: a fast rep's lift and lower
    /// are each about 0.7 s, a slow eccentric up to several seconds. Walking
    /// and running swing every half-second or faster, which is what keeps a
    /// walk to the water fountain from being read as a set.
    static let swingSpacing: ClosedRange<TimeInterval> = 0.7...8
    /// How uneven the swings may be (spread over mean). Reps repeat; fiddling
    /// with a bench, loading plates or a conversation with your hands do not.
    static let steadiness: Double = 0.6
    /// The trace is smoothed over this long before swings are counted, so a
    /// jolt from the bar touching the pins is not a swing of its own.
    static let smoothing: TimeInterval = 0.3
    /// A swing must cross this share of the bout's own range around its
    /// middle, either way, so noise riding on one swing is not counted twice.
    static let swingShare: Double = 0.25
    /// And never less than this, in g, so a near-still stretch's noise is not
    /// counted as swings at all.
    static let smallestSwing: Double = 0.015
    /// Quiet the trace must show before a bout, at its very beginning, for
    /// the bout's start to be known. A bout already moving when the trace
    /// begins (the previous log came mid-movement, or the buffer was cut)
    /// started somewhere nobody saw.
    static let leadingQuiet: TimeInterval = 2

    // MARK: Reading the trace

    /// The one bout of rep-like movement in the trace after `floor` (the
    /// previous log, so the bout belongs to the gap a log would close) and up
    /// to `cutoff`, or `nil` where there is none or more than one reading.
    ///
    /// `quiet` is how long the wrist must have been still before `cutoff` for
    /// the bout to count as over. The offer asks for `settle`; a log asks for
    /// none, since the lifter tapping Log set says the set is over, but the
    /// bout must still have stopped before `cutoff`.
    static func bout(in samples: [MotionSample], after floor: Date, until cutoff: Date,
                     quiet: TimeInterval = settle) -> MotionBout? {
        let trace = samples.filter { $0.time > floor && $0.time <= cutoff }.sorted { $0.time < $1.time }
        guard let origin = trace.first?.time, cutoff > origin else { return nil }

        // Slice the trace and mark each slice moving or still.
        let count = Int((cutoff.timeIntervalSince(origin) / slice).rounded(.down)) + 1
        var buckets = [[MotionSample]](repeating: [], count: count)
        for sample in trace {
            let index = min(count - 1, Int(sample.time.timeIntervalSince(origin) / slice))
            buckets[index].append(sample)
        }
        let active = buckets.map { bucket in
            bucket.count >= fewestReadingsPerSlice
                && bucket.reduce(0) { $0 + $1.magnitude } / Double(bucket.count) >= activeLevel
        }

        // Runs of movement, joined across short pauses.
        let joinSlices = Int((joinGap / slice).rounded(.down))
        var runs: [ClosedRange<Int>] = []
        for index in active.indices where active[index] {
            if let last = runs.last, index - last.upperBound - 1 <= joinSlices {
                runs[runs.count - 1] = last.lowerBound...index
            } else {
                runs.append(index...index)
            }
        }

        let bouts = runs.compactMap { run -> (run: ClosedRange<Int>, bout: MotionBout)? in
            guard let first = buckets[run.lowerBound].first, let last = buckets[run.upperBound].last,
                  let swings = repLikeSwings(trace.filter { $0.time >= first.time && $0.time <= last.time })
            else { return nil }
            return (run, MotionBout(start: first.time, end: last.time, swings: swings))
        }
        // Two bouts in one gap: a set done without logging and another after
        // it, or a warm-up and the work set. Which one this log means is a
        // guess either way.
        guard bouts.count == 1, let found = bouts.first else { return nil }

        // Moving when the trace began: the start is not in it.
        let leadingSlices = Int((leadingQuiet / slice).rounded(.up))
        guard found.run.lowerBound >= leadingSlices else { return nil }
        // Not still for long enough yet. At least a whole slice of stillness
        // either way: a bout still moving at the cutoff may not be over.
        guard cutoff.timeIntervalSince(found.bout.end) >= max(quiet, slice) else { return nil }
        // Any other movement close behind the end: the last rep, or the
        // re-rack after it? Read either way, the end is not known.
        if let next = runs.first(where: { $0.lowerBound > found.run.upperBound }),
           let nextStart = buckets[next.lowerBound].first?.time,
           nextStart.timeIntervalSince(found.bout.end) < settle {
            return nil
        }
        return found.bout
    }

    /// How many swings a stretch of movement holds, if it moved like reps:
    /// long enough, not too long, enough swings, spaced like reps rather than
    /// steps, and evenly. `nil` for anything else.
    static func repLikeSwings(_ stretch: [MotionSample]) -> Int? {
        guard let first = stretch.first?.time, let last = stretch.last?.time else { return nil }
        let length = last.timeIntervalSince(first)
        guard length >= shortestSet, length <= longestSet else { return nil }

        let smooth = smoothed(stretch)
        let sorted = smooth.sorted()
        let low = sorted[Int(Double(sorted.count - 1) * 0.1)]
        let high = sorted[Int(Double(sorted.count - 1) * 0.9)]
        let middle = smooth.reduce(0, +) / Double(smooth.count)
        let band = max(smallestSwing, swingShare * (high - low))

        // A swing is counted on the way up, once the trace has been below the
        // band since the last one, so a wobble at the top counts once.
        var armed = false
        var swingTimes: [Date] = []
        for (sample, value) in zip(stretch, smooth) {
            if value < middle - band {
                armed = true
            } else if armed, value > middle + band {
                swingTimes.append(sample.time)
                armed = false
            }
        }
        guard swingTimes.count >= fewestSwings else { return nil }

        let spacings = zip(swingTimes.dropFirst(), swingTimes).map { $0.timeIntervalSince($1) }
        let ordered = spacings.sorted()
        let median = ordered[ordered.count / 2]
        guard swingSpacing.contains(median) else { return nil }
        let mean = spacings.reduce(0, +) / Double(spacings.count)
        let variance = spacings.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(spacings.count)
        guard mean > 0, variance.squareRoot() / mean <= steadiness else { return nil }
        return swingTimes.count
    }

    /// A centred moving average over `smoothing`, by time rather than by
    /// sample count, so a dropped reading does not stretch the window.
    private static func smoothed(_ stretch: [MotionSample]) -> [Double] {
        let half = smoothing / 2
        var result: [Double] = []
        result.reserveCapacity(stretch.count)
        var lower = 0, upper = 0
        var sum = 0.0
        for sample in stretch {
            while upper < stretch.count, stretch[upper].time.timeIntervalSince(sample.time) <= half {
                sum += stretch[upper].magnitude
                upper += 1
            }
            while sample.time.timeIntervalSince(stretch[lower].time) > half {
                sum -= stretch[lower].magnitude
                lower += 1
            }
            result.append(sum / Double(upper - lower))
        }
        return result
    }

    // MARK: When to read, and which gap

    /// Whether the wrist should be reading its movement at all: the setting
    /// is on (absent from an older phone, which is on), a workout is being
    /// recorded, a session is live, and no set is under way by somebody's
    /// say-so. Outside those the sensor is off, for the battery, and because
    /// an announced set already has its start.
    static func shouldRead(enabled: Bool?, recording: Bool, session: WatchSessionSnapshot?) -> Bool {
        guard enabled ?? true, recording, let session else { return false }
        return !session.allSets.contains { $0.startedAt != nil && !$0.isCompleted }
    }

    /// When the gap a log of `setID` would close opened: the latest log of any
    /// other set in the session, or the session's start. A bout from before
    /// then belongs to a set already logged.
    static func gapOpened(in session: WatchSessionSnapshot, before setID: UUID? = nil) -> Date {
        session.allSets
            .filter { $0.isCompleted && $0.id != setID }
            .compactMap(\.completedAt)
            .reduce(session.startedAt) { max($0, $1) }
    }
}

/// The wrist's one quiet line: "Log set? 0:42" on the set the logger is
/// sitting on, after a bout ended with nothing logged.
///
/// It never buzzes, never covers anything and needs no answer: it lapses on
/// its own after `lifetime`, or as soon as the lifter does something else.
/// Ignored, it leaves nothing anywhere.
struct MotionSetOffer: Equatable, Sendable {
    let bout: MotionBout
    /// The set the logger was on when it was made. Shown on no other.
    let setID: UUID
    let madeAt: Date

    /// About a minute: long enough to finish racking, sit down and look at
    /// the wrist; short enough that it is gone before the next set is.
    static let lifetime: TimeInterval = 60

    func isShowing(on setID: UUID, at now: Date) -> Bool {
        self.setID == setID && now >= madeAt && now.timeIntervalSince(madeAt) < Self.lifetime
    }
}
