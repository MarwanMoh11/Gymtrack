import Foundation

/// Run with scripts/test-watch-link-delivery.sh; nothing here needs a simulator
/// or a paired watch, and none of it has been exercised on one.
///
/// A start that waited in the queue for hours, a command about a session that
/// has since been replaced, and a headless mirror that says "no rest" as fact
/// are all the phone and wrist disagreeing about what is true now. These pin
/// the rules that settle it, and that each protocol change decodes both ways.
@main
struct WatchLinkDeliveryTests {

    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A watch built before the riders existed sends only the command.
    static func legacyPayload(_ command: WatchCommand) -> [String: Any] {
        command.watchPayload(key: WatchLink.commandKey)
    }

    /// What the wrist sends now, through the same stamp `WatchConnector` uses.
    static func payload(_ command: WatchCommand, showing session: UUID?, at moment: Date) -> [String: Any] {
        var payload = command.watchPayload(key: WatchLink.commandKey)
        payload.merge(WatchCommandDelivery.stamp(command, showing: session, at: moment).payload) { $1 }
        return payload
    }

    @MainActor static func main() {
        checkStaleStarts()
        checkSessionFilter()
        checkRidersDecodeBothWays()
        checkMirrorDecodesBothWays()
        checkWristKeepsItsRest()
        print("WatchLinkDeliveryTests passed")
    }

    // MARK: - LINK-06

    static func verdict(_ command: WatchCommand, _ payload: [String: Any], open: UUID?) -> WatchCommandDelivery.Verdict {
        WatchCommandDelivery(payload: payload).verdict(for: command, openSessionID: open, now: now)
    }

    static func checkStaleStarts() {
        for command in [WatchCommand.startToday, .startFreestyle] {
            let hoursOld = payload(command, showing: nil, at: now.addingTimeInterval(-3 * 3600))
            precondition(verdict(command, hoursOld, open: nil) == .staleStart,
                         "A start queued for hours must not begin a workout")
            precondition(verdict(command, hoursOld, open: UUID()) == .staleStart,
                         "...and is refused whether or not a session is already open")

            let justNow = payload(command, showing: nil, at: now.addingTimeInterval(-20))
            precondition(verdict(command, justNow, open: nil) == .apply, "A start from a moment ago is served")

            let skewed = payload(command, showing: nil, at: now.addingTimeInterval(45))
            precondition(verdict(command, skewed, open: nil) == .apply,
                         "A stamp ahead of this clock is skew, not age")

            precondition(verdict(command, legacyPayload(command), open: nil) == .apply,
                         "An older watch stamps nothing and is served as it always was")
        }
        let edge = payload(.startToday, showing: nil, at: now.addingTimeInterval(-WatchCommandDelivery.startShelfLife))
        precondition(verdict(.startToday, edge, open: nil) == .apply, "The shelf life itself is still fresh")
    }

    static func checkSessionFilter() {
        let open = UUID(), replaced = UUID()
        let scoped: [WatchCommand] = [.addSet(catalogID: "bench"), .focusExercise(catalogID: "bench"),
                                      .startRest(seconds: 90), .stopRest, .extendRest(seconds: 30)]
        for command in scoped {
            let stale = payload(command, showing: replaced, at: now)
            precondition(verdict(command, stale, open: open) == .otherSession,
                         "\(command) naming a replaced session must be dropped")
            precondition(verdict(command, stale, open: nil) == .otherSession,
                         "\(command) naming a session that is no longer open must be dropped")
            precondition(verdict(command, payload(command, showing: open, at: now), open: open) == .apply,
                         "\(command) naming the open session is applied")
            precondition(verdict(command, legacyPayload(command), open: open) == .apply,
                         "\(command) from an older watch names nothing and is applied as before")
            precondition(verdict(command, payload(command, showing: nil, at: now), open: open) == .apply,
                         "A wrist that showed no session names none")
        }
        let id = UUID()
        let log = WatchCommand.logSet(id: id, weightKg: 60, reps: 5, seconds: 0, at: now)
        precondition(WatchCommandDelivery.stamp(log, showing: replaced, at: now) == WatchCommandDelivery(),
                     "Set commands find their row by ID and carry no rider")
        precondition(verdict(log, ["x": 1], open: open) == .apply)
        precondition(WatchCommandDelivery.stamp(.startToday, showing: replaced, at: now).sessionID == nil,
                     "A start names no session")
    }

