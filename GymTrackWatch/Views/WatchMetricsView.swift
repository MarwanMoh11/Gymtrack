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
        .watchScreenTint(.working)
    }

    private var elapsedRow: some View {
        metric(
            value: Date().timeIntervalSince(session.startedAt).clockString,
            label: "Elapsed",
            symbol: "stopwatch",
            tint: Theme.accent,
            tintsValue: true
        )
    }

    private var heartRateRow: some View {
        metric(
            value: recorder.heartRate.map { "\(Int($0.rounded()))" } ?? "—",
            label: recorder.averageHeartRate.map { "BPM · avg \(Int($0.rounded()))" } ?? "BPM",
            symbol: "heart.fill",
            tint: Theme.negative,
            tintsValue: true
        )
    }

    private var energyRow: some View {
        metric(
            value: recorder.activeEnergyKcal.map { "\(Int($0.rounded()))" } ?? "—",
            label: "Active kcal",
            symbol: "flame.fill",
            tint: Theme.warning,
            tintsValue: true
        )
    }

    private var volumeRow: some View {
        metric(
            value: session.unit.fromKg(session.volumeKg).compactVolume,
            label: "Volume \(session.unit.short)",
            symbol: "scalemass.fill",
            tint: Theme.accent
        )
    }

    private var setsRow: some View {
        metric(
            value: "\(session.completedSets)/\(session.totalSets)",
            label: "Sets logged",
            symbol: "checklist",
            tint: Theme.accent
        )
    }

    private var notRecording: some View {
        VStack(spacing: 6) {
            WatchGlyphTile(symbol: "heart.slash", tint: Theme.textSecondary, size: 32)
            Text("Not recording")
                .font(Theme.rounded(13, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(recorder.authorizationDenied
                 ? "Allow GymTrack to write workouts in Health to record heart rate."
                 : "Heart rate starts when the workout session does.")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .watchCard()
    }

    /// One row: a tinted tile, the number, and what it is.
    ///
    /// Only the three the watch measures for itself carry their colour into the
    /// number — heart, energy, elapsed. The two mirrored from the phone stay in
    /// white, so a glance tells you which device is doing the counting.
    private func metric(value: String, label: String, symbol: String,
                        tint: Color, tintsValue: Bool = false) -> some View {
        HStack(spacing: 9) {
            WatchGlyphTile(symbol: symbol, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(Theme.number(20))
                    .foregroundStyle(tintsValue ? AnyShapeStyle(tint.wash) : AnyShapeStyle(Theme.ink))
                    .shadow(color: tintsValue ? tint.opacity(0.35) : .clear, radius: 5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label.uppercased())
                    .font(Theme.eyebrow)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .watchCard(padding: 9, radius: 12)
    }
}
