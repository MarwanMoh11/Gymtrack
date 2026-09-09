import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen card and Dynamic Island presentation for a running session.
///
/// Every clock on screen is a `Text(timerInterval:)`, so it keeps time on its
/// own between pushes — the app only sends an update when a set is logged, a
/// rest starts or stops, or the session ends.
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivity.self) { context in
            LockScreenCard(context: context)
                // The Lock Screen presentation needs its own link; the one on
                // the Dynamic Island below doesn't carry over.
                .widgetURL(WorkoutActivity.deepLink)
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandRing(context: context)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.isResting ? "REST" : "ELAPSED")
                            .font(Theme.eyebrow)
                            .tracking(1.0)
                            .foregroundStyle(Theme.textTertiary)
                        HeadlineClock(context: context, size: 20)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(headline(context))
                                .font(Theme.rounded(16, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(statusLine(context))
                                .font(Theme.rounded(12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        SetProgressBar(state: context.state)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                CompactRing(context: context)
            } compactTrailing: {
                HeadlineClock(context: context, size: 13)
            } minimal: {
                CompactRing(context: context)
            }
            .widgetURL(WorkoutActivity.deepLink)
            .keylineTint(Theme.accent)
        }
    }

    private func headline(_ context: ActivityViewContext<WorkoutActivity>) -> String {
        if context.isRestOver { return "Rest done" }
        if context.isResting { return "Resting" }
        return context.state.currentExercise
    }

    private func statusLine(_ context: ActivityViewContext<WorkoutActivity>) -> String {
        if context.isRestOver {
            return "\(context.state.currentExercise) · set \(context.state.currentSetNumber) is up"
        }
        return context.state.statusLine
    }
}

// MARK: - Lock Screen

private struct LockScreenCard: View {
    let context: ActivityViewContext<WorkoutActivity>

