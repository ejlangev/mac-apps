import AppKit
import CoreImage

/// Draws a screenshot and its annotations. The same code paints the editor canvas and the exported image,
/// so what you see is what you get. Every context it draws into has a top-left origin with units in image points.
enum AnnotationRenderer {
    /// Produces the final image at full pixel resolution, cropped if a crop is set.
    static func render(_ document: AnnotationDocument) -> CGImage? {
        let visible = document.visibleRect
        let scale = document.scale
        let width = Int((visible.width * scale).rounded())
        let height = Int((visible.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: document.baseImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Flip to a top-left origin, scale points to pixels, and shift the crop to the corner.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -visible.minX, y: -visible.minY)
        context.interpolationQuality = .high

        drawImage(document.baseImage, in: document.fullRect, context: context)
        for annotation in document.annotations {
            draw(annotation, in: context, document: document)
        }
        return context.makeImage()
    }

    /// Draws a CGImage upright in a top-left-origin context.
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    static func draw(_ annotation: Annotation, in context: CGContext, document: AnnotationDocument) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .line:
            guard annotation.points.count >= 2 else { return }
            context.move(to: annotation.points[0])
            context.addLine(to: annotation.points[1])
            context.strokePath()

        case .arrow:
            guard annotation.points.count >= 2 else { return }
            drawArrow(from: annotation.points[0], to: annotation.points[1], width: annotation.lineWidth, context: context)

        case .rectangle:
            context.stroke(annotation.rect)

        case .ellipse:
            context.strokeEllipse(in: annotation.rect)

        case .pen:
            addSmoothPath(through: annotation.points, to: context)
            context.strokePath()

        case .highlighter:
            context.setLineWidth(annotation.highlighterWidth)
            context.setLineCap(.butt)
            context.setStrokeColor(annotation.color.withAlphaComponent(0.4).cgColor)
            context.setBlendMode(.multiply)
            addSmoothPath(through: annotation.points, to: context)
            context.strokePath()

        case .text(let string):
            drawText(
                NSAttributedString(string: string, attributes: annotation.textAttributes),
                at: annotation.points.first ?? .zero, context: context
            )

        case .counter(let number):
            let frame = annotation.frame
            context.fillEllipse(in: frame)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: frame.insetBy(dx: 0.75, dy: 0.75))
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: annotation.counterRadius * 1.1, weight: .bold),
                .foregroundColor: annotation.color.isLight ? NSColor.black : NSColor.white,
            ])
            let size = label.size()
            drawText(label, at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), context: context)

        case .pixelate, .blur:
            if let effect = document.effects.image(for: annotation, document: document) {
                drawImage(effect.image, in: effect.rect, context: context)
            }
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return }
        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let headLength = min(max(12, width * 4.5), length)
        let headHalfWidth = headLength * 0.55
        let base = CGPoint(x: end.x - direction.x * headLength, y: end.y - direction.y * headLength)
        let normal = CGPoint(x: -direction.y, y: direction.x)

        // The shaft stops inside the head so its round cap doesn't poke through the tip.
        context.move(to: start)
        context.addLine(to: CGPoint(x: base.x + direction.x * headLength * 0.2, y: base.y + direction.y * headLength * 0.2))
        context.strokePath()

        context.move(to: end)
        context.addLine(to: CGPoint(x: base.x + normal.x * headHalfWidth, y: base.y + normal.y * headHalfWidth))
        context.addLine(to: CGPoint(x: base.x - normal.x * headHalfWidth, y: base.y - normal.y * headHalfWidth))
        context.closePath()
        context.fillPath()
    }

    /// A freehand path, rounded off by curving through the midpoints between samples.
    private static func addSmoothPath(through points: [CGPoint], to context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        guard points.count > 2 else {
            if let last = points.last { context.addLine(to: last) }
            return
        }
        for index in 1..<(points.count - 1) {
            let current = points[index], next = points[index + 1]
            let middle = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            context.addQuadCurve(to: middle, control: current)
        }
        context.addLine(to: points[points.count - 1])
    }

    private static func drawText(_ text: NSAttributedString, at point: CGPoint, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Builds and remembers the pixelated or blurred patch for each effect annotation,
/// so it is only recomputed when the annotation's rectangle changes.
final class EffectCache {
    private struct Entry {
        let rect: CGRect
        let kind: Annotation.Kind
        let image: CGImage
    }

    private var entries: [UUID: Entry] = [:]
    private let context = CIContext()

    func image(for annotation: Annotation, document: AnnotationDocument) -> (image: CGImage, rect: CGRect)? {
        let rect = annotation.rect.intersection(document.fullRect)
        if let entry = entries[annotation.id], entry.rect == rect, entry.kind == annotation.kind {
            return (entry.image, rect)
        }

        let scale = document.scale
        let pixels = CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        ).integral
        guard pixels.width >= 1, pixels.height >= 1,
              let patch = document.baseImage.cropping(to: pixels)
        else { return nil }

        let input = CIImage(cgImage: patch)
        let output: CIImage
        if annotation.kind == .pixelate {
            output = input.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: 14 * scale,
                    kCIInputCenterKey: CIVector(x: 0, y: 0),
                ])
                .cropped(to: input.extent)
        } else {
            output = input.clampedToExtent()
                .applyingGaussianBlur(sigma: 9 * scale)
                .cropped(to: input.extent)
        }
        guard let image = context.createCGImage(output, from: input.extent) else { return nil }
        entries[annotation.id] = Entry(rect: rect, kind: annotation.kind, image: image)
        return (image, rect)
    }
}

extension NSColor {
    /// Whether dark text reads better than white text on this colour.
    var isLight: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent > 0.7
    }
}
