import Foundation
import Testing
@testable import GymTrack

/// What the phone and the watch say to each other has to survive the wire, and
/// has to fail quietly when it does not. A command that decodes to something it
/// was not, or a malformed payload that traps, costs a logged set mid-workout;
/// a payload that is merely refused costs nothing, because the wrist resends.
///
/// Complements the legacy `Tests/test-watch-*.swift` scripts, which drive the
/// same wire through a hand-built harness; these run against the real types.
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
}
