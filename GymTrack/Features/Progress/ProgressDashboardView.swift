import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    @State private var window: Window = .month
    @State private var metric: TrainingStats.Metric = .volume
    @State private var selectedMuscle: Muscle?
    @State private var bodySide: BodySide = .front
    @State private var selectedDay: Date?
    @State private var barsGrown = false

    private let calendarWeeks = 17

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

    // MARK: - Derived data

    private var sessions: [WorkoutSession] { allSessions.filter { !$0.isActive } }
    private var windowed: [WorkoutSession] { TrainingStats.sessions(in: sessions, days: window.days) }
    private var previous: [WorkoutSession] { TrainingStats.previousWindow(sessions, days: window.days) }
    private var lastWeek: [WorkoutSession] { TrainingStats.sessions(in: sessions, days: 7) }
    private var streak: TrainingStats.Streak { TrainingStats.streak(from: sessions) }

    private var muscleSets: [Muscle: Double] { TrainingStats.setsPerMuscle(lastWeek) }
    private var ratios: [Muscle: Double] { TrainingStats.muscleRatios(lastWeek) }
    private var coverage: Double { TrainingStats.coverage(ratios) }

    private var points: [TrainingStats.DayPoint] {
        TrainingStats.daily(metric, sessions: sessions, days: window.days)
    }

    private var rolling: [TrainingStats.DayPoint] {
        TrainingStats.rollingAverage(points, window: window == .week ? 3 : 7)
    }

    private var volumeByDay: [Date: Double] {
        Dictionary(uniqueKeysWithValues:
            TrainingStats.daily(.volume, sessions: sessions, days: calendarWeeks * 7)
                .map { ($0.date, $0.value) })
    }

    /// Weekly totals, oldest first — the shape behind each headline number.
    private func weeklyTrend(_ metric: TrainingStats.Metric, weeks: Int = 8) -> [Double] {
        let daily = TrainingStats.daily(metric, sessions: sessions, days: weeks * 7)
        return stride(from: 0, to: daily.count, by: 7).map { start in
            daily[start..<min(start + 7, daily.count)].reduce(0) { $0 + $1.value }
        }
    }

    /// Sessions per week, oldest first.
    private func weeklySessionCounts(weeks: Int = 8) -> [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<weeks).reversed().map { offset in
            guard let end = calendar.date(byAdding: .day, value: -7 * offset, to: today),
                  let start = calendar.date(byAdding: .day, value: -7, to: end)
            else { return 0 }
            return Double(sessions.filter { $0.startedAt > start && $0.startedAt <= end }.count)
        }
    }

    private func delta(_ metric: TrainingStats.Metric) -> Double? {
        TrainingStats.change(from: TrainingStats.total(metric, previous),
                             to: TrainingStats.total(metric, windowed))
    }

    // MARK: - Body

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
                        heroCard.riseIn(0)
                        SegmentedPills(values: Window.allCases, selection: $window) { $0.rawValue }
                            .riseIn(1)
                        statGrid.riseIn(2)
                        trendCard.riseIn(3)
                        heatMapCard.riseIn(4)
                        balanceCard.riseIn(5)
                        consistencyCard.riseIn(6)
                        recordsCard.riseIn(7)
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
            }
            .scrollIndicators(.hidden)
            .background {
                ZStack {
                    Theme.background
                    // A wash of the week's own heat behind the whole screen.
                    RadialGradient(colors: [MuscleHeat.color(max(coverage, 0.3)).opacity(0.16), .clear],
                                   center: .top, startRadius: 0, endRadius: 460)
                        .blur(radius: 40)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Progress")
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.35)) { barsGrown = true }
        }
    }

    // MARK: - Hero

    /// The week at a glance: how much of the plan is actually covered, and the
    /// two numbers that decide whether the streak survives.
    private var heroCard: some View {
        HStack(spacing: 18) {
            CoverageRing(progress: coverage, size: 104)

            VStack(alignment: .leading, spacing: 10) {
                Text("THIS WEEK")
                    .font(Theme.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Theme.textTertiary)

                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(streak.current > 0 ? Theme.accent : Theme.textTertiary)
                    Text("\(streak.current) day streak")
                        .font(Theme.rounded(16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(lastWeek.count) session\(lastWeek.count == 1 ? "" : "s") · \(TrainingStats.totalVolume(lastWeek).compactVolume) \(AppSettings.shared.weightUnit.short)")
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(headline)
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(behind.isEmpty ? Theme.accent : Theme.warning)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gtCard()
    }

    private var headline: String {
        guard !behind.isEmpty else { return "Every muscle group is on schedule." }
        let names = behind.prefix(2).map(\.name)
        if behind.count > 2 {
            return "\(names.joined(separator: ", ")) and \(behind.count - 2) more need work."
        }
        return "\(names.joined(separator: " and ")) need\(behind.count == 1 ? "s" : "") work."
    }

    /// Muscles under half their weekly target, biggest target first.
    private var behind: [Muscle] {
        Muscle.allCases
            .filter { (ratios[$0] ?? 0) < 0.5 }
            .sorted { lhs, rhs in
                lhs.weeklySetTarget == rhs.weeklySetTarget
                    ? (ratios[lhs] ?? 0) < (ratios[rhs] ?? 0)
                    : lhs.weeklySetTarget > rhs.weeklySetTarget
            }
    }

    // MARK: - Headline numbers

    private var statGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(value: Double(windowed.count), label: "Sessions",
                           change: TrainingStats.change(from: Double(previous.count),
                                                        to: Double(windowed.count)),
                           trend: weeklySessionCounts())
                MetricTile(value: TrainingStats.total(.volume, windowed),
                           label: "Volume \(AppSettings.shared.weightUnit.short)",
                           change: delta(.volume),
                           trend: weeklyTrend(.volume),
                           format: { $0.compactVolume })
            }
            HStack(spacing: 10) {
                MetricTile(value: TrainingStats.total(.sets, windowed), label: "Hard sets",
                           change: delta(.sets),
                           trend: weeklyTrend(.sets))
                MetricTile(value: TrainingStats.total(.reps, windowed), label: "Reps",
                           change: delta(.reps),
                           trend: weeklyTrend(.reps))
            }
            HStack(spacing: 10) {
                MetricTile(value: averageDuration, label: "Avg session",
                           caption: window.rawValue,
                           format: { $0.durationString })
                MetricTile(value: Double(streak.longest), label: "Best streak",
                           caption: "\(streak.current) day\(streak.current == 1 ? "" : "s") running")
            }
        }
    }

    private var averageDuration: Double {
        guard !windowed.isEmpty else { return 0 }
        return windowed.reduce(0.0) { $0 + $1.duration } / Double(windowed.count)
    }

    // MARK: - Trend chart

    private var trendCard: some View {
        TrendCard(metric: $metric,
                  points: points,
                  rolling: rolling,
                  total: TrainingStats.total(metric, windowed),
                  change: delta(metric),
                  windowLabel: window.rawValue,
                  rollingWindow: window == .week ? 3 : 7)
    }

    // MARK: - Heat map

    private var heatMapCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MUSCLE HEAT MAP · 7 DAYS")
                        .font(Theme.eyebrow)
                        .tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                    Text("Hard sets vs weekly target")
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                }
                Spacer()
                BodySideSwitch(side: $bodySide)
            }

            MuscleHeatMapView(ratios: ratios, side: $bodySide, selected: $selectedMuscle, height: 340)

            HeatLegend()

            Group {
                if let muscle = selectedMuscle {
                    MuscleDetailPanel(muscle: muscle,
                                      sets: muscleSets[muscle] ?? 0,
                                      lastTrained: TrainingStats.lastTrained(muscle, in: sessions),
                                      exercises: TrainingStats.topExercises(for: muscle, in: lastWeek))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                            removal: .opacity))
                } else {
                    hint
                }
            }
        }
        .gtCard()
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: selectedMuscle)
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap a muscle for its week. Flip the figure for the posterior chain.")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            if !behind.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FALLING BEHIND")
                        .font(Theme.eyebrow).tracking(1.2)
                        .foregroundStyle(Theme.warning)
                    FlowRow(spacing: 6) {
                        ForEach(behind.prefix(6), id: \.self) { muscle in
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    bodySide = muscle.isAnterior ? .front : .back
                                    selectedMuscle = muscle
                                }
                                Haptics.tick()
                            } label: {
                                Pill(text: muscle.name, color: Theme.warning)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Weekly balance")
            ForEach(Muscle.Region.allCases) { region in
                RegionBalanceRow(region: region,
                                 coverage: TrainingStats.coverage(of: region, ratios: ratios),
                                 animate: barsGrown)
            }
            Text(balanceCaption)
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
        }
        .gtCard()
    }

    private var balanceCaption: String {
        let scored = Muscle.Region.allCases
            .map { ($0, TrainingStats.coverage(of: $0, ratios: ratios)) }
            .sorted { $0.1 < $1.1 }
        guard let weakest = scored.first, let strongest = scored.last else { return "" }
        if weakest.1 >= 0.85 { return "Nothing is lagging — the whole body is on target this week." }
        return "\(strongest.0.rawValue) is leading, \(weakest.0.rawValue) is the gap to close."
    }

    // MARK: - Consistency

    private var consistencyCard: some View {
        let trainedDays = volumeByDay.filter { $0.value > 0 }.count

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Consistency · last \(calendarWeeks) weeks")

            ScrollView(.horizontal, showsIndicators: false) {
                ConsistencyGrid(volumeByDay: volumeByDay, weeks: calendarWeeks, selectedDay: $selectedDay)
                    .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .defaultScrollAnchor(.trailing)

            if let day = selectedDay {
                let volume = volumeByDay[day] ?? 0
                HStack(spacing: 6) {
                    Circle()
                        .fill(volume > 0 ? Theme.accent : Theme.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(volume > 0
                         ? "\(volume.compactVolume) \(AppSettings.shared.weightUnit.short)"
                         : "Rest")
                        .font(Theme.number(12, weight: .bold))
                        .foregroundStyle(volume > 0 ? Theme.accent : Theme.textTertiary)
                }
                .transition(.opacity)
            } else {
                HStack {
                    Text("\(trainedDays) days trained")
                    Spacer()
                    Text("\(Int((Double(trainedDays) / Double(calendarWeeks * 7) * 100).rounded()))% of days")
                }
                .font(Theme.rounded(11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .gtCard()
        .animation(.easeInOut(duration: 0.2), value: selectedDay)
    }

    // MARK: - Records

    private var recordsCard: some View {
        let records = Array(TrainingStats.records(in: sessions).prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Personal records")
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(index < 3 ? Theme.accentDim : Color.white.opacity(0.05))
                        if index < 3 {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accent)
                        } else {
                            Text("\(index + 1)")
                                .font(Theme.number(11, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(width: 28, height: 28)

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

// MARK: - Trend chart

/// Daily totals for the chosen window, with a rolling average over the top and
/// a day the user can pin.
///
/// This is its own view so that scrubbing — which changes state on every touch
/// move — only re-renders the chart, instead of making the whole screen
/// recompute every statistic it shows.
private struct TrendCard: View {
    @Binding var metric: TrainingStats.Metric
    let points: [TrainingStats.DayPoint]
    let rolling: [TrainingStats.DayPoint]
    let total: Double
    let change: Double?
    let windowLabel: String
    let rollingWindow: Int

    @State private var scrubbed: Date?
    @State private var scrubbedBefore: Date?
    @State private var isScrubbing = false

    private var peak: Double { max(points.map(\.value).max() ?? 1, 0.0001) }
    private var selection: TrainingStats.DayPoint? { scrubbed.flatMap(nearestPoint(to:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            SegmentedPills(values: TrainingStats.Metric.allCases, selection: $metric,
                           title: { $0.rawValue }, namespaceID: "metric")
            chart
            Text("Dashed line is the \(rollingWindow)-day rolling average. Touch the chart to read a day.")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .gtCard()
        .onChange(of: metric) { _, _ in scrubbed = nil }
        .onChange(of: windowLabel) { _, _ in scrubbed = nil }
    }

    // The readout doubles as the callout: scrubbing a day replaces the window
    // total here rather than floating a label over the picker.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selection.map {
                $0.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
            } ?? metric.rawValue.uppercased() + " · " + windowLabel.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(selection == nil ? Theme.textTertiary : Theme.accent)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.format(selection?.value ?? total))
                    .font(Theme.number(24))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(metric.unit)
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                if selection == nil {
                    DeltaBadge(change: change)
                } else {
                    Text("tap again to clear")
                        .font(Theme.rounded(10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: scrubbed)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(metric.rawValue, point.value)
                )
                .foregroundStyle(barStyle(point))
                .cornerRadius(2.5)
            }

            ForEach(rolling) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Average", point.value),
                    series: .value("Series", "average")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [3, 3]))
                .foregroundStyle(Color.white.opacity(0.45))
            }

            if let selection {
                RuleMark(x: .value("Day", selection.date, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Day", selection.date, unit: .day),
                    y: .value(metric.rawValue, selection.value)
                )
                .symbolSize(60)
                .foregroundStyle(Color.white)
            }
        }
        .chartYScale(domain: 0...(peak * 1.18))
        // Tap pins a day and keeps it pinned; dragging sweeps across the window,
        // and tapping the pinned day again clears it. A callout that vanishes the
        // moment you lift your thumb is unreadable.
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plot = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plot].origin.x
                                guard let date: Date = proxy.value(atX: x),
                                      let nearest = nearestPoint(to: date) else { return }
                                if !isScrubbing {
                                    isScrubbing = true
                                    scrubbedBefore = scrubbed
                                }
                                if scrubbed != nearest.date {
                                    scrubbed = nearest.date
                                    Haptics.tick()
                                }
                            }
                            .onEnded { _ in
                                isScrubbing = false
                                if scrubbedBefore == scrubbed { scrubbed = nil }
                                scrubbedBefore = nil
                            }
                    )
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(metric.format(number))
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
        .frame(height: 168)
        .animation(.easeInOut(duration: 0.3), value: metric)
    }

    /// The plotted day closest to a scrub position.
    private func nearestPoint(to date: Date) -> TrainingStats.DayPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func barStyle(_ point: TrainingStats.DayPoint) -> Color {
        guard point.value > 0 else { return Color.white.opacity(0.05) }
        // Heavier days burn brighter, so the shape of a training block is
        // readable at a glance; scrubbing fades the rest rather than flattening
        // them to one colour.
        let heat = MuscleHeat.color(0.55 + 0.6 * (point.value / peak))
        if let selection, selection.date != point.date { return heat.opacity(0.4) }
        return heat
    }
}

// MARK: - Coverage ring

/// Weekly coverage as a dial. The ring is drawn in the heat-map palette so the
/// hero and the figure below it always agree about what "good" looks like.
struct CoverageRing: View {
    let progress: Double
    var size: CGFloat = 104

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: size * 0.1)

            Circle()
                .trim(from: 0, to: min(max(shown, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [MuscleHeat.color(0.15), MuscleHeat.color(0.6),
                                 MuscleHeat.color(1.0), MuscleHeat.color(1.0)],
                        center: .center, angle: .degrees(-90)),
                    style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: MuscleHeat.color(max(progress, 0.4)).opacity(0.5), radius: 8)

            VStack(spacing: 0) {
                RollingNumber(value: shown * 100, format: { String(format: "%.0f", $0) })
                    .font(Theme.number(size * 0.28))
                    .foregroundStyle(Theme.textPrimary)
                Text("% COVERED")
                    .font(Theme.rounded(size * 0.085, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.2)) { shown = progress }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = new }
        }
    }
}

