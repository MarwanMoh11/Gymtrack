import SwiftUI

/// The coach's notes that are not plan edits. Shared by the review screen and
/// the Settings history so a proposal that is advice alone reads the same in
/// both, and never reads as an empty review.
struct CoachAdviceCard: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Coach's notes")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.textTertiary).frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(Theme.rounded(15, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("These don't change your plan.")
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .gtCard()
            }
        }
    }
}
