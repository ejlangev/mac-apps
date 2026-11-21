import AppKit

/// Lets the user point at a window and click to choose it.
final class WindowPicker: OverlaySession<CGWindowID> {
    /// A window that can be picked, with its frame in Quartz global coordinates.
    fileprivate struct Candidate {
        let id: CGWindowID
        let frame: CGRect
    }

    func pick() async -> CGWindowID? {
        let candidates = Self.candidates()
        let windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen, opaque: false)
            window.contentView = WindowPickerView(screen: screen, candidates: candidates) { [weak self] id in
                self?.finish(id)
            }
            return window
        }
        return await run(windows)
    }

    /// Normal app windows currently on screen, front to back.
    private static func candidates() -> [Candidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsInfo),
                  frame.width >= 40, frame.height >= 40
            else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            return Candidate(id: id, frame: frame)
        }
    }
}

/// Highlights the window under the pointer on one screen.
private final class WindowPickerView: NSView {
    private let screenFrame: CGRect // Quartz global coordinates
    private let candidates: [WindowPicker.Candidate]
    private let onFinish: (CGWindowID?) -> Void

    private var hovered: WindowPicker.Candidate?

    init(screen: NSScreen, candidates: [WindowPicker.Candidate], onFinish: @escaping (CGWindowID?) -> Void) {
        self.screenFrame = screen.quartzFrame
        self.candidates = candidates
        self.onFinish = onFinish
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHover(with: nil)
    }

    private func updateHover(with event: NSEvent?) {
        let local: CGPoint
        if let event {
            local = convert(event.locationInWindow, from: nil)
        } else if let window {
            local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        } else {
            return
        }
        let global = CGPoint(x: local.x + screenFrame.minX, y: local.y + screenFrame.minY)
        let found = bounds.contains(local) ? candidates.first { $0.frame.contains(global) } : nil
        if found?.id != hovered?.id {
            hovered = found
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) { updateHover(with: event) }
    override func mouseEntered(with event: NSEvent) { updateHover(with: event) }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        updateHover(with: event)
        // Clicking empty space (the desktop) does nothing; Escape cancels.
        if let hovered { onFinish(hovered.id) }
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let hovered else { return }
        let local = hovered.frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        let path = NSBezierPath(roundedRect: local, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}
