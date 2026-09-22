import SwiftUI
import SwiftData
import Charts

/// Everything known about one exercise: what it works, and — the part that
/// matters — how your numbers on it have moved.
struct ExerciseDetailView: View {
    let exercise: CatalogExercise

    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    /// The metric the lifter picked, if they picked one. Which metrics there
    /// are depends on what the history turns out to hold, so the default is
    /// worked out from that rather than fixed here.
    @State private var chosenMetric: Metric?
    @State private var showingScale = false

    /// Everything on this screen is one exercise, so every number on it reads
    /// in that exercise's own unit rather than the app-wide one.
    private var scale: LoadScale { exercise.loadScale }

    /// What this exercise's numbers are counted in, read off what was logged
    /// rather than assumed from the library. The library files a pull-up as
    /// weight and reps, so it used to be charted in kilograms it never
    /// carried: a flat line along zero for the one-rep max, the top set and
    /// the volume alike, and tiles saying it had been lifted at 0 kg.
    enum Measure {
        case load, reps, time
    }

    enum Metric: String, CaseIterable, Identifiable {
        case estimatedMax = "Est. 1RM"
        case topSet = "Top set"
        case volume = "Volume"
        case mostReps = "Most reps"
        case totalReps = "Total reps"
        case longestHold = "Longest hold"
        var id: String { rawValue }

        static func options(for measure: Measure) -> [Metric] {
            switch measure {
            case .load: [.estimatedMax, .topSet, .volume]
            case .reps: [.mostReps, .totalReps]
            case .time: [.longestHold]
            }
        }

        /// A weight, so it reads in the exercise's own unit.
        var isLoad: Bool {
            switch self {
            case .estimatedMax, .topSet, .volume: true
            case .mostReps, .totalReps, .longestHold: false
            }
        }

        /// One session's number, or nil where the session has none. Nil
        /// rather than zero, so the chart leaves that session out instead of
        /// plotting a value nobody measured.
        func value(of entry: TrainingStats.ExerciseSessionSummary) -> Double? {
            let value: Double = switch self {
            case .estimatedMax: entry.bestEstimatedOneRepMax
            case .topSet: entry.topSet?.weightKg ?? 0
            case .volume: entry.volumeKg
            case .mostReps: Double(entry.sets.map(\.reps).max() ?? 0)
            case .totalReps: Double(entry.totalReps)
            case .longestHold: Double(entry.sets.map(\.seconds).max() ?? 0)
            }
            return value > 0 ? value : nil
        }
    }

