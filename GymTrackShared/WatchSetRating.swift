import Foundation

/// An answer belongs to one completion, not every future use of the same row.
/// The timestamp prevents a delayed answer from surviving an undo and re-log.
struct WatchSetRating: Codable, Hashable, Sendable {
    var sessionID: UUID
    var setID: UUID
    var completedAt: Date
    var rpe: Double?

    var isValid: Bool { rpe == nil || rpe.flatMap(SetFeel.init(rawValue:)) != nil }

    func matches(_ completion: Date?) -> Bool {
        guard let completion else { return false }
        // Dates pass through milliseconds on the wire. Ignore floating-point
        // round-off without accepting an answer from a different completion.
        return abs(completedAt.timeIntervalSince(completion)) < 0.001
    }
}
