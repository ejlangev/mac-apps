import AppKit
import SwiftUI

/// A button that records a new keyboard shortcut: click it, then press the keys.
/// Escape cancels. The small × removes the shortcut.
struct ShortcutRecorder: View {
    let shortcut: Shortcut?
    let onChange: (Shortcut?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording { stop() } else { start() }
            } label: {
                Text(isRecording ? "Press shortcut…" : (shortcut?.displayString ?? "None"))
                    .foregroundStyle(isRecording || shortcut == nil ? .secondary : .primary)
                    .frame(minWidth: 110)
            }
            .help(isRecording ? "Press Escape to cancel" : "Click, then press a new shortcut")

            Button {
                onChange(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove shortcut")
            .opacity(shortcut != nil && !isRecording ? 1 : 0)
            .disabled(shortcut == nil || isRecording)
        }
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        // Release our own shortcuts so pressing one records it instead of triggering it.
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        HotkeyManager.shared.resume()
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        if event.keyCode == 53 { // Escape
            stop()
            return
        }
        let flags = event.modifierFlags.intersection(Shortcut.allowedModifiers)
        let candidate = Shortcut(keyCode: keyCode, modifiers: flags.rawValue)
        // A global shortcut needs ⌘, ⌥ or ⌃ (or a function key), otherwise it would swallow normal typing.
        guard candidate.isFunctionKey || !flags.isDisjoint(with: [.command, .option, .control]) else {
            NSSound.beep()
            return
        }
        stop()
        onChange(candidate)
    }
}
