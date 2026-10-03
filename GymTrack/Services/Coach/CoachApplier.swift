import Foundation
import SwiftData

/// Edits the plan for an accepted proposal, and puts it back.
///
/// Everything here changes the stored plan objects and leaves the saving to the
/// caller, so the plan and `decisions.json` can be kept in step: a save that
/// fails is rolled back with nothing recorded, and a record that cannot be
/// written has its edits taken out again.
///
/// Edits are made in place. A day and a slot keep their IDs, because the
/// rotation follows the day an earlier session was logged against, and
/// replacing the objects would restart it.
enum CoachApplier {

    /// Why something was not done, in words fit for the screen.
    struct Refusal: Error, Equatable {
        let reason: String
    }

    // MARK: - Apply

    /// Applies the accepted changes that still hold and records the rest as
    /// declined or stale.
    ///
    /// Each accepted change is checked again against the plan as the changes
    /// before it left it, not as the review screen drew it. Two removals that
    /// were each fine alone could empty a day together, and a change that goes
    /// after a slot an earlier one removed has nowhere to go.
    ///
    /// - Returns: the decision to record. `appliedAt` is absent when nothing
    ///   was applied.
    @MainActor
    static func apply(_ proposal: CoachProposal, accepting accepted: Set<String>, notes: [String: String],
                      receivedAt: Date, at now: Date, in context: ModelContext) -> CoachDecision {
        let plans = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        let review = CoachValidator.review(proposal, plans: plans)
        var changeDecisions: [CoachChangeDecision] = []
        var edits = Edits()
        var removed: Set<UUID> = []

        for row in review.rows {
            let change = row.change
            let note = notes[change.id].flatMap(trimmed)
            guard accepted.contains(change.id) else {
                changeDecisions.append(CoachChangeDecision(
                    id: change.id, decision: row.status.isApplicable ? .declined : .stale, note: note))
                continue
            }
            // Only the active plan is ever edited, and only while the review
            // still holds: a proposal that fails as a whole applies nothing.
            guard review.problem == nil, row.status.isApplicable,
                  let plan = CoachValidator.activePlan(in: plans),
                  CoachValidator.status(of: change, in: plan, removed: removed).isApplicable else {
                changeDecisions.append(CoachChangeDecision(id: change.id, decision: .stale, note: note))
                continue
            }
            perform(change, in: plan, edits: &edits, removed: &removed, context: context)
            changeDecisions.append(CoachChangeDecision(id: change.id, decision: .accepted, note: note))
        }

        var decision = CoachDecision(proposalID: proposal.id, receivedAt: receivedAt, decidedAt: now,
                                     changes: changeDecisions)
        if !edits.entries.isEmpty {
            decision.appliedAt = now
            decision.before = edits.entries.map { CoachItemState(dayID: $0.dayID.uuidString,
                                                                 itemID: $0.itemID.uuidString, item: $0.before) }
            decision.after = edits.entries.map { entry in
                let live = plans.lazy.flatMap(\.days).lazy.flatMap(\.items)
                    .first { $0.id == entry.itemID && !removed.contains($0.id) }
                return CoachItemState(dayID: entry.dayID.uuidString, itemID: entry.itemID.uuidString,
                                      item: live.map(BackupService.itemDTO))
            }
        }
        return decision
    }

    /// The slots an apply has touched, each recorded as it stood the first time
    /// it was touched. A slot two changes reach, one by its own edit and one
    /// by being shifted down a place, must come back to its state before
    /// either, so only the first look is kept.
    private struct Edits {
        struct Entry {
            let dayID: UUID
            let itemID: UUID
            /// Nil for a slot the apply created.
            let before: BackupService.ItemDTO?
        }

        private(set) var entries: [Entry] = []
        private var seen: Set<UUID> = []

        mutating func touch(_ item: PlanItem, in day: PlanDay) {
            guard seen.insert(item.id).inserted else { return }
            entries.append(Entry(dayID: day.id, itemID: item.id, before: BackupService.itemDTO(item)))
        }

