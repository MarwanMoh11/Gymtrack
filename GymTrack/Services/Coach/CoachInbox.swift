import Foundation
import Observation
import SwiftData

/// The phone's side of a coach review, for the screens to read and drive: the
/// proposal waiting in the inbox, what each change would do to the plan as it is
/// now, and the decisions made so far.
///
/// One instance serves the whole app (`shared`), configured at launch. It is
/// observable, so a view that reads it redraws when a decision lands, and it
/// reads the files only when told to: call `reload()` when a screen appears or
/// the app becomes active, since `coach push` can drop a new proposal in while
/// the app is open.
///
/// Nothing here asks the lifter for anything. A review that is never opened
/// costs no taps, and a proposal that cannot be applied is simply not offered.
@Observable
@MainActor
final class CoachInbox {

    static let shared = CoachInbox()

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var store = CoachStore.standard
    @ObservationIgnored private var clock: () -> Date = { .now }
    /// The proposal applied during this launch and not yet left behind. Undo is
    /// for a mis-tap, so it is offered for that one and no other: a decision
    /// from an earlier launch is training history, and erasing it would be
    /// rewriting it. Backing that out later is `revert`.
    @ObservationIgnored private var decidedThisLaunch: String?

    /// The proposal in the inbox checked against the live plan, or nil when
    /// there is none or it cannot be read.
    private(set) var review: CoachValidator.Review?
    /// Set when a file is in the inbox and could not be read, so a settings
    /// screen can say so. Nil when the inbox is empty or readable.
    private(set) var unreadableReason: String?
    private(set) var decisions: [CoachDecision] = []
    /// Ratings given to the proposal in the inbox before it was decided, kept
    /// in `Inbox/ratings.json` until the decision has a record to hold them.
    /// Always the current proposal's: `reload()` drops any that belong to
    /// another.
    private(set) var pendingRatings: [CoachRating] = []

    /// What a rating is filed on. Most screens mean the proposal in front of
    /// the lifter; the history means the record, even while a newer proposal
    /// waits, since a rating given there is about the change already made.
    enum RatingSubject {
        /// The proposal in the inbox: its decision once there is one, the
        /// pending file until then.
        case proposal
        /// `ratableDecision`, whatever is waiting in the inbox.
        case decision
    }

    init() {}

    /// For tests, which point it at a temporary folder and a fixed clock.
    init(context: ModelContext, store: CoachStore, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.store = store
        self.clock = now
        store.prepare()
        reload()
    }

    /// Called once at launch, with the store the rest of the app uses.
    func configure(container: ModelContainer, store: CoachStore = .standard) {
        context = container.mainContext
        self.store = store
        store.prepare()
        reload()
    }

    // MARK: - What the screens read

    var proposal: CoachProposal? { review?.proposal }
    var rows: [CoachValidator.Row] { review?.rows ?? [] }
    var advice: [String] { proposal?.advice ?? [] }

    /// Whether Today should show its quiet line: a proposal waiting, with at
    /// least one change that could be applied, and no decision made about it.
    var showsOnToday: Bool {
        guard let review, review.problem == nil, review.hasApplicableChange else { return false }
        return decision(for: review.proposal.id) == nil
    }

    /// The most recent decision of any kind.
    var latestDecision: CoachDecision? { decisions.last }

    /// The decision on the proposal now in the inbox, if there is one.
    var decisionOnProposal: CoachDecision? { proposal.flatMap { decision(for: $0.id) } }

    /// The edits Settings can back out: the latest still in effect.
    var revertibleDecision: CoachDecision? { decisions.last { $0.isInEffect } }

    /// True for the decision just made on this screen, an apply or a decline
    /// of everything, until it is undone or the app is relaunched. A mis-tap on
    /// "Decline all" is as much a mis-tap as one on Apply, and without this it
    /// would take the proposal off Today for good.
    var canUndoLastDecision: Bool {
        guard let id = decidedThisLaunch else { return false }
        return decisions.contains { $0.proposalID == id && ($0.appliedAt == nil || $0.isInEffect) }
    }

