import CoreMotion
import Foundation
import Observation

/// Reads the wrist's movement while a workout is recorded and no set is
/// announced, and hands what it finds to the two places that use it: the
/// logger's "Log set?" line (`offer`), and the next log, which carries the
/// bout to the phone as the set's detected window (`claim`).
///
/// The sensor runs only while `MotionSetDetection.shouldRead` says so and is
/// stopped, with everything it read thrown away, the moment it does not: an
/// announced set already has its start, a session that is not recording has
/// no sets to find, and the setting being off means off.
@MainActor
@Observable
final class WatchMotionSetWatcher {

    static let shared = WatchMotionSetWatcher()

    /// The line the logger may show. See `MotionSetOffer`.
    private(set) var offer: MotionSetOffer?

    /// About 25 readings a second: a rep's swings are a second or so apart, so
    /// this resolves them many times over, at a fraction of the sensor's
    /// battery cost at full rate.
    private static let rate: Double = 25
    /// How much of the trace is kept. Longer than the longest set plus the
    /// quiet either side of it; older readings could only describe a set
    /// whose log is past claiming anyway.
    private static let kept: TimeInterval = 300
    /// How often the trace is looked at for a finished bout.
    private static let lookEvery: TimeInterval = 1
    /// Left off the end of the trace when a log claims a bout: raising the
    /// wrist and tapping Log set is itself movement, and read as part of the
    /// trace it would look like the set still going.
    private static let wristRaise: TimeInterval = 2

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var samples: [MotionSample] = []
    @ObservationIgnored private var isReading = false
    @ObservationIgnored private var lastLook: Date = .distantPast
    /// The end of the last bout offered or claimed, or the last log: nothing
    /// from before it is offered again.
    @ObservationIgnored private var spentUntil: Date = .distantPast
    @ObservationIgnored private var lapse: Task<Void, Never>?

    private init() {}

    /// Starts following the session and the recorder; called once at launch.
    func follow() {
        let wanted = withObservationTracking {
            MotionSetDetection.shouldRead(enabled: WatchConnector.shared.session?.motionSetDetection,
                                          recording: WatchWorkoutRecorder.shared.isRunning,
                                          session: WatchConnector.shared.session)
        } onChange: {
            Task { @MainActor in self.follow() }
        }
        wanted ? startReading() : stopReading()
    }

    /// The bout the log at `moment` closes, if there is one it can carry:
    /// the offer standing for this set, or else one read from the trace with
    /// the wrist raise left off. Whatever happens, nothing read before this
    /// log is offered afterwards.
    func claim(forLogAt moment: Date, of set: WatchSetSnapshot, announced: Bool,
               in session: WatchSessionSnapshot) -> WatchMotionWindow? {
        defer {
            spentUntil = max(spentUntil, moment)
            withdraw()
        }
        guard isReading, !announced else { return nil }
        let previous = MotionSetDetection.gapOpened(in: session, before: set.id)
        let standing = offer.flatMap { $0.isShowing(on: set.id, at: moment) ? $0.bout : nil }
        let bout = standing ?? MotionSetDetection.bout(in: samples, after: previous,
                                                       until: moment.addingTimeInterval(-Self.wristRaise),
                                                       quiet: 0)
        guard let window = bout?.window, window.describes(logAt: moment, after: previous) else { return nil }
        return window
    }

    /// Takes the line away: the lifter did something else.
    func withdraw() {
        lapse?.cancel()
        lapse = nil
        if offer != nil { offer = nil }
    }

    // MARK: - The sensor

    private func startReading() {
        guard !isReading, motion.isDeviceMotionAvailable else { return }
        isReading = true
        samples.removeAll()
        motion.deviceMotionUpdateInterval = 1 / Self.rate
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let a = data.userAcceleration
            let sample = MotionSample(
                // The reading's own timestamp is seconds since boot; turned
                // into a date here so a late-delivered batch keeps its times.
                time: Date(timeIntervalSinceNow: data.timestamp - ProcessInfo.processInfo.systemUptime),
                magnitude: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            )
            MainActor.assumeIsolated { self?.take(sample) }
        }
    }

    private func stopReading() {
        guard isReading else { return }
        motion.stopDeviceMotionUpdates()
        isReading = false
        samples.removeAll()
        withdraw()
    }

    private func take(_ sample: MotionSample) {
        samples.append(sample)
        let oldest = sample.time.addingTimeInterval(-Self.kept)
        if let first = samples.first, first.time < oldest {
            samples.removeAll { $0.time < oldest }
        }
        guard sample.time.timeIntervalSince(lastLook) >= Self.lookEvery else { return }
        lastLook = sample.time
        look(now: sample.time)
    }

    /// Offers a bout that has just settled, once, on the set the logger is on.
    private func look(now: Date) {
        guard offer == nil, let session = WatchConnector.shared.session,
              let set = session.currentSet, !set.isCompleted, set.startedAt == nil else { return }
        let floor = max(MotionSetDetection.gapOpened(in: session, before: set.id), spentUntil)
        guard let bout = MotionSetDetection.bout(in: samples, after: floor, until: now) else { return }
        spentUntil = bout.end
        offer = MotionSetOffer(bout: bout, setID: set.id, madeAt: now)
        lapse = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MotionSetOffer.lifetime))
            guard !Task.isCancelled else { return }
            self?.withdraw()
        }
    }
}