    private struct ChartPoint: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    var body: some View {
        // Walked once, here, and handed to everything that draws it. It was a
        // computed property read by the tiles, the chart, its axis, the list
        // and the scale sheet, so one redraw read every set of every session
        // half a dozen times over — and opened from the logger, this screen
        // redraws on every set logged.
        let history = TrainingStats.history(for: exercise.id, in: sessions)
        return ScrollView {
            VStack(spacing: 16) {
                header(referenceKg: history.first?.topSet?.weightKg ?? 0)
                if history.isEmpty {
                    EmptyStateView(icon: "chart.line.uptrend.xyaxis",
                                   title: "No history yet",
                                   message: "Log this exercise in a workout and your progression shows up here.")
                        .gtCard()
                } else {
                    let measured = measure(of: history)
                    bestRow(history, measure: measured)
                    chartCard(history, measure: measured)
                    historyList(history, measure: measured)
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

    private func header(referenceKg: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                GlyphTile(symbol: exercise.symbol, size: 50, solid: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(Theme.rounded(19, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.equipmentLabel)
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            FlowRow(spacing: 6) {
                if exercise.muscles.isEmpty {
                    ForEach(exercise.muscleGroups, id: \.self) { label in
                        Pill(text: label, color: Theme.accent)
                    }
                } else {
                    ForEach(exercise.muscles, id: \.self) { muscle in
                        Pill(text: muscle.name, color: Theme.accent)
                    }
                }
                Pill(text: exercise.tracking.label)
                if let difficulty = exercise.difficulty {
                    Pill(text: difficulty.capitalized)
                }
            }

            if exercise.tracking != .duration {
                Divider().overlay(Theme.hairline)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Loaded in")
                            .font(Theme.eyebrow)
                            .tracking(1.0)
                            .foregroundStyle(Theme.textTertiary)
                        Text("\(scale.unit.label), \(scale.incrementLabel) at a time")
                            .font(Theme.rounded(13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    LoadScaleChip(scale: scale,
                                  isCustom: LoadScaleBook.shared.isCustomised(exercise.id)) {
                        showingScale = true
                    }
                }
            }
        }
        .gtCard()
        .sheet(isPresented: $showingScale) {
            LoadScaleSheet(exercise: exercise, referenceKg: referenceKg)
        }
    }

    // MARK: - Bests

    /// Weight-and-reps work counts as load once some set of it actually
    /// carried a weight. A bodyweight exercise stays in reps even with a plate
    /// hung off the belt: ten added kilograms on a pull-up is not a
    /// ten-kilogram lift, and a one-rep max estimated from it would say it was.
    private func measure(of history: [TrainingStats.ExerciseSessionSummary]) -> Measure {
        switch exercise.tracking {
        case .duration: .time
        case .bodyweightReps: .reps
        case .weightReps: history.contains { ($0.topSet?.weightKg ?? 0) > 0 } ? .load : .reps
        }
    }

    private func bestRow(_ history: [TrainingStats.ExerciseSessionSummary], measure: Measure) -> some View {
        let allSets = history.flatMap(\.sets)
        let heaviest = allSets.map(\.weightKg).max() ?? 0
        // Each session's own estimate, not one taken across every row: those
        // leave out the rows of a drop or a cluster, which are lifted
        // pre-fatigued as part of the set above them. A light row taken for a
        // pile of reps estimates a one-rep max the lifter never had, and the
        // tile would outrank the chart underneath it and the records both.
        let bestE1RM = history.map(\.bestEstimatedOneRepMax).max() ?? 0
        let bestReps = allSets.map(\.reps).max() ?? 0

        return HStack(spacing: 10) {
            switch measure {
            case .time:
                StatTile(value: "\(allSets.map(\.seconds).max() ?? 0)s", label: "Longest hold", tint: Theme.accent)
                StatTile(value: "\(history.count)", label: "Sessions")
            case .reps:
                StatTile(value: "\(bestReps)", label: "Most reps", tint: Theme.accent)
                StatTile(value: "\(history.count)", label: "Sessions")
            case .load:
                StatTile(value: scale.format(heaviest, showUnit: false),
                         label: "Heaviest \(scale.unit.short)", tint: Theme.accent)
                StatTile(value: scale.format(bestE1RM, showUnit: false),
                         label: "Est. 1RM \(scale.unit.short)")
                StatTile(value: "\(bestReps)", label: "Most reps")
            }
        }
    }

    // MARK: - Chart

    private func shownMetric(from options: [Metric]) -> Metric {
        if let chosenMetric, options.contains(chosenMetric) { return chosenMetric }
        return options[0]
    }

    private func chartCard(_ history: [TrainingStats.ExerciseSessionSummary], measure: Measure) -> some View {
        let options = Metric.options(for: measure)
        let metric = shownMetric(from: options)
        let points = chartPoints(history, metric: metric)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Progression")
                Spacer()
                // With nothing to pick between, the picker goes and the name
                // of what's drawn stays, so the axis still says what it counts.
                if options.count == 1 {
                    Text(metric.rawValue)
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if options.count > 1 {
                Picker("Metric", selection: Binding(get: { metric }, set: { chosenMetric = $0 })) {
                    ForEach(options) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if points.isEmpty {
                Text("Nothing logged for this yet.")
                    .font(Theme.rounded(13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                chart(points, metric: metric)
            }
        }
        .gtCard()
    }

    private func chart(_ points: [ChartPoint], metric: Metric) -> some View {
        Chart(points) { point in
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
        .chartYScale(domain: yDomain(points))
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

    /// Pad around the actual range rather than starting at zero — otherwise a
    /// 10 kg gain over two months looks like a flat line.
    private func yDomain(_ points: [ChartPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...10 }
        if high == low { return max(0, low * 0.9)...(high * 1.1 + 1) }
        let padding = (high - low) * 0.25
        return max(0, low - padding)...(high + padding)
    }

    /// Oldest first, and only the sessions that have the number at all.
    private func chartPoints(_ history: [TrainingStats.ExerciseSessionSummary], metric: Metric) -> [ChartPoint] {
        history.reversed().compactMap { entry in
            guard let value = metric.value(of: entry) else { return nil }
            return ChartPoint(id: entry.id, date: entry.date,
                              value: metric.isLoad ? scale.display(value) : value)
        }
    }

    // MARK: - History

    private func historyList(_ history: [TrainingStats.ExerciseSessionSummary], measure: Measure) -> some View {
        VStack(spacing: 8) {
            SectionHeader("Every session")
            ForEach(history) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(Theme.rounded(13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(sessionLine(entry, measure: measure))
                            .font(Theme.rounded(11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    FlowRow(spacing: 6) {
                        ForEach(entry.sets) { set in
                            setChip(set)
                        }
                    }
                }
                .gtCard(padding: 12)
            }
        }
    }

    /// The sets, then whatever the session added up to in the exercise's own
    /// terms. A pull-up session used to read "3 sets · 0 kg", which says it
    /// was weighed and came to nothing.
    private func sessionLine(_ entry: TrainingStats.ExerciseSessionSummary, measure: Measure) -> String {
        let sets = setCount(entry)
        switch measure {
        case .time:
            let held = entry.sets.reduce(0) { $0 + $1.seconds }
            return held > 0 ? "\(sets) · \(held)s held" : sets
        case .load where entry.volumeKg > 0:
            return "\(sets) · \(scale.format(entry.volumeKg))"
        case .load, .reps:
            return entry.totalReps > 0 ? "\(sets) · \(entry.totalReps) reps" : sets
        }
    }

    /// Sets counted as efforts, the way the logger and the session screens
    /// count them. Counting rows, a session with one drop in it said "4 sets"
    /// here while its own summary said 3.
    private func setCount(_ entry: TrainingStats.ExerciseSessionSummary) -> String {
        let count = entry.sets.filter { !$0.isContinuation }.count
        return count == 1 ? "1 set" : "\(count) sets"
    }

    /// One logged set, with a dot in the colour of how it felt when it was
    /// answered for. Pulled out of the list because the chained ternaries and
    /// the modifiers together are more than the type checker will sit through.
    ///
    /// A drop or cluster row carries the glyph the session screens mark it
    /// with. Without it, 62.5×8 then 50×10 then 40×12 reads as a lifter
    /// falling apart across three sets rather than one set taken further.
    private func setChip(_ set: SetLog) -> some View {
        let value: String
        if set.tracking == .duration {
            value = "\(set.seconds)s"
        } else if set.weightKg == 0 {
            value = "\(set.reps)"
        } else {
            value = "\(scale.format(set.weightKg, showUnit: false))×\(set.reps)"
        }
        let continuation = set.continuation
        return HStack(spacing: 4) {
            if continuation != nil {
                Image(systemName: SetContinuation.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(value)
                .font(Theme.number(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            if let feel = set.feel {
                Circle().fill(feel.tint).frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.panel, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.edge, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chipLabel(value, continuation: continuation, feel: set.feel))
    }

    private func chipLabel(_ value: String, continuation: SetContinuation?, feel: SetFeel?) -> String {
        var parts = [value]
        if let continuation { parts.insert(continuation.label, at: 0) }
        if let feel { parts.append("felt \(feel.label)") }
        return parts.joined(separator: ", ")
    }
}
