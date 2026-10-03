import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var openSessions: [WorkoutSession]

    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = true

    @State private var settings = AppSettings.shared
    @State private var exportURL: URL?
    @State private var showingImporter = false
    @State private var showingRestoreConfirm = false
    @State private var showingWipeConfirm = false
    /// Counted when the erase dialog opens, so its Health button can say how
    /// many workouts it would remove, and is left out when there are none.
    @State private var linkedHealthWorkouts = 0
    @State private var alert: AlertPayload?
    @State private var finishEraseAfterAlert = false
    /// The backup, restore or erase that is running, or `nil`. Set before the
    /// work starts and cleared when it ends, however it ends, so a second one
    /// can't be started on top of it and the sheet can say what it is doing.
    @State private var running: DataTask?
    /// How far the running task is, from 0 to 1, or `nil` before it has said.
    /// The backup and the restore work in slices and report between them; the
    /// bar fills as they go, and until the first report the row shows a spinner.
    @State private var fraction: Double?

    private enum DataTask {
        case exporting, restoring, erasing

        var label: String {
            switch self {
            case .exporting: "Preparing your backup"
            case .restoring: "Restoring your backup"
            case .erasing: "Erasing your data"
            }
        }
    }

    private var isBusy: Bool { running != nil }

    /// "3 set up" — enough to say whether anything has been corrected without
    /// opening the screen.
    private var machineSummary: String {
        let count = LoadScaleBook.shared.overrides.count
        return count == 0 ? "All default" : "\(count) set up"
    }

    /// The row exists only for a lifter the coach has reached: a proposal, a
    /// decision, or a file that arrived and could not be read. Anyone else has
    /// no way to tell the feature is there.
    private var showsPlanReview: Bool {
        let coach = CoachInbox.shared
        return coach.proposal != nil || coach.latestDecision != nil || coach.unreadableReason != nil
    }

    private var planReviewSummary: String {
        let coach = CoachInbox.shared
        if coach.showsOnToday { return "Ready" }
        if coach.unreadableReason != nil { return "Can't be read" }
        guard let decision = coach.latestDecision else { return "Nothing to apply" }
        return decision.decidedAt.formatted(.dateTime.month(.abbreviated).day())
    }

    private struct AlertPayload: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Optional", text: Binding(
                            get: { settings.userName },
                            set: { settings.userName = $0 }
                        ))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Weight unit", selection: Binding(
                        get: { settings.weightUnit },
                        set: { settings.weightUnit = $0 }
                    )) {
                        ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                    }

                    NavigationLink {
                        MachineWeightsView()
                    } label: {
                        HStack {
                            Label("Machine weights", systemImage: "slider.horizontal.3")
                            Spacer()
                            Text(machineSummary)
                                .font(Theme.rounded(13, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                } header: {
                    Text("Weights")
                } footer: {
                    Text("A machine that disagrees with this — a stack stamped in pounds, or one that jumps in fifteens — can be put right on its own, from the unit under the weight while you log it.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Start timer after each set", isOn: Binding(
                        get: { settings.restTimerAutoStart },
                        set: { settings.restTimerAutoStart = $0 }
                    ))
                    .tint(Theme.accent)

                    Picker("Default rest", selection: Binding(
                        get: { settings.defaultRestSeconds },
                        set: { settings.defaultRestSeconds = $0 }
                    )) {
                        ForEach([45, 60, 90, 120, 150, 180], id: \.self) { seconds in
                            Text(seconds >= 60 ? "\(seconds / 60)m\(seconds % 60 == 0 ? "" : " \(seconds % 60)s")" : "\(seconds)s")
                                .tag(seconds)
                        }
                    }
                } header: {
                    Text("Rest timer")
                } footer: {
                    Text("Exercises in your routine can override this individually.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Rate each set", isOn: Binding(
                        get: { settings.trackRPE },
                        set: { settings.trackRPE = $0 }
                    ))
                    .tint(Theme.accent)
                } header: {
                    Text("Effort")
                } footer: {
                    Text("While you rest, the timer bar asks how the set felt — Easy, Solid, Hard or All out. Answer Easy after clearing a rep range and it offers the next rung on that machine there and then, and earns two steps up next session instead of one; answer All out after falling short and it stops suggesting a deload it can tell you don't need. Skipping the question leaves everything exactly as it is.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Haptics", isOn: Binding(
                        get: { settings.hapticsEnabled },
                        set: { settings.hapticsEnabled = $0 }
                    ))
                    .tint(Theme.accent)

                    Toggle("Keep screen awake while training", isOn: Binding(
                        get: { settings.keepScreenAwake },
                        set: { settings.keepScreenAwake = $0 }
                    ))
                    .tint(Theme.accent)
                } header: {
                    Text("Feel")
                } footer: {
                    Text("Keeps the phone from locking while a workout is running and GymTrack is on screen. With no workout running, or once you leave the app, the phone locks on its usual timer.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        HealthWatchSettingsView()
                    } label: {
                        HStack {
                            Label("Health & Watch", systemImage: "heart.text.square.fill")
                            Spacer()
                            Text(connectionSummary)
                                .font(Theme.rounded(13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } footer: {
                    Text("Sessions in Health, heart rate back from your watch, and logging from your wrist.")
                }
                .listRowBackground(Theme.surface)

                if showsPlanReview {
                    Section {
                        NavigationLink {
                            CoachHistoryView()
                        } label: {
                            HStack {
                                Label("Plan review", systemImage: "checklist")
                                Spacer()
                                Text(planReviewSummary)
                                    .font(Theme.rounded(13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    } footer: {
                        Text("What your coach suggested, what you decided, and how it went.")
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export a backup", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isBusy)

                    Button {
                        showingRestoreConfirm = true
                    } label: {
                        Label("Restore from a backup", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isBusy)

                    if let running {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                if fraction == nil { ProgressView() }
                                Text(running.label)
                                    .gtFont(size: 14, weight: .medium, relativeTo: .subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let fraction { ProgressView(value: fraction) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything lives on this device — no account, no server. A backup is a single JSON file you can keep anywhere.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button(role: .destructive) {
                        linkedHealthWorkouts = BackupService.linkedHealthWorkoutCount(context: context)
                        showingWipeConfirm = true
                    } label: {
                        Label("Erase all data", systemImage: "trash")
                            .foregroundStyle(Theme.negative)
                    }
                    .disabled(!openSessions.isEmpty || isBusy)
                } footer: {
                    if !openSessions.isEmpty {
                        Text("Finish or discard the workout that's running before erasing data.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Exercises", value: "\(ExerciseCatalog.shared.all.count)")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .gtScreenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.rounded(15, weight: .bold))
                        .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            // Asked before the picker because picking a file is the last step:
            // the restore runs the moment one is chosen, and it replaces
            // everything in GymTrack.
            .confirmationDialog("Replace everything with a backup?", isPresented: $showingRestoreConfirm,
                                titleVisibility: .visible) {
                Button("Choose a backup", role: .destructive) { showingImporter = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every routine, session and record on this device is replaced by the backup's, and sessions the backup doesn't have are deleted. Workouts in Apple Health are left as they are.")
            }
            // Removing from Health is its own button, never a side effect of
            // erasing: it reaches every device on the account, and the backup
            // this dialog recommends holds only each workout's ID.
            .confirmationDialog("Erase everything?", isPresented: $showingWipeConfirm, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) { wipe(removingHealthWorkouts: false) }
                if linkedHealthWorkouts > 0 {
                    Button(removeFromHealthLabel, role: .destructive) { wipe(removingHealthWorkouts: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(wipeMessage)
            }
            .alert(item: $alert) { payload in
                Alert(title: Text(payload.title), message: Text(payload.message), dismissButton: .default(Text("OK")) {
                    if finishEraseAfterAlert {
                        finishEraseAfterAlert = false
                        hasOnboarded = false
                        dismiss()
                    }
                })
            }
        }
        .gtSheetBackground()
    }

    private var removeFromHealthLabel: String {
        let noun = linkedHealthWorkouts == 1 ? "workout" : "workouts"
        return "Erase and remove \(linkedHealthWorkouts) \(noun) from Health"
    }

    private var wipeMessage: String {
        let local = "Every routine, session and record on this device is deleted. Export a backup first if you might want it back."
        guard linkedHealthWorkouts > 0 else { return local }
        return local + "\n\n\"Erase all data\" keeps the workouts GymTrack saved to Apple Health. Removing them from Health as well deletes them on every device that shares your Health data through iCloud, and no backup can bring them back."
    }

    /// A one-word read on the integration, so the row says something without
    /// being opened.
    private var connectionSummary: String {
        let watchReady = WatchBridge.shared.isLinked
        let healthOn = settings.healthEnabled && HealthKitService.shared.hasRequestedAuthorization
        switch (healthOn, watchReady) {
        case (true, true): return "Health · Watch"
        case (true, false): return "Health"
        case (false, true): return "Watch"
        case (false, false): return "Off"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    // MARK: - Actions

    /// The state change has to reach the screen before the main-actor part of
    /// the work starts, or the spinner would appear only after the freeze it
    /// is there to explain. Returning to the run loop for a frame is enough.
    private func showProgress(_ task: DataTask) async {
        fraction = nil
        running = task
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    private func exportBackup() {
        guard !isBusy else { return }
        Task { @MainActor in
            await showProgress(.exporting)
            defer { running = nil; fraction = nil }
            do {
                exportURL = try await BackupService.exportOffMain(context: context,
                                                                   progress: { fraction = $0 })
                Haptics.success()
            } catch {
                alert = AlertPayload(title: "Export failed", message: error.localizedDescription)
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard !isBusy else { return }
            Task { @MainActor in
                await showProgress(.restoring)
                defer { running = nil; fraction = nil }
                do {
                    try await BackupService.restoreOffMain(from: url, context: context,
                                                           progress: { fraction = $0 })
                    Haptics.success()
                    alert = AlertPayload(title: "Restored", message: "Your routines and history are back.")
                } catch {
                    // Report what actually went wrong: "couldn't be read" hid a
                    // decode error behind a message about the file being invalid.
                    alert = AlertPayload(title: "Restore failed", message: error.localizedDescription)
                }
            }
        case .failure(let error):
            alert = AlertPayload(title: "Restore failed", message: error.localizedDescription)
        }
    }

    private func wipe(removingHealthWorkouts: Bool) {
        guard !isBusy else { return }
        Task { @MainActor in
            await showProgress(.erasing)
            defer { running = nil; fraction = nil }
            do {
                let cleanup = try await BackupService.wipe(context: context,
                                                           removingHealthWorkouts: removingHealthWorkouts)
                Haptics.warn()
                if let cleanup, !cleanup.isComplete {
                    let count = cleanup.failedIDs.count
                    let noun = count == 1 ? "workout" : "workouts"
                    finishEraseAfterAlert = true
                    alert = AlertPayload(title: "Local data erased; Health cleanup incomplete",
                                         message: "We could not confirm removal of \(count) \(noun) from Apple Health. Check Health access or remove them in Health.")
                } else {
                    hasOnboarded = false
                    dismiss()
                }
            } catch {
                alert = AlertPayload(title: "Couldn't erase", message: error.localizedDescription)
            }
        }
    }
}

// `sheet(item:)` needs the URL to be Identifiable.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Bridges UIActivityViewController for sharing the backup file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
