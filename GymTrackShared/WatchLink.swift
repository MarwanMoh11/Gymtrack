import Foundation

/// The contract between the phone and the watch.
///
/// The phone owns the data. The watch holds no store of its own: it draws
/// whatever mirror arrived last and sends back commands for anything the user
/// does on the wrist. That keeps one source of truth — a set logged on the
/// watch is written to SwiftData on the phone and comes straight back in the
/// next mirror, so the two screens can't drift.
enum WatchLink {
    /// Payload keys used on the `WCSession` wire.
    static let mirrorKey = "gymtrack.mirror"
    static let commandKey = "gymtrack.command"
    /// Reply key for a command the phone accepted.
    static let ackKey = "gymtrack.ack"
}

// MARK: - How a set is measured

/// The subset of the app's `TrackingMode` the watch needs. Kept separate so the
/// exercise catalog — 414 entries and a JSON loader — stays on the phone.
enum WatchTracking: String, Codable, Hashable, Sendable {
    case weightReps, bodyweightReps, duration

    var logsWeight: Bool { self == .weightReps }
    var logsReps: Bool { self != .duration }
}

// MARK: - Mirror (phone → watch)

struct WatchSetSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// 0-based position within its exercise.
    var index: Int
    var weightKg: Double
    var reps: Int
    var seconds: Int
    var targetRepsLow: Int
    var targetRepsHigh: Int
    var isCompleted: Bool
    /// Whether this row was taken on from the row above rather than started
    /// fresh — the second half of a drop, the next cluster of a myo-rep run.
    /// Optional only so a mirror in flight during an app update still decodes;
    /// read it through `isContinuation`.
    var continuation: Bool?
    /// When the lifter said this set was beginning, on either device. The wrist
    /// needs it to draw the clock it started, and to know not to offer to start
    /// a set that is already under way.
    ///
    /// Absent means nobody announced anything, which is the ordinary case and
    /// has to stay distinguishable from a set that began at some unknown time.
    var startedAt: Date?

    /// A continuation's weight was chosen for that row alone, so it neither
    /// carries forward onto the sets still to come nor accepts a load carried
    /// down onto it. The watch has to know which rows those are, or its own
    /// prediction of the phone's answer quietly deloads the rest of the
    /// exercise — see `WatchConnector.session`.
    var isContinuation: Bool { continuation == true }

    /// Whether anybody prescribed a rep count for this set.
    ///
    /// `targetLabel` falls back to the reps already dialled when there is no
    /// target, which is the right thing for a line that has to print something
    /// — but a screen offering to show the lifter "their target" must not show
    /// them a number they typed themselves a moment ago and call it one.
    var hasRepTarget: Bool { targetRepsLow > 0 || targetRepsHigh > 0 }

    var targetLabel: String {
        targetRepsHigh <= 0 || targetRepsLow == targetRepsHigh
            ? "\(max(targetRepsLow, reps))"
            : "\(targetRepsLow)–\(targetRepsHigh)"
    }
}

struct WatchExerciseSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: String          // catalog ID
    var name: String
    var order: Int
    var tracking: WatchTracking
    var restSeconds: Int
    var sets: [WatchSetSnapshot]
    /// What the same exercise looked like last time — "last: 60 kg × 8".
    var lastTimeLabel: String?
    /// What this exercise's equipment is marked in, and what one step of the
    /// crown is worth on it. Optional only so a mirror in flight during an app
    /// update still decodes — read it through `resolvedScale`.
    var scale: LoadScale?

    /// The ladder to draw and turn, falling back to the session's unit for a
    /// mirror that predates per-exercise scales.
    func resolvedScale(sessionUnit: WeightUnit) -> LoadScale {
        scale ?? .standard(sessionUnit)
    }

    var completedCount: Int { sets.filter(\.isCompleted).count }
    var isComplete: Bool { !sets.isEmpty && completedCount == sets.count }
    var progress: Double { sets.isEmpty ? 0 : Double(completedCount) / Double(sets.count) }
}

/// A session in progress, as the watch sees it.
struct WatchSessionSnapshot: Codable, Hashable, Sendable {
    var sessionID: UUID
    var title: String
    var planName: String
    var startedAt: Date
    var exercises: [WatchExerciseSnapshot]
    /// The exercise the lifter picked to work out of turn — a superset, or a
    /// machine that was taken when its turn came round. `nil` means "whatever
    /// comes next", which is also what a mirror from a build that predates this
    /// decodes to.
    var preferredExerciseID: String?
    /// The set the logger is sitting on — what the watch opens to.
    var currentSetID: UUID?
    var restEndsAt: Date?
    var restStartedAt: Date?
    var restTotalSeconds: Int
    /// Whether the phone starts a rest after each set. The watch runs the same
    /// rest locally the instant a set is logged, so it has to agree.
    var restAutoStart: Bool
    var volumeKg: Double
    var unit: WeightUnit
    /// True while the phone thinks a rest is running.
    var isResting: Bool { restEndsAt != nil }

