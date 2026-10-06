import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// The coach loop's edges on the phone: the slot ID the backup carries and
/// restore keeps, the two JSON files the loop passes through the phone, and the
/// snapshot file the Mac pulls.
///
/// The rest of the backup's set and day IDs are in `BackupExportFidelityTests`,
/// and the paced export the snapshot is written from in `BackupPacingTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoachModelTests {
    typealias F = CoachFixture

    private let t0 = TestClock.at("2026-09-21T14:13:20")
    private let stamp = PersistenceFixtures.stamp(at: TestClock.at("2026-09-22T22:30:00"), version: "2.1", build: "30")

    // MARK: - Backup slot IDs

    @Test func everySlotIsExportedUnderItsOwnIDAndARestoreKeepsIt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try F.insertPlan(context)
        let live = Set(try context.fetch(FetchDescriptor<PlanItem>()).map(\.id))

        let archive = try BackupService.makeArchive(context: context, stamp: stamp)
        #expect(archive.version == 2)
        let plan = try #require(archive.plans.first)
        let exported = Set(plan.days.flatMap(\.items).compactMap(\.id))
        #expect(exported.count == 6 && exported == live, "Every slot is exported under its own ID")
        #expect(plan.id == F.uuid(0x100) && plan.days.map(\.id).contains(F.uuid(0x200)),
                "Plan and day IDs were already exported and still are")

        let data = try BackupService.encoded(archive)
        let decoded = try BackupService.decodedArchive(from: data)
        #expect(Set(decoded.plans.flatMap(\.days).flatMap(\.items).compactMap(\.id)) == live, "Slot IDs survive the file")

        try BackupService.restore(data: data, context: context)
        #expect(Set(try context.fetch(FetchDescriptor<PlanItem>()).map(\.id)) == live)
        #expect(try F.item(F.bench, context)?.day?.id == F.uuid(0x200), "A restored slot is still in its day")
    }

    @Test func aFileFromBeforeSlotIDsWritesNoKeyAndRestoresUnderNewDistinctOnes() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try F.insertPlan(context)
        let live = Set(try context.fetch(FetchDescriptor<PlanItem>()).map(\.id))
        var older = try BackupService.makeArchive(context: context, stamp: stamp)
        for d in older.plans[0].days.indices {
            for i in older.plans[0].days[d].items.indices { older.plans[0].days[d].items[i].id = nil }
        }

        let data = try BackupService.encoded(older)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("00000000-0000-0000-0000-000000000301"), "A slot with no ID writes no id")
        #expect(!text.contains("null"), "No null anywhere in the file")

        try BackupService.restore(data: data, context: context)
        let fresh = try context.fetch(FetchDescriptor<PlanItem>()).map(\.id)
        #expect(fresh.count == 6 && Set(fresh).count == 6, "Every slot restores under an ID of its own")
        #expect(Set(fresh).isDisjoint(with: live), "The new IDs are not the old ones")
    }

    @Test func aRepeatedSlotIDStaysWithTheFirstSlotAndTheSecondGetsAnother() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        try F.insertPlan(context)
        var repeated = try BackupService.makeArchive(context: context, stamp: stamp)
        repeated.plans[0].days[0].items[1].id = repeated.plans[0].days[0].items[0].id

        try BackupService.restore(data: try BackupService.encoded(repeated), context: context)

        let items = try context.fetch(FetchDescriptor<PlanItem>())
        #expect(items.count == 6 && Set(items.map(\.id)).count == 6, "Replaced, not refused")
        #expect(items.first { $0.catalogID == "barbell-bench-press" }?.id == F.uuid(0x301))
        #expect(items.first { $0.catalogID == "dumbbell-fly" }?.id != F.uuid(0x301))
    }

    // MARK: - Proposal

    @Test func theContractsExampleDecodesUnknownKeysAndAll() throws {
        let proposal = try CoachJSON.decoded(CoachProposal.self, from: Data(Self.contractExample.utf8))

        #expect(proposal.changes.count == 2 && proposal.advice == ["Push the last set closer to failure."])
        #expect(proposal.createdAt == TestClock.at("2026-10-03T18:20:00"), "createdAt reads as the date it names")
        let first = try #require(proposal.changes.first)
        #expect(first.expect?.targetSets == 3 && first.to?.targetSets == 4)
        #expect(first.review?.verdict == "agree" && first.review?.disputed == false)
        let second = proposal.changes[1]
        #expect(second.review == nil, "A change with no review has none")
        #expect(second.expect?.isEmpty == true)
        #expect(second.evidence?.first?.value == .text("high"), "A word as evidence is kept, not fatal")
    }

    @Test func createdAtMayCarryFractionalSecondsAndAnOffset() throws {
        let fractional = Self.contractExample.replacingOccurrences(of: "2026-10-03T18:20:00Z",
                                                                   with: "2026-10-03T18:20:00.250000+00:00")
        let proposal = try CoachJSON.decoded(CoachProposal.self, from: Data(fractional.utf8))

        #expect(proposal.createdAt.timeIntervalSince(TestClock.at("2026-10-03T18:20:00")) == 0.25)
    }

    @Test func aValueOfTheWrongTypeMakesTheFileUnreadableRatherThanGuessedAt() {
        let wrongType = Self.contractExample.replacingOccurrences(of: "\"targetSets\": 3 }",
                                                                  with: "\"targetSets\": \"three\" }")

        #expect(throws: (any Error).self) { try CoachJSON.decoded(CoachProposal.self, from: Data(wrongType.utf8)) }
    }

    // MARK: - Decisions

    @Test func aDecisionWritesTheKeysOnlyOfWhatHappened() throws {
        let bare = String(decoding: try CoachJSON.encoded(CoachDecisionFile(decisions: [declined])), as: UTF8.self)
        for key in ["appliedAt", "before", "after", "revertedAt", "note", "null"] {
            #expect(!bare.contains(key), "A decision nobody applied has no \(key)")
        }
        #expect(bare.contains("\"format\" : \"gymtrack-coach-decisions\"") && bare.contains("\"version\" : 1"),
                "The file names its format and version")

        let full = String(decoding: try CoachJSON.encoded(CoachDecisionFile(decisions: [applied])), as: UTF8.self)
        #expect(!full.contains("revertedAt") && !full.contains("null"), "An applied decision has no revertedAt and no null")
        #expect(full.contains("\"item\" : {") && full.components(separatedBy: "\"item\"").count == 2,
                "A slot that did not exist has no item key at all")
    }

    @Test func decisionsRoundTripAndAnUnreadableFileIsMovedAsideNotOverwritten() throws {
        let store = F.temporaryStore()
        defer { F.discard(store) }
        #expect(store.loadDecisions().decisions.isEmpty, "No file reads as no decisions")
        store.prepare()
        #expect(FileManager.default.fileExists(atPath: store.inboxURL.path), "The inbox is created ahead of the push")

        let both = CoachDecisionFile(decisions: [declined, applied])
        try store.saveDecisions(both)
        #expect(store.loadDecisions() == both)

        try Data("{ not json".utf8).write(to: store.decisionsURL)
        #expect(store.loadDecisions().decisions.isEmpty, "An unreadable file reads as none")
        let names = try FileManager.default.contentsOfDirectory(atPath: store.root.path)
        #expect(names.contains { $0.hasPrefix("decisions.unreadable-") } && !names.contains("decisions.json"))
    }

    @Test func aDecisionsFileWithTheOldRatingsKeyStillReadsAndDropsItOnTheNextWrite() throws {
        let store = F.temporaryStore()
        defer { F.discard(store) }
        store.prepare()
        // Written before ratings were taken out.
        let legacy = """
        {"format":"gymtrack-coach-decisions","version":1,"decisions":[{"proposalID":"P9",
        "receivedAt":"2026-09-20T10:00:00Z","decidedAt":"2026-09-20T10:05:00Z",
        "changes":[{"id":"c1","decision":"accepted"}],
        "ratings":[{"rater":"self","score":4,"ratedAt":"2026-09-21T10:00:00Z"}]}]}
        """
        try Data(legacy.utf8).write(to: store.decisionsURL)

        let old = store.loadDecisions()
        #expect(old.decisions.map(\.proposalID) == ["P9"] && old.decisions.first?.changes.first?.decision == .accepted)
        try store.saveDecisions(old)
        #expect(!((try? String(contentsOf: store.decisionsURL, encoding: .utf8)) ?? "").contains("ratings"))
    }

    @Test func preparingTheStoreDeletesTheOldPendingRatingsFile() throws {
        let store = F.temporaryStore()
        defer { F.discard(store) }
        store.prepare()
        let leftover = store.inboxURL.appendingPathComponent("ratings.json")
        try Data("{}".utf8).write(to: leftover)

        store.prepare()

        #expect(!FileManager.default.fileExists(atPath: leftover.path), "Never left to be pulled")
    }

    @Test func theSnapshotIsReplacedWholeWithNoTemporaryFileBesideIt() throws {
        let store = F.temporaryStore()
        defer { F.discard(store) }
        store.prepare()

        try store.writeSnapshot(Data("one".utf8))
        try store.writeSnapshot(Data("two".utf8))

        #expect(try Data(contentsOf: store.snapshotURL) == Data("two".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: store.root.path)
        #expect(names.allSatisfy { !$0.contains(".tmp") && !$0.hasPrefix(".") })
    }

    // MARK: - Snapshot

    @Test func aLaunchWithNoSnapshotWritesOneAndItIsTheExportByteForByte() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let container = try TestStore.container()
        try F.insertPlan(container.mainContext)
        let store = F.temporaryStore()
        defer { F.discard(store) }
        let snapshot = CoachSnapshot()
        snapshot.quietPeriod = .zero
        defer { snapshot.stop() }

        snapshot.start(container: container, store: store)
        await snapshot.settled()

        #expect(store.hasSnapshot, "A launch with no snapshot writes one")
        #expect(FileManager.default.fileExists(atPath: store.inboxURL.path), "Launch creates the inbox")
        // What the Mac reads must be what the Settings export writes.
        await snapshot.writeNow(stamp: stamp)
        let export = try BackupService.encoded(BackupService.makeArchive(context: container.mainContext, stamp: stamp))
        #expect(try Data(contentsOf: store.snapshotURL) == export)
    }

    /// Each "does not ask" is followed by a save that does ask, looked at the
    /// same way with no sleep between the save and the look. A notification
    /// that arrived late would fail that check rather than let the quiet one
    /// before it pass for nothing.
    @Test func onlyAPlanEditOrAFinishedSessionAsksForANewSnapshot() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let container = try TestStore.container()
        let context = container.mainContext
        try F.insertPlan(context)
        let store = F.temporaryStore()
        defer { F.discard(store) }
        store.prepare()
        try store.writeSnapshot(BackupService.encoded(BackupService.makeArchive(context: context, stamp: stamp)))

        let quiet = CoachSnapshot()
        quiet.quietPeriod = .zero
        defer { quiet.stop() }
        quiet.start(container: container, store: store)
        await quiet.settled()
        #expect(quiet.lastWrittenAt == nil, "A launch with a snapshot already on disk writes none")

        // Logging saves after every set; none of it should rewrite the file.
        context.insert(WorkoutSession(title: "Push", planDayID: F.uuid(0x200), startedAt: t0))
        try context.save()
        await quiet.settled()
        #expect(quiet.lastWrittenAt == nil, "Starting a workout does not ask for a snapshot")

        let bench = try F.item(F.bench, context)
        bench?.targetSets = 5
        bench?.targetRepsHigh = 10
        try context.save()
        await quiet.settled()
        #expect(quiet.lastWrittenAt != nil, "Saving a plan edit asks for a snapshot")

        // A session that is already finished when it is inserted, as one
        // logged afterwards is.
        let later = CoachSnapshot()
        later.quietPeriod = .zero
        defer { later.stop() }
        later.start(container: container, store: store)
        quiet.stop()
        await later.settled()
        #expect(later.lastWrittenAt == nil)
        let past = WorkoutSession(title: "Pull", planDayID: F.uuid(0x201), startedAt: t0.addingTimeInterval(-86_400))
        past.endedAt = past.startedAt
        context.insert(past)
        try context.save()
        await later.settled()
        #expect(later.lastWrittenAt != nil, "Saving a finished session asks for a snapshot")
    }

    // MARK: - Fixtures

    private var declined: CoachDecision {
        CoachDecision(proposalID: "P1", receivedAt: t0, decidedAt: t0,
                      changes: [CoachChangeDecision(id: "c1", decision: .declined, note: nil)])
    }

    /// An apply that turned the bench slot into nothing, so `after` holds an
    /// entry with no item.
    private var applied: CoachDecision {
        let item = BackupService.ItemDTO(id: F.uuid(0x301), catalogID: "barbell-bench-press",
                                         name: "Barbell Bench Press", order: 0, targetSets: 4, targetRepsLow: 8,
                                         targetRepsHigh: 12)
        var applied = declined
        applied.proposalID = "P2"
        applied.changes = [CoachChangeDecision(id: "c1", decision: .accepted, note: "felt right")]
        applied.appliedAt = t0
        applied.before = [CoachItemState(dayID: F.dayA, itemID: F.bench, item: item)]
        applied.after = [CoachItemState(dayID: F.dayA, itemID: F.bench, item: nil)]
        return applied
    }

    private static let contractExample = """
    {
      "format": "gymtrack-coach-proposal", "version": 1,
      "id": "6F1C0000-0000-0000-0000-000000000001",
      "createdAt": "2026-10-03T18:20:00Z",
      "planID": "00000000-0000-0000-0000-000000000100",
      "summary": "One or two plain sentences for the phone.",
      "futureTopLevel": { "anything": [1, 2, 3] },
      "changes": [
        { "id": "c1", "kind": "setSets",
          "dayID": "00000000-0000-0000-0000-000000000200", "itemID": "00000000-0000-0000-0000-000000000301",
          "expect": { "targetSets": 3 }, "to": { "targetSets": 4 },
          "reason": "Short plain sentence shown on the phone.", "lever": "volume",
          "evidence": [ { "metric": "chest.weeklyFractionalSets", "value": 7.5 } ],
          "review": { "verdict": "agree", "score": 4, "note": "One line.", "disputed": false },
          "futureField": true },
        { "id": "c2", "kind": "addSlot", "dayID": "00000000-0000-0000-0000-000000000200",
          "expect": {},
          "to": { "catalogID": "dumbbell-lateral-raise", "name": "Dumbbell Lateral Raise", "targetSets": 3,
                  "targetRepsLow": 10, "targetRepsHigh": 15, "restSeconds": 60 },
          "reason": "r", "lever": "priority", "evidence": [ { "metric": "x", "value": "high" } ] }
      ],
      "advice": [ "Push the last set closer to failure." ]
    }
    """
}
