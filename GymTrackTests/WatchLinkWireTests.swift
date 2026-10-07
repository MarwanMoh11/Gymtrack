import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What the phone and the watch say to each other has to survive the wire, and
/// has to fail quietly when it does not. A command that decodes to something it
/// was not, or a malformed payload that traps, costs a logged set mid-workout;
/// a payload that is merely refused costs nothing, because the wrist resends.
///
/// The two channels the wrist sends on keep no order between them, and either
/// side can be the older build. So past the wire itself, these hold the phone
/// to one record whatever order its commands land in, with the logger on
/// screen and with the phone asleep (through `WatchCommandRig`): a repeated
/// log changes nothing, an undo answers only the log it names, a Finish ends
/// the session when it was tapped, and a live reading never writes over a
/// finished session's totals. The tombstone the wrist keeps for a session it ended, and
/// the rule that decides which Health workout a session links, are here too.
@MainActor @Suite(.serialized)
struct WatchLinkWireTests {

    // MARK: - Fixtures

    /// Whole seconds, so a date survives the trip through milliseconds exactly
    /// and a round trip can be compared with `==`.
    private static let t0 = TestClock.reference
    private static let setID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let sessionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private static let metrics = WatchWorkoutMetrics(
        sessionID: sessionID, currentHeartRate: 131, averageHeartRate: 118,
        maxHeartRate: 162, activeEnergyKcal: 240.5, healthWorkoutID: nil)

    private static let rating = WatchSetRating(
        sessionID: sessionID, setID: setID, completedAt: t0, rpe: 8)

    private static let batch = WatchFinishBatch(
        sessionID: sessionID,
        logs: [WatchPendingLog(setID: setID, weightKg: 82.5, reps: 5, seconds: 0,
                               completedAt: t0.addingTimeInterval(60))],
        undos: [UUID(uuidString: "33333333-3333-3333-3333-333333333333")!],
        starts: [setID: t0.addingTimeInterval(30)],
        cancels: [UUID(uuidString: "44444444-4444-4444-4444-444444444444")!],
        ratings: [rating],
        endedAt: t0.addingTimeInterval(900))

    /// One of every case, and the optional-carrying ones both with and without
    /// the optional, because "no key" is what a set with no data stores.
    static let everyCommand: [WatchCommand] = [
        .requestMirror, .startToday, .startFreestyle,
        .logSet(id: setID, weightKg: 82.5, reps: 5, seconds: 0, at: t0),
        .logSet(id: setID, weightKg: 0, reps: 12, seconds: 45, at: nil),
        .undoSet(id: setID, completedAt: t0),
        .undoSet(id: setID, completedAt: nil),
        .rateSet(rating),
        .rateSet(WatchSetRating(sessionID: sessionID, setID: setID, completedAt: t0, rpe: nil)),
        .announceStart(id: setID, at: t0),
        .cancelStart(id: setID),
        .focusExercise(catalogID: "barbell-squat"),
        .addSet(catalogID: "barbell-squat"),
        .stopRest, .extendRest(seconds: 30), .startRest(seconds: 90),
        .finish(metrics: nil), .finish(metrics: metrics),
        .discard,
        .finishSession(batch, metrics: nil), .finishSession(batch, metrics: metrics),
        .discardSession(id: sessionID),
        .metrics(metrics),
    ]

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder.watchLink.encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodeCommand(_ object: [String: Any]) throws -> WatchCommand? {
        let data = try JSONSerialization.data(withJSONObject: object)
        return WatchCommand.fromWatchPayload([WatchLink.commandKey: data], key: WatchLink.commandKey)
    }

    // MARK: - Round trips

    @Test(arguments: WatchLinkWireTests.everyCommand)
    func everyCommandSurvivesTheWire(_ command: WatchCommand) {
        let payload = command.watchPayload(key: WatchLink.commandKey)
        #expect(Array(payload.keys) == [WatchLink.commandKey])
        #expect(WatchCommand.fromWatchPayload(payload, key: WatchLink.commandKey) == command)
    }

    @Test func aMirrorWithASessionAndAnIdleScreenSurvivesTheWire() {
        let set = WatchSetSnapshot(
            id: Self.setID, index: 0, weightKg: 60, reps: 8, seconds: 0,
            targetRepsLow: 6, targetRepsHigh: 8, isCompleted: true,
            continuation: true, startedAt: Self.t0, completedAt: Self.t0.addingTimeInterval(40), rpe: 9)
        let exercise = WatchExerciseSnapshot(
            id: "barbell-bench-press", name: "Bench Press", order: 0, tracking: .weightReps,
            restSeconds: 120, sets: [set], lastTimeLabel: "60 × 8", scale: LoadScale(unit: .lb, increment: 5))
        let session = WatchSessionSnapshot(
            sessionID: Self.sessionID, title: "Push", planName: "PPL", startedAt: Self.t0,
            exercises: [exercise], preferredExerciseID: "barbell-bench-press", currentSetID: Self.setID,
            restEndsAt: Self.t0.addingTimeInterval(90), restStartedAt: Self.t0, restTotalSeconds: 90,
            restAutoStart: true, volumeKg: 480, unit: .lb, effortEnabled: true, restUnknown: nil)
        let idle = WatchIdleSnapshot(
            day: Self.t0, todayTitle: "Push", todayExerciseCount: 5, todaySetCount: 15,
            todayMuscles: ["Chest", "Triceps"], streak: 3, sessionsThisWeek: 2,
            lastSessionTitle: "Pull", lastSessionDate: Self.t0, unit: .lb, todayIsRotation: true)
        let mirror = WatchMirror(
            revision: 7, sentAt: Self.t0, idle: idle, session: session, healthEnabled: true,
            endedSession: WatchSessionEnd(sessionID: Self.sessionID, reason: .finished,
                                          phoneHealthWorkoutID: Self.setID))

        let payload = mirror.watchPayload(key: WatchLink.mirrorKey)

        #expect(WatchMirror.fromWatchPayload(payload, key: WatchLink.mirrorKey) == mirror)
        #expect(WatchMirror.fromWatchPayload(payload, key: WatchLink.commandKey) == nil)
    }

    // MARK: - Milliseconds

