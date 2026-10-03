import Foundation

/// Checks a proposal against the plan as it stands now, change by change.
///
/// The Mac validates a proposal before it is pushed, but the plan can move
/// between the push and the tap, and an edit made against yesterday's numbers
/// is exactly the false detail the plan must not take. So the phone re-checks
/// everything against the live plan, and a change whose `expect` no longer
/// matches is shown with its reason and can never be applied.
enum CoachValidator {

    /// The six kinds the contract allows. Anything else is rejected by name.
    enum Kind: String, CaseIterable {
        case setSets, setRepRange, setRest, substitute, addSlot, removeSlot
    }

    static let levers: Set<String> = [
        "effort", "volume", "priority", "exerciseChoice", "pain", "repRange", "rest",
    ]

    enum Status: Equatable, Sendable {
        case applicable
        /// The plan has moved on since this was written. Worth showing, never
        /// applicable.
        case stale(String)
        /// The change itself breaks a rule, whatever the plan holds.
        case invalid(String)

        var isApplicable: Bool { self == .applicable }

        /// Plain words for the review screen; nil when there is nothing wrong.
        var reason: String? {
            switch self {
            case .applicable: nil
            case .stale(let reason), .invalid(let reason): reason
            }
        }
    }

    /// One change as the review screen draws it.
    struct Row: Identifiable, Equatable {
        let change: CoachChange
        let status: Status
        let dayName: String?
        let exerciseName: String?
        /// What the slot reads now, and what it would read after. Plain text,
        /// ready to show side by side.
        let before: String
        let after: String

        var id: String { change.id }
    }

    struct Review {
        let proposal: CoachProposal
        let rows: [Row]
        /// Set when the proposal as a whole breaks a rule, in which case every
        /// row is invalid and nothing can be applied.
        let problem: String?

        var hasApplicableChange: Bool { rows.contains { $0.status.isApplicable } }
        var applicableIDs: [String] { rows.filter { $0.status.isApplicable }.map(\.id) }
    }

    // MARK: - Whole proposal

    static func activePlan(in plans: [Plan]) -> Plan? {
        plans.first { $0.isActive }
    }

    static func review(_ proposal: CoachProposal, plans: [Plan]) -> Review {
        let plan = activePlan(in: plans)
        if let problem = problem(with: proposal) {
            return Review(proposal: proposal, rows: proposal.changes.map {
                Row(change: $0, status: .invalid(problem), dayName: nil, exerciseName: nil, before: "", after: "")
            }, problem: problem)
        }
        let rows = proposal.changes.map { change -> Row in
            guard let plan else {
                return Row(change: change, status: .stale("There is no active plan to change."),
                           dayName: nil, exerciseName: nil, before: "", after: "")
            }
            guard UUID(uuidString: proposal.planID) == plan.id else {
                return Row(change: change, status: .stale("This was written for a different plan than the active one."),
                           dayName: nil, exerciseName: nil, before: "", after: "")
            }
            return row(for: change, in: plan)
        }
        return Review(proposal: proposal, rows: rows, problem: nil)
    }

    /// The rules that are about the proposal rather than any one change.
    static func problem(with proposal: CoachProposal) -> String? {
        if proposal.format != CoachProposal.format { return "This is not a coach proposal." }
        if proposal.version != CoachProposal.currentVersion {
            return "This proposal is written in a format this version of the app does not read."
        }
        if UUID(uuidString: proposal.id) == nil { return "The proposal has no valid ID." }
        if proposal.changes.isEmpty { return "The proposal has no changes." }
        if proposal.changes.count > CoachProposal.maxChanges {
            return "The proposal has more than \(CoachProposal.maxChanges) changes."
        }
        if Set(proposal.changes.map(\.id)).count != proposal.changes.count {
            return "Two changes share an ID."
        }
        let itemIDs = proposal.changes.compactMap { $0.itemID.map { $0.lowercased() } }
        if Set(itemIDs).count != itemIDs.count { return "Two changes are about the same exercise." }
        return nil
    }

    // MARK: - One change

    static func row(for change: CoachChange, in plan: Plan, removed: Set<UUID> = []) -> Row {
        let status = status(of: change, in: plan, removed: removed)
        let day = change.dayID.flatMap(UUID.init(uuidString:)).flatMap { id in plan.days.first { $0.id == id } }
        let item = change.itemID.flatMap(UUID.init(uuidString:)).flatMap { id in
            day?.items.first { $0.id == id && !removed.contains(id) }
        }
        let kind = Kind(rawValue: change.kind)
        let (before, after) = description(of: change, kind: kind, item: item)
        return Row(change: change, status: status, dayName: day?.name,
                   exerciseName: item?.name ?? change.to?.name, before: before, after: after)
    }

