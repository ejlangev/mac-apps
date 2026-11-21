import AppKit
import Carbon.HIToolbox

/// Registers system-wide keyboard shortcuts through Carbon's hotkey API,
/// which works without Accessibility permission.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private struct Binding {
        let shortcut: Shortcut
        let handler: () -> Void
    }

    private static let signature: OSType = 0x534E_4150 // "SNAP"

    private var bindings: [UInt32: Binding] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var isInstalled = false
    private var isSuspended = false

    /// Starts listening for hotkey presses. Call once at launch.
    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, nil, nil)
    }

    /// Binds a shortcut to a handler. Returns false when the system refuses it,
    /// which usually means another app already owns that shortcut.
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        bindings[id] = Binding(shortcut: shortcut, handler: handler)
        guard !isSuspended else { return true }
        return activate(id: id, shortcut: shortcut)
    }

    func unregister(id: UInt32) {
        bindings[id] = nil
        deactivate(id: id)
    }

    /// Temporarily releases every shortcut, so the settings window can record new ones.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        for id in Array(references.keys) { deactivate(id: id) }
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for (id, binding) in bindings { activate(id: id, shortcut: binding.shortcut) }
    }

    fileprivate func fire(id: UInt32) {
        bindings[id]?.handler()
    }

    @discardableResult
    private func activate(id: UInt32, shortcut: Shortcut) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else { return false }
        references[id] = reference
        return true
    }

    private func deactivate(id: UInt32) {
        if let reference = references.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
    }
}

/// C callback Carbon invokes when a registered hotkey is pressed.
nonisolated private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID
    )
    guard status == noErr else { return status }
    let id = hotkeyID.id
    Task { @MainActor in
        HotkeyManager.shared.fire(id: id)
    }
    return noErr
}
