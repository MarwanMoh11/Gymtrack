import SwiftUI

/// The things you do to the session rather than in it — rest, and the two ways
/// out. Kept on its own page so neither can be hit while logging.
struct WatchControlsView: View {
    let session: WatchSessionSnapshot
    var connector: WatchConnector
    var rest: WatchRestTimer
    let onEnd: () -> Void
    let onDiscard: () -> Void

    @State private var confirmingDiscard = false

    private var phase: SessionPhase { session.phase(resting: rest.isRunning) }

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                progressCard
                restControls
                addSetButton

                Button(action: onEnd) {
                    Label("Finish workout", systemImage: "flag.checkered")
                }
                // Green rather than the session's colour: finishing is the one
                // button here that ends well, and it should look like it.
                .buttonStyle(WatchProminentButtonStyle(phase: .done))

                Button(role: .destructive) {
                    confirmingDiscard = true
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                // Carried in red on purpose. The app's accent is applied at the
                // root and swallows the destructive role — a discard button the
                // colour of every other button is one someone taps by mistake.
                .buttonStyle(WatchQuietButtonStyle(tint: Theme.negative, weight: .semibold))

                syncFooter
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Controls")
        .watchScreenTint(phase)
        .alert("Discard this workout?", isPresented: $confirmingDiscard) {
            Button("Keep it", role: .cancel) {}
            Button("Discard", role: .destructive, action: onDiscard)
        } message: {
            Text("Every set logged in this session is deleted.")
        }
    }

    private var progressCard: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(session.completedSets)")
                    .font(Theme.number(24))
                    .foregroundStyle(phase.gradient)
                    .shadow(color: phase.glow, radius: 6)
                Text("of \(session.totalSets)")
                    .font(Theme.number(15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("SETS LOGGED")
                .font(Theme.eyebrow)
                .tracking(1.1)
                .foregroundStyle(Theme.textTertiary)

            // Twelve ticks is about all a 41mm screen can show before they
            // stop reading as sets, so anything longer runs as one bar.
            PhaseProgressBar(completed: session.completedSets, total: session.totalSets,
                             phase: phase, height: 5, maxTicks: 12)
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
        .watchCard(phase: phase)
    }

    @ViewBuilder
    private var restControls: some View {
        if rest.isRunning {
            HStack(spacing: 6) {
                Button {
                    rest.add(seconds: 30)
                    connector.send(.extendRest(seconds: 30))
                } label: {
                    Text("+30s")
                }
                .buttonStyle(WatchQuietButtonStyle(tint: SessionPhase.resting.tint))

                Button {
                    rest.stop()
                    connector.send(.stopRest)
                } label: {
                    Text("Skip rest")
                }
                .buttonStyle(WatchQuietButtonStyle())
            }
        } else {
            Button {
                let seconds = session.currentExercise?.restSeconds ?? 90
                rest.startLocal(seconds: seconds)
                connector.send(.startRest(seconds: seconds))
            } label: {
                Label("Start rest", systemImage: "timer")
            }
            .buttonStyle(WatchQuietButtonStyle(tint: SessionPhase.resting.tint, weight: .semibold))
        }
    }

    @ViewBuilder
    private var addSetButton: some View {
        if let exercise = session.currentExercise {
            Button {
                WatchHaptics.tick()
                connector.send(.addSet(catalogID: exercise.id))
            } label: {
                Label("Add a set", systemImage: "plus")
            }
            .buttonStyle(WatchQuietButtonStyle(weight: .semibold))
        }
    }

    /// Says plainly whether the phone has everything — the one thing a mirror
    /// UI owes the user when it's been out of range.
    private var syncFooter: some View {
        WatchChip(tint: connector.hasUnsyncedWork ? Theme.warning : Theme.textTertiary) {
            Image(systemName: connector.hasUnsyncedWork ? "arrow.triangle.2.circlepath" : "checkmark.icloud")
                .font(.system(size: 9, weight: .bold))
            Text(connector.hasUnsyncedWork
                 ? "Sets waiting for your phone"
                 : (connector.isReachable ? "In sync with your phone" : "Will sync when in range"))
                .font(Theme.rounded(10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.top, 2)
    }
}