// MARK: - Muscle detail

/// What the figure can't say: the actual numbers, when it was last hit, and
/// which movements are feeding it.
struct MuscleDetailPanel: View {
    let muscle: Muscle
    let sets: Double
    let lastTrained: Date?
    let exercises: [(name: String, sets: Double)]

    private var target: Double { Double(muscle.weeklySetTarget) }
    private var ratio: Double { sets / target }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(muscle.name)
                    .font(Theme.rounded(17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(MuscleHeat.label(ratio).uppercased())
                    .font(Theme.rounded(9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(MuscleHeat.tint(ratio)))
                Spacer()
                Text("\(String(format: "%g", sets)) / \(muscle.weeklySetTarget)")
                    .font(Theme.number(14, weight: .bold))
                    .foregroundStyle(MuscleHeat.tint(ratio))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(MuscleHeat.gradient(ratio))
                        .frame(width: geo.size.width * min(1, max(ratio, 0.008)))
                    // Where the target sits when the bar has run past it.
                    if ratio > 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 1.5, height: 8)
                            .offset(x: geo.size.width / max(ratio, 1))
                    }
                }
            }
            .frame(height: 8)

            Text(advice)
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !exercises.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(exercises, id: \.name) { exercise in
                        Pill(text: "\(exercise.name) · \(String(format: "%g", exercise.sets))",
                             color: Theme.textSecondary)
                    }
                }
            }

            if let lastTrained {
                Text("Last hit \(Self.dayLabel(for: lastTrained))")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(MuscleHeat.tint(ratio).opacity(0.25), lineWidth: 1))
    }

    /// Counted in calendar days, so a session logged this evening still reads
    /// "today" rather than the relative formatter's "in 5 hours".
    static func dayLabel(for date: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    private var advice: String {
        let remaining = Int((target - sets).rounded(.up))
        switch ratio {
        case ..<0.02:
            return "Nothing logged this week. \(muscle.weeklySetTarget) hard sets is the target."
        case ..<0.85:
            return "\(remaining) more hard set\(remaining == 1 ? "" : "s") to hit the weekly target."
        case ..<1.16:
            return "On target for the week — hold this and let it recover."
        case ..<1.45:
            return "Past target. Fine for a push week, but watch the fatigue elsewhere."
        default:
            return "Well past target. Something else is probably being crowded out."
        }
    }
}
