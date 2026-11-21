import AppKit

/// Runs a capture from start to finish: grab the screen, let the user choose, hand off the result.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    /// True while a capture is under way, so a second shortcut press doesn't start another.
    private var isBusy = false

    private init() {}

    func start(_ action: CaptureAction) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                switch action {
                case .area: try await captureArea()
                case .window: try await captureWindow()
                case .fullScreen: try await captureFullScreen()
                case .repeatArea: try await repeatLastArea()
                case .captureText: try await captureText()
                case .record: try await RecordingController.shared.toggle()
                }
            } catch {
                HUD.show("Capture failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
    }

    // MARK: Actions

    private func captureArea() async throws {
        let shots = try await ScreenCapturer.captureDisplays(NSScreen.screens)
        guard let selection = await AreaSelector().select(from: shots) else { return }
        guard let image = selection.shot.cropped(to: selection.rect) else { throw CaptureError.cropFailed }

        LastArea(displayID: selection.shot.screen.displayID, rect: selection.rect).save()
        try CaptureOutput.deliver(image, scale: selection.shot.scale)
    }

    private func captureWindow() async throws {
        guard let windowID = await WindowPicker().pick() else { return }
        // Give the highlight overlay a moment to leave the screen.
        try await Task.sleep(for: .milliseconds(80))
        var (image, scale) = try await ScreenCapturer.captureWindow(id: windowID)
        if AppSettings.shared.windowShadow {
            image = ImageEffects.addingShadow(to: image, scale: scale) ?? image
        }
        try CaptureOutput.deliver(image, scale: scale)
    }

    private func captureFullScreen() async throws {
        guard let screen = NSScreen.underMouse else { throw CaptureError.displayNotFound }
        let shot = try await ScreenCapturer.captureDisplay(screen)
        try CaptureOutput.deliver(shot.image, scale: shot.scale)
    }

    /// Select an area and copy the text in it. The image itself isn't kept.
    private func captureText() async throws {
        let shots = try await ScreenCapturer.captureDisplays(NSScreen.screens)
        guard let selection = await AreaSelector().select(from: shots) else { return }
        guard let image = selection.shot.cropped(to: selection.rect) else { throw CaptureError.cropFailed }
        await TextRecognizer.copyText(from: image)
    }

    private func repeatLastArea() async throws {
        guard let last = LastArea.load() else {
            HUD.show("No previous area yet — capture an area first", symbol: "arrow.clockwise")
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.displayID == last.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let shot = try await ScreenCapturer.captureDisplay(screen)
        guard let image = shot.cropped(to: last.rect) else { throw CaptureError.cropFailed }
        try CaptureOutput.deliver(image, scale: shot.scale)
    }
}

/// The most recent area selection, remembered between launches for "Repeat Last Area".
struct LastArea: Codable {
    let displayID: CGDirectDisplayID
    /// In points, measured from the display's top-left corner.
    let rect: CGRect

    private static let key = "lastArea"

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    static func load() -> LastArea? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LastArea.self, from: data)
    }
}
