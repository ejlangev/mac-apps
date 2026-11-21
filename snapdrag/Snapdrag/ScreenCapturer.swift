import AppKit
import ScreenCaptureKit

/// A still image of one display, taken at full pixel resolution.
struct DisplayShot {
    let screen: NSScreen
    let image: CGImage

    /// Pixels per point.
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }

    /// Cuts out a rectangle given in points, measured from the display's top-left corner.
    func cropped(to rect: CGRect) -> CGImage? {
        let pixels = CGRect(
            x: (rect.minX * scale).rounded(), y: (rect.minY * scale).rounded(),
            width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded()
        )
        return image.cropping(to: pixels)
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "That display is no longer available."
        case .windowNotFound: "That window is no longer available."
        case .cropFailed: "The selected area couldn't be captured."
        }
    }
}

/// Takes screenshots with ScreenCaptureKit.
enum ScreenCapturer {
    /// Captures the given displays. Snapdrag's own windows are left out of the picture.
    static func captureDisplays(_ screens: [NSScreen]) async throws -> [DisplayShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        var shots: [DisplayShot] = []
        for screen in screens {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration(for: filter)
            )
            shots.append(DisplayShot(screen: screen, image: image))
        }
        guard !shots.isEmpty else { throw CaptureError.displayNotFound }
        return shots
    }

    static func captureDisplay(_ screen: NSScreen) async throws -> DisplayShot {
        try await captureDisplays([screen])[0]
    }

    /// Captures a single window by itself, with transparent corners, even if other windows overlap it.
    /// Returns the image and its pixels-per-point scale.
    static func captureWindow(id: CGWindowID) async throws -> (image: CGImage, scale: CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = configuration(for: filter)
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, CGFloat(filter.pointPixelScale))
    }

    private static func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return config
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// The screen the mouse pointer is on.
    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) } ?? main
    }

    /// This screen's frame in Quartz global coordinates (origin at the top-left of the primary display).
    var quartzFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