    @Test func datesTravelAsMillisecondsSince1970() throws {
        let moment = Self.t0.addingTimeInterval(0.5)
        let data = try JSONEncoder.watchLink.encode(moment)
        let onTheWire = try JSONDecoder().decode(Double.self, from: data)

        #expect(onTheWire == moment.timeIntervalSince1970 * 1000)
        #expect(try JSONDecoder.watchLink.decode(Date.self, from: data) == moment)
    }

    @Test func aFinerDateComesBackCloseEnoughToBeTheSameCompletion() throws {
        // The wrist stamps with full-precision dates. A round trip may move one
        // by float round-off, never by a millisecond: `isSameCompletion` is the
        // comparison the phone makes, and it must hold across the wire.
        let stamp = Self.t0.addingTimeInterval(0.1234567)
        let command = WatchCommand.logSet(id: Self.setID, weightKg: 50, reps: 5, seconds: 0, at: stamp)

        let payload = command.watchPayload(key: WatchLink.commandKey)
        let decoded = try #require(WatchCommand.fromWatchPayload(payload, key: WatchLink.commandKey))
        guard case .logSet(_, _, _, _, let back) = decoded else {
            Issue.record("The command decoded as something else")
            return
        }

        #expect(WatchCommand.isSameCompletion(back, as: stamp))
        #expect(abs(try #require(back).timeIntervalSince(stamp)) < 0.001)
    }

    @Test func completionsAMillisecondApartAreDifferentCompletions() {
        let a = Self.t0
        #expect(WatchCommand.isSameCompletion(a, as: a.addingTimeInterval(0.0005)))
        #expect(!WatchCommand.isSameCompletion(a, as: a.addingTimeInterval(0.001)))
        #expect(!WatchCommand.isSameCompletion(a, as: a.addingTimeInterval(-2)))
        #expect(!WatchCommand.isSameCompletion(nil, as: a))
        #expect(!WatchCommand.isSameCompletion(a, as: nil))
        #expect(!WatchCommand.isSameCompletion(nil, as: nil))
    }

    @Test func aLoggedMomentIsTheWristsStampUnlessItClaimsToBeFromTheFuture() {
        #expect(WatchCommand.loggedMoment(Self.t0) == Self.t0)

        // The one reader of the wall clock here, so the answer is bracketed by
        // it rather than compared with it.
        let before = Date.now
        let noStamp = WatchCommand.loggedMoment(nil)
        let skewed = WatchCommand.loggedMoment(before.addingTimeInterval(WatchCommand.clockSkewTolerance + 60))
        let after = Date.now
        #expect((before...after).contains(noStamp))
        #expect((before...after).contains(skewed))

        let withinTolerance = Date.now.addingTimeInterval(WatchCommand.clockSkewTolerance - 20)
        #expect(WatchCommand.loggedMoment(withinTolerance) == withinTolerance)
    }

    // MARK: - Malformed input

    static let truncated = Data(#"{"logSet":{"id":"11111111-1111-1111-1111-111111111111","weightKg":8"#.utf8)

    @Test(arguments: [
        Data(),
        Data([0x00, 0xFF, 0xFE, 0x7B]),
        Data("not json at all".utf8),
        Data("[1, 2, 3]".utf8),
        Data("\"requestMirror\"".utf8),
        Data("{}".utf8),
        Data(#"{"teleport":{}}"#.utf8),
        Data(#"{"logSet":{"id":"not-a-uuid","weightKg":1,"reps":1,"seconds":0}}"#.utf8),
        Data(#"{"logSet":{"weightKg":1,"reps":1,"seconds":0}}"#.utf8),
        Data(#"{"logSet":{"id":"11111111-1111-1111-1111-111111111111","weightKg":"heavy","reps":1,"seconds":0}}"#.utf8),
        WatchLinkWireTests.truncated,
    ])
    func malformedBytesDecodeToNothing(_ garbage: Data) {
        #expect(WatchCommand.fromWatchPayload([WatchLink.commandKey: garbage], key: WatchLink.commandKey) == nil)
    }

    @Test func aPayloadThatIsNotACommandDecodesToNothing() {
        let valid = WatchCommand.stopRest.watchPayload(key: WatchLink.commandKey)
        let notData: [[String: Any]] = [
            [:],
            ["unrelated": 1],
            [WatchLink.commandKey: "stopRest"],
            [WatchLink.commandKey: 42],
            [WatchLink.commandKey: NSNull()],
            [WatchLink.commandKey: [UInt8](arrayLiteral: 1, 2, 3)],
            [WatchLink.mirrorKey: valid[WatchLink.commandKey] as Any],
        ]
        for payload in notData {
            #expect(WatchCommand.fromWatchPayload(payload, key: WatchLink.commandKey) == nil)
        }
    }

    @Test func aCommandThatCannotBeEncodedLeavesAnEmptyPayloadInsteadOfTrapping() {
        // NaN has no JSON form. The sender gets nothing to send, and a receiver
        // handed that nothing gets nil, so a corrupt reading never becomes a log.
        let broken = WatchCommand.logSet(id: Self.setID, weightKg: .nan, reps: 5, seconds: 0, at: Self.t0)
        let payload = broken.watchPayload(key: WatchLink.commandKey)

        #expect(payload.isEmpty)
        #expect(WatchCommand.fromWatchPayload(payload, key: WatchLink.commandKey) == nil)
    }

    @Test func aFieldAFutureWatchAddsIsIgnoredAndAMissingOptionalIsNil() throws {
        let command = WatchCommand.logSet(id: Self.setID, weightKg: 82.5, reps: 5, seconds: 0, at: Self.t0)
        var object = try json(command)
        var inner = try #require(object["logSet"] as? [String: Any])
        inner["tempo"] = "3-1-1"
        object["logSet"] = inner
        #expect(try decodeCommand(object) == command)

        // An older watch sent no `at` and no `completedAt`: no key, not null.
        inner["at"] = nil
        object["logSet"] = inner
        #expect(try decodeCommand(object)
                == .logSet(id: Self.setID, weightKg: 82.5, reps: 5, seconds: 0, at: nil))
        #expect(try decodeCommand(["undoSet": ["id": Self.setID.uuidString]])
                == .undoSet(id: Self.setID, completedAt: nil))
    }

    @Test func anOlderSnapshotMissingNewerOptionalFieldsStillDecodes() throws {
        let set = WatchSetSnapshot(
            id: Self.setID, index: 1, weightKg: 40, reps: 10, seconds: 0, targetRepsLow: 8,
            targetRepsHigh: 12, isCompleted: false)
        var object = try json(set)
        #expect(object["continuation"] == nil && object["rpe"] == nil)
        #expect(try JSONDecoder.watchLink.decode(
            WatchSetSnapshot.self, from: JSONSerialization.data(withJSONObject: object)) == set)

        object["continuation"] = true
        object["rpe"] = 9
        let richer = try JSONDecoder.watchLink.decode(
            WatchSetSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(richer.isContinuation)
        #expect(richer.rpe == 9)

        let idle = try json(WatchIdleSnapshot.empty)
        #expect(idle["todayIsRotation"] == nil)
        #expect(try JSONDecoder.watchLink.decode(
            WatchIdleSnapshot.self, from: JSONSerialization.data(withJSONObject: idle)) == .empty)
    }

