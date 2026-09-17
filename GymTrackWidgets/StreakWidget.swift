import SwiftUI
import WidgetKit

/// The streak, small enough to live on the Lock Screen.
///
/// Its whole job is to be seen without being opened — the number that makes you
/// not skip today is worth more on the screen you look at forty times a day
/// than on one you have to go and find.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymTrackStreak", provider: SnapshotProvider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    WidgetBackground(phase: entry.snapshot.widgetPhase)
                }
        }
        .configurationDisplayName("Streak")
        .description("Days in a row, and what this week looks like.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

private struct StreakWidgetView: View {
    let snapshot: GymTrackSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(URL(string: "gymtrack://open"))
            .accessibilityLabel(accessibilityLine)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            // One line of system-drawn text, so it takes the tint of whatever
            // it's sitting on rather than choosing a colour of its own.
            Text("\(Image(systemName: "flame.fill")) \(snapshot.streak) day\(snapshot.streak == 1 ? "" : "s") · \(snapshot.sessionsThisWeek) this week")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold))
                    Text("\(snapshot.streak)")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("GYMTRACK")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .widgetAccentable()
                Text(headline)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subline)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            homeScreen
        }
    }

    /// The Home Screen version gets the app's own colour; the Lock Screen ones
    /// above deliberately don't, because a rendered tint there is either washed
    /// out or ignored.
    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SessionPhase.resting.tint)
                Text("STREAK")
                    .font(Theme.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("\(snapshot.streak)")
                .font(Theme.number(44, weight: .black))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 1)

            Text(snapshot.streak == 1 ? "day" : "days")
                .font(Theme.rounded(12, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 5)

            Text(subline)
                .font(Theme.rounded(11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        snapshot.streak > 0
            ? "\(snapshot.streak) day\(snapshot.streak == 1 ? "" : "s") in a row"
            : (snapshot.todayTitle ?? "No streak yet")
    }

    private var subline: String {
        let count = snapshot.sessionsThisWeek
        if let title = snapshot.todayTitle, snapshot.session == nil { return "Today: \(title)" }
        if snapshot.session != nil { return "Session running" }
        return count == 0 ? "Nothing logged this week" : "\(count) session\(count == 1 ? "" : "s") this week"
    }

    private var accessibilityLine: String {
        "\(snapshot.streak) day streak. \(subline)."
    }
}
