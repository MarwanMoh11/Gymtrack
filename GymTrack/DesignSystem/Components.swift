import SwiftUI

// MARK: - Fonts that grow with Dynamic Type

/// A system font at a fixed design size that grows with Dynamic Type along the
/// curve of `style`. `Theme.rounded` can only follow a text style when the size
/// is that style's own default, so 14 pt, the 9-10 pt captions and the icons
/// beside text stayed fixed and were the first thing to become unreadable at a
/// larger setting. `@ScaledMetric` reads the environment, so the
/// `.dynamicTypeSize` caps on the logger and the dock still hold. At the
/// default setting it returns `size` unchanged, so nothing moves.
///
/// `maxScale` bounds the growth as a multiple of `size`. Captions and the
/// symbols beside them sit in pills and badges whose padding is fixed; without
/// a bound a 10 pt label would swell past its capsule at the largest sizes.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let monospacedDigits: Bool
    private let maxScale: CGFloat?

    init(size: CGFloat, weight: Font.Weight, design: Font.Design,
         monospacedDigits: Bool, relativeTo style: Font.TextStyle, maxScale: CGFloat?) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.size = size
        self.weight = weight
        self.design = design
        self.monospacedDigits = monospacedDigits
        self.maxScale = maxScale
    }

    private var font: Font {
        let points = maxScale.map { min(scaledSize, size * $0) } ?? scaledSize
        let base = Font.system(size: points, weight: weight, design: design)
        return monospacedDigits ? base.monospacedDigit() : base
    }

    func body(content: Content) -> some View {
        content.font(font)
    }
}

