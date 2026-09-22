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

/// The one thing a screen is asking for. Filled with the phase gradient, lit
/// across the top the way a physical key is, and burning into the screen under
/// it — at 54pt tall it's the largest object on most screens and a flat fill
/// that size just looks like a swatch.
struct PrimaryButtonStyle: ButtonStyle {
    var phase: SessionPhase = .working
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .font(Theme.rounded(17, weight: .bold))
            .foregroundStyle(isEnabled ? Color.black : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                ZStack {
                    if isEnabled {
                        phase.gradient
                        LinearGradient(colors: [Color.white.opacity(0.24), .clear],
                                       startPoint: .top, endPoint: .center)
                    } else {
                        Theme.panel
                    }
                }
                .clipShape(shape)
                .overlay { if !isEnabled { shape.strokeBorder(Theme.edge, lineWidth: 1) } }
            }
            .shadow(color: isEnabled ? phase.glow.opacity(configuration.isPressed ? 0.3 : 0.55) : .clear,
                    radius: 14, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Everything offered alongside the primary. Same panel as a card so it reads
/// as part of the surface rather than as a competing button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return configuration.label
            .font(Theme.rounded(16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.panel, in: shape)
            .overlay { shape.strokeBorder(Theme.edge, lineWidth: 1) }
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
            .foregroundStyle(filled ? AnyShapeStyle(Color.black) : AnyShapeStyle(color))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(filled ? AnyShapeStyle(color.wash) : AnyShapeStyle(color.opacity(0.13)))
            }
            .overlay { if !filled { Capsule().strokeBorder(color.opacity(0.2), lineWidth: 1) } }
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let value: String
    let label: String
    var caption: String?
    /// A tile that measures something with a colour of its own — heart red,
    /// energy amber. It carries that colour into the number and bleeds a little
    /// of it into the tile, so a row of three is scannable by hue alone.
    var tint: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Theme.number(24))
                .foregroundStyle(tint.map { AnyShapeStyle($0.wash) } ?? AnyShapeStyle(Theme.ink))
                .shadow(color: tint?.opacity(0.35) ?? .clear, radius: 8)
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
        .background {
            ZStack {
                Theme.panel
                if let tint {
                    LinearGradient(colors: [tint.opacity(0.14), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(shape)
        }
        .overlay {
            shape.strokeBorder(tint.map { AnyShapeStyle(LinearGradient(colors: [$0.opacity(0.4), Color.white.opacity(0.04)],
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing)) }
                               ?? AnyShapeStyle(Theme.edge),
                               lineWidth: 1)
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
            GlyphTile(symbol: icon, size: 72)
            Text(title)
                .font(Theme.rounded(19, weight: .bold))
                .foregroundStyle(Theme.ink)
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
                            .foregroundStyle(Theme.ink)
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
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.textTertiary))
                .frame(width: 42, height: 42)
                // White-translucent rather than a fixed grey: it lifts off
                // whatever it's sitting on, including a tinted set row.
                .background(LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.06)],
                                           startPoint: .top, endPoint: .bottom),
                            in: shape)
                .overlay { shape.strokeBorder(Theme.edge, lineWidth: 1) }
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
        }
        .buttonStyle(StepperKeyStyle())
        // Held, a key keeps stepping. Twenty-odd taps to dial a working weight
        // up from an empty bar was the slowest thing in the logger; a tap is
        // still exactly one step, so nobody who never holds it can tell.
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
    }
}

/// The − and + keys. They go down under the thumb and brighten, because a key
/// that doesn't move reads as one that didn't register — and a lifter who isn't
/// sure a tap landed taps again, and ends up a plate heavier than they meant.
private struct StepperKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
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
            .background {
                Capsule().fill(isCustom
                               ? AnyShapeStyle(LinearGradient(colors: [Theme.accent.opacity(0.24), Theme.accent.opacity(0.08)],
                                                              startPoint: .top, endPoint: .bottom))
                               : AnyShapeStyle(Color.white.opacity(0.05)))
            }
            .overlay { Capsule().strokeBorder(isCustom ? Theme.accent.opacity(0.3) : .clear, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weights in \(scale.unit.label), \(scale.incrementLabel) at a time")
        .accessibilityHint("Change how this one is marked")
    }
}
