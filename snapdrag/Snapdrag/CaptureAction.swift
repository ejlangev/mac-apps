import AppKit
import Carbon.HIToolbox

/// Everything the user can trigger from the menu or a global shortcut.
enum CaptureAction: String, CaseIterable, Identifiable, Codable {
    case area
    case window
    case fullScreen
    case repeatArea
    case captureText
    case record

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: "Capture Area"
        case .window: "Capture Window"
        case .fullScreen: "Capture Full Screen"
        case .repeatArea: "Repeat Last Area"
        case .captureText: "Capture Text"
        case .record: "Record Screen"
        }
    }

    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullScreen: "display"
        case .repeatArea: "arrow.clockwise"
        case .captureText: "text.viewfinder"
        case .record: "record.circle"
        }
    }

    /// Stable number used to identify the action's global hotkey.
    var hotkeyID: UInt32 {
        switch self {
        case .area: 1
        case .window: 2
        case .fullScreen: 3
        case .repeatArea: 4
        case .captureText: 5
        case .record: 6
        }
    }

    var defaultShortcut: Shortcut {
        let cmdShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
        return switch self {
        case .fullScreen: Shortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: cmdShift)
        case .area: Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: cmdShift)
        case .window: Shortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: cmdShift)
        case .repeatArea: Shortcut(keyCode: UInt32(kVK_ANSI_6), modifiers: cmdShift)
        case .captureText: Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: cmdShift)
        case .record: Shortcut(keyCode: UInt32(kVK_ANSI_7), modifiers: cmdShift)
        }
    }
}