    /// The decision ratings go to: the one on the proposal in the inbox, else
    /// the latest of any kind. A decline-everything counts: "this proposal was
    /// useless" is the most useful rating there is, and a reverted change still
    /// carries what training on it taught.
    var ratableDecision: CoachDecision? { decisionOnProposal ?? latestDecision }

    /// The ratings on `subject`, or none when there is nothing to rate.
    func ratings(on subject: RatingSubject = .proposal) -> [CoachRating] {
        switch filing(for: subject) {
        case .pending: return pendingRatings
        case .decision(let id): return decisions.first { $0.proposalID == id }?.ratings ?? []
        case nil: return []
        }
    }

    /// Whether `addRating` would file anything on `subject`.
    func canRate(on subject: RatingSubject = .proposal) -> Bool {
        filing(for: subject) != nil
    }
    // MARK: - Reading

    func reload() {
        decisions = store.loadDecisions().decisions
        unreadableReason = nil
        pendingRatings = []
        guard let context else {
            review = nil
            return
        }
        guard let data = store.proposalData() else {
            review = nil
            return
        }
        guard let proposal = try? CoachJSON.decoded(CoachProposal.self, from: data) else {
            review = nil
            unreadableReason = "The coach's proposal could not be read."
            return
        }
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        review = CoachValidator.review(proposal, plans: plans)
        pendingRatings = settledPendingRatings(for: proposal.id)
    }

    /// The pending ratings that belong to `proposalID`. A file for another
    /// proposal is deleted: that review was replaced before anyone decided it,
    /// so its ratings never belonged to a decided one. So is a file for a
    /// proposal that has been decided, which holds only what the decision
    /// already carries, left over from a launch that stopped between writing
    /// the record and deleting the file.
    private func settledPendingRatings(for proposalID: String) -> [CoachRating] {
        guard let file = store.loadPendingRatings() else { return [] }
        let sameProposal = file.proposalID.caseInsensitiveCompare(proposalID) == .orderedSame
        if sameProposal, decision(for: proposalID) == nil { return file.ratings }
        try? store.clearPendingRatings()
        return []
    }

    // MARK: - Deciding

    /// Applies the changes in `accepted` and records the decision. Every other
    /// change is recorded as declined, or as stale when it could not have been
    /// applied. An empty set is a decline of the whole proposal, which changes
    /// nothing and records that it was seen.
    ///
    /// - Parameter notes: optional words per change id, kept in the record.
    func apply(accepted: Set<String>, notes: [String: String] = [:]) -> Result<CoachDecision, CoachApplier.Refusal> {
        guard let context, let review, review.problem == nil else {
            return .failure(.init(reason: "There is no proposal to decide on."))
        }
        let proposal = review.proposal
        guard decision(for: proposal.id) == nil else {
            return .failure(.init(reason: "This proposal has already been decided."))
        }
        guard review.hasApplicableChange else {
            return .failure(.init(reason: "None of these changes fit the plan as it is now."))
        }

        let now = clock()
        var decision = CoachApplier.apply(proposal, accepting: accepted, notes: notes,
                                          receivedAt: store.proposalArrivedAt() ?? now, at: now, in: context)
        // Everything the lifter accepted went stale between the screen being
        // drawn and the tap. Recording that as a decision would take the
        // proposal off Today for changes that were never made, so it is left
        // undecided and the screen is redrawn against the plan as it is.
        if !accepted.isEmpty, decision.appliedAt == nil {
            reload()
            return .failure(.init(reason: "The plan changed, and none of those changes fit it any more."))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            return .failure(.init(reason: "The plan could not be saved, so nothing was changed."))
        }

        // Ratings given before the decision go into its record, so the record
        // is complete the moment it exists. No key when there are none.
        if !pendingRatings.isEmpty { decision.ratings = pendingRatings }
        var file = store.loadDecisions()
        file.decisions.append(decision)
        do {
            try store.saveDecisions(file)
        } catch {
            // The edits are in the plan with no record of them. Taking them
            // out again beats a plan that changed with nothing to say why.
            if decision.appliedAt != nil, CoachApplier.restore(decision, in: context) == nil { try? context.save() }
            return .failure(.init(reason: "The decision could not be recorded, so nothing was changed."))
        }
        decisions = file.decisions
        // The ratings now live in the record. If the file survives this, the
        // next reload sees a decision for its proposal and deletes it.
        try? store.clearPendingRatings()
        pendingRatings = []
        decidedThisLaunch = decision.proposalID
        self.review = CoachValidator.review(proposal, plans: (try? context.fetch(FetchDescriptor<Plan>())) ?? [])
        if decision.appliedAt != nil { CoachSnapshot.shared.request() }
        return .success(decision)
    }

