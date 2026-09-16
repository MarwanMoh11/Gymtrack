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
                .activitySystemActionForegroundColor(context.phase.tint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SetBadge(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockBadge(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandFooter(context: context)
                }
            } compactLeading: {
                CompactRing(context: context)
            } compactTrailing: {
                CompactClock(context: context)
            } minimal: {
                CompactRing(context: context)
            }
            .widgetURL(WorkoutActivity.deepLink)
            .keylineTint(context.phase.tint)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenCard: View {
    let context: ActivityViewContext<WorkoutActivity>

    private var state: WorkoutActivity.ContentState { context.state }
    private var phase: SessionPhase { context.phase }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            hero
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .containerBackground(for: .widget) {
            CardBackground(phase: phase)
        }
    }

    /// Session name on the left, the session clock on the right — the two
    /// things that stay true no matter what part of the workout you're in.
    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(phase: phase)
            Text(context.attributes.sessionTitle.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.3)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Chip {
                Image(systemName: "stopwatch")
                    .font(.system(size: 9, weight: .bold))
                Text(state.elapsedLabel)
                    .font(Theme.number(12, weight: .semibold))
            }
        }
    }

    /// The one number that matters right now: the rest countdown while you're
    /// between sets, the exercise you're on while you're under the bar.
    @ViewBuilder
    private var hero: some View {
        switch phase {
        case .restOver:
            // The prescription sits under the name rather than beside it: gym
            // names run long ("Incline Dumbbell Press"), and a second column
            // was squeezing them into an ellipsis.
            HeroRow(phase: phase, alignment: .top) {
                ExerciseHeadline(state: state, phase: phase)
            } trailing: {
                // The one moment the card is asking for something back, so the
                // ask is the brightest thing on it.
                Text("SET \(state.currentSetNumber)")
                    .font(Theme.rounded(12, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(phase.gradient))
                    .shadow(color: phase.glow, radius: 8, y: 1)
            }
        case .resting:
            HeroRow(phase: phase) {
                RestClock(state: state)
                    .font(Theme.number(31, weight: .bold))
                    .foregroundStyle(phase.tint)
                    .shadow(color: phase.glow, radius: 9)
            } trailing: {
                UpNext(state: state)
            }
        case .done:
            // Nothing on the right: the sets and the volume are both in the
            // footer already, and repeating either one here just crowds the
            // one card that has earned some air.
            HeroRow(phase: phase) {
                Text("Finish up")
                    .font(Theme.rounded(22, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            } trailing: {
                EmptyView()
            }
        case .working:
            HeroRow(phase: phase, alignment: .top) {
                ExerciseHeadline(state: state, phase: phase)
            } trailing: {
                Text("SET \(state.currentSetNumber)/\(state.currentSetTotal)")
                    .font(Theme.eyebrow)
                    .tracking(0.9)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 7) {
            PhaseProgressBar(completed: state.completedSets, total: state.totalSets, phase: phase)
            HStack(spacing: 6) {
                Chip {
                    Text("\(state.completedSets)/\(state.totalSets) sets")
                        .font(Theme.number(11, weight: .semibold))
                }
                Chip {
                    Text(state.volumeLabel)
                        .font(Theme.number(11, weight: .semibold))
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Text(phase == .done ? "Tap to finish" : "Tap to log")
                        .font(Theme.rounded(11, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .black))
                }
                .foregroundStyle(phase.gradient)
            }
            .lineLimit(1)
        }
    }
}

/// The card's ground: near-black, with the phase colour bleeding in behind the
/// glyph tile and cooling out through the opposite corner. A Live Activity is
/// laid over whatever wallpaper the phone has, so the card has to carry its own
/// depth rather than borrow any.
private struct CardBackground: View {
    let phase: SessionPhase

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [phase.tint.opacity(0.20), .clear],
                           center: UnitPoint(x: 0.02, y: -0.10),
                           startRadius: 0, endRadius: 210)
            RadialGradient(colors: [phase.trail.opacity(0.13), .clear],
                           center: UnitPoint(x: 1.05, y: 1.15),
                           startRadius: 0, endRadius: 185)
            LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                           startPoint: .top, endPoint: .center)
        }
    }
}

