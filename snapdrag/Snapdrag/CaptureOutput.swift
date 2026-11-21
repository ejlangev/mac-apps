import AppKit
import ImageIO
import UniformTypeIdentifiers

/// One finished screenshot. The PNG in the app's cache is the master copy;
/// it is what gets dragged out, copied, and converted when the user saves.
struct Capture: Identifiable {
    let id = UUID()
    let image: CGImage
    /// Pixels per point of the display it came from.
    let scale: CGFloat
    let date: Date
    let fileURL: URL
    /// Small version for the floating thumbnail.
    let thumbnail: NSImage
    /// Length in seconds for a recording; nil for a screenshot.
    var duration: Double?

    /// Screenshots are PNGs; anything else in the cache is a recording (MP4 or GIF).
    var isImage: Bool { fileURL.pathExtension.lowercased() == "png" }

    func copyToClipboard() {
        if isImage {
            Clipboard.copyImage(at: fileURL)
        } else {
            Clipboard.copyFile(at: fileURL)
        }
    }
}

enum Clipboard {
    /// Puts the PNG at the given location on the clipboard as an image.
    static func copyImage(at url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    /// Puts a file on the clipboard, so pasting attaches or copies the file itself.
    static func copyFile(at url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}

/// What happens to a finished capture: it is kept in the app's cache (never the Desktop),
/// copied to the clipboard and shown as a floating thumbnail, according to the settings.
enum CaptureOutput {
    /// Private folder for captures the user hasn't explicitly saved.
    static var cacheFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Snapdrag", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    @discardableResult
    static func deliver(_ image: CGImage, scale: CGFloat) throws -> Capture {
        let date = Date()
        let data = try ImageEncoder.data(for: image, scale: scale, format: .png)

        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        let url = cacheFolder.appendingPathComponent(FileNaming.name(for: date, precise: true) + ".png")
        try data.write(to: url, options: .atomic)

        let capture = Capture(
            image: image, scale: scale, date: date, fileURL: url,
            thumbnail: ImageEncoder.thumbnail(from: data) ?? NSImage(cgImage: image, size: .zero)
        )

        HistoryStore.shared.prune()

        let settings = AppSettings.shared
        if settings.copyToClipboard { capture.copyToClipboard() }
        if settings.showThumbnail {
            ThumbnailStack.shared.add(capture)
        } else {
            HUD.show(
                settings.copyToClipboard ? "Copied to clipboard" : "Captured",
                symbol: settings.copyToClipboard ? "doc.on.clipboard" : "checkmark.circle"
            )
        }
        return capture
    }

    /// Hands off a finished recording: into the history, onto the clipboard and into the thumbnail stack.
    static func deliverRecording(at url: URL) async {
        guard let poster = await VideoTools.poster(for: url) ?? ImageEncoder.firstFrame(of: url) else {
            HUD.show("The recording couldn't be read", symbol: "exclamationmark.triangle")
            return
        }
        let side = CGFloat(max(poster.width, poster.height))
        let shrink = min(1, 640 / side)
        let capture = Capture(
            image: poster, scale: 2, date: Date(), fileURL: url,
            thumbnail: NSImage(cgImage: poster, size: NSSize(
                width: CGFloat(poster.width) * shrink / 2, height: CGFloat(poster.height) * shrink / 2
            )),
            duration: await VideoTools.duration(of: url)
        )

        HistoryStore.shared.prune()
        let settings = AppSettings.shared
        if settings.copyToClipboard { capture.copyToClipboard() }
        if settings.showThumbnail {
            ThumbnailStack.shared.add(capture)
        } else {
            HUD.show("Recording finished", symbol: "checkmark.circle")
        }
    }

    /// Writes the capture into the user's save folder in their chosen format.
    @discardableResult
    static func save(_ capture: Capture) throws -> URL {
        try save(fileURL: capture.fileURL, date: capture.date)
    }

    /// Writes an image into the user's save folder in their chosen format.
    @discardableResult
    static func save(image: CGImage, scale: CGFloat, date: Date) throws -> URL {
        let url = try destination(for: date)
        try ImageEncoder.data(for: image, scale: scale, format: AppSettings.shared.imageFormat)
            .write(to: url, options: .atomic)
        return url
    }

    /// A file location in the save folder that isn't taken yet.
    private static func destination(for date: Date, fileExtension: String? = nil) throws -> URL {
        let settings = AppSettings.shared
        let folder = settings.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let ending = fileExtension ?? settings.imageFormat.rawValue
        let base = FileNaming.name(for: date, precise: false)
        var url = folder.appendingPathComponent("\(base).\(ending)")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(counter).\(ending)")
            counter += 1
        }
        return url
    }

    /// Writes a cached capture into the user's save folder in their chosen format.
    @discardableResult
    static func save(fileURL: URL, date: Date) throws -> URL {
        // Recordings are saved as they are; only screenshots are converted to the chosen image format.
        let sourceExtension = fileURL.pathExtension.lowercased()
        if sourceExtension != "png" {
            let url = try destination(for: date, fileExtension: sourceExtension)
            try FileManager.default.copyItem(at: fileURL, to: url)
            return url
        }

        let url = try destination(for: date)
        let format = AppSettings.shared.imageFormat

        if format == .png {
            try FileManager.default.copyItem(at: fileURL, to: url)
        } else {
            let (image, scale) = try ImageEncoder.load(fileURL)
            try ImageEncoder.data(for: image, scale: scale, format: format).write(to: url, options: .atomic)
        }
        return url
    }
}

enum FileNaming {
    /// For example "Snapdrag 2026-11-21 at 14.20.06".
    static func name(for date: Date, precise: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = precise ? "yyyy-MM-dd 'at' HH.mm.ss.SSS" : "yyyy-MM-dd 'at' HH.mm.ss"
        return "Snapdrag \(formatter.string(from: date))"
    }
}

enum ImageEncoder {
    /// Image bytes tagged with the display's resolution, so a Retina capture opens at its true size.
    static func data(for image: CGImage, scale: CGFloat, format: ImageFormat) throws -> Data {
        let type: UTType
        var source = image
        switch format {
        case .png: type = .png
        case .heic: type = .heic
        case .jpg:
            type = .jpeg
            // JPEG has no transparency; put window captures on white instead of black.
            source = flattened(image) ?? image
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dpi = 72 * scale
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format != .png { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    /// Reads an image file along with the pixels-per-point scale recorded in it.
    static func load(_ url: URL) throws -> (image: CGImage, scale: CGFloat) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return (image, max(1, (dpi / 72).rounded()))
    }

    /// The first frame of an image file, including an animated GIF.
    static func firstFrame(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// A downscaled copy, at most 640 pixels on its longer side.
    static func thumbnail(from data: Data) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: small, size: NSSize(width: small.width / 2, height: small.height / 2))
    }

    private static func flattened(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}

enum ImageEffects {
    /// Places the image on a larger transparent canvas with a soft drop shadow, like a floating window.
    static func addingShadow(to image: CGImage, scale: CGFloat) -> CGImage? {
        let padding = Int((56 * scale).rounded())
        let width = image.width + padding * 2
        let height = image.height + padding * 2
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setShadow(
            offset: CGSize(width: 0, height: -14 * scale), blur: 28 * scale,
            color: NSColor.black.withAlphaComponent(0.4).cgColor
        )
        context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
        return context.makeImage()
    }
}
