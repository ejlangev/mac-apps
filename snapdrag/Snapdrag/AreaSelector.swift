import AppKit

/// A rectangle the user dragged out on one display.
struct AreaSelection {
    let shot: DisplayShot
    /// In points, measured from the display's top-left corner.
    let rect: CGRect
    /// True when the user chose the whole display instead of dragging.
    var isFullScreen = false
}

/// Lets the user drag a rectangle over frozen images of the displays.
/// Freezing first means menus, hover states and video frames can't change mid-selection.
final class AreaSelector: OverlaySession<AreaSelection> {
    /// `hint` is shown at the top of each display until a drag begins.
    /// With `allowsFullScreen`, Return or Space chooses the whole display under the pointer.
    func select(from shots: [DisplayShot], hint: String? = nil, allowsFullScreen: Bool = false) async -> AreaSelection? {
        let windows = shots.map { shot in
            let window = OverlayWindow(screen: shot.screen, opaque: true)
            let size = shot.screen.frame.size

            // The frozen display sits in an image view; the selection view draws on top of it,
            // so moving the mouse never has to redraw the full-resolution image.
            let background = NSImageView(frame: CGRect(origin: .zero, size: size))
            background.image = NSImage(cgImage: shot.image, size: size)
            background.imageScaling = .scaleAxesIndependently

            let selectionView = AreaSelectionView(shot: shot) { [weak self] rect in
                self?.finish(rect.map { AreaSelection(shot: shot, rect: $0) })
            }
            selectionView.hint = hint
            if allowsFullScreen {
                selectionView.onFullScreen = { [weak self] in
                    let pointerScreen = NSScreen.underMouse
                    let chosen = shots.first { $0.screen == pointerScreen } ?? shot
                    self?.finish(AreaSelection(
                        shot: chosen, rect: CGRect(origin: .zero, size: chosen.screen.frame.size), isFullScreen: true
                    ))
                }
            }
            selectionView.autoresizingMask = [.width, .height]
            background.addSubview(selectionView)

            window.contentView = background
            window.initialFirstResponder = selectionView
            return window
        }
        return await run(windows)
    }
}

/// Draws the dimmed surround, the selection and the magnifier loupe over the frozen display.
private final class AreaSelectionView: NSView {
    private let shot: DisplayShot
    private let onFinish: (CGRect?) -> Void

    var hint: String?
    var onFullScreen: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var mouse: CGPoint?

    private static let minimumSize: CGFloat = 4

