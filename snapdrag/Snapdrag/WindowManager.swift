import AppKit
import SwiftUI

/// Owns the app's regular windows. A menu bar app has no Dock icon,
/// so each window is created and brought forward by hand.
final class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var historyWindow: NSWindow?

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Snapdrag Settings", content: SettingsView())
        }
        present(settingsWindow)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(title: "Set Up Snapdrag", content: OnboardingView())
        }
        present(onboardingWindow)
    }

    func showHistory() {
        if historyWindow == nil {
            historyWindow = makeWindow(title: "Capture History", content: HistoryView(), resizable: true)
            historyWindow?.setContentSize(NSSize(width: 760, height: 520))
            historyWindow?.center()
            historyWindow?.setFrameAutosaveName("History")
        }
        HistoryStore.shared.prune()
        present(historyWindow)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }

    private func makeWindow(title: String, content: some View, resizable: Bool = false) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .resizable, .miniaturizable] : [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
