import AppKit
import Vision

/// Reads the text in an image with Apple's on-device Vision framework. Nothing leaves the Mac.
enum TextRecognizer {
    /// The recognized lines, top to bottom, joined with line breaks. Empty when no text is found.
    static func recognize(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: image)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Recognizes the text and puts it on the clipboard, reporting the outcome on screen.
    static func copyText(from image: CGImage) async {
        do {
            let text = try await recognize(in: image)
            guard !text.isEmpty else {
                HUD.show("No text found", symbol: "text.viewfinder")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let lines = text.split(separator: "\n").count
            HUD.show("Copied \(lines) \(lines == 1 ? "line" : "lines") of text", symbol: "text.viewfinder")
        } catch {
            HUD.show("Couldn't read text: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    /// Recognizes the text in a cached capture and copies it.
    static func copyText(fromFileAt url: URL) async {
        guard let (image, _) = try? ImageEncoder.load(url) else {
            HUD.show("That capture can't be opened", symbol: "exclamationmark.triangle")
            return
        }
        await copyText(from: image)
    }

    #if DEBUG
    /// Development aid: draws known text into an image, reads it back, and writes what was recognized to a file.
    static func runSelfTest() async {
        let expected = ["Snapdrag reads text 12345", "Second line: hello@example.com"]
        let width = 1200, height = 300
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
        ]
        NSAttributedString(string: expected[0], attributes: attributes).draw(at: CGPoint(x: 40, y: 180))
        NSAttributedString(string: expected[1], attributes: attributes).draw(at: CGPoint(x: 40, y: 80))
        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else { return }
        let recognized = (try? await recognize(in: image)) ?? "<error>"
        let report = """
        expected:
        \(expected.joined(separator: "\n"))
        recognized:
        \(recognized)
        match: \(recognized == expected.joined(separator: "\n"))

        """
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnapdragSelfTest")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? report.write(to: folder.appendingPathComponent("ocr.txt"), atomically: true, encoding: .utf8)
    }
    #endif
}
