import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key plus modifiers, stored by hardware key code so it works on any keyboard layout.
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    /// Raw `NSEvent.ModifierFlags`, limited to ⌘ ⌥ ⌃ ⇧.
    var modifiers: UInt

    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.allowedModifiers)
    }

    /// Modifier mask in the form Carbon's hotkey API expects.
    var carbonModifiers: UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    /// For example "⇧⌘4".
    var displayString: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    /// A SwiftUI key equivalent, when the key is a single printable character.
    var keyEquivalent: KeyEquivalent? {
        guard Self.specialKeyNames[keyCode] == nil else { return nil }
        let name = Self.keyName(for: keyCode).lowercased()
        guard name.count == 1, let character = name.first else { return nil }
        return KeyEquivalent(character)
    }

    var isFunctionKey: Bool { Self.functionKeyCodes.contains(keyCode) }

    // MARK: Key names

    static let functionKeyCodes: Set<UInt32> = Set(
        [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
            .map { UInt32($0) }
    )

    private static let specialKeyNames: [UInt32: String] = {
        let names: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return Dictionary(uniqueKeysWithValues: names.map { (UInt32($0.key), $0.value) })
    }()

    static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        return translatedKeyName(for: keyCode) ?? "Key \(keyCode)"
    }

    /// Asks the current keyboard layout which character a key produces.
    private static func translatedKeyName(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name.uppercased()
    }
}