        mutating func created(_ itemID: UUID, in day: PlanDay) {
            guard seen.insert(itemID).inserted else { return }
            entries.append(Entry(dayID: day.id, itemID: itemID, before: nil))
        }
    }

    @MainActor
    private static func perform(_ change: CoachChange, in plan: Plan, edits: inout Edits,
                                removed: inout Set<UUID>, context: ModelContext) {
        guard let kind = CoachValidator.Kind(rawValue: change.kind),
              let dayID = change.dayID.flatMap(UUID.init(uuidString:)),
              let day = plan.days.first(where: { $0.id == dayID }) else { return }
        let to = change.to ?? CoachValues()
        let item = change.itemID.flatMap(UUID.init(uuidString:)).flatMap { id in day.items.first { $0.id == id } }

        switch kind {
        case .setSets:
            guard let item, let sets = to.targetSets else { return }
            edits.touch(item, in: day)
            item.targetSets = sets
        case .setRepRange:
            guard let item, let low = to.targetRepsLow, let high = to.targetRepsHigh else { return }
            edits.touch(item, in: day)
            item.targetRepsLow = low
            item.targetRepsHigh = high
        case .setRest:
            guard let item, let rest = to.restSeconds else { return }
            edits.touch(item, in: day)
            item.restSeconds = rest
        case .substitute:
            guard let item, let exercise = to.catalogID.flatMap({ ExerciseCatalog.shared.exercise(id: $0) }) else { return }
            edits.touch(item, in: day)
            item.catalogID = exercise.id
            item.name = exercise.name
            item.trackingRaw = exercise.slotTrackingSnapshot
            // The old lift's starting weight means nothing on the new one, and
            // the phone, not the coach, sets loads.
            item.targetWeightKg = 0
        case .addSlot:
            addSlot(to: to, in: day, edits: &edits, removed: removed, context: context)
        case .removeSlot:
            guard let item else { return }
            removeSlot(item, in: day, edits: &edits, removed: &removed, context: context)
        }
    }

    @MainActor
    private static func addSlot(to: CoachValues, in day: PlanDay, edits: inout Edits,
                                removed: Set<UUID>, context: ModelContext) {
        guard let exercise = to.catalogID.flatMap({ ExerciseCatalog.shared.exercise(id: $0) }),
              let sets = to.targetSets, let low = to.targetRepsLow, let high = to.targetRepsHigh else { return }
        let live = day.items.filter { !removed.contains($0.id) }
        var order = (live.map(\.order).max() ?? -1) + 1
        if let afterID = to.afterItemID.flatMap(UUID.init(uuidString:)),
           let after = live.first(where: { $0.id == afterID }) {
            order = after.order + 1
            for later in live where later.order >= order {
                edits.touch(later, in: day)
                later.order += 1
            }
        }
        let item = PlanItem(catalogID: exercise.id, name: exercise.name, order: order,
                            targetSets: sets, targetRepsLow: low, targetRepsHigh: high,
                            restSeconds: to.restSeconds)
        item.trackingRaw = exercise.slotTrackingSnapshot
        item.day = day
        context.insert(item)
        edits.created(item.id, in: day)
    }

    /// Deletes the slot and closes the gap, the way the plan editor does, so
    /// the slots that remain still run 0, 1, 2.
    @MainActor
    private static func removeSlot(_ item: PlanItem, in day: PlanDay, edits: inout Edits,
                                   removed: inout Set<UUID>, context: ModelContext) {
        edits.touch(item, in: day)
        removed.insert(item.id)
        let survivors = day.items.filter { !removed.contains($0.id) }.sorted { $0.order < $1.order }
        context.delete(item)
        for (index, other) in survivors.enumerated() where other.order != index {
            edits.touch(other, in: day)
            other.order = index
        }
    }

    // MARK: - Restore

