import SwiftUI
import SwiftData

/// Body weight, alongside the training that moves it.
///
/// The numbers come from wherever they were measured: a weigh-in typed here is
/// written to Health, and anything recorded by a connected scale is pulled back
/// in. Nothing is duplicated — one entry per day wins, whichever way it arrived.
///
/// A mistyped weigh-in comes out through a long press on the reading, which
/// nobody who never mistypes will ever see.
struct BodyWeightCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]

    @State private var isLogging = false
    @State private var isImporting = false
    @State private var isReviewing = false
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
    private func change(in series: [BodyMetric]) -> Double? {
        guard let first = series.first, let last = series.last, series.count > 1 else { return nil }
        return unit.fromKg(last.weightKg - first.weightKg)
    }

    /// How long that change took, "6 weeks". A bare "+1.2 kg" reads the same
    /// whether it took five days or twelve weeks.
    private func changeSpan(in series: [BodyMetric]) -> String? {
        guard let first = series.first, let last = series.last, series.count > 1 else { return nil }
        return TrainingStats.changeSpan(days: TrainingStats.dayCount(from: first.date, to: last.date,
                                                                     calendar: .current))
    }

    var body: some View {
        let series = self.series
        return VStack(spacing: 8) {
            SectionHeader("Body weight")

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    header(change: change(in: series), span: changeSpan(in: series))
                    if series.count > 1 { chart(series: series) }
                }
                .contentShape(Rectangle())
                .contextMenu { entryMenu }
                actions
            }
            .gtCard()
        }
        .sheet(isPresented: $isLogging) {
            LogWeightSheet(startingKg: latest?.weightKg ?? unit.toKg(unit == .kg ? 75 : 165)) { kg, date in
                try record(kg: kg, on: date)
            }
        }
        .sheet(isPresented: $isReviewing) {
            RecentWeighInsSheet { delete($0) }
        }
    }

    // MARK: - Pieces

    private func header(change: Double?, span: String?) -> some View {
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
                        changeLine(change, span: span)
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
                         ? "No weigh-ins found in Health — add one below."
                         : "Log one here, or turn on Health sync in Settings.")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The change figure with the time it took after it, in a lighter weight so
    /// the number stays the thing the eye lands on.
    private func changeLine(_ change: Double, span: String?) -> some View {
        let figure = "\(change >= 0 ? "+" : "")\(String(format: "%.1f", change)) \(unit.short)"
        return (Text(figure).font(Theme.number(13, weight: .bold))
                + Text(span.map { " over \($0)" } ?? "").font(Theme.rounded(11, weight: .medium)))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// A plain line over the window — the shape is the whole point, so it
    /// carries no axes. Each weigh-in sits where its date falls, so a fortnight
    /// with no entries draws as the long stretch it was, not as one step.
    private func chart(series: [BodyMetric]) -> some View {
        GeometryReader { geo in
            let values = series.map { unit.fromKg($0.weightKg) }
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let span = max(high - low, 0.5)
            let base = low - (span - (high - low)) / 2
            let inset: CGFloat = 4
            let plotWidth = max(geo.size.width - inset * 2, 1)
            let plotHeight = max(geo.size.height - inset * 2, 1)
            let positions = TrainingStats.weighInPositions(series.map(\.date), calendar: .current)

            ZStack {
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = inset + plotWidth * CGFloat(positions[index])
                        let y = inset + plotHeight * (1 - CGFloat((value - base) / span))
                        index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = values.last {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .position(
                            x: inset + plotWidth * CGFloat(positions.last ?? 1),
                            y: inset + plotHeight * (1 - CGFloat((last - base) / span))
                        )
                }
            }
        }
        .frame(height: 54)
        .padding(.vertical, 2)
    }

    /// Empty until there is a weigh-in, so the long press does nothing then.
    /// Deleting straight from here is offered only for one typed here: one
    /// that came from Health would return on the next import, which the list
    /// explains and a menu item has no room to.
    @ViewBuilder
    private var entryMenu: some View {
        if let latest {
            Button { isReviewing = true } label: {
                Label("Recent weigh-ins", systemImage: "list.bullet")
            }
            if !latest.isFromHealth {
                // See the dock's Discard: the accent tint would otherwise
                // draw this icon green.
                Button(role: .destructive) { delete(latest) } label: {
                    Label("Delete \(unit.format(latest.weightKg))", systemImage: "trash")
                }
                .tint(Theme.negative)
            }
        }
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
                    isImporting = true
                    Task {
                        let added = await HealthKitService.shared.importBodyMass(into: context)
                        isImporting = false
                        if added > 0 { Haptics.success() }
                    }
                } label: {
                    Group {
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "heart.text.square")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .frame(width: 38)
                    .padding(.vertical, 9)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Import weigh-ins from Health")
                .disabled(isImporting)
            }
        }
    }

    // MARK: - Writing

    /// One entry per day: a second weigh-in on the same day replaces the first
    /// rather than stacking up. The first one's Health sample goes with it, or
    /// the correction would leave the wrong number in Health beside the right
    /// one.
    private func record(kg: Double, on date: Date) throws {
        let entry: BodyMetric
        var replacedSample: UUID?
        if let existing = BodyMetric.entry(sameDayAs: date, in: metrics) {
            replacedSample = existing.writtenSampleID
            existing.weightKg = kg
            existing.date = date
            existing.source = BodyMetric.Source.manual.rawValue
            entry = existing
        } else {
            entry = BodyMetric(date: date, weightKg: kg)
            context.insert(entry)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        Haptics.success()
        let health = HealthKitService.shared
        // Health is written only once the weigh-in is on disk, so a failed
        // save never leaves a sample no entry knows about. If this second save
        // fails, autosave retries it; the weigh-in itself is already kept.
        entry.healthSampleID = health.saveBodyMass(kg: kg, date: date)
        try? context.save()
        if let replacedSample {
            Task { await health.deleteBodyMass(id: replacedSample) }
        }
    }

    /// Takes a weigh-in back out, with the Health sample GymTrack wrote for
    /// it: a mistyped weight is not data, and left in Health it would still
    /// reach anything that reads from there. A reading another source wrote
    /// stays in Health.
    private func delete(_ metric: BodyMetric) {
        let sample = metric.writtenSampleID
        context.delete(metric)
        do {
            try context.save()
        } catch {
            // The row stays on screen, which says plainly that it wasn't
            // deleted; there is nothing else to tell.
            context.rollback()
            return
        }
        Haptics.tick()
        if let sample {
            Task { await HealthKitService.shared.deleteBodyMass(id: sample) }
        }
    }
}

