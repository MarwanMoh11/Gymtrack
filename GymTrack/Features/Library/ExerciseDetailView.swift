import SwiftUI
import SwiftData
import Charts

/// Everything known about one exercise: what it works, and — the part that
/// matters — how your numbers on it have moved.
struct ExerciseDetailView: View {
    let exercise: CatalogExercise

    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var metric: Metric = .estimatedMax

    enum Metric: String, CaseIterable, Identifiable {
        case estimatedMax = "Est. 1RM"
        case topSet = "Top set"
        case volume = "Volume"
        var id: String { rawValue }
    }

    private var history: [TrainingStats.ExerciseSessionSummary] {
        TrainingStats.history(for: exercise.id, in: sessions)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if history.isEmpty {
                    EmptyStateView(icon: "chart.line.uptrend.xyaxis",
                                   title: "No history yet",
                                   message: "Log this exercise in a workout and your progression shows up here.")
                        .gtCard()
                } else {
                    bestRow
                    chartCard
                    historyList
                }
                if let details = exercise.details, !details.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader("How to do it")
                        Text(details)
                            .font(Theme.rounded(14, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .gtCard()
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .gtScreenBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: exercise.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 50, height: 50)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(Theme.rounded(19, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.equipmentLabel)
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            FlowRow(spacing: 6) {
                ForEach(exercise.muscles, id: \.self) { muscle in
                    Pill(text: muscle.name, color: Theme.accent)
                }
                Pill(text: exercise.tracking.label)
                if let difficulty = exercise.difficulty {
                    Pill(text: difficulty.capitalized)
                }
            }
        }
        .gtCard()
    }

    // MARK: - Bests

    private var bestRow: some View {
        let allSets = history.flatMap(\.sets)
        let heaviest = allSets.map(\.weightKg).max() ?? 0
        let bestE1RM = allSets.map(\.estimatedOneRepMax).max() ?? 0
        let bestReps = allSets.map(\.reps).max() ?? 0

        return HStack(spacing: 10) {
            if exercise.tracking == .duration {
                StatTile(value: "\(allSets.map(\.seconds).max() ?? 0)s", label: "Longest hold")
                StatTile(value: "\(history.count)", label: "Sessions")
            } else {
                StatTile(value: AppSettings.shared.weight(heaviest, showUnit: false),
                         label: "Heaviest \(AppSettings.shared.weightUnit.short)", tint: Theme.accent)
                StatTile(value: AppSettings.shared.weight(bestE1RM, showUnit: false),
                         label: "Est. 1RM")
                StatTile(value: "\(bestReps)", label: "Most reps")
            }
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Progression")
                Spacer()
            }
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart(chartPoints, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(28)
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number.compactVolume)
                                .font(Theme.number(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(Theme.rounded(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 170)
        }
        .gtCard()
    }

    /// Pad around the actual range rather than starting at zero — otherwise a
    /// 10 kg gain over two months looks like a flat line.
    private var yDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.value).filter { $0 > 0 }
        guard let low = values.min(), let high = values.max() else { return 0...10 }
        if high == low { return max(0, low * 0.9)...(high * 1.1 + 1) }
        let padding = (high - low) * 0.25
        return max(0, low - padding)...(high + padding)
    }

    private var chartPoints: [(date: Date, value: Double)] {
        history.reversed().map { entry in
            let value: Double = switch metric {
            case .estimatedMax: entry.bestEstimatedOneRepMax
            case .topSet: entry.topSet?.weightKg ?? 0
            case .volume: entry.volumeKg
            }
            return (entry.date, AppSettings.shared.weightUnit.fromKg(value))
        }
    }

    // MARK: - History

    private var historyList: some View {
        VStack(spacing: 8) {
            SectionHeader("Every session")
            ForEach(history) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.rounded(13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(entry.sets.count) sets · \(AppSettings.shared.weight(entry.volumeKg))")
                            .font(Theme.rounded(11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    FlowRow(spacing: 6) {
                        ForEach(entry.sets) { set in
                            Text(set.tracking == .duration
                                 ? "\(set.seconds)s"
                                 : (set.weightKg == 0 ? "\(set.reps)" : "\(AppSettings.shared.weight(set.weightKg, showUnit: false))×\(set.reps)"))
                                .font(Theme.number(12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.surfaceRaised, in: Capsule())
                        }
                    }
                }
                .gtCard(padding: 12)
            }
        }
    }
}