extension View {
    /// `Theme.rounded(size, weight:)` (or `Theme.number` with `monospacedDigits`)
    /// for a size that has no text style of its own, scaled along `style`.
    func gtFont(size: CGFloat, weight: Font.Weight, monospacedDigits: Bool = false,
                relativeTo style: Font.TextStyle, maxScale: CGFloat? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: .rounded,
                                  monospacedDigits: monospacedDigits,
                                  relativeTo: style, maxScale: maxScale))
    }

    /// The same for an SF Symbol that sits beside text, scaled along the style
    /// of that text. Symbols ignore the font design, so this keeps the default
    /// one and matches the `.font(.system(size:))` it replaces.
    func gtIcon(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle,
                maxScale: CGFloat? = nil) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: .default,
                                  monospacedDigits: false,
                                  relativeTo: style, maxScale: maxScale))
    }
}

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
                .gtFont(size: 14, weight: .medium, relativeTo: .subheadline)
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
            .gtIcon(size: 13, weight: .semibold, relativeTo: .footnote)
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
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
    /// The most the field will take, typed or stepped to. A number past it is
    /// refused rather than pulled down onto it: the ceiling is a guess about
    /// what nobody lifts, and storing it in place of a typo would be a load
    /// nobody lifted either. See `StepperEntry` for how each field's is picked.
    let maximum: Double

    /// Fixed steps: reps, seconds, anything that isn't loaded on a machine.
    init(title: String,
         value: Binding<Double>,
         step: Double,
         format: @escaping (Double) -> String,
         unit: String,
         maximum: Double = StepperEntry.defaultMaximum) {
        self.title = title
        self._value = value
        self.format = format
        self.unit = unit
        self.maximum = maximum
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
        // The same ceiling the Digital Crown stops at, so the phone can't
        // store a load the wrist would refuse to dial.
        self.maximum = scale.displayCeiling
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
                stepButton(icon: "minus", label: "Decrease \(title)", enabled: value > 0) {
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

                stepButton(icon: "plus", label: "Increase \(title)", enabled: canStepUp) {
                    // Checked again here as well as in the key's state: a held
                    // key repeats, and a repeat can land before the redraw that
                    // disables it.
                    guard canStepUp else { return }
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
                if let entered = StepperEntry.parse(draft, maximum: maximum) {
                    value = entered
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
                .gtFont(size: 10, weight: .semibold, relativeTo: .caption2, maxScale: 1.5)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var canStepUp: Bool { advance(value, 1) <= maximum }

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

    private func stepButton(icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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
        .accessibilityLabel(label)
    }
}

/// What a number typed into a stepper, or stepped to, is allowed to become.
///
/// Kept apart from the view, and on Foundation alone, so the test harness can
/// compile it without SwiftUI: every rule here exists because of a crash or a
/// stored value nobody lifted.
///
/// - A long run of digits parses to a `Double` far past `Int.max`, and
///   `Int(_:)` on that traps: the app dies mid-workout.
/// - `1e999`, pasted or typed on a hardware keyboard, parses to infinity. A
///   weight of infinity makes the backup encoder throw and the watch mirror
///   encode to nothing, so the export fails and the wrist goes quiet.
/// - 1000 typed for 100 is stored as a measured set, becomes a record, and
///   feeds the next suggestion.
///
/// Out-of-range input is refused, leaving the field as it was, rather than
/// clamped: a ceiling stored in place of a typo is as false as the typo.
enum StepperEntry {
    /// Reps in one set. A hundred sits well past any range a plan prescribes
    /// and past the longest bodyweight sets a gym session holds; the numbers
    /// above it that turn up are an extra digit on 10 or 12.
    static let maximumReps = 100

    /// Seconds in one timed set. An hour is past any hold or carry, and the
    /// timed sets this logs are measured in tens of seconds, so a longer one is
    /// a typo rather than an effort.
    static let maximumSeconds = 3_600

    /// For a fixed-step field that names no ceiling of its own. The largest of
    /// the counts above, so no field that relies on it refuses a real number,
    /// while still keeping infinity and overflow out.
    static let defaultMaximum = Double(maximumSeconds)

    /// The typed text as a number in `0...maximum`, or nil to leave the field
    /// alone. Reads the decimal comma, the Arabic-Indic and extended
    /// Arabic-Indic digits and the Arabic decimal separator, since the keypad
    /// types whatever the phone's region uses.
    ///
    /// Only those are read. A broader "any Unicode digit" rule also took
    /// fullwidth and other scripts' digits nobody's keypad offers, and
    /// `Double(_:)` on its own accepts hex and exponent forms, so the text is
    /// reduced to ASCII digits and one point before it is parsed.
    static func parse(_ text: String, maximum: Double) -> Double? {
        guard let ascii = asciiNumber(text), let number = Double(ascii) else { return nil }
        return bounded(number, maximum: maximum)
    }

    /// The typed text rewritten with ASCII digits and a "." separator, or nil
    /// if it holds anything else. Surrounding spaces are trimmed, but one
    /// inside the number is a refusal: "6 0" read as 60 would be a guess.
    static func asciiNumber(_ text: String) -> String? {
        var ascii = ""
        var points = 0
        for (index, scalar) in text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.enumerated() {
            switch scalar.value {
            case 0x2D where index == 0:
                // Kept so "-0" still reads as zero; `bounded` refuses the rest.
                ascii.append("-")
            case 0x30...0x39:
                ascii.unicodeScalars.append(scalar)
            case 0x0660...0x0669:
                ascii.unicodeScalars.append(Unicode.Scalar(0x30 + (scalar.value - 0x0660))!)
            case 0x06F0...0x06F9:
                ascii.unicodeScalars.append(Unicode.Scalar(0x30 + (scalar.value - 0x06F0))!)
            case 0x2E, 0x2C, 0x066B:
                points += 1
                ascii.append(".")
            default:
                return nil
            }
        }
        return points <= 1 && ascii.contains(where: \.isNumber) ? ascii : nil
    }

    /// A number in `0...maximum`, or nil. Negative zero comes back as zero so a
    /// field never shows "-0".
    static func bounded(_ value: Double, maximum: Double) -> Double? {
        guard value.isFinite, value >= 0, value <= maximum else { return nil }
        return value == 0 ? 0 : value
    }

    /// Whether a stepper may store `value` over `current`. Inside the range, or
    /// on the way down from a number stored before there was a ceiling: a field
    /// that refused every step down from 1000 kg would be stuck there.
    static func accepts(_ value: Double, maximum: Double, current: Double) -> Bool {
        value.isFinite && value >= 0 && (value <= maximum || value < current)
    }

    /// A stepper's value as a whole count, or nil to leave the count alone. The
    /// conversion is checked, never `Int(_:)` on a `Double` that could be
    /// anything.
    static func count(_ value: Double, maximum: Int, current: Int) -> Int? {
        guard accepts(value, maximum: Double(maximum), current: Double(current)) else { return nil }
        return Int(exactly: value.rounded(.down))
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
                    .gtFont(size: 10, weight: .semibold, relativeTo: .caption2, maxScale: 1.5)
                Image(systemName: "chevron.down")
                    .gtIcon(size: 7, weight: .bold, relativeTo: .caption2, maxScale: 1.5)
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
