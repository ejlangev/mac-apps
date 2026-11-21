import AppKit
import Observation

/// Routes menu items and global shortcuts to the code that carries them out.
@Observable
final class AppController {
    static let shared = AppController()

    /// Actions whose shortcut the system refused, usually because another app owns it.
    private(set) var unavailableShortcuts: Set<CaptureAction> = []

    private init() {}

    func perform(_ action: CaptureAction) {
        guard Permissions.hasScreenRecording else {
            WindowManager.shared.showOnboarding()
            return
        }
        CaptureCoordinator.shared.start(action)
    }

    /// Registers every configured shortcut with the system.
    func applyShortcuts() {
        var failed: Set<CaptureAction> = []
        for action in CaptureAction.allCases {
            guard let shortcut = AppSettings.shared.shortcuts[action] else {
                HotkeyManager.shared.unregister(id: action.hotkeyID)
                continue
            }
            let registered = HotkeyManager.shared.register(id: action.hotkeyID, shortcut: shortcut) { [weak self] in
                self?.perform(action)
            }
            if !registered { failed.insert(action) }
        }
        unavailableShortcuts = failed
    }

    /// Changes or removes an action's shortcut. A shortcut can belong to only one action,
    /// so assigning it here takes it away from any other action that had it.
    func setShortcut(_ shortcut: Shortcut?, for action: CaptureAction) {
        var shortcuts = AppSettings.shared.shortcuts
        if let shortcut {
            for (other, existing) in shortcuts where other != action && existing == shortcut {
                shortcuts[other] = nil
            }
        }
        shortcuts[action] = shortcut
        AppSettings.shared.shortcuts = shortcuts
        applyShortcuts()
    }

    func resetShortcuts() {
        AppSettings.shared.shortcuts = AppSettings.defaultShortcuts
        applyShortcuts()
    }
}
