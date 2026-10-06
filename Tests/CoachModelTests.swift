import Foundation
import SwiftData

/// Run with scripts/test-coach-models.sh; no simulator is needed.
///
/// The data layer's edges: the slot ID the backup now carries and restore
/// keeps, the two JSON files the loop passes through the phone, and the
/// snapshot file the Mac pulls.
@main
struct CoachModelTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let stamp = BackupService.ExportStamp(
        exportedAt: Date(timeIntervalSince1970: 1_790_116_200),
        timeZone: TimeZone(identifier: "Africa/Cairo")!, appVersion: "2.1", appBuild: "30")

    static func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // MARK: Backup slot IDs

    @MainActor static func checkSlotIDs() throws {
        let container = try CoachFixture.makeContainer()
        let context = container.mainContext
        try CoachFixture.insertPlan(context)

        let archive = try BackupService.makeArchive(context: context, stamp: stamp)
        check(archive.version == 2, "the archive version stays 2")
        let exported = Set(archive.plans[0].days.flatMap(\.items).compactMap(\.id))
        let live = Set(try context.fetch(FetchDescriptor<PlanItem>()).map(\.id))
        check(exported.count == 6 && exported == live, "every slot is exported under its own ID")
        check(archive.plans[0].id == CoachFixture.uuid(0x100)
              && archive.plans[0].days.map(\.id).contains(CoachFixture.uuid(0x200)),
              "plan and day IDs were already exported and still are")

        let data = try BackupService.encoded(archive)
        let decoded = try BackupService.decodedArchive(from: data)
        check(Set(decoded.plans[0].days.flatMap(\.items).compactMap(\.id)) == live, "slot IDs survive the file")

        try BackupService.restore(data: data, context: context)
        let restored = Set(try context.fetch(FetchDescriptor<PlanItem>()).map(\.id))
        check(restored == live, "restore keeps the slot IDs the file carries")
        let bench = try CoachFixture.item(CoachFixture.bench, context)
        check(bench?.day?.id == CoachFixture.uuid(0x200), "a restored slot is still in its day")

        // An older file has no slot IDs at all.
        var older = archive
        for d in older.plans[0].days.indices {
            for i in older.plans[0].days[d].items.indices { older.plans[0].days[d].items[i].id = nil }
        }
        let olderData = try BackupService.encoded(older)
        check(!text(olderData).contains("00000000-0000-0000-0000-000000000301"),
              "a slot with no ID writes no id key, and no null in its place")
        check(!text(olderData).contains("null"), "no null anywhere in the file")
        try BackupService.restore(data: olderData, context: context)
        let fresh = try context.fetch(FetchDescriptor<PlanItem>()).map(\.id)
        check(fresh.count == 6 && Set(fresh).count == 6, "an older file restores all its slots under new, distinct IDs")
        check(Set(fresh).isDisjoint(with: live), "the new IDs are not the old ones")

        // A file that repeats one: the first keeps it, the other gets a new one.
        var repeated = archive
        repeated.plans[0].days[0].items[1].id = repeated.plans[0].days[0].items[0].id
        try BackupService.restore(data: try BackupService.encoded(repeated), context: context)
        let items = try context.fetch(FetchDescriptor<PlanItem>())
        check(items.count == 6 && Set(items.map(\.id)).count == 6, "a repeated slot ID is replaced, not refused")
        check(items.first { $0.catalogID == "barbell-bench-press" }?.id == CoachFixture.uuid(0x301),
              "the first slot with the ID keeps it")
        check(items.first { $0.catalogID == "dumbbell-fly" }?.id != CoachFixture.uuid(0x301),
              "the second gets another")
    }

    // MARK: Proposal

    static let contractExample = """
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

    @MainActor static func checkProposalDecode() throws {
        let proposal = try CoachJSON.decoded(CoachProposal.self, from: Data(contractExample.utf8))
        check(proposal.changes.count == 2 && proposal.advice == ["Push the last set closer to failure."],
              "the contract's example decodes, unknown keys and all")
        let expectedDate = ISO8601DateFormatter().date(from: "2026-10-03T18:20:00Z")
        check(proposal.createdAt == expectedDate, "createdAt reads as the date it names")
        let first = proposal.changes[0]
        check(first.expect?.targetSets == 3 && first.to?.targetSets == 4 && first.review?.verdict == "agree"
              && first.review?.disputed == false, "a change keeps its expect, to and review")
        check(proposal.changes[1].review == nil, "a change with no review has none")
        check(proposal.changes[1].expect?.isEmpty == true, "an empty expect is empty")
        check(proposal.changes[1].evidence?.first?.value == .text("high"), "a word as evidence is kept, not fatal")

        let fractional = contractExample.replacingOccurrences(of: "2026-10-03T18:20:00Z",
                                                               with: "2026-10-03T18:20:00.250000+00:00")
        let loose = try CoachJSON.decoded(CoachProposal.self, from: Data(fractional.utf8))
        check(loose.createdAt.timeIntervalSince(expectedDate!) == 0.25, "fractional seconds and an offset are accepted")

        let wrongType = contractExample.replacingOccurrences(of: "\"targetSets\": 3 }", with: "\"targetSets\": \"three\" }")
        check((try? CoachJSON.decoded(CoachProposal.self, from: Data(wrongType.utf8))) == nil,
              "a value of the wrong type makes the file unreadable rather than guessed at")
    }

    // MARK: Decisions

    @MainActor static func checkDecisionsFile() throws {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let declined = CoachDecision(proposalID: "P1", receivedAt: t, decidedAt: t,
                                     changes: [CoachChangeDecision(id: "c1", decision: .declined, note: nil)])
        let item = BackupService.ItemDTO(id: CoachFixture.uuid(0x301), catalogID: "barbell-bench-press",
                                         name: "Barbell Bench Press", order: 0, targetSets: 4, targetRepsLow: 8,
                                         targetRepsHigh: 12)
        var applied = declined
        applied.proposalID = "P2"
        applied.changes = [CoachChangeDecision(id: "c1", decision: .accepted, note: "felt right")]
        applied.appliedAt = t
        applied.before = [CoachItemState(dayID: CoachFixture.dayA, itemID: CoachFixture.bench, item: item)]
        applied.after = [CoachItemState(dayID: CoachFixture.dayA, itemID: CoachFixture.bench, item: nil)]

        let bare = text(try CoachJSON.encoded(CoachDecisionFile(decisions: [declined])))
        for key in ["appliedAt", "before", "after", "revertedAt", "note", "null"] {
            check(!bare.contains(key), "a decision nobody applied has no \(key) key")
        }
        check(bare.contains("\"format\" : \"gymtrack-coach-decisions\"") && bare.contains("\"version\" : 1"),
              "the file names its format and version")

        let full = text(try CoachJSON.encoded(CoachDecisionFile(decisions: [applied])))
        check(!full.contains("revertedAt") && !full.contains("null"), "an applied decision has no revertedAt and no null")
        check(full.contains("\"item\" : {") && full.components(separatedBy: "\"item\"").count == 2,
              "a slot that did not exist has no item key at all")

        let store = CoachFixture.temporaryStore()
        check(store.loadDecisions().decisions.isEmpty, "no file reads as no decisions")
        store.prepare()
        check(FileManager.default.fileExists(atPath: store.inboxURL.path), "the inbox folder is created ahead of the push")
        let both = CoachDecisionFile(decisions: [declined, applied])
        try store.saveDecisions(both)
        check(store.loadDecisions() == both, "decisions round trip through the file")

        try Data("{ not json".utf8).write(to: store.decisionsURL)
        check(store.loadDecisions().decisions.isEmpty, "an unreadable file reads as none")
        let names = try FileManager.default.contentsOfDirectory(atPath: store.root.path)
        check(names.contains { $0.hasPrefix("decisions.unreadable-") } && !names.contains("decisions.json"),
              "an unreadable file is moved aside rather than overwritten")

        // A file written before ratings were taken out still carries the key.
        // It must read as the history it is, and the next write drops the key.
        let legacy = """
        {"format":"gymtrack-coach-decisions","version":1,"decisions":[{"proposalID":"P9",
        "receivedAt":"2026-09-20T10:00:00Z","decidedAt":"2026-09-20T10:05:00Z",
        "changes":[{"id":"c1","decision":"accepted"}],
        "ratings":[{"rater":"self","score":4,"ratedAt":"2026-09-21T10:00:00Z"}]}]}
        """
        try Data(legacy.utf8).write(to: store.decisionsURL)
        let old = store.loadDecisions()
        check(old.decisions.map(\.proposalID) == ["P9"] && old.decisions[0].changes.first?.decision == .accepted,
              "a decisions file with the old ratings key still decodes")
        try store.saveDecisions(old)
        check(!((try? String(contentsOf: store.decisionsURL, encoding: .utf8)) ?? "").contains("ratings"),
              "and the key is gone once the file is written again")

        // The old pending-ratings file is deleted when the store is prepared.
        let leftover = store.inboxURL.appendingPathComponent("ratings.json")
        try Data("{}".utf8).write(to: leftover)
        store.prepare()
        check(!FileManager.default.fileExists(atPath: leftover.path), "a leftover ratings.json is deleted, never left to be pulled")

        try store.writeSnapshot(Data("one".utf8))
        try store.writeSnapshot(Data("two".utf8))
        check((try? Data(contentsOf: store.snapshotURL)) == Data("two".utf8), "the snapshot is replaced whole")
        let after = try FileManager.default.contentsOfDirectory(atPath: store.root.path)
        check(after.allSatisfy { !$0.contains(".tmp") && !$0.hasPrefix(".") }, "no temporary file is left beside it")
    }

    // MARK: Snapshot

    @MainActor static func checkSnapshot() async throws {
        let container = try CoachFixture.makeContainer()
        let context = container.mainContext
        try CoachFixture.insertPlan(context)
        let store = CoachFixture.temporaryStore()

        // Same bytes as the Settings export, which is what the Mac reads.
        let snapshot = CoachSnapshot()
        snapshot.quietPeriod = .milliseconds(10)
        snapshot.start(container: container, store: store)
        await snapshot.settled()
        check(store.hasSnapshot, "a launch with no snapshot writes one")
        check(FileManager.default.fileExists(atPath: store.inboxURL.path), "launch creates the inbox")
        await snapshot.writeNow(stamp: stamp)
        let expected = try BackupService.encoded(BackupService.makeArchive(context: context, stamp: stamp))
        check((try? Data(contentsOf: store.snapshotURL)) == expected, "the snapshot is byte for byte the export")
        snapshot.stop()

        // With a file already there, a launch asks for nothing.
        let quiet = CoachSnapshot()
        quiet.quietPeriod = .milliseconds(10)
        quiet.start(container: container, store: store)
        await quiet.settled()
        check(quiet.lastWrittenAt == nil, "a launch with a snapshot already on disk writes none")

        // Logging saves after every set; none of it should rewrite the file.
        let session = WorkoutSession(title: "Push", planDayID: CoachFixture.uuid(0x200), startedAt: .now)
        context.insert(session)
        try context.save()
        try await Task.sleep(for: .milliseconds(100))
        await quiet.settled()
        check(quiet.lastWrittenAt == nil, "starting a workout does not ask for a snapshot")

        // A plan edit does, once, however many fields it touched.
        let bench = try CoachFixture.item(CoachFixture.bench, context)
        bench?.targetSets = 5
        bench?.targetRepsHigh = 10
        try context.save()
        try await Task.sleep(for: .milliseconds(100))
        await quiet.settled()
        check(quiet.lastWrittenAt != nil, "saving a plan edit asks for a snapshot")

        // A session that is already finished, as a logged-afterwards one is.
        let later = CoachSnapshot()
        later.quietPeriod = .milliseconds(10)
        later.start(container: container, store: store)
        quiet.stop()
        let past = WorkoutSession(title: "Pull", planDayID: CoachFixture.uuid(0x201), startedAt: .now.addingTimeInterval(-86_400))
        past.endedAt = past.startedAt
        context.insert(past)
        try context.save()
        try await Task.sleep(for: .milliseconds(100))
        await later.settled()
        check(later.lastWrittenAt != nil, "saving a finished session asks for a snapshot")
        later.stop()
    }

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        do {
            try await MainActor.run { try checkSlotIDs(); try checkProposalDecode(); try checkDecisionsFile() }
            try await checkSnapshot()
        } catch {
            print("FAIL: threw \(error)")
            exit(1)
        }
        let failed = await MainActor.run { failures }
        if failed > 0 { exit(1) }
        print("Coach model checks passed")
    }
}
