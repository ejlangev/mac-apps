#if DEBUG
import AppKit

/// Development aid: renders one of every annotation kind onto a made-up image,
/// so the drawing code can be checked without using a real screenshot.
enum AnnotationSelfTest {
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("SnapdragSelfTest") }

    static func run() {
        let scale: CGFloat = 2
        guard let base = sampleImage(width: 1600, height: 1000) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let baseURL = folder.appendingPathComponent("base.png")
        try? ImageEncoder.data(for: base, scale: scale, format: .png).write(to: baseURL)

        // Rendered straight to a file…
        let document = AnnotationDocument(image: base, scale: scale)
        populate(document)
        if let image = AnnotationRenderer.render(document) {
            try? ImageEncoder.data(for: image, scale: scale, format: .png)
                .write(to: folder.appendingPathComponent("rendered.png"))
        }
        document.setCrop(CGRect(x: 40, y: 30, width: 420, height: 260))
        if let image = AnnotationRenderer.render(document) {
            try? ImageEncoder.data(for: image, scale: scale, format: .png)
                .write(to: folder.appendingPathComponent("cropped.png"))
        }
        document.undo()
        let afterUndo = document.cropRect == nil && document.annotations.count == 10
        try? "undo restores crop: \(afterUndo)\n".write(
            to: folder.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8
        )

        // …and shown in a real editor window.
        AnnotationEditor.open(fileURL: baseURL, prepare: populate)
    }

    private static func populate(_ document: AnnotationDocument) {
        func add(_ kind: Annotation.Kind, _ points: [CGPoint], _ color: NSColor, _ width: CGFloat = 4) {
            document.add(Annotation(kind: kind, points: points, color: color, lineWidth: width))
        }
        add(.pixelate, [CGPoint(x: 60, y: 60), CGPoint(x: 260, y: 130)], .black)
        add(.blur, [CGPoint(x: 300, y: 60), CGPoint(x: 500, y: 130)], .black)
        add(.arrow, [CGPoint(x: 80, y: 220), CGPoint(x: 300, y: 170)], .systemRed)
        add(.line, [CGPoint(x: 80, y: 260), CGPoint(x: 300, y: 260)], .systemBlue, 8)
        add(.rectangle, [CGPoint(x: 360, y: 180), CGPoint(x: 560, y: 280)], .systemGreen)
        add(.ellipse, [CGPoint(x: 600, y: 180), CGPoint(x: 760, y: 280)], .systemPurple, 2)
        add(.pen, stride(from: 0.0, to: 200.0, by: 8).map { CGPoint(x: 80 + $0, y: 340 + sin($0 / 20) * 20) }, .systemOrange)
        add(.highlighter, [CGPoint(x: 340, y: 345), CGPoint(x: 420, y: 345), CGPoint(x: 560, y: 345)], .systemYellow)
        add(.text("Sample text"), [CGPoint(x: 80, y: 400)], .systemRed, 4)
        add(.counter(1), [CGPoint(x: 640, y: 350)], .systemRed, 4)
    }

    /// A light background with rows of dark "text" bars, so blur and pixelate have something to hide.
    private static func sampleImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        for row in 0..<24 {
            for column in 0..<20 where (row + column) % 3 != 0 {
                context.fill(CGRect(x: 60 + column * 76, y: 40 + row * 40, width: 56, height: 14))
            }
        }
        return context.makeImage()
    }
}
#endif
