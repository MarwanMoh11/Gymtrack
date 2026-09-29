import SwiftUI

/// The effort question for the set that was just logged, as a compact card in
/// the logger's own scroll, below Log set.
///
/// It takes nothing over. It used to replace the whole logger until it was
/// answered, skipped or ten seconds had gone by, which put a step between the
/// lifter and the next set of a drop set or a superset. Now Log set, the rest
/// and the next exercise are all where they were, there is no Skip because
/// there is nothing to dismiss, and an unanswered question records nothing.
struct WatchSetFeelView: View {
    let exerciseName: String
    let setNumber: Int
    let current: SetFeel?
    let onPick: (SetFeel) -> Void

    var body: some View {
        VStack(spacing: 5) {
            Text("How did \(exerciseName) set \(setNumber) feel?")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(SetFeel.allCases) { feel in
                    Button { onPick(feel) } label: {
                        Text(feel.label)
                            .font(Theme.rounded(14, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 38)
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
        }
    }
}