    var allSets: [WatchSetSnapshot] { exercises.flatMap(\.sets) }
    var completedSets: Int { allSets.filter(\.isCompleted).count }
    var totalSets: Int { allSets.count }
    var progress: Double { totalSets > 0 ? Double(completedSets) / Double(totalSets) : 0 }

    /// The exercise the logger belongs on — `ActiveWorkout.currentGroup` said
    /// again in the shared types, so both sides can reach it. The phone answers
    /// the question here when it builds a mirror; the watch asks it again while
    /// it is drawing work the phone hasn't confirmed yet, and the two have to
    /// come back with the same exercise or the logger jumps when the mirror
    /// lands.
    ///
    /// Whatever the lifter picked, as long as there is still something left on
    /// it, else whatever comes next.
    var focusedExercise: WatchExerciseSnapshot? {
        if let preferredExerciseID,
           let picked = exercises.first(where: { $0.id == preferredExerciseID && !$0.isComplete }) {
            return picked
        }
        return exercises.first { !$0.isComplete } ?? exercises.last
    }

    var currentExercise: WatchExerciseSnapshot? {
        if let currentSetID, let match = exercises.first(where: { $0.sets.contains { $0.id == currentSetID } }) {
            return match
        }
        return focusedExercise
    }

    var currentSet: WatchSetSnapshot? {
        guard let exercise = currentExercise else { return nil }
        if let currentSetID, let set = exercise.sets.first(where: { $0.id == currentSetID }) { return set }
        return exercise.sets.first { !$0.isCompleted }
    }

    /// 1-based position of the current set within its exercise.
    var currentSetNumber: Int {
        guard let exercise = currentExercise, let set = currentSet,
              let index = exercise.sets.firstIndex(where: { $0.id == set.id })
        else { return 1 }
        return index + 1
    }

    var upNextName: String? {
        guard let current = currentExercise else { return nil }
        return exercises.first { $0.order > current.order && !$0.isComplete }?.name
    }
}

/// What the watch shows when nothing is running.
struct WatchIdleSnapshot: Codable, Hashable, Sendable {
    /// Midnight of the day this was built for.
    ///
    /// Everything below answers "today", and the watch may be holding the
    /// answer for a day that has since ended — the phone only restamps the
    /// mirror when it is woken, and nothing wakes it at midnight. Without the
    /// stamp the wrist presented yesterday's training day as today's, which on
    /// a rest day is the app inventing a workout.
    ///
    /// Optional only so a mirror in flight during an app update still decodes.
    /// A mirror that doesn't carry one is taken at its word, exactly as it was
    /// before this existed.
    var day: Date?
    var todayTitle: String?
    var todayExerciseCount: Int
    var todaySetCount: Int
    var todayMuscles: [String]
    var streak: Int
    var sessionsThisWeek: Int
    var lastSessionTitle: String?
    var lastSessionDate: Date?
    var unit: WeightUnit

    /// Whether this still describes today. A snapshot from an older build
    /// carries no day and is believed — it is the only thing the watch has.
    var describesToday: Bool {
        guard let day else { return true }
        return Calendar.current.isDateInToday(day)
    }

    static let empty = WatchIdleSnapshot(
        day: nil, todayTitle: nil, todayExerciseCount: 0, todaySetCount: 0, todayMuscles: [],
        streak: 0, sessionsThisWeek: 0, lastSessionTitle: nil, lastSessionDate: nil, unit: .kg
    )
}

/// Everything the phone sends in one go. `sentAt` is what orders them: the
/// application context and a live message can race, and the watch drops
/// whichever arrives out of order rather than flickering the screen backwards.
/// `revision` counts pushes within one run of the phone app — useful in a log,
/// never for ordering, since it starts over when that app is relaunched.
struct WatchMirror: Codable, Hashable, Sendable {
    var revision: Int
    var sentAt: Date
    var idle: WatchIdleSnapshot
    var session: WatchSessionSnapshot?
    /// Whether the phone is set up to record to Health, so the watch can say
    /// what will happen to the workout rather than guessing.
    var healthEnabled: Bool

    static let placeholder = WatchMirror(
        revision: 0, sentAt: .distantPast, idle: .empty, session: nil, healthEnabled: false
    )
}

// MARK: - Commands (watch → phone)

/// Live numbers the watch collects that the phone has no way to measure.
struct WatchWorkoutMetrics: Codable, Hashable, Sendable {
    /// Which session these belong to. Metrics can land after the phone has
    /// already closed the session out — the watch saves its workout to Health
    /// on the way down — and this is what lets them be filed correctly.
    var sessionID: UUID?
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKcal: Double?
    /// Set once the watch has saved the workout to Health, so the phone knows
    /// not to write a second copy of the same session.
    var healthWorkoutID: UUID?