    // MARK: - Riders on a command

    @Test func onlyStartsCarryATimeAndOnlyOpenSessionCommandsCarryASession() {
        let now = Self.t0
        for command: WatchCommand in [.startToday, .startFreestyle] {
            let stamp = WatchCommandDelivery.stamp(command, showing: Self.sessionID, at: now)
            #expect(stamp == WatchCommandDelivery(sentAt: now, sessionID: nil))
        }
        for command: WatchCommand in [.addSet(catalogID: "x"), .focusExercise(catalogID: "x"),
                                      .startRest(seconds: 60), .stopRest, .extendRest(seconds: 15)] {
            let stamp = WatchCommandDelivery.stamp(command, showing: Self.sessionID, at: now)
            #expect(stamp == WatchCommandDelivery(sentAt: nil, sessionID: Self.sessionID))
        }
        for command: WatchCommand in [.requestMirror, .logSet(id: Self.setID, weightKg: 1, reps: 1, seconds: 0, at: nil),
                                      .undoSet(id: Self.setID, completedAt: nil), .discard] {
            let stamp = WatchCommandDelivery.stamp(command, showing: Self.sessionID, at: now)
            #expect(stamp == WatchCommandDelivery())
            #expect(stamp.payload.isEmpty)
        }
    }

    @Test func theRidersSurviveAPayloadAndGarbageRidersAreIgnored() {
        let delivery = WatchCommandDelivery(sentAt: Self.t0, sessionID: Self.sessionID)
        #expect(WatchCommandDelivery(payload: delivery.payload) == delivery)

        let garbage: [String: Any] = [
            WatchLink.commandSentAtKey: "yesterday",
            WatchLink.commandSessionKey: "not-a-uuid",
        ]
        #expect(WatchCommandDelivery(payload: garbage) == WatchCommandDelivery())
        #expect(WatchCommandDelivery(payload: [:]) == WatchCommandDelivery())
    }

