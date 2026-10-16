import SwiftUI

/// "last 80 × 8 · 42s": what the set opposite this one did last session, in
/// the exercise's own unit. The target to beat before the set is logged, and
/// the number the gain badge was measured from once it has been.
///
/// Kept off the completed row's busy first line, which already holds the
/// value, a PR mark, a drop label, the gain and the time under tension.
struct LastSessionLine: View {
    let previous: SetLog
    let tracking: TrackingMode
    let scale: LoadScale
    /// True on the PR row, which is filled and needs dark text.
    var onDark = false

    /// The words, shared with the collapsed and expanded rows.
    static func text(_ previous: SetLog, tracking: TrackingMode, scale: LoadScale) -> String {
        "last " + LastSetRecap(previous).label(tracking: WatchTracking(tracking), scale: scale)
    }

    var body: some View {
        Text(Self.text(previous, tracking: tracking, scale: scale))
            .font(Theme.rounded(11, weight: .medium))
            .foregroundStyle(onDark ? AnyShapeStyle(Color.black.opacity(0.55)) : AnyShapeStyle(Theme.textTertiary))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
