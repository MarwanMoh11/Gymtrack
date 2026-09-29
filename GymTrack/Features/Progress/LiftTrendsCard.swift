import SwiftUI

/// Which lifts are moving, flat or sliding. Nothing on it is tappable. The
/// dashboard leaves it out until at least one lift has enough recent history to
/// be judged: an empty card would say "no data" where a missing one says
/// nothing false. The tags come from `LiftTrends` and are never stored.
struct LiftTrendsCard: View {
    let lifts: [LiftTrends.Lift]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Lifts")
            ForEach(lifts) { lift in
                row(lift)
            }
            Text("Best set per session by estimated one-rep max, over the last \(LiftTrends.windowWeeks) weeks. Changes of a single weight step count as flat.")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
        }
        .gtCard()
    }

    private func row(_ lift: LiftTrends.Lift) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(lift.name)
                    .font(Theme.rounded(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(lift.sessionCount) sessions")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: symbol(lift.trend))
                    .font(.system(size: 10, weight: .black))
                Text(title(lift.trend))
                    .font(Theme.rounded(12, weight: .bold))
            }
            .foregroundStyle(color(lift.trend))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color(lift.trend).opacity(0.14)))
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lift.name), \(title(lift.trend)), from \(lift.sessionCount) sessions")
    }

    private func title(_ trend: LiftTrends.Trend) -> String {
        switch trend {
        case .moving: "Moving"
        case .flat: "Flat"
        case .sliding: "Sliding"
        }
    }

    private func symbol(_ trend: LiftTrends.Trend) -> String {
        switch trend {
        case .moving: "arrow.up.right"
        case .flat: "arrow.right"
        case .sliding: "arrow.down.right"
        }
    }

    private func color(_ trend: LiftTrends.Trend) -> Color {
        switch trend {
        case .moving: Theme.positive
        case .flat: Theme.textSecondary
        case .sliding: Theme.negative
        }
    }
}
