import Foundation

/// The channel between the app and the two things that run outside it: the
/// widgets, and the intents Siri, Spotlight and the Action Button fire.
///
/// Deliberately a small snapshot rather than a shared database. Moving the
/// SwiftData store into the group container would strand the history already on
/// the device, and a widget only ever needs a dozen numbers — so the app
/// restamps those numbers whenever they change, and nothing outside the app
/// writes here except to leave a pending action behind.
///
/// Every call is safe when the App Group isn't provisioned: a free Apple ID
/// can't have one, and in that case the writes simply land somewhere the widget
/// can't read. The app keeps working and the widgets show their placeholder,
/// which is the right failure for a capability the user may not be able to buy.
enum SharedStore {

    static let appGroup = "group.com.marwanmohamed.gymtrack"

    private static let snapshotKey = "gymtrack.snapshot"
    private static let actionKey = "gymtrack.pendingAction"
    private static let actionStampKey = "gymtrack.pendingActionAt"

    /// An action left behind by something outside the app, for the app to pick
    /// up the moment it comes to the front.
    enum PendingAction: String, Codable, Sendable {
        case startToday, startFreestyle, openSession
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    // MARK: - Snapshot

    static func write(_ snapshot: GymTrackSnapshot) {
        guard let data = try? JSONEncoder.shared.encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func readSnapshot() -> GymTrackSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder.shared.decode(GymTrackSnapshot.self, from: data)
    }

    // MARK: - Pending actions

    static func request(_ action: PendingAction) {
        defaults?.set(action.rawValue, forKey: actionKey)
        defaults?.set(Date.now.timeIntervalSince1970, forKey: actionStampKey)
    }

    /// Takes the action and clears it, so a workout is never started twice by
    /// one tap. Anything older than two minutes is dropped rather than replayed:
    /// a request that failed to reach the app when it was made is a request the
    /// user has long since given up on.
    static func takeAction() -> PendingAction? {
        guard let defaults,
              let raw = defaults.string(forKey: actionKey),
              let action = PendingAction(rawValue: raw)
        else { return nil }

        defaults.removeObject(forKey: actionKey)
        let stamp = defaults.double(forKey: actionStampKey)
        defaults.removeObject(forKey: actionStampKey)

        guard Date.now.timeIntervalSince1970 - stamp < 120 else { return nil }
        return action
    }
}

// MARK: - What a widget draws

/// Everything the widgets know. Flat and small on purpose — it is rewritten on
/// every logged set while a session is running.
struct GymTrackSnapshot: Codable, Hashable, Sendable {

    /// A session in progress, as a widget sees it.
    struct Running: Codable, Hashable, Sendable {
        var title: String
        var startedAt: Date
        var completedSets: Int
        var totalSets: Int
        var exercise: String
        var target: String
        var restEndsAt: Date?

        init(title: String, startedAt: Date, completedSets: Int, totalSets: Int,
                    exercise: String, target: String, restEndsAt: Date?) {
            self.title = title
            self.startedAt = startedAt
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.exercise = exercise
            self.target = target
            self.restEndsAt = restEndsAt
        }

        var progress: Double {
            totalSets > 0 ? min(1, Double(completedSets) / Double(totalSets)) : 0
        }
    }

    var updatedAt: Date
    /// Whether there's an active routine at all, which is what separates "rest
    /// day" from "nothing set up yet".
    var hasPlan: Bool
    /// Today's scheduled session. `nil` on a rest day, and with no plan.
    var todayTitle: String?
    var todayExerciseCount: Int
    var todaySetCount: Int
    var todayMuscles: [String]
    var streak: Int
    var sessionsThisWeek: Int
    var weekVolumeKg: Double
    var unit: WeightUnit
    var session: Running?

    init(updatedAt: Date = .now,
                hasPlan: Bool = false,
                todayTitle: String? = nil,
                todayExerciseCount: Int = 0,
                todaySetCount: Int = 0,
                todayMuscles: [String] = [],
                streak: Int = 0,
                sessionsThisWeek: Int = 0,
                weekVolumeKg: Double = 0,
                unit: WeightUnit = .kg,
                session: Running? = nil) {
        self.updatedAt = updatedAt
        self.hasPlan = hasPlan
        self.todayTitle = todayTitle
        self.todayExerciseCount = todayExerciseCount
        self.todaySetCount = todaySetCount
        self.todayMuscles = todayMuscles
        self.streak = streak
        self.sessionsThisWeek = sessionsThisWeek
        self.weekVolumeKg = weekVolumeKg
        self.unit = unit
        self.session = session
    }

    /// Today is a training day with something prescribed on it.
    var hasSessionToday: Bool { todayTitle != nil }

    /// What the widget gallery shows, and what a widget falls back to before
    /// the app has ever written a snapshot.
    static let placeholder = GymTrackSnapshot(
        hasPlan: true,
        todayTitle: "Push Day",
        todayExerciseCount: 5,
        todaySetCount: 18,
        todayMuscles: ["Chest", "Shoulders", "Triceps"],
        streak: 4,
        sessionsThisWeek: 3,
        weekVolumeKg: 14_800
    )
}

// MARK: - Wire format

private extension JSONEncoder {
    static let shared: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()
}

private extension JSONDecoder {
    static let shared: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
