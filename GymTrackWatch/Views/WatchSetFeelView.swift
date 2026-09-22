import SwiftUI

/// The just-finished set gets the first glance; the rest keeps counting behind it.
struct WatchSetFeelView: View {
    let exerciseName: String
    let setNumber: Int
    let current: SetFeel?
    let onPick: (SetFeel) -> Void
    let onSkip: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("How did it feel?")
                    .font(Theme.rounded(17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("\(exerciseName) · Set \(setNumber)")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SetFeel.allCases) { feel in
                    Button { onPick(feel) } label: {
                        VStack(spacing: 2) {
                            Text(feel.label)
                                .font(Theme.rounded(14, weight: .heavy))
                            Text(feel.detail)
                                .font(Theme.rounded(10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(feel.tint)
                        .background(feel.tint.opacity(current == feel ? 0.3 : 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(feel.tint.opacity(current == feel ? 0.8 : 0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(feel.label). \(feel.spokenDetail)")
                    .accessibilityAddTraits(current == feel ? [.isSelected] : [])
                }
            }

            Button(current == nil ? "Skip" : "Done", action: onSkip)
                .buttonStyle(WatchQuietButtonStyle(tint: Theme.textSecondary, size: 12))
            Button("Undo set", action: onUndo)
                .buttonStyle(WatchQuietButtonStyle(tint: Theme.textTertiary, size: 11))
        }
    }
}
