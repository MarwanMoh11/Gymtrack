import Foundation

// The two files the coach loop passes through the phone: `proposal.json`, which
// the Mac pushes in, and `decisions.json`, which the phone writes for the Mac to
// pull. Both formats are fixed by the contract between the two sides, so nothing
// here is renamed or reshaped on its own.
//
// Every optional is optional so that its key is left out when there is no value.
// A null, a zero or an empty string standing in for "nothing" reads to the coach
// as something that was recorded, and false detail is worse than missing detail.

// MARK: - Proposal

/// What the coach proposes, as read from `Inbox/proposal.json`.
///
/// Only the fields the contract names are modelled; Swift's decoder drops the
/// rest, which is how a newer Mac keeps working against an older phone.
struct CoachProposal: Codable, Equatable, Sendable {
    static let format = "gymtrack-coach-proposal"
    static let currentVersion = 1
    static let maxChanges = 3

    var format: String
    var version: Int
    var id: String
    var createdAt: Date
    var planID: String
    var summary: String
    var changes: [CoachChange]
    /// Things that are not plan edits. Shown, never acted on.
    var advice: [String]?
}

/// One edit to one slot (or one day, for adding a slot).
///
/// `reason`, `lever` and `evidence` are required by the contract but modelled
/// as optional: a proposal missing one on a single change should mark that
/// change invalid with a plain reason rather than make the whole file unreadable.
struct CoachChange: Codable, Equatable, Sendable, Identifiable {
    var id: String
    /// A string rather than an enum, so a kind from a newer coach decodes and
    /// is rejected by name instead of failing the whole proposal.
    var kind: String
    var dayID: String?
    var itemID: String?
    var expect: CoachValues?
    var to: CoachValues?
    var reason: String?
    var lever: String?
    var evidence: [CoachEvidence]?
    /// Written by `coach submit` and never by the coach. Absent means the phone
    /// shows no reviewer line.
    var review: CoachReviewNote?
}

/// The values a change expects to find and the values it sets. One shape for
/// both, because each kind uses a different subset of the keys.
struct CoachValues: Codable, Equatable, Sendable {
    var targetSets: Int?
    var targetRepsLow: Int?
    var targetRepsHigh: Int?
    var restSeconds: Int?
    var catalogID: String?
    var name: String?
    /// For `addSlot` only. Absent means the end of the day.
    var afterItemID: String?

    var isEmpty: Bool { self == CoachValues() }
}

/// A number the reviewer can check against `stats.json`.
struct CoachEvidence: Codable, Equatable, Sendable {
    var metric: String
    var value: CoachScalar?
}

/// An evidence value. A number in every proposal written so far, but nothing in
/// the contract forbids a word, and one the phone did not expect must not
/// make the proposal unreadable.
enum CoachScalar: Codable, Equatable, Sendable {
    case number(Double)
    case text(String)
    case flag(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let flag = try? container.decode(Bool.self) {
            self = .flag(flag)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .text(let text): try container.encode(text)
        case .flag(let flag): try container.encode(flag)
        }
    }
}

/// The independent reviewer's verdict on one change.
struct CoachReviewNote: Codable, Equatable, Sendable {
    var verdict: String?
    var score: Int?
    var note: String?
    /// True when the reviewer still objected after the second round and the
    /// user kept the change anyway.
    var disputed: Bool?
}

// MARK: - Decisions

/// `decisions.json`: every proposal the user has decided on, newest last.
struct CoachDecisionFile: Codable, Equatable, Sendable {
    static let format = "gymtrack-coach-decisions"
    static let currentVersion = 1

    var format: String = Self.format
    var version: Int = Self.currentVersion
    var decisions: [CoachDecision] = []
}

/// What was decided about one proposal, and what applying it changed.
struct CoachDecision: Codable, Equatable, Sendable, Identifiable {
    var proposalID: String
    /// When the proposal file reached the phone.
    var receivedAt: Date
    var decidedAt: Date
    var changes: [CoachChangeDecision]
    /// Absent when nothing was applied, so a decline-everything record can't be
    /// read as an edit that happened.
    var appliedAt: Date?
    /// Every slot the apply touched, as it stood before: enough to put it back
    /// exactly, order included. A slot the apply created has an entry with no
    /// `item`, which means "it was not there".
    var before: [CoachItemState]?
    /// The same slots as they stood right after the apply. The contract lists
    /// only `before`, but revert-later has to tell an item the user has since
    /// edited from one still holding what the apply wrote, and the proposal
    /// file it was applied from is long gone by then. A slot the apply removed
    /// has an entry with no `item`.
    var after: [CoachItemState]?
    /// Absent unless the apply was backed out later, from Settings.
    var revertedAt: Date?

    var id: String { proposalID }

    /// True while the plan still carries this decision's edits.
    var isInEffect: Bool { appliedAt != nil && revertedAt == nil }
}

struct CoachChangeDecision: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case accepted
        case declined
        /// Could not be applied: it no longer matched the plan when decided.
        case stale
    }

    var id: String
    var decision: Outcome
    var note: String?
}

/// One plan slot's stored values, or its absence.
struct CoachItemState: Codable, Equatable, Sendable {
    var dayID: String
    var itemID: String
    /// The same record the backup writes for a slot, so whatever reads one
    /// reads the other. Absent where the slot did not exist at that moment.
    var item: BackupService.ItemDTO?
}

// MARK: - Reading and writing

/// The one place dates and layout are decided for both files.
enum CoachJSON {

    /// Sorted keys so the same record is the same bytes, like the backup.
    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    /// Accepts the whole-second `Z` form the contract shows and also a
    /// fractional-second or `+00:00` form: a Python `isoformat()` writes either,
    /// and refusing a proposal over its timestamp would be a poor reason.
    static func decoded<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let whole = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = whole.date(from: text) ?? fractional.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return try decoder.decode(type, from: data)
    }
}