    /// - Parameter removed: slots an earlier change in the same apply has
    ///   already deleted. A deleted row stays in `day.items` until the save, so
    ///   without this a later change would count a slot that is already gone.
    static func status(of change: CoachChange, in plan: Plan, removed: Set<UUID> = []) -> Status {
        guard let kind = Kind(rawValue: change.kind) else {
            return .invalid("The phone does not know this kind of change.")
        }
        if let problem = problem(with: change) { return .invalid(problem) }
        if let problem = shape(of: change, kind: kind) { return .invalid(problem) }

        guard let dayID = change.dayID.flatMap(UUID.init(uuidString:)) else {
            return .invalid("It does not name a day.")
        }
        guard let day = plan.days.first(where: { $0.id == dayID }) else {
            return .stale("That day is no longer in the plan.")
        }
        let live = day.items.filter { !removed.contains($0.id) }

        if kind == .addSlot {
            return addSlotStatus(change, day: day, live: live)
        }

        guard let itemID = change.itemID.flatMap(UUID.init(uuidString:)) else {
            return .invalid("It does not name an exercise.")
        }
        guard let item = live.first(where: { $0.id == itemID }) else {
            return .stale("That exercise is no longer in this day.")
        }
        return itemStatus(change, kind: kind, item: item, liveCount: live.count)
    }

    // MARK: Rules that need no plan

