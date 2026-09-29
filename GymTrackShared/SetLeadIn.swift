import Foundation

/// The count-in between tapping *Start set* and the set beginning.
///
/// Nobody is under the bar when they tap it. The phone is on a bench and the
/// wrist is hanging at your side, and between the tap and the first rep there
/// is the step to the bar, the grip and the unrack. Stamping the tap as the
/// start put those seconds inside every announced set: its length came out long
/// and the rest in front of it short by the same amount, every time — and those
/// two numbers are the only reason the start is recorded at all.
///
/// So the tap starts a count, and the set is taken to begin when the count runs
/// out. That is still a moment somebody marked rather than one the app guessed:
/// both strips count it down on screen, so the stamp is the "go" the lifter was
/// shown and agreed to by tapping, not an estimate of when they got round to it.
///
/// Added once, on the device that was tapped, and never again. A start from the
/// wrist reaches the phone with the count already in it, and adding it a second
/// time on arrival would push every set begun on the watch three seconds into
/// its own first rep.
enum SetLeadIn {
    /// Long enough to get from a tap to a grip, short enough that a lifter who
    /// was already set up isn't kept waiting. Whole seconds, so the count-in and
    /// the clock that follows it tick on the same beat.
    static let seconds: TimeInterval = 3

    /// When a set announced at `tap` begins.
    static func start(forTapAt tap: Date) -> Date {
        tap.addingTimeInterval(seconds)
    }

    /// Where a strip's `TimelineView` draws its ticks from.
    ///
    /// Not the start itself: while the count is running the start hasn't
    /// happened yet, and a periodic schedule isn't promised to tick before the
    /// date it runs from — the count would sit on 3 and then jump straight to a
    /// running clock. Anchored back far enough to cover any start either device
    /// accepts (the count, plus the most the two clocks are allowed to disagree),
    /// and by whole seconds, so the ticks still land exactly on the start.
    static func tickAnchor(for start: Date) -> Date {
        start.addingTimeInterval(-(seconds + WatchCommand.clockSkewTolerance))
    }
}

/// What a start strip reads at a given moment — the count-in while the set is
/// still a few seconds off, then the clock from 0:00.
///
/// Shared so the phone and the wrist say the same words about the same set:
/// with a start announced on one, the other is drawing it too, and the two
/// disagreeing about whether the lifter is going yet would be the screens
/// arguing about the one thing the lifter is looking at them for.
struct SetStartReading {
    let start: Date
    let now: Date

    /// 3, 2, 1 — whole seconds until the set begins, or `nil` once it has.
    var countdown: Int? {
        let remaining = start.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return Int(remaining.rounded(.up))
    }

    var isCountingIn: Bool { countdown != nil }

    var eyebrow: String { isCountingIn ? "GET SET" : "WORKING" }

    /// The count on its own during the count-in, since a clock reading "-0:02"
    /// is a set going backwards; after it, time under the bar.
    var figure: String {
        if let countdown { return "\(countdown)" }
        return max(0, now.timeIntervalSince(start)).clockString
    }

    /// The whole strip as one sentence for VoiceOver, which would otherwise read
    /// a lone "3" with nothing to say what it is counting towards.
    var spoken: String {
        if let countdown { return "Get set. Starting in \(countdown)" }
        let elapsed = Duration.seconds(max(0, now.timeIntervalSince(start)).rounded())
        return "Working, \(elapsed.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))"
    }
}

extension WatchCommand {
    /// Whether a start is a moment worth writing down, on either path that
    /// writes one.
    ///
    /// A start is ahead of the clock by design now — it is the end of the
    /// count-in, not the tap — so the allowance for a stamp from the future is
    /// the count plus the skew `clockSkewTolerance` already forgives. Checked
    /// against the skew alone, the count would quietly spend three seconds of
    /// that allowance, and a start that was exactly as far ahead as it was
    /// meant to be would be refused as a clock being wrong.
    static func isBelievableStart(_ start: Date) -> Bool {
        start.timeIntervalSinceNow <= SetLeadIn.seconds + clockSkewTolerance
    }
}
