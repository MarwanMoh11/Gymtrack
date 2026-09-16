import SwiftUI

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var action: (label: String, perform: () -> Void)?

    init(_ title: String, action: (label: String, perform: () -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if let action {
                Button(action.label, action: action.perform)
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(17, weight: .bold))
            .foregroundStyle(isEnabled ? Color.black : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? tint : Theme.surfaceRaised)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(16, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pill

struct Pill: View {
    let text: String
    var color: Color = Theme.textSecondary
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.rounded(11, weight: .semibold))
            .foregroundStyle(filled ? .black : color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(filled ? color : color.opacity(0.14))
            )
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let value: String
    let label: String
    var caption: String?
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Theme.number(24))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(Theme.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            if let caption {
                Text(caption)
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double          // 0...1
    var lineWidth: CGFloat = 8
    var tint: Color = Theme.accent
    var label: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
            if let label {
                Text(label)
                    .font(Theme.number(15))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(title)
                .font(Theme.rounded(19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.rounded(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                    .frame(maxWidth: 260)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row chevron

struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Numeric stepper field

/// Big tap targets and haptics — designed for use mid-set with sweaty hands.
struct StepperField: View {
    let title: String
    @Binding var value: Double
    var format: (Double) -> String
    var unit: String
    /// Where a tap of − or + lands. A plain step for reps and seconds; the
    /// machine's own ladder for a weight, so the field can't offer a load the
    /// equipment doesn't have.
    var advance: (Double, Int) -> Double
    /// Set to make the unit caption a button — how the weight field opens
    /// "how is this one marked?".
    var unitAction: (() -> Void)?
    /// Whether the caption describes something the user set themselves, which
    /// is worth the accent so an unusual machine looks unusual.
    var unitIsCustom = false
    /// The ladder behind a weight field, drawn in the caption.
    private var scale: LoadScale?

    /// Fixed steps: reps, seconds, anything that isn't loaded on a machine.
    init(title: String,
         value: Binding<Double>,
         step: Double,
         format: @escaping (Double) -> String,
         unit: String) {
        self.title = title
        self._value = value
        self.format = format
        self.unit = unit
        self.advance = { current, direction in
            max(0, current + Double(direction) * step)
        }
    }

    /// A weight, stepped along the ladder its equipment actually has.
    init(title: String,
         value: Binding<Double>,
         scale: LoadScale,
         format: @escaping (Double) -> String,
         unitAction: (() -> Void)? = nil,
         unitIsCustom: Bool = false) {
        self.title = title
        self._value = value
        self.format = format
        self.unit = scale.shortLabel
        self.advance = { current, direction in scale.step(display: current, by: direction) }
        self.unitAction = unitAction
        self.unitIsCustom = unitIsCustom
        self.scale = scale
    }

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.0)
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 4) {
                stepButton(icon: "minus", enabled: value > 0) {
                    value = max(0, advance(value, -1))
                    Haptics.tick()
                }

                VStack(spacing: 0) {
                    // Tapping the number types it directly — stepping from 0 to
                    // a working weight would otherwise take dozens of taps.
                    Button {
                        draft = value == 0 ? "" : trimmed(value)
                        isEditing = true
                        Haptics.tick()
                    } label: {
                        Text(format(value))
                            .font(Theme.number(26))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    caption
                }
                .frame(maxWidth: .infinity)

                stepButton(icon: "plus", enabled: true) {
                    value = advance(value, 1)
                    Haptics.tick()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .alert("Enter \(title.lowercased())", isPresented: $isEditing) {
            TextField(unitName, text: $draft)
                .keyboardType(.decimalPad)
            Button("Set") {
                if let entered = Double(draft.replacingOccurrences(of: ",", with: ".")) {
                    value = max(0, entered)
                    Haptics.tick()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The unit under the number. For a weight it's a button — it's what opens
    /// "how is this one marked?", and the only place anyone would look for it.
    @ViewBuilder
    private var caption: some View {
        if let scale, let unitAction {
            LoadScaleChip(scale: scale, isCustom: unitIsCustom, action: unitAction)
        } else {
            Text(unit)
                .font(Theme.rounded(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Just the unit, for the keypad's placeholder — "kg · 2.5" reads as a
    /// value to type rather than a hint.
    private var unitName: String {
        scale?.unit.short ?? unit
    }

    /// What the keypad opens on. A weight prefills at the precision its ladder
    /// can express, so the number you're handed is the number you were reading.
    private func trimmed(_ number: Double) -> String {
        if let scale { return scale.text(number) }
        return number.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", number)
            : String(format: "%.2f", number).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 42, height: 42)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Load scale chip

/// "kg · 2.5" — what a weight is being entered in, and what one tap of + is
/// worth. Tapping it is how anyone discovers that a machine can be corrected.
struct LoadScaleChip: View {
    let scale: LoadScale
    var isCustom: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(scale.shortLabel)
                    .font(Theme.rounded(10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(isCustom ? Theme.accent : Theme.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isCustom ? Theme.accentDim : Color.white.opacity(0.05))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weights in \(scale.unit.label), \(scale.incrementLabel) at a time")
        .accessibilityHint("Change how this one is marked")
    }
}