    /// Takes back the decision just made, as if it had never happened: the plan
    /// goes back (when anything was applied) and the decision record is erased. A mis-tap is not data, and
    /// a record of it would tell the coach a change was tried and abandoned
    /// when it never was. Ratings people gave in the meantime are not the
    /// mis-tap, so they go back to waiting on the proposal.
    @discardableResult
    func undoLastDecision() -> CoachApplier.Refusal? {
        guard canUndoLastDecision, let id = decidedThisLaunch,
              let decision = decisions.first(where: { $0.proposalID == id }) else {
            return .init(reason: "There is nothing to undo.")
        }
        var file = store.loadDecisions()
        file.decisions.removeAll { $0.proposalID == id }
        // Kept first, so a failure here leaves the decision and its ratings
        // where they are; cleared again if the undo is then refused.
        if let ratings = decision.ratings, !ratings.isEmpty {
            do {
                try store.savePendingRatings(CoachPendingRatings(proposalID: id, ratings: ratings))
            } catch {
                return .init(reason: "The ratings could not be kept, so nothing was undone.")
            }
        }
        if let refusal = takeBack(decision, newRecord: file) {
            if decision.ratings != nil { try? store.clearPendingRatings() }
            return refusal
        }
        decidedThisLaunch = nil
        reload()
        return nil
    }

    /// A decline of everything touched no slot, so there is nothing to put back;
    /// only the record goes.
    private func takeBack(_ decision: CoachDecision, newRecord: CoachDecisionFile) -> CoachApplier.Refusal? {
        guard decision.appliedAt == nil else { return restoreAndRecord(decision, newRecord: newRecord) }
        do {
            try store.saveDecisions(newRecord)
        } catch {
            return .init(reason: "The record could not be written, so nothing was undone.")
        }
        return nil
    }

    /// Backs out the latest applied change set from Settings: the plan goes
    /// back and the record is stamped `revertedAt`, which stays. Training on a
    /// change and then dropping it is real information for the coach.
    ///
    /// Refused, with the reason, when a slot it touched has been edited since.
    @discardableResult
    func revert() -> CoachApplier.Refusal? {
        guard let decision = revertibleDecision else { return .init(reason: "There is nothing to revert.") }
        var file = store.loadDecisions()
        guard let index = file.decisions.firstIndex(where: { $0.proposalID == decision.proposalID }) else {
            return .init(reason: "There is nothing to revert.")
        }
        file.decisions[index].revertedAt = clock()
        if let refusal = restoreAndRecord(decision, newRecord: file) { return refusal }
        decidedThisLaunch = nil
        reload()
        return nil
    }

    /// Puts the plan back and writes the new record, in an order that leaves
    /// the two agreeing whichever step fails: the plan is checked first, the
    /// record written next, and the plan changed last.
    private func restoreAndRecord(_ decision: CoachDecision, newRecord: CoachDecisionFile) -> CoachApplier.Refusal? {
        guard let context else { return .init(reason: "The plan is not available.") }
        let restoration: CoachApplier.Restoration
        switch CoachApplier.prepareRestore(decision, in: context) {
        case .success(let ready): restoration = ready
        case .failure(let refusal): return refusal
        }
        let previous = store.loadDecisions()
        do {
            try store.saveDecisions(newRecord)
        } catch {
            return .init(reason: "The record could not be written, so nothing was changed.")
        }
        restoration.perform()
        do {
            try context.save()
        } catch {
            context.rollback()
            try? store.saveDecisions(previous)
            return .init(reason: "The plan could not be saved, so nothing was changed.")
        }
        CoachSnapshot.shared.request()
        return nil
    }

