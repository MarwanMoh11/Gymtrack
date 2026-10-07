import Foundation
import SwiftData
@testable import GymTrack

/// The plan every coach suite runs against, and proposals written as JSON so
/// each check also goes through the decoder the phone uses on the file the Mac
/// pushes. Shared by `CoachApplyTests`, `CoachValidationTests` and
/// `CoachModelTests`.
enum CoachFixture {

    static func uuid(_ n: Int) -> UUID { PersistenceFixtures.uuid(n) }

    static func id(_ n: Int) -> String { uuid(n).uuidString }

    static let planID = id(0x100)
    static let dayA = id(0x200)
    static let dayB = id(0x201)
    static let restDay = id(0x202)
    static let soloDay = id(0x203)
    static let bench = id(0x301)
    static let fly = id(0x302)
    static let curl = id(0x303)
    static let row = id(0x304)
    static let plank = id(0x305)
    static let squat = id(0x306)

    static let proposalID = "6F1C0000-0000-0000-0000-000000000001"

    /// A folder of its own standing in for `Documents/Coach`, so no test reads
    /// another's decisions. The caller removes it with `discard`.
    static func temporaryStore() -> CoachStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("coach-tests-\(UUID().uuidString)", isDirectory: true)
        return CoachStore(root: root)
    }

    static func discard(_ store: CoachStore) {
        try? FileManager.default.removeItem(at: store.root)
    }

    /// The active plan: a push day with three slots, a pull day with a timed
    /// plank, a rest day, and a day with a single slot.
    @MainActor @discardableResult
    static func insertPlan(_ context: ModelContext) throws -> Plan {
        let plan = Plan(name: "Plan", isActive: true)
        plan.id = uuid(0x100)
        context.insert(plan)

        func day(_ n: Int, _ name: String, order: Int, rest: Bool = false) -> PlanDay {
            let day = PlanDay(name: name, order: order, isRest: rest)
            day.id = uuid(n)
            day.plan = plan
            context.insert(day)
            return day
        }
        func item(_ n: Int, _ catalogID: String, _ name: String, order: Int, sets: Int, low: Int, high: Int,
                  rest: Int? = nil, weight: Double = 0, in day: PlanDay) {
            let item = PlanItem(catalogID: catalogID, name: name, order: order, targetSets: sets,
                                targetRepsLow: low, targetRepsHigh: high, targetWeightKg: weight,
                                restSeconds: rest)
            item.id = uuid(n)
            item.day = day
            context.insert(item)
        }

        let a = day(0x200, "Push", order: 0)
        item(0x301, "barbell-bench-press", "Barbell Bench Press", order: 0, sets: 4, low: 8, high: 12, in: a)
        item(0x302, "dumbbell-fly", "Dumbbell Fly", order: 1, sets: 3, low: 10, high: 15, rest: 60, in: a)
        item(0x303, "dumbbell-curl", "Dumbbell Bicep Curl", order: 2, sets: 3, low: 8, high: 12, weight: 12.5, in: a)
        let b = day(0x201, "Pull", order: 1)
        item(0x304, "barbell-row", "Bent Over Barbell Row", order: 0, sets: 3, low: 8, high: 12, in: b)
        item(0x305, "plank-bodyweight", "Standard Plank", order: 1, sets: 3, low: 0, high: 0, in: b)
        _ = day(0x202, "Rest", order: 2, rest: true)
        let solo = day(0x203, "Legs", order: 3)
        item(0x306, "barbell-back-squat", "Barbell Back Squat", order: 0, sets: 3, low: 5, high: 8, in: solo)
        try context.save()
        return plan
    }

    @MainActor static func day(_ dayID: String, _ context: ModelContext) throws -> PlanDay? {
        let id = UUID(uuidString: dayID)!
        return try context.fetch(FetchDescriptor<PlanDay>()).first { $0.id == id }
    }

    @MainActor static func items(of dayID: String, _ context: ModelContext) throws -> [PlanItem] {
        (try day(dayID, context)?.items ?? []).sorted { $0.order < $1.order }
    }

    @MainActor static func item(_ itemID: String, _ context: ModelContext) throws -> PlanItem? {
        let id = UUID(uuidString: itemID)!
        return try context.fetch(FetchDescriptor<PlanItem>()).first { $0.id == id }
    }

    // MARK: Proposals

    /// One change, with the required `reason`, `lever` and `evidence` filled in
    /// unless a check overrides them.
    static func change(_ id: String, _ kind: String, day: String? = nil, item: String? = nil,
                       expect: [String: Any]? = nil, to: [String: Any]? = nil,
                       extra: [String: Any] = [:]) -> [String: Any] {
        var change: [String: Any] = [
            "id": id, "kind": kind,
            "reason": "Because the numbers say so.", "lever": "volume",
            "evidence": [["metric": "chest.weeklyFractionalSets", "value": 7.5]],
        ]
        if let day { change["dayID"] = day }
        if let item { change["itemID"] = item }
        if let expect { change["expect"] = expect }
        if let to { change["to"] = to }
        for (key, value) in extra { change[key] = value }
        return change
    }

    static func proposalJSON(id: String = proposalID, planID: String = planID,
                             changes: [[String: Any]], extra: [String: Any] = [:]) throws -> Data {
        var object: [String: Any] = [
            "format": "gymtrack-coach-proposal", "version": 1, "id": id,
            "createdAt": "2026-10-03T18:20:00Z", "planID": planID,
            "summary": "Two plain sentences.", "changes": changes,
        ]
        for (key, value) in extra { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func proposal(id: String = proposalID, planID: String = planID,
                         changes: [[String: Any]], extra: [String: Any] = [:]) throws -> CoachProposal {
        try CoachJSON.decoded(CoachProposal.self,
                              from: try proposalJSON(id: id, planID: planID, changes: changes, extra: extra))
    }

    /// The first row's status, for the checks that look at one change alone.
    @MainActor static func status(_ change: [String: Any], plans: [Plan]) throws -> CoachValidator.Status {
        CoachValidator.review(try proposal(changes: [change]), plans: plans).rows[0].status
    }
}