    /// A checked, ready-to-run way of putting the plan back. Built before
    /// anything is written, so the caller can write the record first and know
    /// the plan will follow.
    struct Restoration {
        fileprivate let steps: [() -> Void]
        fileprivate let days: [PlanDay]
        fileprivate let deleting: Set<UUID>
        fileprivate let restoring: Set<UUID>

        @MainActor
        func perform() {
            for step in steps { step() }
            for day in days { closeGaps(in: day) }
        }

        /// Puts the day's slots back on 0, 1, 2 after the steps ran. A slot the
        /// lifter added since the apply took the next free place, which is the
        /// very place a restored slot is about to take back, and two slots on
        /// one place have no order. The restored slot goes first on a tie, as
        /// it was there before.
        @MainActor
        private func closeGaps(in day: PlanDay) {
            let live = day.items.filter { !deleting.contains($0.id) }
            let ordered = live.enumerated().sorted { a, b in
                let (x, y) = (a.element, b.element)
                if x.order != y.order { return x.order < y.order }
                let (rx, ry) = (restoring.contains(x.id), restoring.contains(y.id))
                return rx != ry ? rx : a.offset < b.offset
            }
            for (index, entry) in ordered.enumerated() where entry.element.order != index {
                entry.element.order = index
            }
        }
    }

    /// Checks that the plan can be put back as the decision found it, and says
    /// why not when it cannot. Changes nothing.
    ///
    /// Only the values an apply changed are written back, and only if the slot
    /// still holds what the apply wrote. A slot the lifter has edited since
    /// (a new rep range, a heavier load) is left alone and the revert refused,
    /// because guessing which of two edits the lifter meant would put numbers
    /// in the plan nobody chose. Every touched slot is checked before any step
    /// is returned, so a refusal never means half a revert.
    @MainActor
    static func prepareRestore(_ decision: CoachDecision, in context: ModelContext) -> Result<Restoration, Refusal> {
        guard let before = decision.before, let after = decision.after, before.count == after.count else {
            return .failure(Refusal(reason: "Nothing was applied, so there is nothing to put back."))
        }
        let days = ((try? context.fetch(FetchDescriptor<Plan>())) ?? []).flatMap(\.days)

        var steps: [() -> Void] = []
        var touchedDays: [PlanDay] = []
        var deleting: Set<UUID> = []
        var restoring: Set<UUID> = []
        for (was, now) in zip(before, after) {
            guard let dayID = UUID(uuidString: was.dayID), let itemID = UUID(uuidString: was.itemID),
                  let day = days.first(where: { $0.id == dayID }) else {
                return .failure(Refusal(reason: "A day this changed is no longer in your plan, so it was left as it is."))
            }
            if !touchedDays.contains(where: { $0.id == day.id }) { touchedDays.append(day) }
            let live = day.items.first { $0.id == itemID }
            switch (was.item, now.item) {
            case let (old?, new?):
                guard let live, let step = revertEdit(old, new, live) else {
                    return .failure(changedSince(live?.name ?? old.name))
                }
                steps.append(step)
            case (nil, let new?):
                guard let live, createdSlotUnchanged(new, live) else { return .failure(changedSince(new.name)) }
                deleting.insert(itemID)
                steps.append { context.delete(live) }
            case (let old?, nil):
                guard live == nil else { return .failure(changedSince(old.name)) }
                restoring.insert(itemID)
                steps.append { recreate(old, id: itemID, in: day, context: context) }
            case (nil, nil):
                continue
            }
        }
        return .success(Restoration(steps: steps, days: touchedDays, deleting: deleting, restoring: restoring))
    }

    /// `prepareRestore` and then the restoring, for callers that have no record
    /// to keep in step.
    @MainActor
    static func restore(_ decision: CoachDecision, in context: ModelContext) -> Refusal? {
        switch prepareRestore(decision, in: context) {
        case .success(let restoration):
            restoration.perform()
            return nil
        case .failure(let refusal):
            return refusal
        }
    }

    private static func changedSince(_ name: String) -> Refusal {
        Refusal(reason: "\(name) has been changed since, so this was left as it is.")
    }