    // MARK: - Ratings

    /// Where a rating goes: with the decision once there is one, or in the
    /// pending file while the proposal is still undecided.
    private enum Filing: Equatable {
        case pending(String)
        case decision(String)
    }

    private func filing(for subject: RatingSubject) -> Filing? {
        switch subject {
        case .decision:
            return ratableDecision.map { .decision($0.proposalID) }
        case .proposal:
            guard let review else { return latestDecision.map { .decision($0.proposalID) } }
            if let decided = decision(for: review.proposal.id) { return .decision(decided.proposalID) }
            // A proposal that can never be decided would keep its ratings in
            // the pending file until something replaced it, and nothing reads
            // them there, so offering to rate it would only mislead.
            guard review.problem == nil, review.hasApplicableChange else { return nil }
            return .pending(review.proposal.id)
        }
    }

    /// Files a rating on `subject`: the proposal in the inbox by default,
    /// whether or not it has been decided.
    ///
    /// `rater` has no default: a rating from someone the phone was handed to
    /// must never land as the lifter's own, so every caller says whose it is.
    /// `raterName` is kept only for `.other`, and only when given.
    ///
    /// - Returns: the stored rating, or nil when there is nothing to rate or
    ///   the score is outside 1...5.
    @discardableResult
    func addRating(score: Int, rater: CoachRating.Rater, raterName: String? = nil,
                   note: String? = nil, on subject: RatingSubject = .proposal) -> CoachRating? {
        guard (1...5).contains(score), let target = filing(for: subject) else { return nil }
        let rating = CoachRating(rater: rater,
                                 raterName: rater == .other ? raterName.flatMap(Self.trimmed) : nil,
                                 score: score, note: note.flatMap(Self.trimmed), ratedAt: clock())
        let stored: Bool
        switch target {
        case .pending(let id): stored = writePendingRatings(of: id) { $0.append(rating) }
        case .decision(let id): stored = writeRatings(of: id) { $0.append(rating) }
        }
        return stored ? rating : nil
    }

    /// Takes a rating back out, so a mis-tapped score leaves no trace.
    func removeRating(_ rating: CoachRating) {
        if pendingRatings.contains(rating), let id = review?.proposal.id {
            _ = writePendingRatings(of: id) { ratings in
                if let index = ratings.firstIndex(of: rating) { ratings.remove(at: index) }
            }
            return
        }
        guard let target = decisions.last(where: { $0.ratings?.contains(rating) == true }) else { return }
        _ = writeRatings(of: target.proposalID) { ratings in
            if let index = ratings.firstIndex(of: rating) { ratings.remove(at: index) }
        }
    }

    private func writeRatings(of proposalID: String, _ change: (inout [CoachRating]) -> Void) -> Bool {
        var file = store.loadDecisions()
        guard let index = file.decisions.firstIndex(where: { $0.proposalID == proposalID }) else { return false }
        var ratings = file.decisions[index].ratings ?? []
        change(&ratings)
        // An empty list is left out, not written as one: no ratings is the
        // absence of the key, the same as a decision nobody rated.
        file.decisions[index].ratings = ratings.isEmpty ? nil : ratings
        guard (try? store.saveDecisions(file)) != nil else { return false }
        decisions = file.decisions
        return true
    }

    private func writePendingRatings(of proposalID: String, _ change: (inout [CoachRating]) -> Void) -> Bool {
        var ratings = pendingRatings
        change(&ratings)
        // No ratings means no file, for the same reason as above.
        do {
            if ratings.isEmpty {
                try store.clearPendingRatings()
            } else {
                try store.savePendingRatings(CoachPendingRatings(proposalID: proposalID, ratings: ratings))
            }
        } catch {
            return false
        }
        pendingRatings = ratings
        return true
    }

    // MARK: -

    private func decision(for proposalID: String) -> CoachDecision? {
        decisions.last { $0.proposalID.caseInsensitiveCompare(proposalID) == .orderedSame }
    }

    private static func trimmed(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