/// Eyebrow and headline under a tinted glyph, with whatever the phase wants to
/// say on the right.
private struct HeroRow<Leading: View, Trailing: View>: View {
    let phase: SessionPhase
    /// `.top` when the left column runs to three lines, so the trailing label
    /// stays level with the eyebrow instead of drifting to the middle of it.
    var alignment: VerticalAlignment = .center
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: alignment, spacing: 11) {
            GlyphTile(phase: phase)
            VStack(alignment: .leading, spacing: 1) {
                Text(phase.eyebrow)
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(phase.tint.opacity(0.9))
                    .lineLimit(1)
                leading
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// The exercise you're on, with what's prescribed for the set underneath it.
private struct ExerciseHeadline: View {
    let state: WorkoutActivity.ContentState
    let phase: SessionPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(state.currentExercise)
                .font(Theme.rounded(21, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(state.currentTarget)
                .font(Theme.number(12, weight: .semibold))
                .foregroundStyle(phase.gradient)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// The square of colour that answers "which of the four is this?" before the
/// eyebrow beside it has been read.
private struct GlyphTile: View {
    let phase: SessionPhase

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(LinearGradient(colors: [phase.tint.opacity(0.28), phase.trail.opacity(0.08)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [phase.tint.opacity(0.55),
                                                          phase.tint.opacity(0.08)],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing),
                                  lineWidth: 1)
            )
            .overlay(
                Image(systemName: phase.glyph)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(phase.gradient)
            )
            .frame(width: 34, height: 34)
            .shadow(color: phase.tint.opacity(0.22), radius: 7, y: 2)
    }
}

/// Where the rest countdown is pointing.
private struct UpNext: View {
    let state: WorkoutActivity.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("NEXT UP")
                .font(Theme.eyebrow)
                .tracking(1.0)
                .foregroundStyle(Theme.textTertiary)
            Text(state.currentExercise)
                .font(Theme.rounded(14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Set \(state.currentSetNumber) · \(state.currentTarget)")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Translucent capsule for the small readouts, so the numbers have an edge to
/// sit against instead of floating on whatever is behind the card.
private struct Chip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
            )
    }
}

/// The live dot beside the session name. Haloed rather than plain, which is
/// the difference between "a session is running" and "there is a dot here".
private struct StatusDot: View {
    let phase: SessionPhase

    var body: some View {
        Circle()
            .fill(phase.gradient)
            .frame(width: 7, height: 7)
            // Sized past its own bounds on purpose: the halo draws outside the
            // dot without taking any width off the title next to it.
            .overlay(
                Circle()
                    .strokeBorder(phase.tint.opacity(0.22), lineWidth: 3)
                    .frame(width: 13, height: 13)
            )
            .shadow(color: phase.glow, radius: 5)
    }
}

// MARK: - Pieces

/// Ring used in the Dynamic Island. Shows rest remaining while resting and
/// session completion otherwise, so the glanceable shape always answers the
/// question you actually have.
private struct CompactRing: View {
    let context: ActivityViewContext<WorkoutActivity>

    var body: some View {
        let phase = context.phase
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [phase.tint.opacity(0.20), .clear],
                                     center: .center, startRadius: 0, endRadius: 12))
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, trim))
                .stroke(phase.arc, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: phase.glow, radius: 2.5)
            Image(systemName: phase.glyph)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(phase.tint)
        }
        .frame(width: 18, height: 18)
    }

    private var trim: Double {
        context.isResting ? 1 - context.state.restProgress : context.state.progress
    }
}

/// Expanded leading: session progress as an arc, with the same count spelled
/// out beside it. Deliberately narrow — the leading region sits against the
/// camera, and anything wider than the ring plus a fraction gets squeezed.
private struct SetBadge: View {
    let context: ActivityViewContext<WorkoutActivity>

