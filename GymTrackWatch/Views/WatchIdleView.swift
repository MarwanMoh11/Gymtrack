import SwiftUI

/// What the watch shows when nothing is running: today's session, and one tap
/// to start it.
struct WatchIdleView: View {
    var connector: WatchConnector

    private var idle: WatchIdleSnapshot { connector.idle }
    /// Nothing is running, so the screen wears the colour a session would be
    /// started in — except on a rest day, which has earned the calm green.
    private var phase: SessionPhase { idle.todayTitle == nil ? .done : .working }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if connector.hasEverReceivedMirror {
                    todayCard
                    startButtons
                    footer
                } else {
                    waitingForPhone
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("GymTrack")
        .watchScreenTint(phase)
        .onAppear { connector.requestMirror() }
    }

    // MARK: - Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WatchGlyphTile(symbol: idle.todayTitle == nil ? "moon.zzz.fill"
                                                             : "figure.strengthtraining.traditional",
                               tint: phase.tint, size: 24)
                Text(idle.todayTitle == nil ? "REST DAY" : "TODAY")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(phase.tint.opacity(0.9))
                Spacer(minLength: 0)
            }

            Text(idle.todayTitle ?? "Nothing scheduled")
                .font(Theme.rounded(19, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if idle.todayTitle != nil {
                Text("\(idle.todayExerciseCount) exercises · \(idle.todaySetCount) sets")
                    .font(Theme.number(12, weight: .semibold))
                    .foregroundStyle(phase.gradient)
            }

            if !idle.todayMuscles.isEmpty {
                Text(idle.todayMuscles.joined(separator: " · "))
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .watchCard(phase: phase)
    }

    private var startButtons: some View {
        VStack(spacing: 6) {
            Button {
                WatchHaptics.log()
                connector.send(idle.todayTitle == nil ? .startFreestyle : .startToday)
            } label: {
                Label(idle.todayTitle == nil ? "Start freestyle" : "Start workout",
                      systemImage: "figure.strengthtraining.traditional")
            }
            .buttonStyle(WatchProminentButtonStyle(phase: .working))

            if idle.todayTitle != nil {
                Button {
                    WatchHaptics.tick()
                    connector.send(.startFreestyle)
                } label: {
                    Text("Freestyle instead")
                }
                .buttonStyle(WatchQuietButtonStyle(weight: .semibold))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.warning.wash)
                    .shadow(color: Theme.warning.opacity(idle.streak > 0 ? 0.5 : 0), radius: 4)
                Text(idle.streak > 0 ? "\(idle.streak) day streak" : "No streak yet")
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("· \(idle.sessionsThisWeek) this week")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            if let title = idle.lastSessionTitle, let date = idle.lastSessionDate {
                Text("Last: \(title), \(date.formatted(.relative(presentation: .numeric)))")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    // MARK: - Before the first mirror

    private var waitingForPhone: some View {
        VStack(spacing: 9) {
            WatchGlyphTile(symbol: "iphone.gen3.radiowaves.left.and.right",
                           tint: Theme.accent, size: 46)
                .shadow(color: Theme.accent.opacity(0.28), radius: 10)
            Text("Waiting for your phone")
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Open GymTrack on iPhone once and your routine appears here.")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }
}
