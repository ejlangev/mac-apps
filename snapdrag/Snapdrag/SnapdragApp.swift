import ServiceManagement
import SwiftUI

@main
struct SnapdragApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            // The icon turns into a stop symbol while a recording is running.
            Image(systemName: ScreenRecorder.shared.isRecording ? "stop.circle.fill" : "camera.viewfinder")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // `Snapdrag --register-login-item` turns on "open at login", reports the result and quits.
        // The install script uses it, because only the app itself can register as a login item.
        guard CommandLine.arguments.contains("--register-login-item") else { return }
        do {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            print("login item enabled: \(SMAppService.mainApp.status == .enabled)")
        } catch {
            print("login item failed: \(error.localizedDescription)")
        }
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        HotkeyManager.shared.install()
        AppController.shared.applyShortcuts()
        HistoryStore.shared.prune()

        #if DEBUG
        // Lets a script trigger an action for testing, without pressing keys.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.local.Snapdrag.debug.perform"), object: nil, queue: .main
        ) { notification in
            let name = notification.object as? String
            Task { @MainActor in
                if name == "cancel" {
                    OverlayCancellation.cancelActive?()
                } else if name == "saveLatest" {
                    if let capture = ThumbnailStack.shared.captures.last { _ = try? CaptureOutput.save(capture) }
                } else if name == "recordFlowTest" {
                    await RecordingController.shared.runSelfTest()
                } else if name == "recordTest" {
                    await RecordingSelfTest.run()
                } else if name == "ocrTest" {
                    await TextRecognizer.runSelfTest()
                } else if name == "annotationTest" {
                    AnnotationSelfTest.run()
                } else if name == "history" {
                    WindowManager.shared.showHistory()
                } else if name == "closeAll" {
                    ThumbnailStack.shared.removeAll()
                } else if let name, let action = CaptureAction(rawValue: name) {
                    AppController.shared.perform(action)
                }
            }
        }
        #endif

        if !AppSettings.shared.hasCompletedOnboarding || !Permissions.hasScreenRecording {
            WindowManager.shared.showOnboarding()
        }
    }
}

extension AppDelegate {
    /// A menu bar app shows no main menu, but without one the standard shortcuts
    /// (⌘C, ⌘V, ⌘A, ⌘W) wouldn't work in its windows and text fields.
    fileprivate func installMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}

/// The menu shown from the menu bar icon.
struct MenuContent: View {
    private let settings = AppSettings.shared

    var body: some View {
        ForEach(CaptureAction.allCases) { action in
            Button {
                AppController.shared.perform(action)
            } label: {
                if action == .record, ScreenRecorder.shared.isRecording {
                    Label("Stop Recording", systemImage: "stop.circle")
                } else {
                    Label(action.title, systemImage: action.symbol)
                }
            }
            .shortcutHint(settings.shortcuts[action])
        }

        Divider()

        Button("Capture History…") { WindowManager.shared.showHistory() }
            .keyboardShortcut("h")

        Divider()

        Button("Settings…") { WindowManager.shared.showSettings() }
            .keyboardShortcut(",")
        Button("Permissions & Setup…") { WindowManager.shared.showOnboarding() }

        Divider()

        Button("Quit Snapdrag") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private extension View {
    /// Shows the action's global shortcut next to its menu item, when it can be displayed.
    @ViewBuilder
    func shortcutHint(_ shortcut: Shortcut?) -> some View {
        if let shortcut, let key = shortcut.keyEquivalent {
            keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            self
        }
    }
}
