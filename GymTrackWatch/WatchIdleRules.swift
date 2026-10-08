import Foundation

/// What the idle screen says once today's workout is done, kept free of
/// SwiftUI so the test harness can hold it to account without a watch.
///
/// The idle screen used to be built only from what the phone sent before the
/// workout, so the moment Finish was tapped it went back to offering the same
/// day's Start workout, one tap from a duplicate session.
enum WatchIdleRules {

    /// The card the idle screen leads with when today's workout is done.
    enum DoneCard: Equatable {
        /// The phone's account, with the sets, volume and time its Today card
        /// shows.
        case confirmed(WatchIdleSnapshot.Completed)
        /// A session this wrist finished that the phone has not answered for
        /// yet. Its name and nothing else; see `WatchWristFinish`.
        case awaitingPhone(WatchWristFinish)

        var title: String {
            switch self {
            case .confirmed(let done): done.title
            case .awaitingPhone(let finish): finish.title
            }
        }
    }

    /// What a Finish on this wrist leaves for the idle screen to show, or
    /// `nil` when nothing was logged: the phone deletes an empty session, and
    /// a day with nothing trained is not a done one.
    static func wristFinish(of session: WatchSessionSnapshot) -> WatchWristFinish? {
        guard session.completedSets > 0 else { return nil }
        return WatchWristFinish(sessionID: session.sessionID, title: session.title,
                                startedAt: session.startedAt, planName: session.planName)
    }

    /// The done card, if today has one.
    ///
    /// A Finish the phone has not answered for comes first, since the idle
    /// screen the phone sent before it cannot count it. It is asked the
    /// phone's question with what the wrist holds: it has to have started this
    /// training day, and a freestyle session does not make a day done while
    /// the mirror says a day of the plan is scheduled. A mirror that has gone
    /// out of date cannot say that, so a freestyle Finish waits for the phone.
    ///
    /// Otherwise it is the phone's word, and only while the mirror still
    /// describes this training day: yesterday's done card is not today's.
    static func doneCard(idle: WatchIdleSnapshot, finishedHere: WatchWristFinish?,
                         now: Date, calendar: Calendar) -> DoneCard? {
        let describesToday = idle.describesTrainingDay(at: now, calendar: calendar)
        let confirmed = describesToday ? idle.completedToday : nil
        if let finishedHere, finishedHere.sessionID != confirmed?.sessionID,
           TrainingDay.key(for: finishedHere.startedAt, calendar: calendar)
               == TrainingDay.key(for: now, calendar: calendar),
           !finishedHere.planName.isEmpty || (describesToday && idle.todayTitle == nil) {
            return .awaitingPhone(finishedHere)
        }
        return confirmed.map(DoneCard.confirmed)
    }
}
