import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var window: Window = .month
    @State private var selectedMuscle: Muscle?

    enum Window: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "30 days"
        case quarter = "90 days"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            }
        }
    }

    private var sessions: [WorkoutSession] { allSessions.filter { !$0.isActive } }
    private var windowed: [WorkoutSession] { TrainingStats.sessions(in: sessions, days: window.days) }
    private var lastWeek: [WorkoutSession] { TrainingStats.sessions(in: sessions, days: 7) }
    private var streak: TrainingStats.Streak { TrainingStats.streak(from: sessions) }
    private var muscleVolumes: [Muscle: Double] { TrainingStats.setsPerMuscle(lastWeek) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if sessions.isEmpty {
                    EmptyStateView(icon: "chart.xyaxis.line",
                                   title: "Nothing to chart yet",
                                   message: "Finish your first workout and this screen fills up with streaks, volume and records.")
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 16) {
                        windowPicker
                        headlineStats
                        volumeChart
                        coverageCard
                        consistencyCard
                        recordsCard
                    }
                    .padding(16)
                }
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
            .navigationTitle("Progress")
        }
    }

    // MARK: - Window

    private var windowPicker: some View {
        Picker("Window", selection: $window) {
            ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Headline

    private var headlineStats: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatTile(value: "\(streak.current)", label: "Day streak",
                         caption: "best \(streak.longest)", tint: Theme.accent)
                StatTile(value: "\(windowed.count)", label: "Sessions", caption: window.rawValue)
                StatTile(value: "\(windowed.reduce(0) { $0 + $1.completedSets.count })",
                         label: "Sets logged", caption: window.rawValue)
            }
            HStack(spacing: 10) {
                StatTile(value: TrainingStats.totalVolume(windowed).compactVolume,
                         label: "Volume \(AppSettings.shared.weightUnit.short)", caption: window.rawValue)
                StatTile(value: averageDuration, label: "Avg session")
                StatTile(value: "\(windowed.reduce(0) { $0 + $1.totalReps })", label: "Total reps")
            }
        }
    }

    private var averageDuration: String {
        guard !windowed.isEmpty else { return "—" }
        let total = windowed.reduce(0.0) { $0 + $1.duration }
        return (total / Double(windowed.count)).durationString
    }

    // MARK: - Volume chart

    private var volumeChart: some View {
        let points = TrainingStats.dailyVolume(sessions, days: window.days)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Volume per day")
            Chart(points, id: \.date) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Volume", AppSettings.shared.weightUnit.fromKg(point.volume))
                )
                .foregroundStyle(point.volume > 0 ? Theme.accent : Color.white.opacity(0.06))
                .cornerRadius(3)
            }
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
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(Theme.rounded(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 150)
        }
        .gtCard()
    }

    // MARK: - Muscle coverage

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Muscle coverage · last 7 days")

            BodyMapView(volumes: muscleVolumes, selected: selectedMuscle) { muscle in
                selectedMuscle = selectedMuscle == muscle ? nil : muscle
            }
            .frame(height: 240)

            legend

            if let muscle = selectedMuscle {
                muscleDetail(muscle)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Tap a muscle to see how its week is going.")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            if !underworked.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FALLING BEHIND")
                        .font(Theme.eyebrow).tracking(1.2)
                        .foregroundStyle(Theme.warning)
                    FlowRow(spacing: 6) {
                        ForEach(underworked, id: \.self) { muscle in
                            Pill(text: muscle.name, color: Theme.warning)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .gtCard()
        .animation(.easeInOut(duration: 0.2), value: selectedMuscle)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach([("None", Color.white.opacity(0.10)),
                     ("Light", Theme.accent.opacity(0.30)),
                     ("Solid", Theme.accent.opacity(0.55)),
                     ("On target", Theme.accent)], id: \.0) { label, color in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
                    Text(label)
                        .font(Theme.rounded(10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    /// Muscles under half their weekly set target.
    private var underworked: [Muscle] {
        Muscle.allCases
            .filter { (muscleVolumes[$0] ?? 0) < Double($0.weeklySetTarget) * 0.5 }
            .sorted { ($0.weeklySetTarget) > ($1.weeklySetTarget) }
            .prefix(5)
            .map { $0 }
    }

    private func muscleDetail(_ muscle: Muscle) -> some View {
        let sets = muscleVolumes[muscle] ?? 0
        let target = Double(muscle.weeklySetTarget)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(muscle.name)
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(String(format: "%.0f", sets)) / \(muscle.weeklySetTarget) sets")
                    .font(Theme.number(13, weight: .semibold))
                    .foregroundStyle(sets >= target ? Theme.accent : Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(sets >= target ? Theme.accent : Theme.accent.opacity(0.6))
                        .frame(width: geo.size.width * min(1, sets / target))
                }
            }
            .frame(height: 7)
            Text(sets >= target
                 ? "On target for the week."
                 : "\(Int((target - sets).rounded())) more hard sets to hit the weekly target.")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Consistency calendar

    private var consistencyCard: some View {
        let calendar = Calendar.current
        let trained = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        let weeks = 16
        let today = calendar.startOfDay(for: .now)
        // Start on the Sunday that begins the first visible week.
        let startOffset = calendar.component(.weekday, from: today) - 1
        let lastColumnStart = calendar.date(byAdding: .day, value: -startOffset, to: today)!
        let firstDay = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: lastColumnStart)!

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Consistency · last \(weeks) weeks")
            HStack(spacing: 4) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstDay)!
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(cellColor(date: date, today: today, trained: trained))
                                .frame(height: 12)
                        }
                    }
                }
            }
            HStack {
                Text(firstDay.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                Text("Today")
            }
            .font(Theme.rounded(10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .gtCard()
    }

    private func cellColor(date: Date, today: Date, trained: Set<Date>) -> Color {
        if date > today { return Color.white.opacity(0.02) }
        if trained.contains(date) { return Theme.accent }
        return Color.white.opacity(0.07)
    }

    // MARK: - Records

    private var recordsCard: some View {
        let records = TrainingStats.records(in: sessions).prefix(8)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Personal records")
            ForEach(Array(records)) { record in
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentDim, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.exerciseName)
                            .font(Theme.rounded(14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.rounded(11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(AppSettings.shared.weight(record.heaviestKg)) × \(record.bestReps)")
                            .font(Theme.number(13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("1RM ≈ \(AppSettings.shared.weight(record.bestEstimatedOneRepMax))")
                            .font(Theme.rounded(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .gtCard()
    }
}
