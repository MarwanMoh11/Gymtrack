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

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                progressCard
                restControls
                addSetButton

                Button(action: onEnd) {
                    Label("Finish workout", systemImage: "flag.checkered")
                        .font(Theme.rounded(14, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)

                Button(role: .destructive) {
                    confirmingDiscard = true
                } label: {
                    Label("Discard", systemImage: "trash")
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(Theme.negative)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                // The app's accent is applied at the root, and it swallows the
                // destructive role — a discard button the colour of every
                // other button is a discard button someone taps by mistake.
                .tint(Theme.negative)

                syncFooter
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Controls")
        .alert("Discard this workout?", isPresented: $confirmingDiscard) {
            Button("Keep it", role: .cancel) {}
            Button("Discard", role: .destructive, action: onDiscard)
        } message: {
            Text("Every set logged in this session is deleted.")
        }
    }

    private var progressCard: some View {
        VStack(spacing: 4) {
            Text("\(session.completedSets) of \(session.totalSets)")
                .font(Theme.number(22))
                .foregroundStyle(Theme.textPrimary)
            Text("sets logged")
                .font(Theme.eyebrow)
                .foregroundStyle(Theme.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(2, geo.size.width * session.progress))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .font(Theme.rounded(13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.surfaceRaised)

                Button {
                    rest.stop()
                    connector.send(.stopRest)
                } label: {
                    Text("Skip rest")
                        .font(Theme.rounded(13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.surfaceRaised)
            }
        } else {
            Button {
                let seconds = session.currentExercise?.restSeconds ?? 90
                rest.startLocal(seconds: seconds)
                connector.send(.startRest(seconds: seconds))
            } label: {
                Label("Start rest", systemImage: "timer")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.surfaceRaised)
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
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.surfaceRaised)
        }
    }

    /// Says plainly whether the phone has everything — the one thing a mirror
    /// UI owes the user when it's been out of range.
    private var syncFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: connector.hasUnsyncedWork ? "arrow.triangle.2.circlepath" : "checkmark.icloud")
                .font(.system(size: 10))
            Text(connector.hasUnsyncedWork
                 ? "Sets waiting for your phone"
                 : (connector.isReachable ? "In sync with your phone" : "Will sync when in range"))
                .font(Theme.rounded(10, weight: .medium))
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(.top, 2)
    }
}
