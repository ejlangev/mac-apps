import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutSettings() }
            Tab("Saving", systemImage: "folder") { SavingSettings() }
            Tab("Recording", systemImage: "record.circle") { RecordingSettings() }
            Tab("History", systemImage: "clock.arrow.circlepath") { HistorySettings() }
        }
        .frame(width: 480, height: 580)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("After a capture") {
                Toggle("Show floating thumbnail", isOn: $settings.showThumbnail)
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
            }

            Section("Thumbnail") {
                Picker("Position", selection: $settings.thumbnailCorner) {
                    ForEach(ThumbnailCorner.allCases) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
                Picker("Close automatically", selection: $settings.thumbnailAutoClose) {
                    Text("Never").tag(0)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 20 seconds").tag(20)
                    Text("After 30 seconds").tag(30)
                    Text("After 1 minute").tag(60)
                }
            }
            .disabled(!settings.showThumbnail)

            Section("Area captures") {
                Toggle("Show magnifier while selecting", isOn: $settings.showMagnifier)
            }

            Section("Window captures") {
                Toggle("Add a shadow around the window", isOn: $settings.windowShadow)
            }

            Section {
                Toggle("Open Snapdrag at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Couldn't change the login setting: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    private let settings = AppSettings.shared
    private let controller = AppController.shared

    var body: some View {
        Form {
            Section {
                ForEach(CaptureAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(shortcut: settings.shortcuts[action]) { newValue in
                            controller.setShortcut(newValue, for: action)
                        }
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                        if controller.unavailableShortcuts.contains(action) {
                            Text("Another app is already using this shortcut.")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⇧⌘3, ⇧⌘4 and ⇧⌘5 only reach Snapdrag after you turn off the built-in macOS screenshot shortcuts.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Open Keyboard Settings…") { Permissions.openKeyboardSettings() }
                        Spacer()
                        Button("Restore Defaults") { controller.resetShortcuts() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Saving

private struct SavingSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Save folder") {
                    HStack {
                        Text(settings.saveFolder.path(percentEncoded: false).abbreviatingHomeDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseFolder() }
                    }
                }
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
            } footer: {
                Text("Captures are never saved automatically. This folder is used only when you choose Save.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolder = url
        }
    }
}

// MARK: - Recording

private struct RecordingSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Format", selection: $settings.recordingFormat) {
                    ForEach(RecordingFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Picker("Frame rate", selection: $settings.recordFrameRate) {
                    Text("30 frames per second").tag(30)
                    Text("60 frames per second").tag(60)
                }
                Toggle("Show the mouse pointer", isOn: $settings.recordCursor)
            } footer: {
                Text("GIFs have no sound, play at 12 frames per second, and are scaled down to keep the file size reasonable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Sound") {
                Toggle("Record computer audio", isOn: $settings.recordSystemAudio)
                Toggle("Record microphone", isOn: $settings.recordMicrophone)
            }
            .disabled(settings.recordingFormat == .gif)
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

private struct HistorySettings: View {
    @Bindable private var settings = AppSettings.shared
    private let store = HistoryStore.shared
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Picker("Keep captures for", selection: $settings.historyRetentionDays) {
                    Text("1 day").tag(1)
                    Text("1 week").tag(7)
                    Text("1 month").tag(30)
                    Text("Forever").tag(0)
                }
                .onChange(of: settings.historyRetentionDays) { store.prune() }
            } footer: {
                Text("Older captures are deleted from the history automatically. Captures you saved to a folder are never touched.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("In history") {
                    Text("\(store.items.count) captures, \(Int64(store.totalBytes).formatted(.byteCount(style: .file)))")
                }
                HStack {
                    Button("Show History…") { WindowManager.shared.showHistory() }
                    Spacer()
                    Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                        .disabled(store.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { store.reload() }
        .confirmationDialog(
            "Delete all \(store.items.count) captures from the history?",
            isPresented: $isConfirmingClear
        ) {
            Button("Delete All", role: .destructive) { store.clear() }
        } message: {
            Text("This can't be undone. Captures you saved to a folder are not affected.")
        }
    }
}

private extension String {
    /// Replaces the home folder prefix with "~" for display.
    var abbreviatingHomeDirectory: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
