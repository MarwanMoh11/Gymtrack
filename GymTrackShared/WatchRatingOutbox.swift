import Foundation

/// Keeps explicit answers until the phone echoes them, including across a
/// watch relaunch. A log and its answer can take different delivery routes.
struct WatchRatingOutbox: Codable {
    /// A confirmed completion can subsequently be undone; an unconfirmed one may still be in transit.
    struct Entry: Codable {
        var rating: WatchSetRating
        var sawCompletion = false
    }

    private(set) var entries: [UUID: Entry] = [:]

    mutating func record(_ rating: WatchSetRating, confirmed: Bool = false) {
        guard rating.isValid else { return }
        entries[rating.setID] = Entry(rating: rating, sawCompletion: confirmed)
    }

    mutating func remove(_ id: UUID) { entries.removeValue(forKey: id) }

    /// Resends once the log is confirmed if the first answer could have beaten
    /// it to the phone. Repeated mirrors never make a send-and-echo loop.
    mutating func reconcile(with session: WatchSessionSnapshot) -> [WatchSetRating] {
        let sets = Dictionary(session.allSets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var resend: [WatchSetRating] = []
        for (id, var entry) in entries {
            guard entry.rating.sessionID == session.sessionID else {
                if session.startedAt > entry.rating.completedAt {
                    resend.append(entry.rating)
                    entries.removeValue(forKey: id)
                }
                continue
            }
            guard let set = sets[id] else {
                entries.removeValue(forKey: id)
                continue
            }
            if set.isCompleted, entry.rating.matches(set.completedAt) {
                if set.rpe == entry.rating.rpe {
                    entries.removeValue(forKey: id)
                } else if !entry.sawCompletion {
                    entry.sawCompletion = true
                    entries[id] = entry
                    resend.append(entry.rating)
                }
            } else if entry.sawCompletion {
                // The phone has taken this completion back or replaced it.
                entries.removeValue(forKey: id)
            }
        }
        return resend
    }
}
