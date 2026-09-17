import SwiftUI
import WidgetKit

/// Today's session on the Home Screen, and a way into it that skips the app.
///
/// It has three things to say and shows exactly one: what's running, what's
/// scheduled, or that today is a rest day. Starting is a link rather than an
/// interactive button on purpose — the app has to come forward to build a
/// session anyway, and a link needs nothing shared with this process, which
/// keeps the App Group to the one job only it can do: the numbers above.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymTrackToday", provider: SnapshotProvider()) { entry in
            Group {
                if let snapshot = entry.snapshot {
                    TodayWidgetView(snapshot: snapshot)
                } else {
                    WidgetUnavailableView()
                }
            }
            .containerBackground(for: .widget) {
                WidgetBackground(phase: entry.snapshot?.widgetPhase ?? .working)
            }
        }
        .configurationDisplayName("Today")
        .description("The session you're due to do, or the one you're in.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - The card

private struct TodayWidgetView: View {
    let snapshot: GymTrackSnapshot
    @Environment(\.widgetFamily) private var family

    private var isMedium: Bool { family == .systemMedium }

    var body: some View {
        Group {
            if let session = snapshot.session {
                running(session)
            } else if snapshot.hasSessionToday {
                scheduled
            } else {
                resting
            }
        }
        .widgetURL(snapshot.session == nil ? GymTrackDeepLink.open : GymTrackDeepLink.session)
    }

    // MARK: A session in progress

    private func running(_ session: GymTrackSnapshot.Running) -> some View {
        let phase = snapshot.widgetPhase
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: phase.eyebrow, tint: phase.tint)

            Text(session.exercise)
                .font(Theme.rounded(isMedium ? 20 : 16, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 5)

            // The rest countdown displaces the target while it runs: waiting is
            // what you're doing, so it's what the card should be about.
            if let restEndsAt = session.restEndsAt, restEndsAt > .now {
                Text(timerInterval: Date.now...restEndsAt, countsDown: true)
                    .font(Theme.number(isMedium ? 26 : 22, weight: .bold))
                    .foregroundStyle(SessionPhase.resting.tint)
                    .lineLimit(1)
                    .padding(.top, 1)
            } else if !session.target.isEmpty {
                Text(session.target)
                    .font(Theme.number(isMedium ? 17 : 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 1)
            }

            Spacer(minLength: 6)

            PhaseProgressBar(completed: session.completedSets,
                             total: session.totalSets,
                             phase: phase,
                             height: 4,
                             maxTicks: isMedium ? 24 : 14)

            HStack(spacing: 5) {
                Text("\(session.completedSets)/\(session.totalSets) sets")
                    .font(Theme.number(11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 2)
                Text(session.startedAt, style: .timer)
                    .font(Theme.number(11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 56, alignment: .trailing)
            }
            .padding(.top, 6)
        }
    }

    // MARK: Nothing running, something scheduled

    private var scheduled: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Eyebrow(text: "TODAY", tint: Theme.accent)
                Spacer(minLength: 2)
                if snapshot.streak > 0 { StreakPill(days: snapshot.streak) }
            }

            Text(snapshot.todayTitle ?? "")
                .font(Theme.rounded(isMedium ? 22 : 17, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 5)

            Text("\(snapshot.todayExerciseCount) exercises · \(snapshot.todaySetCount) sets")
                .font(Theme.rounded(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)

            if isMedium, !snapshot.todayMuscles.isEmpty {
                HStack(spacing: 4) {
                    ForEach(snapshot.todayMuscles.prefix(3), id: \.self) { muscle in
                        Text(muscle.uppercased())
                            .font(Theme.microCaps)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                }
                .padding(.top, 7)
            }

            Spacer(minLength: 6)

            StartLink(title: "Start")
        }
    }

    // MARK: Nothing running, nothing scheduled

    private var resting: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Eyebrow(text: snapshot.hasPlan ? "REST DAY" : "NO ROUTINE YET",
                        tint: snapshot.hasPlan ? SessionPhase.done.tint : Theme.textSecondary)
                Spacer(minLength: 2)
                if snapshot.streak > 0 { StreakPill(days: snapshot.streak) }
            }

            Text(snapshot.hasPlan ? weekLine : "Build a routine in GymTrack")
                .font(Theme.rounded(isMedium ? 18 : 15, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 5)

            if snapshot.hasPlan, snapshot.weekVolumeKg > 0 {
                // Converted, not just labelled: the snapshot carries kilograms
                // like everything else in the app, and a pound user reading the
                // kg number under a "lb" would be the worst kind of wrong.
                Text("\(snapshot.unit.fromKg(snapshot.weekVolumeKg).compactVolume) \(snapshot.unit.short) moved")
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }

            Spacer(minLength: 6)

            // A rest day is a suggestion, not a lock — the routine doesn't know
            // you moved leg day.
            StartLink(title: snapshot.hasPlan ? "Train anyway" : "Start a session")
        }
    }

    private var weekLine: String {
        let count = snapshot.sessionsThisWeek
        return count == 0 ? "Nothing logged this week" : "\(count) session\(count == 1 ? "" : "s") this week"
    }
}

// MARK: - Pieces

private struct Eyebrow: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(text)
                .font(Theme.eyebrow)
                .tracking(1.1)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct StreakPill: View {
    let days: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill").font(.system(size: 8, weight: .bold))
            Text("\(days)").font(Theme.number(10, weight: .black))
        }
        .foregroundStyle(SessionPhase.resting.tint)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(SessionPhase.resting.tint.opacity(0.15), in: Capsule())
        .accessibilityLabel("\(days) day streak")
    }
}