    /// What every change must carry, whatever its kind.
    private static func problem(with change: CoachChange) -> String? {
        if change.reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            return "It gives no reason."
        }
        guard let lever = change.lever, levers.contains(lever) else {
            return "It names no known lever."
        }
        if change.evidence == nil { return "It lists no evidence." }
        return nil
    }

    /// The limits in the contract, checked on the values alone.
    private static func shape(of change: CoachChange, kind: Kind) -> String? {
        let expect = change.expect ?? CoachValues()
        let to = change.to ?? CoachValues()
        switch kind {
        case .setSets:
            guard let from = expect.targetSets, let target = to.targetSets else {
                return "It does not say the sets it expects and the sets it wants."
            }
            if abs(target - from) != 1 { return "Sets change by exactly one at a time." }
            if !(1...10).contains(target) { return "Sets must stay between 1 and 10." }
        case .setRepRange:
            guard expect.targetRepsLow != nil, expect.targetRepsHigh != nil,
                  let low = to.targetRepsLow, let high = to.targetRepsHigh else {
                return "It does not give both ends of the rep range, before and after."
            }
            if !(1...30).contains(low) || !(1...30).contains(high) || low > high {
                return "A rep range must run from 1 up to at most 30, low to high."
            }
            if expect.targetRepsLow == low && expect.targetRepsHigh == high { return "It changes nothing." }
        case .setRest:
            guard let from = expect.restSeconds, let target = to.restSeconds else {
                return "It does not say the rest it expects and the rest it wants."
            }
            if !(30...600).contains(target) { return "Rest must be between 30 and 600 seconds." }
            if from == target { return "It changes nothing." }
        case .substitute:
            guard let from = expect.catalogID, let target = to.catalogID, to.name != nil else {
                return "It does not name the exercise it replaces and the one it puts in."
            }
            if from == target { return "It swaps an exercise for itself." }
            if let problem = exerciseProblem(catalogID: target, name: to.name) { return problem }
        case .addSlot:
            if !expect.isEmpty { return "A new slot expects nothing to be there already." }
            guard let id = to.catalogID, to.name != nil, let sets = to.targetSets,
                  let low = to.targetRepsLow, let high = to.targetRepsHigh, let rest = to.restSeconds else {
                return "It does not give the exercise, sets, reps and rest for the new slot."
            }
            if !(1...10).contains(sets) { return "Sets must stay between 1 and 10." }
            if !(1...30).contains(low) || !(1...30).contains(high) || low > high {
                return "A rep range must run from 1 up to at most 30, low to high."
            }
            if !(30...600).contains(rest) { return "Rest must be between 30 and 600 seconds." }
            if let after = to.afterItemID, UUID(uuidString: after) == nil {
                return "The exercise it goes after is not a valid ID."
            }
            if let problem = exerciseProblem(catalogID: id, name: to.name) { return problem }
        case .removeSlot:
            if expect.catalogID == nil { return "It does not say which exercise it expects to remove." }
            if !(change.to ?? CoachValues()).isEmpty { return "Removing a slot sets nothing." }
        }
        return nil
    }

    /// The exercise a change would put in the plan has to be one the library
    /// knows, measured in reps, and called what the library calls it. A name
    /// that disagrees with its ID means the coach has the wrong exercise in
    /// mind, and the review screen would then show one lift while the plan
    /// took another.
    private static func exerciseProblem(catalogID: String, name: String?) -> String? {
        guard let exercise = ExerciseCatalog.shared.exercise(id: catalogID) else {
            return "That exercise is not in the library."
        }
        if exercise.tracking == .duration { return "\(exercise.name) is a timed exercise, which a coach cannot set." }
        if let name, name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(exercise.name) != .orderedSame {
            return "The name \"\(name)\" is not what the library calls that exercise (\(exercise.name))."
        }
        return nil
    }

    // MARK: Rules that need the plan

    private static func itemStatus(_ change: CoachChange, kind: Kind, item: PlanItem, liveCount: Int) -> Status {
        let expect = change.expect ?? CoachValues()
        switch kind {
        case .setSets:
            if item.targetSets != expect.targetSets {
                return .stale("It was written for \(plural(expect.targetSets ?? 0, "set")); \(item.name) now has \(item.targetSets).")
            }
        case .setRepRange:
            if item.tracking == .duration { return .invalid("\(item.name) is timed, so it has no rep range.") }
            if item.targetRepsLow != expect.targetRepsLow || item.targetRepsHigh != expect.targetRepsHigh {
                return .stale("It was written for \(repRange(expect.targetRepsLow ?? 0, expect.targetRepsHigh ?? 0)) reps; \(item.name) is now \(item.repRangeLabel).")
            }
        case .setRest:
            if item.resolvedRestSeconds != expect.restSeconds {
                return .stale("It was written for \(expect.restSeconds ?? 0) s rest; \(item.name) now has \(item.resolvedRestSeconds) s.")
            }
        case .substitute:
            if item.tracking == .duration { return .invalid("\(item.name) is timed, so it cannot be swapped by a coach.") }
            if !sameExercise(item.catalogID, expect.catalogID) {
                return .stale("It was written for a different exercise; this slot is now \(item.name).")
            }
        case .removeSlot:
            if !sameExercise(item.catalogID, expect.catalogID) {
                return .stale("It was written for a different exercise; this slot is now \(item.name).")
            }
            if liveCount < 2 { return .invalid("It would leave the day with no exercises.") }
        case .addSlot:
            break
        }
        return .applicable
    }

    private static func addSlotStatus(_ change: CoachChange, day: PlanDay, live: [PlanItem]) -> Status {
        if day.isRest { return .invalid("\(day.name) is a rest day.") }
        if let after = change.to?.afterItemID.flatMap(UUID.init(uuidString:)),
           !live.contains(where: { $0.id == after }) {
            return .stale("The exercise it goes after is no longer in this day.")
        }
        return .applicable
    }

    /// Two catalog IDs that mean one exercise, once the library's merged
    /// duplicates are sent to the one that survived.
    private static func sameExercise(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        return a == b || ExerciseCatalog.canonicalID(for: a) == ExerciseCatalog.canonicalID(for: b)
    }

    // MARK: Wording

    private static func description(of change: CoachChange, kind: Kind?, item: PlanItem?) -> (String, String) {
        let to = change.to ?? CoachValues()
        switch kind {
        case .setSets:
            return (item.map { plural($0.targetSets, "set") } ?? missing, to.targetSets.map { plural($0, "set") } ?? "")
        case .setRepRange:
            return (item.map { "\($0.repRangeLabel) reps" } ?? missing,
                    to.targetRepsLow.flatMap { low in to.targetRepsHigh.map { "\(repRange(low, $0)) reps" } } ?? "")
        case .setRest:
            let now = item.map { $0.restSeconds == nil ? "\($0.resolvedRestSeconds) s rest (default)" : "\($0.resolvedRestSeconds) s rest" }
            return (now ?? missing, to.restSeconds.map { "\($0) s rest" } ?? "")
        case .substitute:
            let target = to.catalogID.flatMap { ExerciseCatalog.shared.exercise(id: $0)?.name } ?? to.name ?? ""
            return (item?.name ?? missing, target)
        case .addSlot:
            let name = to.catalogID.flatMap { ExerciseCatalog.shared.exercise(id: $0)?.name } ?? to.name ?? "An exercise"
            var line = name
            if let sets = to.targetSets, let low = to.targetRepsLow, let high = to.targetRepsHigh {
                line += " · \(sets) × \(repRange(low, high))"
            }
            if let rest = to.restSeconds { line += " · \(rest) s rest" }
            return ("Not in this day", line)
        case .removeSlot:
            return (item.map { "\($0.name) · \($0.targetSets) × \($0.repRangeLabel)" } ?? missing, "Removed")
        case nil:
            return ("", "")
        }
    }

    private static let missing = "Not in the plan"

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// The en dash the plan screens use for a range.
    private static func repRange(_ low: Int, _ high: Int) -> String {
        low == high ? "\(low)" : "\(low)–\(high)"
    }
}