    // MARK: - Both directions

    static func checkRidersDecodeBothWays() {
        // The command itself is untouched by the riders, so an older phone
        // decodes exactly what it always did and never looks at the extras.
        let id = UUID()
        for command in [WatchCommand.startToday, .addSet(catalogID: "bench"), .stopRest,
                        .extendRest(seconds: 30)] {
            let stamped = payload(command, showing: id, at: now)
            precondition(stamped.count > 1 || !(command.isStart || command.actsOnOpenSession))
            precondition(WatchCommand.fromWatchPayload(stamped, key: WatchLink.commandKey) == command,
                         "A stamped command decodes as the same command")
            precondition(WatchCommand.fromWatchPayload(legacyPayload(command), key: WatchLink.commandKey) == command)
            precondition(stamped[WatchLink.commandKey] as? Data == legacyPayload(command)[WatchLink.commandKey] as? Data,
                         "The encoded command is byte for byte what an older watch sends")
        }
        // Round trip of the riders themselves, through millisecond-free doubles.
        let sent = WatchCommandDelivery(sentAt: now, sessionID: id)
        let read = WatchCommandDelivery(payload: sent.payload)
        precondition(read.sessionID == id && abs(read.sentAt!.timeIntervalSince(now)) < 0.001)
        precondition(WatchCommandDelivery(payload: ["garbage": 1]) == WatchCommandDelivery())
    }

    /// The mirror as an older phone builds it: no `restUnknown`.
    struct LegacySession: Codable {
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

    static func newSession(unknown: Bool?) -> WatchSessionSnapshot {
        WatchSessionSnapshot(sessionID: UUID(), title: "Push", planName: "", startedAt: now, exercises: [],
                             restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg,
                             effortEnabled: true, restUnknown: unknown)
    }

    static func checkMirrorDecodesBothWays() {
        let old = LegacySession(sessionID: UUID(), title: "Push", planName: "", startedAt: now, exercises: [],
                                restEndsAt: now, restStartedAt: now, restTotalSeconds: 90,
                                restAutoStart: true, volumeKg: 0, unit: .kg)
        let oldData = try! JSONEncoder.watchLink.encode(old)
        let fromOld = try! JSONDecoder.watchLink.decode(WatchSessionSnapshot.self, from: oldData)
        precondition(fromOld.restUnknown == nil && fromOld.restEndsAt != nil,
                     "A mirror from an older phone is a real rest answer")

        let unknown = newSession(unknown: true)
        let data = try! JSONEncoder.watchLink.encode(unknown)
        precondition(try! JSONDecoder.watchLink.decode(WatchSessionSnapshot.self, from: data).restUnknown == true)
        let seenByOld = try! JSONDecoder.watchLink.decode(LegacySession.self, from: data)
        precondition(seenByOld.sessionID == unknown.sessionID && seenByOld.restEndsAt == nil,
                     "An older watch still decodes it, and reads the blank rest as it always did")

        let known = try! JSONEncoder.watchLink.encode(newSession(unknown: nil))
        precondition(!String(decoding: known, as: UTF8.self).contains("restUnknown"),
                     "A known rest adds no key at all")
    }

    // MARK: - LINK-07

    @MainActor static func checkWristKeepsItsRest() {
        let timer = WatchRestTimer()
        timer.startLocal(seconds: 90, now: now)
        precondition(timer.isRunning && timer.isLocal)

        // The headless mirror that used to end it, arriving after the phone
        // has had time to hear of the rest.
        timer.sync(endsAt: nil, total: 0, unknown: true, now: now.addingTimeInterval(8))
        precondition(timer.isRunning && timer.isLocal,
                     "A mirror that does not know the rest must not clear the wrist's own")

        // A phone that does know, and says there is none, still ends it.
        timer.sync(endsAt: nil, total: 0, now: now.addingTimeInterval(9))
        precondition(!timer.isRunning, "A real 'no rest' from the phone is still followed")

        // Also for a rest that is the phone's: an unknown blank leaves it be.
        let followed = WatchRestTimer()
        followed.sync(endsAt: now.addingTimeInterval(60), total: 90, now: now)
        precondition(followed.isRunning && !followed.isLocal)
        followed.sync(endsAt: nil, total: 0, unknown: true, now: now.addingTimeInterval(10))
        precondition(followed.isRunning, "An unknown blank must not stop a rest the phone started")
    }
}
