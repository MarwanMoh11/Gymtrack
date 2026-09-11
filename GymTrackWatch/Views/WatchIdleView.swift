import SwiftUI

/// What the watch shows when nothing is running: today's session, and one tap
/// to start it.
struct WatchIdleView: View {
    var connector: WatchConnector

    private var idle: WatchIdleSnapshot { connector.idle }

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
        .containerBackground(Theme.accent.gradient.opacity(0.25), for: .navigation)
        .onAppear { connector.requestMirror() }
    }

    // MARK: - Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(idle.todayTitle == nil ? "Rest day" : "Today")
                .font(Theme.eyebrow)
                .foregroundStyle(Theme.textTertiary)

            Text(idle.todayTitle ?? "Nothing scheduled")
                .font(Theme.rounded(19, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if idle.todayTitle != nil {
                Text("\(idle.todayExerciseCount) exercises · \(idle.todaySetCount) sets")
                    .font(Theme.number(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            if !idle.todayMuscles.isEmpty {
                Text(idle.todayMuscles.joined(separator: " · "))
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var startButtons: some View {
        VStack(spacing: 6) {
            Button {
                WatchHaptics.log()
                connector.send(idle.todayTitle == nil ? .startFreestyle : .startToday)
            } label: {
                Label(idle.todayTitle == nil ? "Start freestyle" : "Start workout",
                      systemImage: "figure.strengthtraining.traditional")
                    .font(Theme.rounded(15, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(.black)

            if idle.todayTitle != nil {
                Button {
                    WatchHaptics.tick()
                    connector.send(.startFreestyle)
                } label: {
                    Text("Freestyle instead")
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.surfaceRaised)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text(idle.streak > 0 ? "\(idle.streak) day streak" : "No streak yet")
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("· \(idle.sessionsThisWeek) this week")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let title = idle.lastSessionTitle, let date = idle.lastSessionDate {
                Text("Last: \(title), \(date.formatted(.relative(presentation: .numeric)))")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Before the first mirror

    private var waitingForPhone: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 26))
                .foregroundStyle(Theme.accent)
            Text("Waiting for your phone")
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Open GymTrack on iPhone once and your routine appears here.")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }
}
