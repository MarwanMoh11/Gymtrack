import Foundation

/// How a command leaves the wrist: as a live message, through the delivery
/// queue, or not at all.
///
/// This lived inside `WatchConnector.send`, next to the WatchConnectivity
/// calls, where nothing short of a paired phone could ask it anything. It is
/// pure over its inputs now, and the connector only carries the answer out.
enum WatchCommandRouting {

    enum Route: Equatable, Sendable {
        /// `sendMessage`, now. It wakes the phone app if it has to, and a
        /// Start or a request for the mirror gets its answer in the reply.
        case live
        /// `transferUserInfo`, behind whatever is already waiting there. The
        /// system delivers that queue when it chooses, which can be minutes.
        case queued
        /// Not sent.
        case dropped
    }

    /// - Parameters:
    ///   - reachable: whether the phone can be messaged right now.
    ///   - waiting: the commands still in the delivery queue.
    static func route(_ command: WatchCommand, reachable: Bool, waiting: [WatchCommand]) -> Route {
        guard isWorthQueueing(command) else { return reachable ? .live : .dropped }
        guard reachable else { return .queued }
        // WatchConnectivity keeps order only inside the queue. A command sent
        // live while earlier ones still wait there reaches the phone first, so
        // an undo landed before its own log and the log then put the set back.
        // Behind a backlog the command queues too, and the phone hears the
        // wrist in the order the lifter tapped.
        //
        // A Start names no set and no session, so the only thing it can
        // overtake to any harm is the end of the last workout: ahead of that,
        // the phone still has the old session open and answers with it, which
        // this wrist refuses to draw (see `WatchSessionTombstone`). Behind
        // anything else it goes live. Queued, it waited for the system to get
        // round to the queue: the wrist sat on "Starting" and gave up, and the
        // phone began the workout whenever the queue finally arrived.
        let mustWait = command.isStart
            ? waiting.contains(where: endsSession)
            : waiting.contains(where: isWorthQueueing)
        return mustWait ? .queued : .live
    }

    /// Whether a live message that failed goes into the queue instead.
    /// Reachability can lapse between the check and the send, and a failure
    /// can be reported for a message that did arrive, which the phone treats
    /// as the same command arriving twice.
    static func requeuesAfterFailure(_ command: WatchCommand) -> Bool {
        isWorthQueueing(command)
    }

    /// Whether a command is still worth acting on whenever the queue delivers
    /// it. Two are not, and they go live or not at all.
    ///
    /// A request for the mirror asks for the phone's answer now. Queued, it
    /// landed long after anybody was waiting, and until then it sat in the
    /// queue holding every later command behind it, a Start included. It was
    /// queued at the moments most likely to find the phone out of reach, a
    /// launch and a wrist raise, so a Start tapped just after went to the queue
    /// with it, and so did the request the idle screen sends three seconds
    /// later to recover a lost reply. Nothing is lost by dropping one: the next
    /// launch, wrist raise or return to range asks again, and the phone's
    /// application context carries its latest state regardless.
    ///
    /// A live heart-rate reading is out of date by the next one; see
    /// `WatchWorkoutMetrics.isHandover`. Queued, hundreds drained after the
    /// Finish and wrote partway numbers over the session's totals.
    private static func isWorthQueueing(_ command: WatchCommand) -> Bool {
        switch command {
        case .requestMirror: false
        case .metrics(let metrics): metrics.isHandover
        default: true
        }
    }

    private static func endsSession(_ command: WatchCommand) -> Bool {
        switch command {
        case .finishSession, .discardSession, .finish, .discard: true
        default: false
        }
    }
}
