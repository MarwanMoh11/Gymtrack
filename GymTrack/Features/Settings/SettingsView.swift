import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = true

    @State private var settings = AppSettings.shared
    @State private var exportURL: URL?
    @State private var showingImporter = false
    @State private var showingWipeConfirm = false
    @State private var alert: AlertPayload?

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

                    Picker("Weight unit", selection: Binding(
                        get: { settings.weightUnit },
                        set: { settings.weightUnit = $0 }
                    )) {
                        ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                    }
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
        .presentationBackground(Theme.background)
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
