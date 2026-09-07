import SwiftUI
import SwiftData

/// Three quick steps: name, units, starting routine. No account, no network —
/// the app is usable from the first tap.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    let onFinish: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var unit: WeightUnit = .kg
    @State private var selectedTemplate: PlanTemplate.ID = PlanTemplate.upperLower.id

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 24)
                .padding(.bottom, 8)

            TabView(selection: $step) {
                welcomeStep.tag(0)
                unitStep.tag(1)
                planStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .gtScreenBackground()
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Theme.accent : Color.white.opacity(0.15))
                    .frame(width: index == step ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 96, height: 96)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 8) {
                Text("GymTrack")
                    .font(Theme.rounded(34, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("Log every set. Watch the numbers move.")
                    .font(Theme.rounded(16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What should we call you?")
                    .font(Theme.rounded(14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Your name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.rounded(19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                    .submitLabel(.next)
                    .autocorrectionDisabled()
            }
            .padding(.top, 12)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var unitStep: some View {
        VStack(spacing: 22) {
            Spacer()
            stepHeader(icon: "scalemass.fill",
                       title: "Kilos or pounds?",
                       subtitle: "Everything you log is stored once and shown in the unit you pick. You can change it any time.")

            VStack(spacing: 12) {
                ForEach(WeightUnit.allCases) { option in
                    Button {
                        unit = option
                        Haptics.tick()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(Theme.rounded(17, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(option == .kg ? "Steps in 2.5 kg" : "Steps in 5 lb")
                                    .font(Theme.rounded(13, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: unit == option ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(unit == option ? Theme.accent : Theme.textTertiary)
                        }
                        .gtCard(padding: 18, background: unit == option ? Theme.surfaceRaised : Theme.surface)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var planStep: some View {
        VStack(spacing: 16) {
            stepHeader(icon: "calendar",
                       title: "Pick a starting routine",
                       subtitle: "Every exercise, set and rep is editable later — this is just a head start.")
                .padding(.top, 20)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(PlanTemplate.all) { template in
                        Button {
                            selectedTemplate = template.id
                            Haptics.tick()
                        } label: {
                            templateRow(template)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
    }

    private func templateRow(_ template: PlanTemplate) -> some View {
        let isSelected = selectedTemplate == template.id
        return HStack(spacing: 14) {
            Image(systemName: template.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? .black : Theme.accent)
                .frame(width: 44, height: 44)
                .background(isSelected ? Theme.accent : Theme.accentDim,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(template.summary)
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Pill(text: "\(template.daysPerWeek)×/week", color: Theme.accent)
                    Pill(text: template.level)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .gtCard(padding: 14, background: isSelected ? Theme.surfaceRaised : Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
        )
    }

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 62, height: 62)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(title)
                .font(Theme.rounded(26, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(Theme.rounded(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Button(step == 2 ? "Start training" : "Continue") {
                if step < 2 {
                    withAnimation { step += 1 }
                    Haptics.tick()
                } else {
                    finish()
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .font(Theme.rounded(14, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func finish() {
        AppSettings.shared.userName = name.trimmingCharacters(in: .whitespaces)
        AppSettings.shared.weightUnit = unit

        let template = PlanTemplate.all.first { $0.id == selectedTemplate } ?? PlanTemplate.upperLower
        template.materialise(in: context, makeActive: true)
        try? context.save()

        Haptics.success()
        onFinish()
    }
}
