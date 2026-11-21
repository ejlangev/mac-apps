import Foundation
import Observation

enum ThumbnailCorner: String, CaseIterable, Identifiable, Codable {
    case bottomLeft, bottomRight

    var id: String { rawValue }
    var title: String { self == .bottomLeft ? "Bottom left" : "Bottom right" }
}

enum RecordingFormat: String, CaseIterable, Identifiable, Codable {
    case mp4, gif

    var id: String { rawValue }
    var title: String { self == .mp4 ? "MP4 video" : "GIF animation" }
}

enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case png, jpg, heic

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

/// User preferences, saved in UserDefaults as they change.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let shortcuts = "shortcuts"
        static let knownActions = "knownActions"
        static let copyToClipboard = "copyToClipboard"
        static let showThumbnail = "showThumbnail"
        static let thumbnailCorner = "thumbnailCorner"
        static let thumbnailAutoClose = "thumbnailAutoClose"
        static let historyRetentionDays = "historyRetentionDays"
        static let recordingFormat = "recordingFormat"
        static let recordFrameRate = "recordFrameRate"
        static let recordCursor = "recordCursor"
        static let recordSystemAudio = "recordSystemAudio"
        static let recordMicrophone = "recordMicrophone"
        static let showMagnifier = "showMagnifier"
        static let windowShadow = "windowShadow"
        static let imageFormat = "imageFormat"
        static let saveFolder = "saveFolder"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Global shortcut for each action. An action with no entry has no shortcut.
    var shortcuts: [CaptureAction: Shortcut] {
        didSet {
            let keyed = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(keyed), forKey: Key.shortcuts)
        }
    }

    var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Key.copyToClipboard) }
    }

    var showThumbnail: Bool {
        didSet { defaults.set(showThumbnail, forKey: Key.showThumbnail) }
    }

    var thumbnailCorner: ThumbnailCorner {
        didSet { defaults.set(thumbnailCorner.rawValue, forKey: Key.thumbnailCorner) }
    }

    /// Seconds before a thumbnail closes by itself. Zero means it stays until dismissed.
    var thumbnailAutoClose: Int {
        didSet { defaults.set(thumbnailAutoClose, forKey: Key.thumbnailAutoClose) }
    }

    var recordingFormat: RecordingFormat {
        didSet { defaults.set(recordingFormat.rawValue, forKey: Key.recordingFormat) }
    }

    /// Frames per second for recordings.
    var recordFrameRate: Int {
        didSet { defaults.set(recordFrameRate, forKey: Key.recordFrameRate) }
    }

    var recordCursor: Bool {
        didSet { defaults.set(recordCursor, forKey: Key.recordCursor) }
    }

    var recordSystemAudio: Bool {
        didSet { defaults.set(recordSystemAudio, forKey: Key.recordSystemAudio) }
    }

    var recordMicrophone: Bool {
        didSet { defaults.set(recordMicrophone, forKey: Key.recordMicrophone) }
    }

    /// Days a capture stays in the history before it is deleted. Zero keeps captures forever.
    var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: Key.historyRetentionDays) }
    }

    /// Whether area selection shows the magnified circle next to the pointer.
    var showMagnifier: Bool {
        didSet { defaults.set(showMagnifier, forKey: Key.showMagnifier) }
    }

    /// Whether window captures get a drop shadow.
    var windowShadow: Bool {
        didSet { defaults.set(windowShadow, forKey: Key.windowShadow) }
    }

    var imageFormat: ImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: Key.imageFormat) }
    }

    /// Where a capture goes when the user chooses to save it. Nothing is saved automatically.
    var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapdrag", isDirectory: true)
    }

    static var defaultShortcuts: [CaptureAction: Shortcut] {
        Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, $0.defaultShortcut) })
    }

    private init() {
        if let data = defaults.data(forKey: Key.shortcuts),
           let keyed = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            var loaded: [CaptureAction: Shortcut] = [:]
            for (name, shortcut) in keyed {
                if let action = CaptureAction(rawValue: name) { loaded[action] = shortcut }
            }
            // An action added in a newer version gets its default shortcut once,
            // unless something else already uses that key combination.
            let known = Set(defaults.stringArray(forKey: Key.knownActions) ?? ["area", "window", "fullScreen", "repeatArea", "captureText"])
            for action in CaptureAction.allCases where !known.contains(action.rawValue) {
                if !loaded.values.contains(action.defaultShortcut) { loaded[action] = action.defaultShortcut }
            }
            shortcuts = loaded
        } else {
            shortcuts = Self.defaultShortcuts
        }

        defaults.set(CaptureAction.allCases.map(\.rawValue), forKey: Key.knownActions)

        copyToClipboard = defaults.object(forKey: Key.copyToClipboard) as? Bool ?? true
        showThumbnail = defaults.object(forKey: Key.showThumbnail) as? Bool ?? true
        thumbnailCorner = defaults.string(forKey: Key.thumbnailCorner).flatMap(ThumbnailCorner.init) ?? .bottomRight
        thumbnailAutoClose = defaults.object(forKey: Key.thumbnailAutoClose) as? Int ?? 20
        recordingFormat = defaults.string(forKey: Key.recordingFormat).flatMap(RecordingFormat.init) ?? .mp4
        recordFrameRate = defaults.object(forKey: Key.recordFrameRate) as? Int ?? 30
        recordCursor = defaults.object(forKey: Key.recordCursor) as? Bool ?? true
        recordSystemAudio = defaults.bool(forKey: Key.recordSystemAudio)
        recordMicrophone = defaults.bool(forKey: Key.recordMicrophone)
        historyRetentionDays = defaults.object(forKey: Key.historyRetentionDays) as? Int ?? 7
        showMagnifier = defaults.bool(forKey: Key.showMagnifier)
        windowShadow = defaults.object(forKey: Key.windowShadow) as? Bool ?? true
        imageFormat = defaults.string(forKey: Key.imageFormat).flatMap(ImageFormat.init) ?? .png
        saveFolder = defaults.string(forKey: Key.saveFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultSaveFolder
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }
}
