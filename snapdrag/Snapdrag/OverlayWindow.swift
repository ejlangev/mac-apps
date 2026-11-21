import AppKit

/// A borderless window covering one whole screen, above everything else,
/// used for selecting an area or picking a window.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen, opaque: Bool) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = opaque
        backgroundColor = opaque ? .black : .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows a set of overlay windows, waits for the user to finish, then restores the previous app.
/// `AreaSelector` and `WindowPicker` build on this.
@MainActor
class OverlaySession<Result> {
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var result: Result?
    private var previousApp: NSRunningApplication?

    init() {}

    /// Puts the windows on screen and suspends until `finish` is called.
    func run(_ windows: [OverlayWindow]) async -> Result? {
        self.windows = windows
        OverlayCancellation.cancelActive = { [weak self] in self?.finish(nil) }
        previousApp = NSWorkspace.shared.frontmostApplication

        NSApp.activate()
        for window in windows { window.orderFrontRegardless() }
        // Keyboard input (Escape) goes to the overlay under the pointer.
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        if let view = keyWindow?.initialFirstResponder ?? keyWindow?.contentView { keyWindow?.makeFirstResponder(view) }

        await withCheckedContinuation { continuation = $0 }
        return result
    }

    func finish(_ result: Result?) {
        guard let continuation else { return }
        self.continuation = nil
        OverlayCancellation.cancelActive = nil
        for window in windows { window.orderOut(nil) }
        windows = []
        if let previousApp, previousApp != .current { previousApp.activate() }
        self.result = result
        continuation.resume()
    }
}

/// Dismisses whichever overlay is on screen, as if the user pressed Escape.
enum OverlayCancellation {
    static var cancelActive: (() -> Void)?
}
