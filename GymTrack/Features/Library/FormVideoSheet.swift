import SwiftUI
import SwiftData

/// A replacement link costs taps only when the lifter wants a different video.
struct FormVideoSheet: View {
    let exercise: CatalogExercise
    let records: [FormVideoRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(exercise: CatalogExercise, records: [FormVideoRecord]) {
        self.exercise = exercise
        self.records = records
        _draft = State(initialValue: FormVideos.video(for: exercise.id, records: records)?.link ?? "")
    }

    private var video: FormVideo? { FormVideo(link: draft) }
    private var hasOverride: Bool { FormVideos.override(for: exercise.id, in: records) != nil }
    private var resetLabel: String {
        FormVideos.suggestion(for: exercise.id) == nil ? "Remove this video" : "Use the suggested video"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("YouTube link")
                        TextField("Paste a YouTube link", text: $draft)
                            .font(Theme.rounded(15, weight: .medium))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("formVideo.link")
                        if !draft.isEmpty && video == nil {
                            Text("That isn't a YouTube video link.")
                                .font(Theme.rounded(12, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .gtCard()
                    if hasOverride {
                        Button(resetLabel) {
                            FormVideos.reset(exercise.id, context: context)
                            dismiss()
                        }
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("formVideo.reset")
                    }
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
                    Button("Save") {
                        guard let video else { return }
                        FormVideos.set(video, for: exercise.id, context: context)
                        Haptics.success()
                        dismiss()
                    }
                    .font(Theme.rounded(15, weight: .bold))
                    .disabled(video == nil)
                    .accessibilityIdentifier("formVideo.save")
                }
            }
        }
        .gtSheetBackground()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
