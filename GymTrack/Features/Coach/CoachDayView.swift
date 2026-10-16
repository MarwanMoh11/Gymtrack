import SwiftUI

/// The daily check's note on one workout: the verdict, what went well, what to
/// watch and what to do next time. Opened from Today's quiet line. Read-only:
/// nothing here changes the plan or needs an answer, so closing it is all
/// there is to do.
struct CoachDayView: View {
    let note: CoachDayNote

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                section("Went well", note.wentWellLines)
                section("Watch", note.watchLines)
                section("Next time", note.nextTimeLines)
                Text("These don't change your plan.")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .gtScreenBackground()
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
                    .font(Theme.rounded(15, weight: .bold))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.workoutName().uppercased())
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            Text(note.verdict)
                .font(Theme.rounded(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Absent when the coach had nothing for it, rather than an empty card.
    @ViewBuilder private func section(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        CoachBulletLine(text: line)
                    }
                }
                .gtCard()
            }
        }
    }
}
