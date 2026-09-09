import SwiftUI

/// The bar that sits above the tab bar while a session is minimised.
///
/// A workout that's been minimised has to stay *visible* — the whole reason
/// people used to discard one instead of backgrounding it is that once it left
/// the screen there was no sign it still existed. This is that sign: it shows
/// the same three things the Live Activity does, and tapping anywhere on it
/// puts the logger back.
struct SessionDockBar: View {
    @Bindable var workout: ActiveWorkout

    let onResume: () -> Void
    let onFinish: () -> Void
    let onDiscard: () -> Void

    @State private var isPulsing = false

    private var isResting: Bool { workout.restTimer.isRunning }

    var body: some View {
        Button(action: onResume) {
            VStack(spacing: 0) {
                progressLine
                bar
            }
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isResting ? Theme.accent.opacity(0.45) : Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 14, y: 5)
        }
        .buttonStyle(DockPressStyle())
        .contextMenu {
            Button { onResume() } label: { Label("Resume workout", systemImage: "arrow.up.forward.app") }
            Button { onFinish() } label: { Label("Finish workout", systemImage: "checkmark.circle") }
            Button(role: .destructive) { onDiscard() } label: {
                Label("Discard workout", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workout.session.title), workout in progress")
        .accessibilityValue(statusText)
        .accessibilityHint("Double tap to go back to logging")
        .onAppear { isPulsing = true }
    }

    // MARK: - Pieces

    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * workout.progress)
                    .animation(.spring(response: 0.45, dampingFraction: 0.9), value: workout.progress)
            }
        }
        .frame(height: 3)
    }

    private var bar: some View {
        HStack(spacing: 11) {
            ring

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing ? 0.35 : 1)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isPulsing)
                    Text(workout.session.title)
                        .font(Theme.rounded(14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Text(statusText)
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(isResting ? Theme.accent : Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            headlineClock

            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// Rest remaining while resting, sets completed otherwise — the ring always
    /// answers whatever the current question is.
    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.02, isResting ? 1 - workout.restTimer.progress : workout.progress))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: isResting ? "hourglass" : "dumbbell.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var headlineClock: some View {
        if isResting {
            Text(workout.restTimer.remaining.clockString)
                .font(Theme.number(17))
                .foregroundStyle(Theme.accent)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(workout.session.duration.clockString)
                    .font(Theme.number(17))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var statusText: String {
        if isResting {
            let next = workout.currentGroup?.name ?? "next set"
            return "Resting · then \(next)"
        }
        if workout.completedCount >= workout.totalCount && workout.totalCount > 0 {
            return "All \(workout.totalCount) sets logged — tap to finish"
        }
        guard let group = workout.currentGroup else { return "Tap to log a set" }
        return "\(group.name) · set \(workout.nextSetNumber) of \(group.sets.count)"
    }
}

private struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Attaching it to a tab

extension View {
    /// Docks the minimised session above the tab bar of whichever tab is open,
    /// insetting the content so nothing hides behind it.
    func sessionDock(
        _ workout: ActiveWorkout?,
        isExpanded: Bool,
        onResume: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let workout, !isExpanded {
                SessionDockBar(
                    workout: workout,
                    onResume: onResume,
                    onFinish: onFinish,
                    onDiscard: onDiscard
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