    static let empty = WatchWorkoutMetrics()
}

enum WatchCommand: Codable, Hashable, Sendable {
    /// "Send me what you've got" — on launch, and when the watch reconnects.
    case requestMirror
    case startToday
    case startFreestyle
    /// A set the lifter logged on the wrist, and the moment they logged it.
    ///
    /// The moment travels with the command for the same reason `announceStart`
    /// carries one: out of range this waits in the `transferUserInfo` queue
    /// until the phone is nearby again, and a phone stamping its own clock on
    /// arrival would record the set as having finished when the lifter walked
    /// back rather than when they put the bar down. Three things read that
    /// stamp and would all be wrong together — the session's end, the rest in
    /// front of the next set, and the window a set's heart rate is read from.
    ///
    /// Optional only so a command already queued when the apps are updated
    /// still decodes; see `loggedMoment` for what a command without one gets.
    case logSet(id: UUID, weightKg: Double, reps: Int, seconds: Int, at: Date?)
    case undoSet(id: UUID)
    /// "I'm starting this set, now." The moment travels with the command
    /// rather than being stamped on arrival: out of range this sits in the
    /// `transferUserInfo` queue until the phone is nearby again, and a phone
    /// that stamped its own clock would write a set that began when the lifter
    /// walked back to their locker.
    case announceStart(id: UUID, at: Date)
    /// Takes the announcement back, all the way to never having tapped.
    case cancelStart(id: UUID)
    /// Jump the logger to a different exercise.
    case focusExercise(catalogID: String)
    case addSet(catalogID: String)
    case stopRest
    case extendRest(seconds: Int)
    case startRest(seconds: Int)
    case finish(metrics: WatchWorkoutMetrics?)
    case discard
    /// Heart rate and energy as they change, so the phone's logger and Live
    /// Activity can show what the watch is reading.
    case metrics(WatchWorkoutMetrics)
}

extension WatchCommand {
    /// How far ahead of this device's clock a moment stamped on the wrist may
    /// be and still be worth writing down.
    ///
    /// This used to be a shelf life, and the difference is worth stating. A
    /// set's length is `completedAt - startedAt`, and there was a time when
    /// only the start travelled with a timestamp of its own — the log was
    /// stamped when the phone applied it. Out of range both commands waited in
    /// the queue and landed together when the lifter was back: the start kept
    /// the moment they actually went, the log took the moment the phone
    /// finally heard about it, and the export showed a set held for as long as
    /// the walk back to the locker room took. Dropping a start that had been
    /// waiting was the lesser of those two wrongs.
    ///
    /// Both ends carry the wrist's own clock now, so a pair that waited eleven
    /// minutes in the queue is as true as one that arrived instantly, and
    /// refusing it would be throwing away the only honest record of the set
    /// there is. Waiting is no longer a reason to disbelieve anything.
    ///
    /// What waiting cannot explain is a stamp from the *future*. That is the
    /// two devices disagreeing about what time it is, and a set that began
    /// after it ended has no length, no rest in front of it and no heart-rate
    /// window — every screen drawing it would count backwards. A watch keeps
    /// time with the phone it is paired to, so thirty seconds is already far
    /// more drift than there is; past it, what arrived is somebody's clock
    /// being wrong rather than a moment.
    static let clockSkewTolerance: TimeInterval = 30

    /// When to record a set as having been logged, given whatever the wrist
    /// sent with it.
    ///
    /// A command from a build that predates the stamp carries none, and falls
    /// back to the moment the phone applies it — exactly what every set did
    /// before this, so a log already sitting in the queue when the apps were
    /// updated lands no worse off than it would have.
    static func loggedMoment(_ stamp: Date?) -> Date {
        guard let stamp, stamp.timeIntervalSinceNow <= clockSkewTolerance else { return .now }
        return stamp
    }
}

// MARK: - Wire format

/// `WCSession` takes a dictionary; both sides put JSON in a single key so the
/// payload evolves with the types rather than with stringly-typed dictionaries.
extension Encodable {
    func watchPayload(key: String) -> [String: Any] {
        guard let data = try? JSONEncoder.watchLink.encode(self) else { return [:] }
        return [key: data]
    }
}

extension Decodable {
    static func fromWatchPayload(_ payload: [String: Any], key: String) -> Self? {
        guard let data = payload[key] as? Data else { return nil }
        return try? JSONDecoder.watchLink.decode(Self.self, from: data)
    }
}

extension JSONEncoder {
    static let watchLink: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()
}

extension JSONDecoder {
    static let watchLink: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