    @Test func aStartIsRefusedOnlyOnceItHasWaitedLongerThanItsShelfLife() {
        let sentAt = Self.t0
        let delivery = WatchCommandDelivery(sentAt: sentAt, sessionID: nil)
        let shelf = WatchCommandDelivery.startShelfLife

        #expect(delivery.verdict(for: .startToday, openSessionID: nil, now: sentAt) == .apply)
        #expect(delivery.verdict(for: .startToday, openSessionID: nil, now: sentAt.addingTimeInterval(shelf)) == .apply)
        #expect(delivery.verdict(for: .startFreestyle, openSessionID: nil,
                                 now: sentAt.addingTimeInterval(shelf + 1)) == .staleStart)
        // A wrist clock ahead of the phone's makes the age negative, not stale.
        #expect(delivery.verdict(for: .startToday, openSessionID: nil, now: sentAt.addingTimeInterval(-600)) == .apply)
        // An older watch build sent no time: nothing to judge it by.
        #expect(WatchCommandDelivery().verdict(for: .startToday, openSessionID: nil,
                                               now: sentAt.addingTimeInterval(86_400)) == .apply)
    }

    @Test func aCommandAboutAnotherSessionIsRefusedWhetherOrNotThePhoneStillHasOne() {
        let stamped = WatchCommandDelivery(sentAt: nil, sessionID: Self.sessionID)
        let other = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let commands: [WatchCommand] = [.addSet(catalogID: "x"), .focusExercise(catalogID: "x"),
                                        .startRest(seconds: 60), .stopRest, .extendRest(seconds: 15)]

        for command in commands {
            #expect(stamped.verdict(for: command, openSessionID: Self.sessionID, now: Self.t0) == .apply)
            #expect(stamped.verdict(for: command, openSessionID: other, now: Self.t0) == .otherSession)
            // The phone has no session at all: the one the wrist was showing is gone.
            #expect(stamped.verdict(for: command, openSessionID: nil, now: Self.t0) == .otherSession)
            // No stamp, as an older watch sends: applied to whatever is open.
            #expect(WatchCommandDelivery().verdict(for: command, openSessionID: other, now: Self.t0) == .apply)
        }
        // A log names its own set, so the session rider never applies to it.
        #expect(stamped.verdict(for: .logSet(id: Self.setID, weightKg: 1, reps: 1, seconds: 0, at: nil),
                                openSessionID: other, now: Self.t0) == .apply)
    }

    @Test func todayDescribesTodayOnlyWhenItsDayIsToday() {
        var idle = WatchIdleSnapshot.empty
        #expect(idle.describesToday)

        idle.day = .now
        #expect(idle.describesToday)

        idle.day = Date.now.addingTimeInterval(-3 * 86_400)
        #expect(!idle.describesToday)
    }

    // MARK: - Riders, end to end

    /// The payload as `WatchConnector` sends it: the command, with the riders
    /// stamped beside it for the session the wrist is showing.
    private func sent(_ command: WatchCommand, showing session: UUID?, at moment: Date) -> [String: Any] {
        var payload = command.watchPayload(key: WatchLink.commandKey)
        payload.merge(WatchCommandDelivery.stamp(command, showing: session, at: moment).payload) { _, new in new }
        return payload
    }

    private func verdict(_ command: WatchCommand, _ payload: [String: Any], open: UUID?) -> WatchCommandDelivery.Verdict {
        WatchCommandDelivery(payload: payload).verdict(for: command, openSessionID: open, now: Self.t0)
    }

    @Test(arguments: [WatchCommand.startToday, .startFreestyle])
    func aStartThatWaitedHoursIsRefusedWhetherOrNotASessionIsOpen(_ start: WatchCommand) {
        let hoursOld = sent(start, showing: nil, at: Self.t0.addingTimeInterval(-3 * 3600))
        #expect(verdict(start, hoursOld, open: nil) == .staleStart)
        #expect(verdict(start, hoursOld, open: UUID()) == .staleStart,
                "a start hours old is no more wanted because a session happens to be open")

        #expect(verdict(start, sent(start, showing: nil, at: Self.t0.addingTimeInterval(-20)), open: nil) == .apply)
        #expect(verdict(start, sent(start, showing: nil, at: Self.t0.addingTimeInterval(45)), open: nil) == .apply,
                "a stamp ahead of this clock is skew, not age")
        let edge = sent(start, showing: nil, at: Self.t0.addingTimeInterval(-WatchCommandDelivery.startShelfLife))
        #expect(verdict(start, edge, open: nil) == .apply, "the shelf life itself is still fresh")
        #expect(verdict(start, start.watchPayload(key: WatchLink.commandKey), open: nil) == .apply,
                "an older watch stamps nothing and is served as it always was")
    }

    @Test(arguments: [WatchCommand.addSet(catalogID: "bench"), .focusExercise(catalogID: "bench"),
                      .startRest(seconds: 90), .stopRest, .extendRest(seconds: 30)])
    func aCommandForTheOpenSessionIsDroppedOnlyWhenItNamesAnother(_ command: WatchCommand) {
        let open = Self.sessionID
        let replaced = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let stale = sent(command, showing: replaced, at: Self.t0)

        #expect(verdict(command, stale, open: open) == .otherSession)
        #expect(verdict(command, stale, open: nil) == .otherSession)
        #expect(verdict(command, sent(command, showing: open, at: Self.t0), open: open) == .apply)
        #expect(verdict(command, sent(command, showing: nil, at: Self.t0), open: open) == .apply,
                "a wrist that showed no session names none")
        #expect(verdict(command, command.watchPayload(key: WatchLink.commandKey), open: open) == .apply)
    }

    /// The riders sit beside the command, so the command itself is the bytes
    /// an older watch sends and an older phone reads.
    @Test(arguments: [WatchCommand.startToday, .addSet(catalogID: "bench"), .stopRest, .extendRest(seconds: 30)])
    func aStampedCommandIsByteForByteTheOneAnOlderWatchSends(_ command: WatchCommand) {
        let stamped = sent(command, showing: Self.sessionID, at: Self.t0)
        let legacy = command.watchPayload(key: WatchLink.commandKey)

        #expect(stamped.count > 1, "a start or a command for the open session carries a rider")
        #expect(WatchCommand.fromWatchPayload(stamped, key: WatchLink.commandKey) == command)
        #expect(WatchCommand.fromWatchPayload(legacy, key: WatchLink.commandKey) == command)
        #expect(stamped[WatchLink.commandKey] as? Data == legacy[WatchLink.commandKey] as? Data)
    }

    // MARK: - Builds from either side of a change to the wire

    /// `WatchFinishBatch` as a build from before `endedAt` has it.
    private struct LegacyFinishBatch: Codable {
        var sessionID: UUID
        var logs: [WatchPendingLog]
        var undos: Set<UUID>
        var starts: [UUID: Date]
        var cancels: Set<UUID>
        var ratings: [WatchSetRating]
    }

    /// The two commands as a build from before stamped undos and `endedAt`
    /// sends and reads them.
    private enum LegacyCommand: Codable {
        case undoSet(id: UUID)
        case finishSession(LegacyFinishBatch, metrics: WatchWorkoutMetrics?)
    }

    /// `WatchSessionSnapshot` as a build from before `restUnknown` has it.
    private struct LegacySession: Codable {
        var sessionID: UUID
        var title: String
        var planName: String
        var startedAt: Date
        var exercises: [WatchExerciseSnapshot]
        var restEndsAt: Date?
        var restStartedAt: Date?
        var restTotalSeconds: Int
        var restAutoStart: Bool
        var volumeKg: Double
        var unit: WeightUnit
    }

    @Test func anUndoReadsTheSameOnABuildFromEitherSideOfItsStamp() {
        // Not a whole millisecond, so the trip through milliseconds rounds it.
        let stamp = Self.t0.addingTimeInterval(0.1234)
        let key = WatchLink.commandKey

        let newUndo = WatchCommand.undoSet(id: Self.setID, completedAt: stamp).watchPayload(key: key)
        guard case .undoSet(let oldID)? = LegacyCommand.fromWatchPayload(newUndo, key: key) else {
            Issue.record("An older phone could not read a stamped undo")
            return
        }
        #expect(oldID == Self.setID)

        let oldUndo = LegacyCommand.undoSet(id: Self.setID).watchPayload(key: key)
        #expect(WatchCommand.fromWatchPayload(oldUndo, key: key) == .undoSet(id: Self.setID, completedAt: nil),
                "an older watch's undo names no completion")

        guard case .undoSet(_, let roundTrip)? = WatchCommand.fromWatchPayload(newUndo, key: key) else {
            Issue.record("A stamped undo did not survive the wire")
            return
        }
        #expect(WatchCommand.isSameCompletion(roundTrip, as: stamp))
        #expect(!WatchCommand.isSameCompletion(roundTrip, as: stamp.addingTimeInterval(0.002)))
    }

    @Test func aFinishReadsTheSameOnABuildFromEitherSideOfItsEnd() {
        let key = WatchLink.commandKey
        let tapped = Self.t0.addingTimeInterval(900)
        let log = WatchPendingLog(setID: Self.setID, weightKg: 60, reps: 8, seconds: 0,
                                  completedAt: Self.t0.addingTimeInterval(600))
        let batch = WatchFinishBatch(sessionID: Self.sessionID, logs: [log], undos: [], starts: [:], cancels: [],
                                     ratings: [], endedAt: tapped)

        let newFinish = WatchCommand.finishSession(batch, metrics: nil).watchPayload(key: key)
        guard case .finishSession(let oldBatch, _)? = LegacyCommand.fromWatchPayload(newFinish, key: key) else {
            Issue.record("An older phone could not read a Finish with an end")
            return
        }
        #expect(oldBatch.sessionID == Self.sessionID)
        #expect(oldBatch.logs == [log])

        let legacy = LegacyFinishBatch(sessionID: Self.sessionID, logs: [log], undos: [Self.setID], starts: [:],
                                       cancels: [], ratings: [])
        let oldFinish = LegacyCommand.finishSession(legacy, metrics: nil).watchPayload(key: key)
        guard case .finishSession(let newBatch, _)? = WatchCommand.fromWatchPayload(oldFinish, key: key) else {
            Issue.record("A newer phone could not read a Finish without an end")
            return
        }
        #expect(newBatch.endedAt == nil)
        #expect(newBatch.undos == [Self.setID])
        #expect(newBatch.logs == [log])

        guard case .finishSession(let roundBatch, _)? = WatchCommand.fromWatchPayload(newFinish, key: key) else {
            Issue.record("A Finish with an end did not survive the wire")
            return
        }
        #expect(roundBatch.endedAt == tapped)
    }

    @Test func aFinishQueuedByABuildThatWroteItsMissingMetricsAsNullStillDecodes() throws {
        #expect(try decodeCommand(["finish": ["metrics": NSNull()]]) == .finish(metrics: nil))
        #expect(try JSONDecoder().decode(WatchCommand.self, from: Data(#"{"finish":{"metrics":null}}"#.utf8))
                == .finish(metrics: nil))
    }

    @Test func aMirrorSaysItDoesNotKnowTheRestWithAKeyOnlyNewerBuildsRead() throws {
        let old = LegacySession(sessionID: Self.sessionID, title: "Push", planName: "", startedAt: Self.t0,
                                exercises: [], restEndsAt: Self.t0, restStartedAt: Self.t0, restTotalSeconds: 90,
                                restAutoStart: true, volumeKg: 0, unit: .kg)
        let fromOld = try JSONDecoder.watchLink.decode(WatchSessionSnapshot.self,
                                                       from: JSONEncoder.watchLink.encode(old))
        #expect(fromOld.restUnknown == nil)
        #expect(fromOld.restEndsAt == Self.t0, "a mirror from an older phone is a real answer about the rest")

        func session(restUnknown: Bool?) -> WatchSessionSnapshot {
            WatchSessionSnapshot(sessionID: Self.sessionID, title: "Push", planName: "", startedAt: Self.t0,
                                 exercises: [], restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg,
                                 effortEnabled: true, restUnknown: restUnknown)
        }
        let unknown = try JSONEncoder.watchLink.encode(session(restUnknown: true))
        #expect(try JSONDecoder.watchLink.decode(WatchSessionSnapshot.self, from: unknown).restUnknown == true)
        let seenByOld = try JSONDecoder.watchLink.decode(LegacySession.self, from: unknown)
        #expect(seenByOld.sessionID == Self.sessionID)
        #expect(seenByOld.restEndsAt == nil, "an older watch reads the blank rest as it always did")

        let known = try json(session(restUnknown: nil))
        #expect(known["restUnknown"] == nil, "a known rest adds no key at all")
    }

    @Test(arguments: [WatchSessionEnd.Reason.finished, .discarded])
    func theWatchHearsWhetherASessionWasFinishedOrDiscarded(_ reason: WatchSessionEnd.Reason) throws {
        let end = WatchSessionEnd(sessionID: Self.sessionID, reason: reason)
        let mirror = WatchMirror(revision: 1, sentAt: Self.t0, idle: .empty, session: nil, healthEnabled: true,
                                 endedSession: end)

        let back = WatchMirror.fromWatchPayload(mirror.watchPayload(key: WatchLink.mirrorKey), key: WatchLink.mirrorKey)
        #expect(back?.endedSession == end)
        // No phone workout yet is no key, not a null the watch has to read past.
        #expect(try json(end)["phoneHealthWorkoutID"] == nil)
    }

    // MARK: - What the wrist keeps until the phone confirms it

    @Test func aLateReadingFromThePreviousSessionLendsItsTotalsToNothing() {
        var previous = WatchWorkoutMetrics.empty
        previous.sessionID = Self.sessionID
        previous.averageHeartRate = 140
        var next = WatchWorkoutMetrics.empty
        next.sessionID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        next.activeEnergyKcal = 85

        let merged = previous.merging(next)
        #expect(merged.sessionID == next.sessionID)
        #expect(merged.averageHeartRate == nil, "the last workout's heart rate cannot enter this one")
        #expect(merged.activeEnergyKcal == 85)
    }

    @Test func aNewWorkoutInheritsNothingTheLastOneHadPending() {
        let undone = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        var pending = WatchPendingActions()
        pending.adopt(Self.sessionID)
        pending.logs[Self.setID] = WatchPendingLog(setID: Self.setID, weightKg: 55, reps: 8, seconds: 0,
                                                   completedAt: Self.t0)
        pending.recordUndo(of: undone, completedAt: Self.t0)
        pending.starts[Self.setID] = Self.t0.addingTimeInterval(-25)
        pending.cancels.insert(undone)
        pending.focus = "squat"

        var same = pending
        same.adopt(Self.sessionID)
        #expect(same.logs.count == 1 && same.undos == [undone] && same.focus == "squat",
                "adopting the session already held keeps its work")

        var next = pending
        next.adopt(UUID())
        #expect(next.logs.isEmpty && next.undos.isEmpty && next.undoStamps.isEmpty)
        #expect(next.starts.isEmpty && next.cancels.isEmpty && next.focus == nil)
    }

    /// A Finish can overtake the queued log it follows, or arrive after it.
    /// Either way the record is the wrist's last word: the logged set with its
    /// start, and nothing of the set it took back or the one it never touched.
    @Test(arguments: [false, true])
    func aWristFinishLeavesOneRecordWhetherItOrItsQueuedLogLandsFirst(finishFirst: Bool) throws {
        DroppedSetMemory.shared.replaceStore(with: TestClock.freshDefaults())
        defer { DroppedSetMemory.shared.replaceStore(with: .standard) }
        let moment = Self.t0
        let loggedID = Self.setID
        let undoneID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        var pending = WatchPendingActions()
        pending.adopt(Self.sessionID)
        pending.logs[loggedID] = WatchPendingLog(setID: loggedID, weightKg: 55, reps: 8, seconds: 0,
                                                 completedAt: moment)
        pending.undos.insert(undoneID)
        pending.starts[loggedID] = moment.addingTimeInterval(-25)
        let batch = pending.finishBatch(for: Self.sessionID, ratings: [])

        let context = try TestStore.context()
        let session = WorkoutSession(title: "Test", startedAt: moment.addingTimeInterval(-300))
        session.id = Self.sessionID
        context.insert(session)
        func row(_ index: Int) -> SetLog {
            let set = SetLog(catalogID: "squat", exerciseName: "Squat", exerciseOrder: 0, setIndex: index,
                             tracking: .weightReps)
            set.session = session
            context.insert(set)
            return set
        }
        let logged = row(0)
        logged.id = loggedID
        let undone = row(1)
        undone.id = undoneID
        undone.isCompleted = true
        undone.completedAt = moment
        _ = row(2)
        try context.save()

        if !finishFirst {
            // The queued log got here before the Finish.
            logged.weightKg = 55
            logged.reps = 8
            logged.isCompleted = true
            logged.completedAt = moment
        }
        #expect(session.applyWatchFinish(batch))
        session.close(at: moment.addingTimeInterval(10), in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<SetLog>())
        #expect(remaining.map(\.id) == [loggedID])
        let kept = try #require(remaining.first)
        #expect(kept.weightKg == 55 && kept.reps == 8)
        #expect(kept.completedAt == moment)
        #expect(kept.startedAt == moment.addingTimeInterval(-25))

        #expect(!session.applyWatchFinish(batch), "a repeated Finish cannot alter a closed session")
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 1,
                "a late copy of the batch must not bring back a row the close removed")
    }

    // MARK: - The tombstone, across a relaunch

    /// `WatchConnector` and `WatchRootView` across a relaunch: the tombstone is
    /// loaded from defaults as the connector's init loads it, every mirror goes
    /// through the wire and is settled as `receive` settles it, and the two
    /// questions asked before a Health workout starts are asked at `now`.
    private struct Wrist {
        let defaults: UserDefaults
        var now: Date
        var mirror = WatchMirror.placeholder
        var awaitingFreshMirror = false
        var tombstone: WatchSessionTombstone

        init(defaults: UserDefaults, now: Date) {
            self.defaults = defaults
            self.now = now
            tombstone = WatchSessionTombstone(defaults: defaults)
        }

        var session: WatchSessionSnapshot? {
            tombstone.liveSession(in: mirror, awaitingFreshMirror: awaitingFreshMirror, now: now)
        }

        /// What `syncRecorder` and `startIfNeeded` decide together.
        var startsRecorder: Bool {
            guard let session else { return false }
            return tombstone.admits(session.sessionID)
        }

        mutating func end(_ id: UUID) {
            tombstone.mark(id)
            tombstone.save(to: defaults)
        }

        mutating func receive(_ incoming: WatchMirror, fromCache: Bool = false) {
            let payload = incoming.watchPayload(key: WatchLink.mirrorKey)
            guard let decoded = WatchMirror.fromWatchPayload(payload, key: WatchLink.mirrorKey) else {
                Issue.record("A mirror did not survive the wire")
                return
            }
            guard decoded.sentAt >= mirror.sentAt else { return }
            mirror = decoded
            tombstone.settle(with: decoded, fromCache: fromCache)
            tombstone.save(to: defaults)
        }
    }

    private func tombstoneSession(startedAt: Date) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: UUID(), title: "Push", planName: "", startedAt: startedAt,
            exercises: [WatchExerciseSnapshot(id: "bench", name: "Bench", order: 0, tracking: .weightReps,
                                              restSeconds: 90, sets: [])],
            restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg)
    }

    private func mirror(_ session: WatchSessionSnapshot?, sentAt: Date) -> WatchMirror {
        var mirror = WatchMirror.placeholder
        mirror.sentAt = sentAt
        mirror.session = session
        return mirror
    }

    @Test func aSessionEndedOnTheWristStaysEndedAcrossARelaunchUntilThePhoneMovesOn() {
        let suite = "WatchLinkWireTests.tombstone", bare = suite + ".bare"
        let defaults = TestClock.freshDefaults(suite)
        let unguarded = TestClock.freshDefaults(bare)
        defer { for name in [suite, bare] { UserDefaults().removePersistentDomain(forName: "GymTrackTests." + name) } }

        let now = Self.t0
        let start = now.addingTimeInterval(-40 * 60)
        let s = tombstoneSession(startedAt: start)
        let t = tombstoneSession(startedAt: now.addingTimeInterval(-60))
        let sMirror = mirror(s, sentAt: start.addingTimeInterval(30 * 60))

        // The wrist is showing S when the lifter taps Finish out of range.
        var wrist = Wrist(defaults: defaults, now: now)
        wrist.receive(sMirror)
        #expect(wrist.session?.sessionID == s.sessionID && wrist.startsRecorder)
        wrist.end(s.sessionID)
        #expect(wrist.session == nil, "a session ended on the wrist leaves the screen at once")

        // Terminated on the walk back and relaunched with the phone still away:
        // the cached context describes S as live.
        var relaunched = Wrist(defaults: defaults, now: now)
        #expect(relaunched.tombstone.sessionID == s.sessionID, "the tombstone survives a relaunch")
        relaunched.receive(sMirror, fromCache: true)
        #expect(relaunched.session == nil, "a cached mirror of an ended session does not show it")
        #expect(!relaunched.startsRecorder, "nor start Health for it")
        #expect(!relaunched.tombstone.admits(s.sessionID))
        #expect(relaunched.tombstone.sessionID == s.sessionID,
                "a cached context proves nothing about whether the phone heard the Finish")

        // Back in range, the reply to `requestMirror` overtakes the queued Finish.
        relaunched.receive(mirror(s, sentAt: now))
        #expect(relaunched.session == nil && !relaunched.startsRecorder,
                "a reply that still calls the session live does not revive it")
        #expect(relaunched.tombstone.sessionID == s.sessionID)

        // Without the tombstone the same cached mirror restarts the recording,
        // which is the bug it exists for.
        var untouched = Wrist(defaults: unguarded, now: now)
        untouched.receive(sMirror, fromCache: true)
        #expect(untouched.startsRecorder)

        // A new session T shows and records while S's tombstone still stands,
        // even from a cached context that cannot retire it.
        var next = Wrist(defaults: defaults, now: now)
        next.receive(mirror(t, sentAt: now.addingTimeInterval(1)), fromCache: true)
        #expect(next.tombstone.sessionID == s.sessionID)
        #expect(next.session?.sessionID == t.sessionID && next.startsRecorder,
                "a later session is not hidden by the one before it")

        // The phone's answer without S retires it, for good and with no key left.
        next.receive(mirror(nil, sentAt: now.addingTimeInterval(2)))
        #expect(next.tombstone.sessionID == nil)
        #expect(defaults.string(forKey: WatchSessionTombstone.defaultsKey) == nil)
        #expect(Wrist(defaults: defaults, now: now).tombstone.sessionID == nil)

        var switched = Wrist(defaults: defaults, now: now)
        switched.end(s.sessionID)
        switched.receive(mirror(t, sentAt: now.addingTimeInterval(3)))
        #expect(switched.tombstone.sessionID == nil, "a fresh mirror carrying another session retires it too")

        // The twelve-hour rule it replaced in the connector still stands beside it.
        var stale = Wrist(defaults: defaults, now: now)
        stale.receive(mirror(tombstoneSession(startedAt: now.addingTimeInterval(-13 * 3600)),
                             sentAt: now.addingTimeInterval(4)))
        #expect(stale.session == nil)
        var waiting = Wrist(defaults: defaults, now: now)
        waiting.awaitingFreshMirror = true
        waiting.receive(mirror(t, sentAt: now.addingTimeInterval(5)), fromCache: true)
        #expect(waiting.session == nil)
    }

    // MARK: - Which Health workout a session links

    struct LinkCase: Sendable, CustomTestStringConvertible {
        var current: UUID?
        var incoming: UUID
        var phoneWritten: Set<UUID>
        var expected: WatchWorkoutLink
        var testDescription: String
    }

    private static let phoneSave = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private static let firstWatchSave = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
    private static let secondWatchSave = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!

    static let linkCases: [LinkCase] = [
        LinkCase(current: nil, incoming: firstWatchSave, phoneWritten: [phoneSave], expected: .link,
                 testDescription: "nothing linked yet"),
        LinkCase(current: firstWatchSave, incoming: firstWatchSave, phoneWritten: [], expected: .alreadyLinked,
                 testDescription: "the same workout again"),
        LinkCase(current: phoneSave, incoming: firstWatchSave, phoneWritten: [phoneSave],
                 expected: .replacePhoneFallback(phoneSave),
                 testDescription: "a late watch save replaces the phone's fallback"),
        LinkCase(current: firstWatchSave, incoming: secondWatchSave, phoneWritten: [phoneSave],
                 expected: .keepExisting, testDescription: "a second watch workout never replaces the first"),
        LinkCase(current: firstWatchSave, incoming: secondWatchSave, phoneWritten: [], expected: .keepExisting,
                 testDescription: "an ID the phone never wrote is not the phone's to retire"),
    ]

    @Test(arguments: WatchLinkWireTests.linkCases)
    func aWatchWorkoutReplacesOnlyAFallbackThePhoneWroteItself(_ link: LinkCase) {
        #expect(WatchWorkoutLink.decide(current: link.current, incoming: link.incoming,
                                        phoneWritten: link.phoneWritten) == link.expected)
    }

    // MARK: - The first mirror after a launch

    @Test func theFirstAnswerIsSentOnceAndARunningSessionIsWhatItCarries() {
        var state = WatchMirrorState()
        var idle = WatchIdleSnapshot.empty
        idle.todayTitle = "Push"
        _ = state.update(idle: idle)
        let established = state.update(session: nil, ended: nil)
        let unchanged = state.update(session: nil, ended: nil)
        #expect(established)
        #expect(!unchanged, "an unchanged answer is not resent")
        let first = state.nextMirror(sentAt: Self.t0, healthEnabled: true)
        #expect(first?.session == nil && first?.idle.todayTitle == "Push" && first?.revision == 1)

        let snapshot = WatchSessionSnapshot(
            sessionID: Self.sessionID, title: "Push", planName: "", startedAt: Self.t0, exercises: [],
            restTotalSeconds: 0, restAutoStart: false, volumeKg: 0, unit: .kg, effortEnabled: true)
        var running = WatchMirrorState()
        let started = running.update(session: snapshot, ended: nil)
        #expect(started)
        #expect(running.nextMirror(sentAt: Self.t0, healthEnabled: true)?.session == snapshot)
    }

    // MARK: - Out of order, with the phone asleep

    private func same(_ a: Date?, _ b: Date?) -> Bool { WatchCommand.isSameCompletion(a, as: b) }

    @Test func aSecondCopyOfALogTheWristTookBackStaysTakenBack() throws {
        try WatchCommandRig.run { rig in
            let (_, sets) = try rig.seed()
            let log = rig.log(sets[2], at: 600)
            rig.send(log)
            #expect(sets[2].isCompleted)
            rig.send(.undoSet(id: sets[2].id, completedAt: rig.at(600)))
            rig.send(log)

            #expect(!sets[2].isCompleted)
            #expect(sets[2].completedAt == nil)
        }
    }

    @Test func aWristFinishWhoseBatchLogsASetAfterTheTapEndsAtThatSet() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed()
            let logged = rig.at(3000)
            let batch = WatchFinishBatch(
                sessionID: session.id,
                logs: [WatchPendingLog(setID: sets[0].id, weightKg: 60, reps: 8, seconds: 0, completedAt: logged)],
                undos: [], starts: [:], cancels: [], ratings: [], endedAt: rig.at(2700))

            rig.send(.finishSession(batch, metrics: nil))

            #expect(!session.isActive)
            #expect(same(session.endedAt, logged), "the batch's own logs count as the last set")
        }
    }

    /// LINK-04. A reading taken partway through the workout and delivered
    /// after its Finish must not stand in for the whole workout's numbers.
    @Test func aLiveReadingThatLandsAfterTheFinishNeverWritesOverItsTotals() throws {
        try WatchCommandRig.run { rig in
            let (session, sets) = try rig.seed()
            rig.complete(sets[0], at: rig.at(3000))
            try rig.context.save()
            let id = session.id

            rig.send(.metrics(WatchWorkoutMetrics(sessionID: id, currentHeartRate: 120, averageHeartRate: 118,
                                                  maxHeartRate: 150, activeEnergyKcal: 200)))
            #expect(session.averageHeartRate == 118, "a running session takes a live reading, phone asleep or not")

            let finals = WatchWorkoutMetrics(sessionID: id, averageHeartRate: 142, maxHeartRate: 178,
                                             activeEnergyKcal: 410)
            rig.send(.finishSession(WatchFinishBatch(sessionID: id, logs: [], undos: [], starts: [:], cancels: [],
                                                     ratings: []), metrics: finals))
            #expect(!session.isActive)
            #expect(session.averageHeartRate == 142)

            let late = WatchWorkoutMetrics(sessionID: id, currentHeartRate: 110, averageHeartRate: 128,
                                           maxHeartRate: 161, activeEnergyKcal: 190)
            #expect(!late.isHandover)
            rig.send(.metrics(late))
            #expect(session.averageHeartRate == 142)
            #expect(session.maxHeartRate == 178)
            #expect(session.activeEnergyKcal == 410)
            #expect(!session.takeWatchMetrics(late, final: false))

            // The watch's hand-over of the workout it saved to Health still lands,
            // and the real service links that workout to the session.
            var handover = finals
            handover.averageHeartRate = 143
            handover.healthWorkoutID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
            #expect(handover.isHandover)
            rig.send(.metrics(handover))
            #expect(session.averageHeartRate == 143)
            #expect(session.healthWorkoutID == handover.healthWorkoutID)
        }
    }

    @Test func bringingTheLinkUpRetiresAStaleEmptySessionBeforeAnythingIsMirrored() throws {
        try WatchCommandRig.run { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let abandonedID = try rig.seed(startedAt: longAgo).session.id
            #expect(rig.sessions().map(\.id) == [abandonedID])

            // A background launch: the link comes up over a store that already holds it.
            rig.center.configure(container: rig.container)

            #expect(!rig.sessions().contains { $0.id == abandonedID })
        }
    }

    @Test func aStartFromTheWristClosesYesterdaysSessionAtItsLastSetAndOpensItsOwn() throws {
        try WatchCommandRig.run { rig in
            let longAgo = rig.started.addingTimeInterval(-(WorkoutSession.staleAfter + 3600))
            let (yesterday, sets) = try rig.seed(startedAt: longAgo)
            let lastSet = longAgo.addingTimeInterval(40 * 60)
            rig.complete(sets[0], at: lastSet)
            try rig.context.save()
            let yesterdayID = yesterday.id
            #expect(yesterday.isActive && yesterday.sets.count == 3)

            rig.send(.startFreestyle)

            let closed = try #require(rig.sessions().first { $0.id == yesterdayID },
                                      "a stale session with a set logged is closed, not deleted")
            #expect(closed.endedAt == lastSet)
            #expect(closed.sets.map(\.id) == [sets[0].id], "its unlifted rows go with the close")
            let open = rig.sessions().filter(\.isActive)
            #expect(open.count == 1)
            #expect(open.first?.id != yesterdayID)
            #expect(open.first?.wasWatchDriven == true)
        }
    }

    // MARK: - Out of order, with the logger on screen

    @Test func aRepeatedWristLogLeavesTheEffortQuestionAndTheRowsBelowWhereTheLifterLeftThem() throws {
        try WorkoutBench.run { bench in
            let session = bench.session()
            let rows = bench.addRows(to: session, count: 3, weightKg: 60, low: 6, high: 10)
            let workout = bench.open(session)
            let first = WorkoutBench.t0.addingTimeInterval(300)
            let second = WorkoutBench.t0.addingTimeInterval(480)

            #expect(workout.apply(.logSet(id: rows[0].id, weightKg: 60, reps: 8, seconds: 0, at: first)))
            #expect(workout.apply(.logSet(id: rows[1].id, weightKg: 62.5, reps: 8, seconds: 0, at: second)))
            #expect(workout.lastLoggedSetID == rows[1].id)
            #expect(rows[2].weightKg == 62.5)
            rows[2].weightKg = 70

            #expect(workout.apply(.logSet(id: rows[0].id, weightKg: 60, reps: 8, seconds: 0, at: first)))
            #expect(workout.lastLoggedSetID == rows[1].id, "the effort question stays on the set logged last")
            #expect(rows[2].weightKg == 70, "a row the lifter re-dialled keeps what they dialled")
            #expect(rows[0].completedAt == first)
        }
    }

    @Test func anUndoOnScreenThatOvertookItsLogRefusesOnlyThatLogAndAnUnstampedOneTakesWhateverIsThere() throws {
        try WorkoutBench.run { bench in
            let (_, rows, workout) = bench.standard()
            let logged = WorkoutBench.t0.addingTimeInterval(240)
            let later = WorkoutBench.t0.addingTimeInterval(300)
            func log(_ row: SetLog, at moment: Date) -> WatchCommand {
                .logSet(id: row.id, weightKg: 100, reps: 8, seconds: 0, at: moment)
            }

            #expect(workout.apply(.undoSet(id: rows[1].id, completedAt: logged)))
            #expect(workout.apply(log(rows[1], at: logged)))
            #expect(!rows[1].isCompleted && rows[1].completedAt == nil,
                    "a log its undo overtook does not put the set back")
            #expect(workout.apply(log(rows[1], at: later)))
            #expect(rows[1].isCompleted, "only the log the undo named is refused")

            // An older watch's undo carries no stamp, and takes back whatever is there.
            #expect(workout.apply(log(rows[2], at: later)))
            #expect(workout.apply(.undoSet(id: rows[2].id, completedAt: nil)))
            #expect(!rows[2].isCompleted)
            #expect(rows[2].completedAt == nil && rows[2].rpe == nil && rows[2].startedAt == nil)
        }
    }
}
