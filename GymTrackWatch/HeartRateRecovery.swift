import Foundation
import Observation

/// One heart-rate reading, as plain values, so the decision below can be run
/// over made-up traces without HealthKit or a wrist.
struct HeartRateReading: Equatable, Sendable {
    let date: Date
    let bpm: Double
}

/// Whether the heart rate has come back down from a set and levelled off, which
/// is the lifter's cue that the next set can start.
///
/// It reads a trace and answers yes only when the trace plainly says so; a
/// doubtful trace is "not yet", never a guess. Nothing it decides is recorded:
/// it only ever taps the wrist, and a cue that never comes costs the lifter
/// nothing, because the rest countdown still ends the rest as it always did.
enum HeartRateRecovery {

    /// The least rest before a cue is possible. A heart rate does not level
    /// off in the seconds after a set: it is still climbing for a few of them,
    /// and a sensor that lags the wrist can read a brief flat spot at the top.
    /// Without a floor, the cue would tell the lifter to go while still
    /// breathing hard.
    static let minimumRest: TimeInterval = 40

    /// How much of the end of the trace has to be flat. Long enough that a
    /// pause in the middle of a fall is not read as the bottom, short enough
    /// that the cue is not a long time behind the heart rate.
    static let flatWindow: TimeInterval = 25

    /// Readings needed inside that window. A watch in a workout reads every
    /// few seconds; fewer than four means it dropped most of them, and a flat
    /// line drawn through two points proves nothing.
    static let minimumReadings = 4

    /// The longest silence tolerated inside the window, at its edges, or since
    /// the last reading. A longer gap means the sensor lost the pulse (a loose
    /// strap, a wrist turned over the bar) and the beats it missed could be
    /// anything, so the flat line would be a guess dressed as a reading.
    static let longestGap: TimeInterval = 12

    /// The most the window may range, in beats per minute. A wrist reading
    /// wanders by a handful of beats standing still; this clears that and is
    /// well below the swing of a heart rate still coming down or going up.
    static let maximumSpread: Double = 6

    /// The most the second half of the window may differ from the first, in
    /// beats per minute. Spread alone passes a slow slide of five beats across
    /// the window, which is ten or more beats a minute, still falling; this
    /// also refuses the opposite, a rate rising because the lifter has already
    /// picked up the bar or walked off.
    static let maximumTrend: Double = 3

    /// How far the level must sit below the rest's peak, in beats per minute.
    /// A heart rate that never rose much has not recovered from anything, and
    /// its flat line is just a light set; below this the lifter is told
    /// nothing and the countdown decides. It also clears the wander that
    /// `maximumSpread` allows, so a trace cannot satisfy both with noise alone.
    static let minimumDrop: Double = 15

    /// How far before the rest began the peak is looked for. The set's climb
    /// goes on for several seconds after it is logged, and a set logged as the
    /// bar goes back can be logged before the rate tops out; a peak taken only
    /// from the rest itself would miss part of the climb and under-count the drop.
    static let peakLookback: TimeInterval = 15

    /// The plausible range of a reading. Zero is the sensor reporting no
    /// pulse, not a heart that stopped; anything wild above is a glitch. Either
    /// inside the window and the trace is not trusted.
    static let plausible: ClosedRange<Double> = 30...240

    /// True when the heart rate has settled after a set.
    ///
    /// - Parameters:
    ///   - readings: every reading from just before the rest began onward, in
    ///     any order.
    ///   - restStartedAt: when the rest began.
    ///   - now: the moment being judged.
    static func hasSettled(readings: [HeartRateReading], restStartedAt: Date, now: Date) -> Bool {
        guard now.timeIntervalSince(restStartedAt) >= minimumRest else { return false }

        let relevant = readings
            .filter { $0.date >= restStartedAt.addingTimeInterval(-peakLookback) && $0.date <= now }
            .sorted { $0.date < $1.date }
        let windowStart = now.addingTimeInterval(-flatWindow)
        let window = relevant.filter { $0.date >= windowStart }

        guard window.count >= minimumReadings,
              window.allSatisfy({ plausible.contains($0.bpm) }),
              // The window's ends: a trace that starts late or stops early
              // cannot vouch for the stretch it does not cover.
              window[0].date.timeIntervalSince(windowStart) <= longestGap,
              now.timeIntervalSince(window[window.count - 1].date) <= longestGap
        else { return false }

        for (earlier, later) in zip(window, window.dropFirst())
        where later.date.timeIntervalSince(earlier.date) > longestGap {
            return false
        }

        let levels = window.map(\.bpm)
        guard let high = levels.max(), let low = levels.min(), high - low <= maximumSpread else { return false }

        let half = window.count / 2
        let first = levels[..<half].reduce(0, +) / Double(half)
        let second = levels[(window.count - half)...].reduce(0, +) / Double(half)
        guard abs(second - first) <= maximumTrend else { return false }

        guard let peak = relevant.map(\.bpm).max() else { return false }
        let level = levels.reduce(0, +) / Double(levels.count)
        return peak - level >= minimumDrop
    }
}

/// The watch's "heart rate settled" cue for the rest in progress.
///
/// At most one per rest: it latches when it fires and is cleared only by the
/// next rest. It changes nothing about the countdown and has nothing to
/// dismiss; the view draws `isSettled` for as long as the rest runs.
@MainActor
@Observable
final class WatchRecoveryCue {

    /// True from the moment the cue fires until the rest ends.
    private(set) var isSettled = false

    /// The phone's setting, mirrored. Absent on the wire means on.
    var isEnabled = true

    @ObservationIgnored private var restStartedAt: Date?
    @ObservationIgnored private var fired = false
    @ObservationIgnored private var readings: [HeartRateReading] = []
    /// The tap. Handed in so a test can count it.
    @ObservationIgnored private let tap: () -> Void

    /// Readings older than this are dropped. Enough to cover a peak just before
    /// a rest and the window after it, with room; a workout streams for an hour
    /// and the buffer must not grow with it.
    private static let retention: TimeInterval = 120

    init(tap: @escaping () -> Void = WatchHaptics.recovered) {
        self.tap = tap
    }

    func beginRest(at date: Date = .now) {
        restStartedAt = date
        fired = false
        isSettled = false
    }

    func endRest() {
        restStartedAt = nil
        fired = false
        isSettled = false
    }

    /// Takes a reading, and fires the cue if the rest it belongs to has now
    /// settled. Readings outside a rest are kept for the peak that precedes one.
    func record(bpm: Double, at date: Date, now: Date = .now) {
        readings.append(HeartRateReading(date: date, bpm: bpm))
        readings.removeAll { now.timeIntervalSince($0.date) > Self.retention }

        guard isEnabled, !fired, let restStartedAt,
              HeartRateRecovery.hasSettled(readings: readings, restStartedAt: restStartedAt, now: max(now, date))
        else { return }
        fired = true
        isSettled = true
        tap()
    }
}
