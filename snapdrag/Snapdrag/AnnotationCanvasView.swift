import AppKit

/// The drawing surface of the annotation editor. Shows the screenshot scaled to fit,
/// and turns mouse and keyboard input into annotations on the document.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    let document: AnnotationDocument

    /// The shape being dragged out, before it is added to the document.
    private var draft: Annotation?
    private var cropDraft: CGRect?
    private var dragStart: CGPoint?
    private var lastMovePoint: CGPoint?
    private var didCheckpointMove = false

    private var textField: NSTextField?
    private var editingID: UUID?
    private var textOrigin: CGPoint = .zero
    private var textColor: NSColor = .systemRed
    private var textLineWidth: CGFloat = 4

    init(document: AnnotationDocument) {
        self.document = document
        super.init(frame: .zero)
        document.canvas = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    func toolDidChange() {
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch document.tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: Layout

    /// Where the visible part of the screenshot sits in the view, and how much it is scaled down.
    private var layout: (origin: CGPoint, zoom: CGFloat) {
        let visible = document.visibleRect
        let margin: CGFloat = 24
        let fit = min(
            (bounds.width - margin * 2) / visible.width,
            (bounds.height - margin * 2) / visible.height
        )
        let zoom = max(0.05, min(1, fit))
        let origin = CGPoint(
            x: ((bounds.width - visible.width * zoom) / 2).rounded(),
            y: ((bounds.height - visible.height * zoom) / 2).rounded()
        )
        return (origin, zoom)
    }

    private func documentPoint(_ viewPoint: CGPoint) -> CGPoint {
        let (origin, zoom) = layout
        let visible = document.visibleRect
        return CGPoint(
            x: (viewPoint.x - origin.x) / zoom + visible.minX,
            y: (viewPoint.y - origin.y) / zoom + visible.minY
        )
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint {
        documentPoint(convert(event.locationInWindow, from: nil))
    }

    private func viewPoint(_ point: CGPoint) -> CGPoint {
        let (origin, zoom) = layout
        let visible = document.visibleRect
        return CGPoint(
            x: (point.x - visible.minX) * zoom + origin.x,
            y: (point.y - visible.minY) * zoom + origin.y
        )
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        let zoom = layout.zoom
        return CGRect(origin: viewPoint(rect.origin), size: CGSize(width: rect.width * zoom, height: rect.height * zoom))
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let visible = document.visibleRect
        return CGPoint(
            x: min(max(point.x, visible.minX), visible.maxX),
            y: min(max(point.y, visible.minY), visible.maxY)
        )
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let (origin, zoom) = layout
        let visible = document.visibleRect

        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -visible.minX, y: -visible.minY)
        context.clip(to: visible)
        context.interpolationQuality = .high

        AnnotationRenderer.drawImage(document.baseImage, in: document.fullRect, context: context)
        for annotation in document.annotations where annotation.id != editingID {
            AnnotationRenderer.draw(annotation, in: context, document: document)
        }
        if let draft {
            AnnotationRenderer.draw(draft, in: context, document: document)
        }
        context.restoreGState()

        let imageFrame = viewRect(visible)
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: imageFrame.insetBy(dx: -0.5, dy: -0.5)).stroke()

        if let cropDraft {
            // Dim what the crop would remove.
            let keep = viewRect(cropDraft)
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.addRect(imageFrame)
            context.addRect(keep)
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(keep)
        }

        if let selected = document.selected, selected.id != editingID {
            let outline = NSBezierPath(rect: viewRect(selected.frame).insetBy(dx: -4, dy: -4))
            outline.lineWidth = 1.5
            outline.setLineDash([5, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if textField != nil {
            // A click outside the text box finishes the text and does nothing else.
            window?.makeFirstResponder(self)
            return
        }
        window?.makeFirstResponder(self)
        let point = documentPoint(event)

        switch document.tool {
        case .select:
            if let hit = document.annotations.last(where: { $0.hitTest(point) }) {
                if event.clickCount == 2, case .text = hit.kind {
                    beginTextEditing(at: hit.points.first ?? point, existing: hit)
                    return
                }
                document.selectedID = hit.id
                lastMovePoint = point
                didCheckpointMove = false
            } else {
                document.selectedID = nil
                lastMovePoint = nil
            }

        case .text:
            guard document.visibleRect.contains(point) else { return }
            beginTextEditing(at: point, existing: nil)

        case .counter:
            guard document.visibleRect.contains(point) else { return }
            document.add(Annotation(
                kind: .counter(document.nextCounter), points: [point],
                color: document.color, lineWidth: document.lineWidth
            ))

        case .crop:
            dragStart = clamped(point)
            cropDraft = nil

        default:
            guard let kind = document.tool.draggedKind else { return }
            let start = clamped(point)
            dragStart = start
            draft = Annotation(kind: kind, points: [start, start], color: document.color, lineWidth: document.lineWidth)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = documentPoint(event)

        switch document.tool {
        case .select:
            guard let id = document.selectedID, let last = lastMovePoint else { return }
            if !didCheckpointMove {
                document.checkpoint()
                didCheckpointMove = true
            }
            document.translate(id, by: CGSize(width: point.x - last.x, height: point.y - last.y))
            lastMovePoint = point

        case .crop:
            guard let start = dragStart else { return }
            let end = clamped(point)
            cropDraft = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
            needsDisplay = true

        case .pen, .highlighter:
            draft?.points.append(clamped(point))
            needsDisplay = true

        default:
            guard draft != nil, let start = dragStart else { return }
            var end = clamped(point)
            if event.modifierFlags.contains(.shift) {
                end = constrained(end, from: start, tool: document.tool)
            }
            draft?.points[1] = end
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            draft = nil
            cropDraft = nil
            dragStart = nil
            lastMovePoint = nil
            needsDisplay = true
        }

        if document.tool == .crop {
            if let cropDraft {
                document.setCrop(cropDraft)
                document.tool = .select
            }
            return
        }

        guard let draft else { return }
        // Ignore accidental clicks that didn't really draw anything.
        let isFreehand = draft.kind == .pen || draft.kind == .highlighter
        let extent = draft.frame
        let drewSomething = isFreehand
            ? draft.points.count > 2
            : hypot(draft.rect.width, draft.rect.height) > 3 && extent.width + extent.height > 3
        if drewSomething { document.add(draft) }
    }

    /// Shift held: squares for boxes and ellipses, 45° steps for lines and arrows.
    private func constrained(_ point: CGPoint, from start: CGPoint, tool: AnnotationTool) -> CGPoint {
        let dx = point.x - start.x, dy = point.y - start.y
        if tool == .line || tool == .arrow {
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            document.deleteSelected()
        case 53: // Escape
            draft = nil
            cropDraft = nil
            dragStart = nil
            document.selectedID = nil
            needsDisplay = true
        default:
            if modifiers.isEmpty,
               let character = event.charactersIgnoringModifiers?.lowercased().first,
               let tool = AnnotationTool.allCases.first(where: { $0.key == character }) {
                document.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: Text

    private func beginTextEditing(at origin: CGPoint, existing: Annotation?) {
        var existingText = ""
        if let existing, case .text(let string) = existing.kind { existingText = string }

        textOrigin = origin
        textColor = existing?.color ?? document.color
        textLineWidth = existing?.lineWidth ?? document.lineWidth
        editingID = existing?.id

        let zoom = layout.zoom
        let sample = Annotation(kind: .text(""), points: [origin], color: textColor, lineWidth: textLineWidth)
        let fontSize = sample.fontSize * zoom

        let field = NSTextField(string: existingText)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = textColor
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self

        // The field insets its text by 2 points; shift it so the typed text lines up with the final result.
        let position = viewPoint(origin)
        field.frame = CGRect(
            x: position.x - 2, y: position.y,
            width: max(80, bounds.maxX - position.x - 8), height: (fontSize * 1.3).rounded(.up) + 4
        )
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitText()
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()

        if let editingID {
            if text.isEmpty {
                document.delete(editingID)
            } else {
                document.setText(text, for: editingID)
            }
        } else if !text.isEmpty {
            document.add(Annotation(kind: .text(text), points: [textOrigin], color: textColor, lineWidth: textLineWidth))
        }
        editingID = nil
        needsDisplay = true

        // Give the keyboard back to the canvas so tool shortcuts keep working.
        Task { [weak self] in
            guard let self, textField == nil else { return }
            window?.makeFirstResponder(self)
        }
    }
}