    private enum Field: CaseIterable {
        case catalogID, name, order, targetSets, targetRepsLow, targetRepsHigh, targetWeightKg
        case targetSeconds, tracking, restSeconds
    }

    private static func differs(_ a: BackupService.ItemDTO, _ b: BackupService.ItemDTO, _ field: Field) -> Bool {
        switch field {
        case .catalogID: a.catalogID != b.catalogID
        case .name: a.name != b.name
        case .order: a.order != b.order
        case .targetSets: a.targetSets != b.targetSets
        case .targetRepsLow: a.targetRepsLow != b.targetRepsLow
        case .targetRepsHigh: a.targetRepsHigh != b.targetRepsHigh
        case .targetWeightKg: a.targetWeightKg != b.targetWeightKg
        case .targetSeconds: a.targetSeconds != b.targetSeconds
        case .tracking: a.tracking != b.tracking
        case .restSeconds: a.restSeconds != b.restSeconds
        }
    }

    /// An absent value restores as what absent stands for in the backup: a
    /// zero for a rep target or a weight, and no override for rest.
    private static func write(_ field: Field, from dto: BackupService.ItemDTO, to item: PlanItem) {
        switch field {
        case .catalogID: item.catalogID = dto.catalogID
        case .name: item.name = dto.name
        case .order: item.order = dto.order
        case .targetSets: item.targetSets = dto.targetSets
        case .targetRepsLow: item.targetRepsLow = dto.targetRepsLow ?? 0
        case .targetRepsHigh: item.targetRepsHigh = dto.targetRepsHigh ?? 0
        case .targetWeightKg: item.targetWeightKg = dto.targetWeightKg ?? 0
        case .targetSeconds: if let seconds = dto.targetSeconds { item.targetSeconds = seconds }
        case .tracking: item.trackingRaw = dto.tracking
        case .restSeconds: item.restSeconds = dto.restSeconds
        }
    }

    /// The step that undoes one edited slot, or nil when the slot no longer
    /// holds what the apply wrote in the fields it changed.
    @MainActor
    private static func revertEdit(_ old: BackupService.ItemDTO, _ new: BackupService.ItemDTO,
                                   _ live: PlanItem) -> (() -> Void)? {
        let now = BackupService.itemDTO(live)
        let touched = Field.allCases.filter { differs(old, new, $0) }
        guard touched.allSatisfy({ !differs(now, new, $0) }) else { return nil }
        return { for field in touched { write(field, from: old, to: live) } }
    }

    /// A slot the apply created is still the slot it made when its exercise,
    /// sets, reps and rest are as written. Its place in the day is left out:
    /// the lifter deleting some other exercise later closes the gap and moves
    /// it, and that is no reason to keep it.
    @MainActor
    private static func createdSlotUnchanged(_ made: BackupService.ItemDTO, _ live: PlanItem) -> Bool {
        let now = BackupService.itemDTO(live)
        let prescription: [Field] = [.catalogID, .name, .targetSets, .targetRepsLow, .targetRepsHigh, .restSeconds]
        return prescription.allSatisfy { !differs(now, made, $0) }
    }

    /// Puts a deleted slot back with the ID it had, so history that names it
    /// still finds it.
    @MainActor
    private static func recreate(_ dto: BackupService.ItemDTO, id: UUID, in day: PlanDay, context: ModelContext) {
        let item = PlanItem(catalogID: dto.catalogID, name: dto.name, order: dto.order,
                            targetSets: dto.targetSets, targetRepsLow: dto.targetRepsLow ?? 0,
                            targetRepsHigh: dto.targetRepsHigh ?? 0, targetWeightKg: dto.targetWeightKg ?? 0,
                            restSeconds: dto.restSeconds)
        item.id = id
        if let seconds = dto.targetSeconds { item.targetSeconds = seconds }
        item.trackingRaw = dto.tracking
        item.notes = dto.notes ?? ""
        item.day = day
        context.insert(item)
    }

    private static func trimmed(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
