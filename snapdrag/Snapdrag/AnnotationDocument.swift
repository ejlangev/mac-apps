import AppKit
import Observation

/// The state of one annotation editor: the screenshot, the marks drawn on it, and the undo history.
@Observable
final class AnnotationDocument {
    let baseImage: CGImage
    /// Pixels per point of the screenshot.
    let scale: CGFloat
    /// The whole screenshot, in points.
    let fullRect: CGRect

    private(set) var annotations: [Annotation] = [] { didSet { redraw() } }
    /// The part of the screenshot that is kept, or nil for all of it.
    private(set) var cropRect: CGRect? { didSet { redraw() } }
    var selectedID: UUID? { didSet { redraw() } }

    var tool: AnnotationTool = .arrow {
        didSet {
            if tool != .select { selectedID = nil }
            canvas?.toolDidChange()
        }
    }

    /// Colour for new marks. Changing it also recolours the selected mark.
    var color: NSColor = .systemRed {
        didSet {
            guard color != oldValue, let id = selectedID else { return }
            checkpoint()
            modify(id) { $0.color = color }
        }
    }

    /// Stroke width for new marks. Changing it also resizes the selected mark.
    var lineWidth: CGFloat = 4 {
        didSet {
            guard lineWidth != oldValue, let id = selectedID else { return }
            checkpoint()
            modify(id) { $0.lineWidth = lineWidth }
        }
    }

    private struct Snapshot {
        let annotations: [Annotation]
        let cropRect: CGRect?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    @ObservationIgnored weak var canvas: AnnotationCanvasView?
    @ObservationIgnored let effects = EffectCache()

    static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .black, .white,
    ]

    init(image: CGImage, scale: CGFloat) {
        baseImage = image
        self.scale = scale
        fullRect = CGRect(x: 0, y: 0, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    var visibleRect: CGRect { cropRect ?? fullRect }
    var selected: Annotation? { annotations.first { $0.id == selectedID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// The number the next counter should show.
    var nextCounter: Int {
        let used = annotations.compactMap { annotation -> Int? in
            if case .counter(let number) = annotation.kind { return number }
            return nil
        }
        return (used.max() ?? 0) + 1
    }

    // MARK: Editing

    /// Records the current state so the next change can be undone.
    func checkpoint() {
        undoStack.append(Snapshot(annotations: annotations, cropRect: cropRect))
        redoStack.removeAll()
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
    }

    /// Moves a mark. The caller takes a checkpoint once at the start of the drag.
    func translate(_ id: UUID, by delta: CGSize) {
        modify(id) { $0 = $0.translated(by: delta) }
    }

    func setText(_ text: String, for id: UUID) {
        checkpoint()
        modify(id) { $0.kind = .text(text) }
    }

    func delete(_ id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        checkpoint()
        annotations.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    func deleteSelected() {
        if let selectedID { delete(selectedID) }
    }

    func setCrop(_ rect: CGRect) {
        let clipped = rect.intersection(visibleRect).integral
        guard clipped.width >= 8, clipped.height >= 8 else { return }
        checkpoint()
        cropRect = clipped
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(annotations: annotations, cropRect: cropRect))
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(annotations: annotations, cropRect: cropRect))
        restore(next)
    }

    private func restore(_ snapshot: Snapshot) {
        annotations = snapshot.annotations
        cropRect = snapshot.cropRect
        if let selectedID, !annotations.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
    }

    private func modify(_ id: UUID, _ change: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        change(&annotations[index])
    }

    private func redraw() {
        canvas?.needsDisplay = true
    }
}