/// The one control on the card.
///
/// An interactive widget could run an intent in place, but building a session
/// needs the store, the plan, the progression, a Live Activity and the watch
/// link — so it has to open the app whatever it does. A link does that without
/// the widget process needing to write anywhere the app can read, which leaves
/// the App Group responsible for the one thing only it can do.
private struct StartLink: View {
    let title: String

    var body: some View {
        Link(destination: GymTrackDeepLink.startToday) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal.fill").font(.system(size: 10, weight: .black))
                Text(title).font(Theme.rounded(12, weight: .heavy))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(SessionPhase.working.gradient, in: Capsule())
        }
    }
}

/// What a widget has instead of data: the app has never published a snapshot.
/// On a build where the App Group isn't provisioned, this is every refresh —
/// so it says what's true rather than borrowing "no routine yet", which would
/// tell someone with a routine that they haven't got one.
///
/// The whole widget is already a link to the app, so the accessory sizes say
/// their piece and stop; only the Home Screen ones have room for a control.
struct WidgetUnavailableView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.widgetURL(GymTrackDeepLink.open)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text("GymTrack — open to set up")

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "bolt.horizontal.fill").font(.system(size: 17, weight: .bold))
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("GYMTRACK")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .widgetAccentable()
                Text("Open to fill this in")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: "GYMTRACK", tint: Theme.textSecondary)
                Text("Open GymTrack to fill this in")
                    .font(Theme.rounded(15, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 5)
                Spacer(minLength: 6)
                StartLink(title: "Open")
            }
        }
    }
}

/// The URLs the app answers on — see `RootView.onOpenURL`.
enum GymTrackDeepLink {
    static let open = URL(string: "gymtrack://open")!
    static let session = URL(string: "gymtrack://session")!
    /// Falls back to a freestyle session when today isn't a training day.
    static let startToday = URL(string: "gymtrack://start-today")!
}

/// The ground every GymTrack widget sits on: the app's near-black, lifted by a
/// wash of whatever the session's colour currently is.
struct WidgetBackground: View {
    let phase: SessionPhase

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [phase.tint.opacity(0.16), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 190)
        }
    }
}

// MARK: - Phase

extension GymTrackSnapshot {
    /// Which colour the card belongs to, read the same way the Lock Screen and
    /// the wrist read it.
    var widgetPhase: SessionPhase {
        guard let session else { return hasSessionToday ? .working : .done }
        if let restEndsAt = session.restEndsAt, restEndsAt > .now { return .resting }
        if session.totalSets > 0, session.completedSets >= session.totalSets { return .done }
        return .working
    }
}
