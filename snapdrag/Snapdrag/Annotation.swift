import AppKit

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rectangle, ellipse, pen, highlighter, text, counter, pixelate, blur, crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select and Move"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .counter: "Numbered Step"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop"
        case .crop: "crop"
        }
    }

    /// Single key that switches to this tool while the canvas has focus.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .counter: "n"
        case .pixelate: "x"
        case .blur: "b"
        case .crop: "c"
        }
    }

    /// The kind of annotation a drag with this tool creates, if any.
    var draggedKind: Annotation.Kind? {
        switch self {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .pen: .pen
        case .highlighter: .highlighter
        case .pixelate: .pixelate
        case .blur: .blur
        case .select, .text, .counter, .crop: nil
        }
    }
}

/// One mark drawn on a screenshot. Coordinates are in image points, measured from the top-left corner.
struct Annotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case arrow, line, rectangle, ellipse, pen, highlighter, pixelate, blur
        case text(String)
        case counter(Int)
    }

    var id = UUID()
    var kind: Kind
    /// Two points (start and end) for shapes and effects, the whole path for pen strokes,
    /// and a single anchor point for text and counters.
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat

    // MARK: Sizes derived from the stroke width

    var fontSize: CGFloat { 10 + lineWidth * 3.5 }
    var counterRadius: CGFloat { 9 + lineWidth * 1.75 }
    var highlighterWidth: CGFloat { max(14, lineWidth * 5) }

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: color]
    }

    // MARK: Geometry

    /// The rectangle spanned by the first and last points.
    var rect: CGRect {
        guard let first = points.first, let last = points.last else { return .zero }
        return CGRect(
            x: min(first.x, last.x), y: min(first.y, last.y),
            width: abs(last.x - first.x), height: abs(last.y - first.y)
        )
    }

    /// The area the annotation covers, used for the selection outline.
    var frame: CGRect {
        switch kind {
        case .text(let string):
            let size = NSAttributedString(string: string, attributes: textAttributes).size()
            return CGRect(origin: points.first ?? .zero, size: size)
        case .counter:
            let center = points.first ?? .zero
            return CGRect(
                x: center.x - counterRadius, y: center.y - counterRadius,
                width: counterRadius * 2, height: counterRadius * 2
            )
        case .pen, .highlighter:
            guard let first = points.first else { return .zero }
            var box = CGRect(origin: first, size: .zero)
            for point in points { box = box.union(CGRect(origin: point, size: .zero)) }
            let half = (kind == .highlighter ? highlighterWidth : lineWidth) / 2
            return box.insetBy(dx: -half, dy: -half)
        case .pixelate, .blur:
            return rect
        case .arrow, .line, .rectangle, .ellipse:
            return rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        }
    }

    /// Whether a click at `point` should select this annotation.
    func hitTest(_ point: CGPoint) -> Bool {
        let tolerance = max(8, lineWidth / 2 + 4)
        switch kind {
        case .text, .pixelate, .blur:
            return frame.insetBy(dx: -4, dy: -4).contains(point)
        case .counter:
            let center = points.first ?? .zero
            return hypot(point.x - center.x, point.y - center.y) <= counterRadius + 4
        case .arrow, .line:
            guard points.count >= 2 else { return false }
            return Self.distance(from: point, toSegment: points[0], points[1]) <= tolerance
        case .pen, .highlighter:
            let reach = kind == .highlighter ? max(tolerance, highlighterWidth / 2) : tolerance
            for index in points.indices.dropLast()
            where Self.distance(from: point, toSegment: points[index], points[index + 1]) <= reach {
                return true
            }
            return false
        case .rectangle:
            // Only the outline counts, so things inside a box can still be clicked.
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                && !rect.insetBy(dx: tolerance, dy: tolerance).contains(point)
        case .ellipse:
            let radiusX = rect.width / 2, radiusY = rect.height / 2
            guard radiusX > 0, radiusY > 0 else { return false }
            let normalized = hypot((point.x - rect.midX) / radiusX, (point.y - rect.midY) / radiusY)
            return abs(normalized - 1) * min(radiusX, radiusY) <= tolerance
        }
    }

    func translated(by delta: CGSize) -> Annotation {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        return copy
    }

    private static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}
