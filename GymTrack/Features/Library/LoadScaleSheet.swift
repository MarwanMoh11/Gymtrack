import SwiftUI

/// "How is this one marked?" — the sheet behind every weight field in the app.
///
/// It exists because gyms are inconsistent and the app shouldn't pretend
/// otherwise: the leg press is stamped in pounds and pins in fifteens, the
/// dumbbells go up in twos, and the barbell takes whatever plates that gym
/// owns. Correcting one exercise takes two taps and sticks forever, and
/// everything else in the app keeps following the app-wide unit.
struct LoadScaleSheet: View {

    let exercise: CatalogExercise
    /// The weight on screen when the sheet opened, so the preview shows rungs
    /// around where the lifter actually is rather than around zero.
    var referenceKg: Double = 0
    /// Called with the saved scale, for callers that want to re-snap what
    /// they're showing.
    var onSave: ((LoadScale) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var unit: WeightUnit
    @State private var increment: Double

    init(exercise: CatalogExercise, referenceKg: Double = 0, onSave: ((LoadScale) -> Void)? = nil) {
        self.exercise = exercise
        self.referenceKg = referenceKg
        self.onSave = onSave
        let scale = LoadScaleBook.shared.scale(for: exercise)
        _unit = State(initialValue: scale.unit)
        _increment = State(initialValue: scale.increment)
    }

    /// What the sheet currently describes.
    private var scale: LoadScale { LoadScale(unit: unit, increment: increment) }

    /// What this exercise would do with nothing saved against it.
    private var derived: LoadScale { LoadScaleBook.derived(for: exercise) }

    /// Matching the default exactly *is* the default — saving then drops the
    /// override, so the exercise keeps following the app unit if that changes.
    private var followsDefault: Bool { scale == derived }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    unitSection
                    incrementSection
                    ladderCard
                    footnote
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.rounded(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .font(Theme.rounded(15, weight: .bold))
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Unit

    private var unitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Marked in")
            HStack(spacing: 8) {
                ForEach(WeightUnit.allCases) { option in
                    Button {
                        guard option != unit else { return }
                        // Keep the jump roughly what it was — someone switching
                        // a 2.5 kg machine to pounds means 5 lb, not 2.5.
                        let moved = scale.converted(to: option)
                        unit = moved.unit
                        increment = moved.increment
                        Haptics.tick()
                    } label: {
                        VStack(spacing: 2) {
                            Text(option.short.uppercased())
                                .font(Theme.number(18))
                            Text(option.label)
                                .font(Theme.rounded(11, weight: .medium))
                                .opacity(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(option == unit ? .black : Theme.textSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(option == unit ? Theme.accent : Theme.surfaceRaised)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .gtCard()
    }

    // MARK: - Increment

    private var incrementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("One step")
            FlowRow(spacing: 8) {
                ForEach(LoadScale.choices(for: unit) + extraChoice, id: \.self) { choice in
                    Button {
                        increment = choice
                        Haptics.tick()
                    } label: {
                        Text(LoadScale.trim(choice))
                            .font(Theme.number(15))
                            .foregroundStyle(choice == increment ? .black : Theme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(choice == increment ? Theme.accent : Theme.surfaceRaised)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("What one pin, one notch, or the smallest pair of plates is worth on this machine.")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gtCard()
    }

    /// A saved increment that isn't one of the usual suspects still gets a chip,
    /// so reopening the sheet never silently loses it.
    private var extraChoice: [Double] {
        LoadScale.choices(for: unit).contains(increment) ? [] : [increment]
    }

    // MARK: - Preview

    private var ladderCard: some View {
        let rungs = scale.ladder(around: referenceKg)
        let here = scale.snap(display: scale.display(referenceKg))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("What you'll be offered")
            HStack(spacing: 6) {
                Text("…")
                    .font(Theme.number(14))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(Array(rungs.enumerated()), id: \.offset) { _, rung in
                    let isCentre = abs(rung - here) < 0.001
                    Text(scale.text(rung))
                        .font(Theme.number(isCentre ? 16 : 14))
                        .foregroundStyle(isCentre ? Theme.accent : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text("…")
                    .font(Theme.number(14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            Text("\(scale.unit.label.lowercased()), \(scale.incrementLabel) at a time")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .gtCard()
    }

    // MARK: - Footnote

    private var footnote: some View {
        VStack(spacing: 10) {
            Text(followsDefault
                 ? "Following the app default for \(exercise.equipmentLabel.lowercased())."
                 : "Only \(exercise.name) changes. Everything else keeps following the unit in Settings.")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your history is stored in kilograms and converted, so records and volume stay comparable whatever the machine says.")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !followsDefault {
                Button("Use the app default (\(derived.shortLabel))") {
                    unit = derived.unit
                    increment = derived.increment
                    Haptics.tick()
                }
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Saving

    private func save() {
        if followsDefault {
            LoadScaleBook.shared.clear(exercise.id)
        } else {
            LoadScaleBook.shared.set(scale, for: exercise.id)
        }
        Haptics.success()
        onSave?(scale)
        dismiss()
    }
}

// MARK: - The control that opens it

/// The caption under a weight field: what the machine is marked in, and what a
/// tap of + is worth. Tapping it is how anyone ever discovers this exists.
struct LoadScaleCaption: View {
    let scale: LoadScale
    var isCustomised: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(scale.shortLabel)
                    .font(Theme.rounded(10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(isCustomised ? Theme.accent : Theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weights in \(scale.unit.label), \(scale.incrementLabel) at a time")
        .accessibilityHint("Change how this machine is marked")
    }
}
