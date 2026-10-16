import SwiftUI

/// "Take 30 kg · 3 sets": the phone's load offer, on the wrist, under the
/// numbers it would change. One tap takes it through the phone's own take, and
/// the row turns into that take's Undo until the next of its sets is logged.
///
/// It is drawn because a session run from the wrist never saw the offer, and
/// the next set logged there at the old weight was filed as the lifter turning
/// it down. Like everything else optional on this screen it never buzzes,
/// blocks nothing and needs no answer: ignored, it costs no tap at all.
struct WatchLoadOfferRow: View {
    let offer: WatchLoadOffer
    let scale: LoadScale
    let take: () -> Void
    let undo: () -> Void

    var body: some View {
        if offer.taken {
            Button(action: undo) {
                Label("Undo \(rung)", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(WatchQuietButtonStyle(tint: Theme.textSecondary, weight: .semibold, size: 12))
            .accessibilityIdentifier("watch.loadOffer.undo")
            .accessibilityHint("Puts the sets still to come back to the weight they had")
        } else {
            Button(action: take) {
                Label("Take \(rung) · \(sets)", systemImage: offer.isBackOff ? "arrow.down.right" : "arrow.up.right")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(WatchQuietButtonStyle(tint: tint, weight: .heavy, size: 13))
            .accessibilityIdentifier("watch.loadOffer")
            .accessibilityHint("Moves the sets still to come to this weight")
        }
    }

    /// Green for more weight and amber for less, as on the phone's card.
    private var tint: Color { offer.isBackOff ? Theme.warning : Theme.positive }

    private var rung: String { scale.format(offer.toKg) }

    private var sets: String { "\(offer.rows.count) set\(offer.rows.count == 1 ? "" : "s")" }
}