    private var state: WorkoutActivity.ContentState { context.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            hero
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Session name on the left, the session clock on the right — the two
    /// things that stay true no matter what part of the workout you're in.
    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 7, height: 7)
            Text(context.attributes.sessionTitle.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "stopwatch")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            Text(state.elapsedLabel)
                .font(Theme.number(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// The one number that matters right now: the rest countdown while you're
    /// between sets, the exercise you're on while you're under the bar.
    @ViewBuilder
    private var hero: some View {
        if context.isRestOver {
            heroBlock(eyebrow: "REST DONE", eyebrowTint: Theme.accent) {
                Text(state.currentExercise)
                    .font(Theme.rounded(22, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } trailing: {
                Text("Set \(state.currentSetNumber)")
                    .font(Theme.rounded(13, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        } else if state.isResting {
            heroBlock(eyebrow: "RESTING", eyebrowTint: Theme.accent) {
                RestClock(state: state)
                    .font(Theme.number(34, weight: .bold))
                    .foregroundStyle(Theme.accent)
            } trailing: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("NEXT UP")
                        .font(Theme.eyebrow)
                        .tracking(1.0)
                        .foregroundStyle(Theme.textTertiary)
                    Text(state.currentExercise)
                        .font(Theme.rounded(14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("Set \(state.currentSetNumber) · \(state.currentTarget)")
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        } else if state.setsRemaining == 0 {
            heroBlock(eyebrow: "ALL SETS LOGGED", eyebrowTint: Theme.accent) {
                Text("Finish up")
                    .font(Theme.rounded(22, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
            } trailing: {
                Text(state.volumeLabel)
                    .font(Theme.number(15, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        } else {
            heroBlock(eyebrow: "ON DECK", eyebrowTint: Theme.textTertiary) {
                Text(state.currentExercise)
                    .font(Theme.rounded(22, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } trailing: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SET \(state.currentSetNumber)/\(state.currentSetTotal)")
                        .font(Theme.eyebrow)
                        .tracking(1.0)
                        .foregroundStyle(Theme.textTertiary)
                    Text(state.currentTarget)
                        .font(Theme.number(15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            }
        }
    }

    private func heroBlock<Leading: View, Trailing: View>(
        eyebrow: String,
        eyebrowTint: Color,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(eyebrowTint)
                leading()
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            SetProgressBar(state: state)
            HStack(spacing: 6) {
                Text("\(state.completedSets)/\(state.totalSets) sets")
                    .font(Theme.number(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.textTertiary)
                Text(state.volumeLabel)
                    .font(Theme.number(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
                Text("Tap to log")
                    .font(Theme.rounded(11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - Pieces

/// Sets completed across the whole session.
private struct SetProgressBar: View {
    let state: WorkoutActivity.ContentState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: filledWidth(in: geo.size.width))
            }
        }
        .frame(height: 4)
    }

    private func filledWidth(in total: CGFloat) -> CGFloat {
        guard total.isFinite, total > 0 else { return 0 }
        let fraction = state.progress.isFinite ? min(1, max(0, state.progress)) : 0
        guard fraction > 0 else { return 0 }
        return min(total, max(4, total * fraction))
    }
}

/// Ring used in the Dynamic Island. Shows rest remaining while resting and
/// session completion otherwise, so the glanceable shape always answers the
/// question you actually have.
private struct CompactRing: View {
    let context: ActivityViewContext<WorkoutActivity>

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, trim))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: glyph)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Theme.accent)
        }
        .frame(width: 18, height: 18)
    }

    private var trim: Double {
        context.isResting ? 1 - context.state.restProgress : context.state.progress
    }

    private var glyph: String {
        if context.isRestOver { return "bolt.fill" }
        return context.isResting ? "hourglass" : "dumbbell.fill"
    }
}

private struct IslandRing: View {
    let context: ActivityViewContext<WorkoutActivity>

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.02, context.state.progress))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(context.state.completedSets)/\(context.state.totalSets)")
                    .font(Theme.number(14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("SETS")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// The headline number: the rest countdown when there is one, the session
/// length otherwise.
///
/// Only the countdown is a live timer. A count-up `Text(timerInterval:)` gets
/// its seconds rendered as "--" in a Live Activity, and a session clock is
/// worth reading to the minute anyway — the app restamps `elapsedLabel` on
/// every set, rest and foreground.
private struct HeadlineClock: View {
    let context: ActivityViewContext<WorkoutActivity>
    let size: CGFloat

    var body: some View {
        Group {
            if context.isRestOver {
                Text("GO")
                    .font(Theme.rounded(size, weight: .heavy))
            } else if context.state.isResting {
                RestClock(state: context.state)
                    .font(Theme.number(size, weight: .bold))
            } else {
                Text(context.state.elapsedLabel)
                    .font(Theme.number(size, weight: .bold))
            }
        }
        .foregroundStyle(Theme.accent)
    }
}

/// The live countdown between sets.
///
/// `Text(timerInterval:)` is the only clock a Live Activity keeps running by
/// itself — `.relative` renders once and then freezes. How finely it ticks is
/// the system's call: it always counts the last minute down to the second, and
/// throttles to whole minutes above that when it's conserving updates (which
/// the Simulator does constantly).
private struct RestClock: View {
    let state: WorkoutActivity.ContentState

    var body: some View {
        Group {
            if let start = state.restStartedAt, let end = state.restEndsAt, end > start {
                Text(timerInterval: start...end, countsDown: true)
            } else {
                Text("0:00")
            }
        }
        .monospacedDigit()
    }
}


// MARK: - Context helpers

extension ActivityViewContext where Attributes == WorkoutActivity {
    var isResting: Bool { state.isResting && !isRestOver }

    /// A rest we pushed with a stale date that has since passed. The system
    /// flips `isStale` for us, which is how the card announces the rest is over
    /// without the app waking up to push anything.
    var isRestOver: Bool { state.isResting && isStale }
}