// MARK: - Recent weigh-ins

/// The last few weigh-ins, so one that was mistyped or saved on the wrong
/// date can be swiped away. Only the card's long-press menu leads here.
private struct RecentWeighInsSheet: View {
    let onDelete: (BodyMetric) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]
    @State private var settings = AppSettings.shared

    /// Enough to reach a slip noticed a few weeks later. Older history isn't
    /// what this list is for.
    private static let limit = 30

    private var recent: [BodyMetric] { Array(metrics.prefix(Self.limit)) }
    private var unit: WeightUnit { settings.weightUnit }

    private var footer: String {
        settings.healthBodyWeight
            ? "Swipe one away to delete it. A weigh-in typed here leaves Health too. One that came from Health stays there and returns on the next import, so delete it in Health as well."
            : "Swipe one away to delete it."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(recent) { metric in
                        row(metric)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { recent[$0] }
                        for metric in doomed { onDelete(metric) }
                    }
                } footer: {
                    Text(footer)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .gtScreenBackground()
            .navigationTitle("Weigh-ins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .gtSheetBackground()
    }

    private func row(_ metric: BodyMetric) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.date.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if metric.isFromHealth {
                    Text("From Health")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text(unit.format(metric.weightKg))
                .font(Theme.number(15))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Entry sheet

/// Typing a weight. Deliberately one number and a date — anything more and
/// people stop logging it.
private struct LogWeightSheet: View {
    let startingKg: Double
    let onSave: (Double, Date) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double
    @State private var date: Date = .now
    @State private var settings = AppSettings.shared
    @State private var saveError: String?

    init(startingKg: Double, onSave: @escaping (Double, Date) throws -> Void) {
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
                    Label(HealthKitService.shared.canWriteBodyMass
                          ? "Can also save to Health"
                          : "Health write access is off; this stays here",
                          systemImage: "heart.text.square.fill")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Button("Save") {
                    do {
                        try onSave(unit.toKg(value), date)
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: value > 0 && value.isFinite))
                .disabled(value <= 0 || !value.isFinite)

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
        .alert("Couldn't save weigh-in", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }
}
