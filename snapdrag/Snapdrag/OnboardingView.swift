import Combine
import SwiftUI

/// First-run setup: grant Screen Recording and free up the system screenshot shortcuts.
struct OnboardingView: View {
    private let settings = AppSettings.shared

    @State private var hasScreenRecording = Permissions.hasScreenRecording
    @State private var didRequest = false

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Up Snapdrag")
                    .font(.title2.bold())
                Text("Snapdrag lives in the menu bar. Two things need your attention before it can capture.")
                    .foregroundStyle(.secondary)
            }

            step(
                number: 1,
                title: "Allow Screen Recording",
                detail: "macOS requires this permission for any app that captures the screen.",
                done: hasScreenRecording
            ) {
                if hasScreenRecording {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Button(didRequest ? "Open Privacy Settings…" : "Allow…") { requestAccess() }
                        if didRequest {
                            Button("Relaunch Snapdrag") { Permissions.relaunch() }
                        }
                    }
                    if didRequest {
                        Text("Turn on Snapdrag under Screen & System Audio Recording, then relaunch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            step(
                number: 2,
                title: "Turn off the built-in screenshot shortcuts",
                detail: "So ⇧⌘3, ⇧⌘4 and ⇧⌘5 reach Snapdrag: in Keyboard settings, click Keyboard Shortcuts…, choose Screenshots, and untick the entries. You can also pick different shortcuts in Snapdrag's settings instead.",
                done: false
            ) {
                HStack {
                    Button("Open Keyboard Settings…") { Permissions.openKeyboardSettings() }
                    Button("Change Snapdrag Shortcuts…") { WindowManager.shared.showSettings() }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    settings.hasCompletedOnboarding = true
                    WindowManager.shared.closeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onReceive(refresh) { _ in
            hasScreenRecording = Permissions.hasScreenRecording
        }
    }

    private func requestAccess() {
        if didRequest {
            Permissions.openScreenRecordingSettings()
        } else {
            didRequest = true
            // Shows the system prompt the first time only; the button then opens Settings directly.
            Permissions.requestScreenRecording()
        }
        hasScreenRecording = Permissions.hasScreenRecording
    }

    private func step(
        number: Int,
        title: String,
        detail: String,
        done: Bool,
        @ViewBuilder controls: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle.fill")
                .font(.title2)
                .foregroundStyle(done ? .green : .accentColor)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                controls()
            }
        }
    }
}
