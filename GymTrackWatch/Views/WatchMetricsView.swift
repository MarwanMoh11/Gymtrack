import SwiftUI

/// What the session is costing you: heart rate, energy, time, and the volume
/// moved so far. The numbers the watch can measure and the phone can't.
struct WatchMetricsView: View {
    let session: WatchSessionSnapshot
    var recorder: WatchWorkoutRecorder

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TimelineView(.periodic(from: session.startedAt, by: 1)) { _ in
                    elapsedRow
                }

                if recorder.isRunning {
                    heartRateRow
                    energyRow
                } else {
                    notRecording
                }

                volumeRow
                setsRow
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Session")
    }

    private var elapsedRow: some View {
        metric(
            value: Date().timeIntervalSince(session.startedAt).clockString,
            label: "Elapsed",
            symbol: "stopwatch",
            tint: Theme.accent
        )
    }

    private var heartRateRow: some View {
        metric(
            value: recorder.heartRate.map { "\(Int($0.rounded()))" } ?? "—",
            label: recorder.averageHeartRate.map { "BPM · avg \(Int($0.rounded()))" } ?? "BPM",
            symbol: "heart.fill",
            tint: Theme.negative
        )
    }

    private var energyRow: some View {
        metric(
            value: recorder.activeEnergyKcal.map { "\(Int($0.rounded()))" } ?? "—",
            label: "Active kcal",
            symbol: "flame.fill",
            tint: Theme.warning
        )
    }

    private var volumeRow: some View {
        metric(
            value: session.unit.fromKg(session.volumeKg).compactVolume,
            label: "Volume \(session.unit.short)",
            symbol: "scalemass.fill",
            tint: Theme.textPrimary
        )
    }

    private var setsRow: some View {
        metric(
            value: "\(session.completedSets)/\(session.totalSets)",
            label: "Sets logged",
            symbol: "checklist",
            tint: Theme.textPrimary
        )
    }

    private var notRecording: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.slash")
                .font(.system(size: 18))
                .foregroundStyle(Theme.textTertiary)
            Text("Not recording")
                .font(Theme.rounded(13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(recorder.authorizationDenied
                 ? "Allow GymTrack to write workouts in Health to record heart rate."
                 : "Heart rate starts when the workout session does.")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(value: String, label: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(Theme.number(20))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label.uppercased())
                    .font(Theme.eyebrow)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