    init(shot: DisplayShot, onFinish: @escaping (CGRect?) -> Void) {
        self.shot = shot
        self.onFinish = onFinish
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Top-left origin, so view coordinates line up with image pixels.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selection: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x), y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x), height: abs(dragCurrent.y - dragStart.y)
        )
    }

    // MARK: Input

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x.rounded(), 0), bounds.width),
            y: min(max(point.y.rounded(), 0), bounds.height)
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        dragStart = location(of: event)
        dragCurrent = dragStart
        mouse = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = location(of: event)
        mouse = dragCurrent
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = location(of: event)
        if let selection, selection.width >= Self.minimumSize, selection.height >= Self.minimumSize {
            onFinish(selection)
        } else {
            // A plain click isn't a selection; keep waiting for a drag.
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = location(of: event)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStart == nil else { return }
        mouse = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onFinish(nil)
        } else if let onFullScreen, [36, 76, 49].contains(event.keyCode) { // Return, Enter, Space
            onFullScreen()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim everything outside the selection.
        context.setFillColor(NSColor.black.withAlphaComponent(selection == nil ? 0.2 : 0.4).cgColor)
        if let selection {
            context.addRect(bounds)
            context.addRect(selection)
            context.fillPath(using: .evenOdd)

            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
        } else {
            context.fill(bounds)
        }

        if selection == nil, let hint {
            let size = pillSize(for: hint)
            drawPill(hint, at: CGPoint(x: bounds.midX - size.width / 2, y: 72))
        }

        if let mouse {
            if AppSettings.shared.showMagnifier {
                drawLoupe(at: mouse, context: context)
            } else if let selection {
                // Without the magnifier, the selection size still follows the pointer.
                let text = "\(Int(selection.width)) × \(Int(selection.height))"
                var origin = CGPoint(x: mouse.x + 14, y: mouse.y + 14)
                let size = pillSize(for: text)
                if origin.x + size.width > bounds.maxX - 8 { origin.x = mouse.x - 14 - size.width }
                if origin.y + size.height > bounds.maxY - 8 { origin.y = mouse.y - 14 - size.height }
                drawPill(text, at: origin)
            }
        }
    }

    private static let pillAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private func pillSize(for text: String) -> CGSize {
        let textSize = NSAttributedString(string: text, attributes: Self.pillAttributes).size()
        return CGSize(width: textSize.width + 16, height: textSize.height + 6)
    }

    /// A small dark rounded label with white text; `origin` is its top-left corner.
    private func drawPill(_ text: String, at origin: CGPoint) {
        let pill = CGRect(origin: origin, size: pillSize(for: text))
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        NSAttributedString(string: text, attributes: Self.pillAttributes)
            .draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 3))
    }

    /// Draws a CGImage upright in this flipped view.
    private func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// A magnified circle next to the pointer, with the selection size (or pointer position) under it.
    private func drawLoupe(at point: CGPoint, context: CGContext) {
        let diameter: CGFloat = 128
        let zoom: CGFloat = 8
        let gap: CGFloat = 22
        let labelHeight: CGFloat = 26

        // Sit below-right of the pointer, flipping sides near the screen edges.
        var origin = CGPoint(x: point.x + gap, y: point.y + gap)
        if origin.x + diameter > bounds.maxX - 8 { origin.x = point.x - gap - diameter }
        if origin.y + diameter + labelHeight > bounds.maxY - 8 { origin.y = point.y - gap - diameter - labelHeight }
        let loupe = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))

        // The patch of screen being magnified, in points and then in image pixels.
        let sourceSide = diameter / zoom
        let source = CGRect(x: point.x - sourceSide / 2, y: point.y - sourceSide / 2, width: sourceSide, height: sourceSide)
        let scale = shot.scale
        let sourcePixels = CGRect(
            x: source.minX * scale, y: source.minY * scale,
            width: source.width * scale, height: source.height * scale
        )
        let imageBounds = CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height)
        let visiblePixels = sourcePixels.intersection(imageBounds).integral

        context.saveGState()
        context.addEllipse(in: loupe)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(loupe)
        if !visiblePixels.isEmpty, let patch = shot.image.cropping(to: visiblePixels) {
            // Near an edge only part of the patch exists; place it where it belongs in the circle.
            let unit = diameter / sourcePixels.width
            let target = CGRect(
                x: loupe.minX + (visiblePixels.minX - sourcePixels.minX) * unit,
                y: loupe.minY + (visiblePixels.minY - sourcePixels.minY) * unit,
                width: visiblePixels.width * unit, height: visiblePixels.height * unit
            )
            context.interpolationQuality = .none
            drawImage(patch, in: target, context: context)
        }
        // Crosshair marking the exact pixel under the pointer.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: loupe.midX, y: loupe.minY))
        context.addLine(to: CGPoint(x: loupe.midX, y: loupe.maxY))
        context.move(to: CGPoint(x: loupe.minX, y: loupe.midY))
        context.addLine(to: CGPoint(x: loupe.maxX, y: loupe.midY))
        context.strokePath()
        context.restoreGState()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: loupe.insetBy(dx: 1, dy: 1))
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: loupe.insetBy(dx: -0.5, dy: -0.5))

        // Label: selection size while dragging, pointer position otherwise.
        let text: String
        if let selection {
            text = "\(Int(selection.width)) × \(Int(selection.height))"
        } else {
            text = "\(Int(point.x)), \(Int(point.y))"
        }
        drawPill(text, at: CGPoint(x: loupe.midX - pillSize(for: text).width / 2, y: loupe.maxY + 6))
    }
}
