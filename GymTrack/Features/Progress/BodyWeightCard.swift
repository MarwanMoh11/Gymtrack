import SwiftUI
import SwiftData

/// Body weight, alongside the training that moves it.
///
/// The numbers come from wherever they were measured: a weigh-in typed here is
/// written to Health, and anything recorded by a connected scale is pulled back
/// in. Nothing is duplicated — one entry per day wins, whichever way it arrived.
struct BodyWeightCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]

    @State private var isLogging = false
    @State private var settings = AppSettings.shared

    private var unit: WeightUnit { settings.weightUnit }
    private var latest: BodyMetric? { metrics.first }

    /// Entries inside the last twelve weeks, oldest first — enough to see a
    /// direction without turning into a second progress screen.
    private var series: [BodyMetric] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -84, to: .now) ?? .distantPast
        return metrics.filter { $0.date >= cutoff }.reversed()
    }

    /// Change across the window, in the display unit.
    private var change: Double? {
        guard let first = series.first, let last = series.last, series.count > 1 else { return nil }
        return unit.fromKg(last.weightKg - first.weightKg)
    }

    var body: some View {
        VStack(spacing: 8) {
            SectionHeader("Body weight")

            VStack(alignment: .leading, spacing: 12) {
                header
                if series.count > 1 { chart }
                actions
            }
            .gtCard()
        }
        .sheet(isPresented: $isLogging) {
            LogWeightSheet(startingKg: latest?.weightKg ?? unit.toKg(unit == .kg ? 75 : 165)) { kg, date in
                record(kg: kg, on: date)
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let latest {
                Text(unit.format(latest.weightKg, showUnit: false))
                    .font(Theme.number(30))
                    .foregroundStyle(Theme.textPrimary)
                Text(unit.short)
                    .font(Theme.rounded(14, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    if let change {
                        Text("\(change >= 0 ? "+" : "")\(String(format: "%.1f", change)) \(unit.short)")
                            .font(Theme.number(13, weight: .bold))
                            .foregroundStyle(change >= 0 ? Theme.warning : Theme.positive)
                    }
                    Text(latest.date.formatted(.relative(presentation: .numeric)))
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No weigh-ins yet")
                        .font(Theme.rounded(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(settings.healthBodyWeight
                         ? "Nothing in Health to import — add one below."
                         : "Log one here, or turn on Health sync in Settings.")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// A plain line over the window — the shape is the whole point, so it
    /// carries no axes.
    private var chart: some View {
        GeometryReader { geo in
            let values = series.map { unit.fromKg($0.weightKg) }
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let span = max(high - low, 0.5)

            ZStack {
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = values.count == 1 ? geo.size.width / 2
                            : geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((value - low) / span))
                        index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = values.last {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .position(
                            x: geo.size.width,
                            y: geo.size.height * (1 - CGFloat((last - low) / span))
                        )
                }
            }
        }
        .frame(height: 54)
        .padding(.vertical, 2)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tick()
                isLogging = true
            } label: {
                Label("Log weight", systemImage: "plus")
                    .font(Theme.rounded(13, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            if settings.healthBodyWeight {
                Button {
                    Task {
                        let added = await HealthKitService.shared.importBodyMass(into: context)
                        if added > 0 { Haptics.success() }
                    }
                } label: {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 38)
                        .padding(.vertical, 9)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Import weigh-ins from Health")
            }
        }
    }

    // MARK: - Writing

    /// One entry per day: a second weigh-in on the same day replaces the first
    /// rather than stacking up.
    private func record(kg: Double, on date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if let existing = metrics.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            existing.weightKg = kg
            existing.date = date
            existing.source = BodyMetric.Source.manual.rawValue
        } else {
            context.insert(BodyMetric(date: date, weightKg: kg))
        }
        try? context.save()
        Haptics.success()
        Task { await HealthKitService.shared.saveBodyMass(kg: kg, date: date) }
    }
}

// MARK: - Entry sheet

/// Typing a weight. Deliberately one number and a date — anything more and
/// people stop logging it.
private struct LogWeightSheet: View {
    let startingKg: Double
    let onSave: (Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double
    @State private var date: Date = .now
    @State private var settings = AppSettings.shared

    init(startingKg: Double, onSave: @escaping (Double, Date) -> Void) {
        self.startingKg = startingKg
        self.onSave = onSave
        _value = State(initialValue: AppSettings.shared.weightUnit.snap(AppSettings.shared.weightUnit.fromKg(startingKg)))
    }

    private var unit: WeightUnit { settings.weightUnit }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                StepperField(
                    title: "Weight",
                    value: $value,
                    step: unit == .kg ? 0.1 : 0.5,
                    format: { String(format: "%.1f", $0) },
                    unit: unit.short
                )
                .padding(.top, 10)

                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.horizontal, 4)
                    .tint(Theme.accent)

                if settings.healthBodyWeight {
                    Label("Also saved to Health", systemImage: "heart.text.square.fill")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Button("Save") {
                    onSave(unit.toKg(value), date)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())

                Spacer()
            }
            .padding(16)
            .gtScreenBackground()
            .navigationTitle("Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .gtSheetBackground()
    }
}