    var body: some View {
        let phase = context.phase
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, context.state.progress))
                    .stroke(phase.arc, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: phase.glow, radius: 3)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(context.state.completedSets)/\(context.state.totalSets)")
                    .font(Theme.number(13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("SETS")
                    .font(Theme.microCaps)
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Expanded trailing: whichever clock matters right now, labelled so that
/// "1:12" can't be read as the other one.
private struct ClockBadge: View {
    let context: ActivityViewContext<WorkoutActivity>

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label)
                .font(Theme.microCaps)
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            HeadlineClock(context: context, size: 17)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var label: String {
        if context.isRestOver { return "GO TIME" }
        return context.isResting ? "REST" : "ELAPSED"
    }
}

/// Expanded bottom: the sentence version of the two badges above it, over the
/// same set bar the Lock Screen card carries.
private struct IslandFooter: View {
    let context: ActivityViewContext<WorkoutActivity>

    var body: some View {
        let phase = context.phase
        VStack(alignment: .leading, spacing: 5) {
            Text(headline)
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(phase == .restOver ? AnyShapeStyle(phase.gradient) : AnyShapeStyle(Theme.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(statusLine)
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(context.state.volumeLabel)
                    .font(Theme.number(12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            // Continuous here: the island is half the Lock Screen's width, and
            // eighteen ticks across it would be lint rather than a bar.
            PhaseProgressBar(completed: context.state.completedSets, total: context.state.totalSets,
                             phase: phase, height: 5, maxTicks: 0)
                .padding(.top, 2)
        }
        .padding(.top, 7)
    }

    private var headline: String {
        if context.isRestOver { return "Rest done" }
        if context.isResting { return "Resting" }
        return context.state.currentExercise
    }

    private var statusLine: String {
        if context.isRestOver {
            return "\(context.state.currentExercise) · set \(context.state.currentSetNumber) is up"
        }
        return context.state.statusLine
    }
}

/// Compact trailing. The width is fixed on purpose: left to size itself, the
/// pill grew and shrank every time the clock rolled onto a longer string, and
/// a live `Text(timerInterval:)` reserves room for the widest reading it might
/// ever show.
private struct CompactClock: View {
    let context: ActivityViewContext<WorkoutActivity>

    var body: some View {
        HeadlineClock(context: context, size: 13, short: true)
            .frame(width: 34, alignment: .trailing)
    }
}

/// The headline number: the rest countdown when there is one, the session
/// length otherwise.
///
/// Only the countdown is a live timer. A count-up `Text(timerInterval:)` gets
/// its seconds rendered as "--" in a Live Activity, and a session clock is
/// worth reading to the minute anyway — the app restamps `elapsedLabel` on
/// every set, rest and foreground.
///
/// Drawn in flat tint rather than the phase gradient: the system substitutes
/// its own glyphs into a running timer, and a solid colour is the one fill it
/// can't get halfway through. The glow does the lifting instead.
private struct HeadlineClock: View {
    let context: ActivityViewContext<WorkoutActivity>
    let size: CGFloat
    /// Draw the session length as "1:12" rather than "1h 12m", for the compact
    /// pill where those two extra glyphs are the difference.
    var short = false

    var body: some View {
        let phase = context.phase
        Group {
            if context.isRestOver {
                Text("GO")
                    .font(Theme.rounded(size, weight: .heavy))
            } else if context.state.isResting {
                RestClock(state: context.state)
                    .font(Theme.number(size, weight: .bold))
            } else {
                Text(short ? context.state.elapsedShort : context.state.elapsedLabel)
                    .font(Theme.number(size, weight: .bold))
            }
        }
        .foregroundStyle(phase.tint)
        .shadow(color: phase.tint.opacity(0.35), radius: 3.5)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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

    /// Which of the four the card is drawing. Rest wins over a finished set
    /// count: you are still resting even if that was the last set.
    var phase: SessionPhase {
        if isRestOver { return .restOver }
        if state.isResting { return .resting }
        if state.totalSets > 0, state.setsRemaining == 0 { return .done }
        return .working
    }
}
