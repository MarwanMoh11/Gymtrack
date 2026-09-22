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
    @State private var showingWipeConfirm = false
    @State private var alert: AlertPayload?

    /// "3 set up" — enough to say whether anything has been corrected without
    /// opening the screen.
    private var machineSummary: String {
        let count = LoadScaleBook.shared.overrides.count
        return count == 0 ? "All default" : "\(count) set up"
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

                Section("Feel") {
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

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Export a backup", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Restore from a backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything lives on this device — no account, no server. A backup is a single JSON file you can keep anywhere.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button(role: .destructive) {
                        showingWipeConfirm = true
                    } label: {
                        Label("Erase all data", systemImage: "trash")
                            .foregroundStyle(Theme.negative)
                    }
                    .disabled(!openSessions.isEmpty)
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
                }
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog("Erase everything?", isPresented: $showingWipeConfirm, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) { wipe() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every routine, session and record on this device is deleted. Export a backup first if you might want it back.")
            }
            .alert(item: $alert) { payload in
                Alert(title: Text(payload.title), message: Text(payload.message), dismissButton: .default(Text("OK")))
            }
        }
        .gtSheetBackground()
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

    private func exportBackup() {
        do {
            exportURL = try BackupService.export(context: context)
            Haptics.success()
        } catch {
            alert = AlertPayload(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try BackupService.restore(from: url, context: context)
                Haptics.success()
                alert = AlertPayload(title: "Restored", message: "Your routines and history are back.")
            } catch {
                // Report what actually went wrong — "couldn't be read" hid a
                // decode error behind a message about the file being invalid.
                alert = AlertPayload(title: "Restore failed", message: error.localizedDescription)
            }
        case .failure(let error):
            alert = AlertPayload(title: "Restore failed", message: error.localizedDescription)
        }
    }

    private func wipe() {
        do {
            try BackupService.wipe(context: context)
            hasOnboarded = false
            Haptics.warn()
            dismiss()
        } catch {
            alert = AlertPayload(title: "Couldn't erase", message: error.localizedDescription)
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
