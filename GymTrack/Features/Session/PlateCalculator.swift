import SwiftUI

/// "Per side 20 + 10 + 2.5" under a barbell exercise's header, for the set the
/// lifter is about to do. Zero taps to read; a tap opens the calculator for any
/// other weight.
///
/// Shown for the next set only, and only on a plain barbell lift. It holds no
/// state beyond whether its sheet is open, and nothing it shows is stored.
struct PlatesStrip: View {
    let group: SessionExerciseGroup
    @State private var showsCalculator = false

    private var row: SetLog? { group.sets.first { !$0.isCompleted } }

    var body: some View {
        if let row, row.tracking.logsWeight, row.weightKg > 0,
           let bar = PlateLoading.bar(for: group.catalog, scale: row.loadScale) {
            let scale = row.loadScale
            let total = scale.display(row.weightKg)
            let outcome = PlateMath.outcome(total: total, bar: bar, plates: PlateMath.standardPlates(scale.unit))
            Button { showsCalculator = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.2x1.fill")
                        .gtIcon(size: 11, relativeTo: .caption)
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                    Text(PlateCalculatorText.line(outcome, scale: scale, bar: bar))
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plates.strip")
            .accessibilityHint("Opens the plate calculator")
            .sheet(isPresented: $showsCalculator) {
                PlateCalculatorSheet(startingKg: row.weightKg, scale: scale, bar: bar)
            }
        }
    }
}

/// The wording, kept out of the views so every outcome reads the same in the
/// strip and in the sheet.
enum PlateCalculatorText {
    static func line(_ outcome: PlateMath.Outcome, scale: LoadScale, bar: Double) -> String {
        switch outcome {
        case .exact(let plates):
            return plates.isEmpty ? "Bar only · \(scale.text(bar)) \(scale.unit.short)"
                                  : "Per side \(PlateMath.caption(plates))"
        case .unreachable(let plates, let short):
            let made = plates.isEmpty ? "bar only" : PlateMath.caption(plates)
            return "Per side \(made) · \(PlateMath.label(short)) \(scale.unit.short) short"
        case .belowBar:
            return "Lighter than the \(scale.text(bar)) \(scale.unit.short) bar"
        }
    }
}

/// A small calculator: type or step any total and see the plates for one end of
/// the bar. Starts on the weight of the set it was opened from and never writes
/// back to it, so playing with numbers cannot change a logged or planned load.
struct PlateCalculatorSheet: View {
    let scale: LoadScale
    let bar: Double
    @State private var total: Double
    @State private var text: String
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    init(startingKg: Double, scale: LoadScale, bar: Double) {
        self.scale = scale
        self.bar = bar
        let start = scale.display(startingKg)
        _total = State(initialValue: start)
        _text = State(initialValue: scale.text(start))
    }

    private var outcome: PlateMath.Outcome {
        PlateMath.outcome(total: total, bar: bar, plates: PlateMath.standardPlates(scale.unit))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                weightEntry
                plateStack
                Text(PlateCalculatorText.line(outcome, scale: scale, bar: bar))
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("plates.result")
                Text("Bar \(scale.text(bar)) \(scale.unit.short), the same plates on both ends. Change the bar in Settings.")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(16)
            .gtScreenBackground()
            .navigationTitle("Plates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.rounded(15, weight: .bold))
                }
            }
        }
        .gtSheetBackground()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Entry

    private var weightEntry: some View {
        HStack(spacing: 14) {
            stepButton("minus", direction: -1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($typing)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.rounded(40, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 90, maxWidth: 150)
                    .onChange(of: text) { _, typed in
                        // A half-typed number leaves the last good total alone.
                        if let value = Double(typed.replacingOccurrences(of: ",", with: ".")),
                           value >= 0, value <= scale.displayCeiling { total = value }
                    }
                    .accessibilityIdentifier("plates.total")
                Text(scale.unit.short)
                    .font(Theme.rounded(16, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            stepButton("plus", direction: 1)
        }
    }

    private func stepButton(_ symbol: String, direction: Int) -> some View {
        Button {
            typing = false
            total = min(scale.displayCeiling, scale.step(display: total, by: direction))
            text = scale.text(total)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.surfaceRaised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction > 0 ? "Heavier" : "Lighter")
    }

    // MARK: - The bar, side-on

    /// One end of the bar with the plates stacked on it, heaviest against the
    /// collar the way they are loaded. Height follows the plate's weight so a
    /// glance tells a 25 from a 2.5.
    private var plateStack: some View {
        let plates = outcome.perSide ?? []
        let largest = PlateMath.standardPlates(scale.unit).max() ?? 1
        return HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.textTertiary)
                .frame(width: 44, height: 10)
            ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.accent.opacity(0.35 + 0.65 * plate / largest))
                    .frame(width: 12, height: 24 + 70 * plate / largest)
                    .overlay {
                        Text(PlateMath.label(plate))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.background)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                    }
            }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.textTertiary)
                .frame(width: 24, height: 10)
            Spacer(minLength: 0)
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .gtWell(vertical: 8, horizontal: 12)
        .accessibilityHidden(true)
    }
}
