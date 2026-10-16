import SwiftUI

/// "Log set? 0:42": the logger's one quiet line after the wrist saw a set end
/// with nothing logged, in the slot *Start set* sits in, so nothing below it
/// moves under the thumb when it appears or goes. The figure is how long the
/// movement lasted.
///
/// One tap logs the set at the numbers on screen, exactly as *Log set* would,
/// and the movement goes with it as the set's detected window. It never buzzes
/// on arriving and needs no answer: `WatchMotionSetWatcher` takes it away after
/// a minute or as soon as the lifter does something else.
struct WatchMotionOfferRow: View {
    let offer: MotionSetOffer
    let log: () -> Void

    var body: some View {
        Button(action: log) {
            Label("Log set? \(Self.clock(offer.bout.duration))", systemImage: "figure.strengthtraining.traditional")
        }
        .buttonStyle(WatchQuietButtonStyle(tint: Theme.accent, weight: .heavy, size: 14))
        .accessibilityIdentifier("watch.motionOffer")
        .accessibilityHint("Logs this set with when your wrist's movement showed it started and ended")
    }

    /// Minutes and seconds, as the rest of the wrist writes a length.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
