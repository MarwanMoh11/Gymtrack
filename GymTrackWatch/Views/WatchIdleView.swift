import SwiftUI

/// What the watch shows when nothing is running: today's session, and one tap
/// to start it.
struct WatchIdleView: View {
    var connector: WatchConnector

    /// A start has been asked for and the session hasn't arrived yet.
    @State private var isStarting = false

    private var idle: WatchIdleSnapshot { connector.idle }

    /// Whether the mirror still describes the day it is being read on.
    ///
    /// The phone restamps it when something wakes it, and nothing wakes it at
    /// midnight. So a wrist raised the morning after a session is routinely
    /// holding yesterday's answer — and since every line below says "today",
    /// the watch was presenting yesterday's training day as today's. On a rest
    /// day that is the app inventing a workout, which is the one thing it is
    /// not allowed to do. It asks for a fresh mirror on the way in; until one
    /// lands it says plainly that it doesn't know yet.
    private var isStale: Bool { !idle.describesToday }

    /// Nothing is running, so the screen wears the colour a session would be
    /// started in — except on a rest day, which has earned the calm green. A
    /// mirror that has gone out of date can't claim either, and a green screen
    /// is a claim that today is a rest day.
    private var phase: SessionPhase { idle.todayTitle == nil && !isStale ? .done : .working }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if connector.hasEverReceivedMirror {
                    if isStale { stalePlanCard } else { todayCard }
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

    /// A card for a mirror the watch can no longer read as "today".
    ///
    /// It names the day the plan it holds belongs to rather than showing a
    /// spinner: "waiting" with nothing behind it reads as something that has
    /// hung, and the lifter can't tell whether to keep looking at their wrist
    /// or go and get their phone.
    private var stalePlanCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WatchGlyphTile(symbol: "arrow.clockwise", tint: phase.tint, size: 24)
                Text("NOT TODAY YET")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(phase.tint.opacity(0.9))
                Spacer(minLength: 0)
            }

            Text("Waiting for today")
                .font(Theme.rounded(19, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(staleDetail)
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(4)
        }
        .watchCard(phase: phase)
    }

    private var staleDetail: String {
        guard let day = idle.day else { return "Your phone hasn't sent today's plan yet." }
        let weekday = day.formatted(.dateTime.weekday(.wide))
        return "The last plan your phone sent was \(weekday)'s. Start anyway and your phone picks today's."
    }

    /// Whether the start button is offering a freestyle session rather than a
    /// prescribed one.
    ///
    /// `.startToday` is right whenever there might be something scheduled — the
    /// phone resolves it against the real today and falls back to freestyle
    /// when there is nothing — so it is also the right thing to send while the
    /// watch doesn't yet know what today is.
    private var startsFreestyle: Bool { idle.todayTitle == nil && !isStale }

    private var startButtons: some View {
        VStack(spacing: 6) {
            Button {
                WatchHaptics.log()
                start(startsFreestyle ? .startFreestyle : .startToday)
            } label: {
                if isStarting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.black)
                            .frame(width: 16, height: 16)
                        Text("Starting")
                    }
                } else {
                    Label(startsFreestyle ? "Start freestyle" : "Start workout",
                          systemImage: "figure.strengthtraining.traditional")
                }
            }
            .buttonStyle(WatchProminentButtonStyle(phase: .working))
            .disabled(isStarting)

            if isStarting {
                Text(connector.isReachable
                     ? "Your phone is building the session."
                     : "Your phone is out of reach. It starts the session as soon as it's back.")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else if !startsFreestyle {
                Button {
                    WatchHaptics.tick()
                    start(.startFreestyle)
                } label: {
                    Text("Freestyle instead")
                }
                .buttonStyle(WatchQuietButtonStyle(weight: .semibold))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isStarting)
        // Long enough for a phone in range to answer, short enough that a
        // command lost on the way doesn't leave the button locked; the queue
        // makes a second press harmless either way, because the phone never
        // starts a session while one is running.
        .task(id: isStarting) {
            guard isStarting else { return }
            try? await Task.sleep(for: .seconds(8))
            isStarting = false
        }
    }

    /// Asks the phone for a session and says so until one arrives.
    ///
    /// The watch can't build a session itself — the plan, the progression and
    /// the store are all on the phone — so the tap is answered by a mirror a
    /// moment later, or, with the phone out of range, by nothing at all. The
    /// button used to sit there unchanged either way, which reads as a tap that
    /// didn't register and invites a second one.
    private func start(_ command: WatchCommand) {
        isStarting = true
        connector.send(command)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The streak was counted on the day this mirror was built and can
            // have broken since, which is a number that would be wrong rather
            // than merely old. The last session's date is relative to now and
            // stays true however stale the rest of this is, so it stays.
            if !isStale {
                streakRow
            }

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

    private var streakRow: some View {
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
