import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// "Erase all data" must take the coach's files with it, and only once the
/// local erase has gone through.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoachEraseTests {

    @MainActor private struct Rig {
        let container: ModelContainer
        let store: CoachStore
        let inbox: CoachInbox
        let snapshot: CoachSnapshot
        var context: ModelContext { container.mainContext }

        /// A plan, a decision with a private note, and a proposal pushed by the
        /// Mac, all on disk and loaded into the inbox.
        static func seeded() throws -> Rig {
            let container = try TestStore.container()
            let context = container.mainContext
            try CoachFixture.insertPlan(context)
            let store = CoachFixture.temporaryStore()
            store.prepare()
            var file = CoachDecisionFile()
            file.decisions = [CoachDecision(proposalID: CoachFixture.proposalID, receivedAt: .now, decidedAt: .now,
                changes: [CoachChangeDecision(id: "c1", decision: .declined, note: "My private training note")])]
            try store.saveDecisions(file)
            try CoachFixture.proposalJSON(id: "P-PENDING", changes: [])
                .write(to: store.proposalURL)
            let snapshot = CoachSnapshot()
            snapshot.quietPeriod = .zero
            return Rig(container: container, store: store,
                       inbox: CoachInbox(context: context, store: store), snapshot: snapshot)
        }

        func erase() async throws {
            try await BackupService.wipe(context: context, coachInbox: inbox, coachSnapshot: snapshot)
        }

        func discard() {
            snapshot.stop()
            CoachFixture.discard(store)
        }
    }

    @Test func eraseMustRemoveTheCoachDecisionRecord() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig.seeded()
        defer { rig.discard() }
        #expect(rig.inbox.decisions.count == 1)
        try await rig.erase()
        rig.inbox.reload()
        #expect(rig.inbox.decisions.isEmpty, "Erase all data must include the coach decisions in use by this app")
        #expect(!FileManager.default.fileExists(atPath: rig.store.decisionsURL.path))
    }

    @Test func aPendingProposalIsRemovedWithTheData() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig.seeded()
        defer { rig.discard() }
        #expect(rig.inbox.proposal != nil)
        try await rig.erase()
        #expect(rig.inbox.proposal == nil)
        #expect(rig.inbox.review == nil)
        #expect(rig.inbox.latestDecision == nil)
        #expect(!FileManager.default.fileExists(atPath: rig.store.proposalURL.path))
        #expect(FileManager.default.fileExists(atPath: rig.store.inboxURL.path),
                "The Mac's next push still has a folder to land in")
    }

    @Test func aFailedEraseLeavesTheCoachRecordsAlone() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig.seeded()
        defer { rig.discard() }
        try rig.store.writeSnapshot(Data("{}".utf8))
        // A workout in progress refuses the erase before anything is deleted.
        rig.context.insert(WorkoutSession(title: "Live", startedAt: TestClock.reference))
        try rig.context.save()

        await #expect(throws: BackupService.WipeError.self) { try await rig.erase() }

        rig.inbox.reload()
        #expect(rig.inbox.decisions.count == 1)
        #expect(rig.inbox.proposal != nil)
        #expect(rig.store.hasSnapshot)
        #expect(try rig.context.fetchCount(FetchDescriptor<Plan>()) == 1)
    }

    @Test func anEraseThatFailsAfterCancellingWritesLeavesTheCoachFilesAndAsksForANewWrite() async throws {
        struct Refused: Error {}
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig.seeded()
        defer { rig.discard() }
        rig.snapshot.start(container: rig.container, store: rig.store)
        await rig.snapshot.settled()
        // Marks the file the cancelled write would have replaced, so a fresh
        // write is told apart from the one the launch made.
        let marker = Data("{}".utf8)
        try rig.store.writeSnapshot(marker)

        await #expect(throws: Refused.self) {
            try await BackupService.wipe(context: rig.context, coachInbox: rig.inbox,
                                         coachSnapshot: rig.snapshot, beforeDeleting: { throw Refused() })
        }
        await rig.snapshot.settled()

        rig.inbox.reload()
        #expect(rig.inbox.decisions.count == 1, "A failed erase leaves the decisions")
        #expect(rig.inbox.proposal != nil)
        #expect(try rig.context.fetchCount(FetchDescriptor<Plan>()) == 1)
        let rewritten = try Data(contentsOf: rig.store.snapshotURL)
        #expect(rewritten != marker, "The cancelled write is replaced, not lost")
        #expect(try BackupService.decodedArchive(from: rewritten).plans.count == 1)
    }

    @Test func aFreshInboxOverTheSameFolderFindsNothingAfterErase() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig.seeded()
        defer { rig.discard() }
        try rig.store.writeSnapshot(Data("{}".utf8))
        // A decision file an earlier launch could not read and set aside.
        try Data("not json".utf8).write(to: rig.store.root.appendingPathComponent("decisions.unreadable-1.json"))
        try await rig.erase()

        let relaunched = CoachInbox(context: rig.context, store: CoachStore(root: rig.store.root))
        #expect(relaunched.decisions.isEmpty)
        #expect(relaunched.proposal == nil)
        #expect(CoachStore(root: rig.store.root).loadDecisions().decisions.isEmpty)
        #expect(!rig.store.hasSnapshot)
        let left = try FileManager.default.contentsOfDirectory(atPath: rig.store.root.path)
        #expect(left == ["Inbox"])
    }

    @Test func aSnapshotWaitingToBeWrittenDoesNotBringTheOldDataBack() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig.seeded()
        defer { rig.discard() }
        // The writer is watching and a write is waiting out its quiet period
        // when the erase's own save arrives.
        rig.snapshot.quietPeriod = .milliseconds(200)
        rig.snapshot.start(container: rig.container, store: rig.store)
        try await rig.erase()
        // `settled` returns only when the writer has nothing running or waiting,
        // so a write that survived the erase would have landed by now.
        await rig.snapshot.settled()
        #expect(!rig.store.hasSnapshot, "A write requested before the erase must not land after it")
    }

    @Test func aWriteThatReadTheStoreBeforeTheEraseWritesNothing() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig.seeded()
        defer { rig.discard() }
        rig.snapshot.start(container: rig.container, store: rig.store)
        // Started but not yet awaited: the write begins reading the store, and
        // the erase deletes it while the read is between slices.
        let write = Task { await rig.snapshot.writeNow() }
        await Task.yield()
        try await rig.erase()
        await write.value
        #expect(!rig.store.hasSnapshot)
    }
}
