import AppKit
import AVFoundation
import Combine
import SwiftUI

/// One capture in the floating stack: drag it into another app, or hover for Copy, Save and Close.
struct ThumbnailCard: View {
    let capture: Capture

    @State private var isHovering = false
    @State private var didCopy = false
    /// Playback of a recording inside the card.
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showsPlayback = false

    private var isGIF: Bool { capture.fileURL.pathExtension.lowercased() == "gif" }

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(.regularMaterial)

            Image(nsImage: capture.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(6)

            if showsPlayback {
                // The recording plays in place of its still frame.
                Group {
                    if isGIF {
                        InlineGIF(url: capture.fileURL)
                    } else if let player {
                        InlineVideo(player: player)
                    }
                }
                .padding(6)
                .background(shape.fill(.black))
            }

            if showsPlayback {
                EmptyView()
            } else if let duration = capture.duration {
                // Marks the card as a recording and shows its length.
                Label(Self.format(duration), systemImage: "play.fill")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else if !capture.isImage {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            // Sits above the picture and below the buttons: handles dragging and reports hovering.
            DragSource(capture: capture, isHovering: $isHovering)

            if isHovering {
                Color.black.opacity(isPlaying ? 0.2 : 0.45)
                    .allowsHitTesting(false)
                controls
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
            // When the clip reaches its end, go back to the still frame.
            guard let player, notification.object as? AVPlayerItem === player.currentItem else { return }
            stopPlayback()
        }
        .onDisappear { player?.pause() }
        .frame(width: ThumbnailStack.cardSize.width, height: ThumbnailStack.cardSize.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var controls: some View {
        ZStack {
            VStack(spacing: 8) {
            if !capture.isImage {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Pause" : "Play here")
            }
            HStack(spacing: 8) {
                pillButton(didCopy ? "Copied" : "Copy", symbol: didCopy ? "checkmark" : "doc.on.doc") {
                    capture.copyToClipboard()
                    didCopy = true
                    // Show the "Copied" confirmation briefly, then close the card.
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        ThumbnailStack.shared.remove(capture.id)
                    }
                }
                pillButton("Save", symbol: "square.and.arrow.down") { save() }
            }
            }

            Button {
                ThumbnailStack.shared.remove(capture.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if capture.isImage {
            Button {
                ThumbnailStack.shared.remove(capture.id)
                AnnotationEditor.open(fileURL: capture.fileURL)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .help("Annotate")
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            } else {
                Button {
                    stopPlayback()
                    NSWorkspace.shared.open(capture.fileURL)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .help("Open in your default player")
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    private func pillButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(.white.opacity(0.22), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            if !isGIF {
                if player == nil { player = AVPlayer(url: capture.fileURL) }
                player?.play()
            }
            showsPlayback = true
            isPlaying = true
        }
        // A card that is playing doesn't close by itself.
        ThumbnailStack.shared.setPlaying(isPlaying, for: capture.id)
    }

    private func stopPlayback() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        showsPlayback = false
        ThumbnailStack.shared.setPlaying(false, for: capture.id)
    }

    private static func format(_ duration: Double) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func save() {
        do {
            let url = try CaptureOutput.save(capture)
            ThumbnailStack.shared.remove(capture.id)
            HUD.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "checkmark.circle")
        } catch {
            HUD.show("Couldn't save: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }
}

// MARK: - Playback

/// Shows a video inside the card.
private struct InlineVideo: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.layer as? AVPlayerLayer)?.player = player
    }
}

/// Shows an animated GIF inside the card.
private struct InlineGIF: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(contentsOf: url)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        // Let the card size the view rather than the image's own size.
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {}
}

// MARK: - Dragging

/// An invisible AppKit view that starts a file drag and tracks the pointer.
/// AppKit is used here because it reports whether the drop was accepted and works while Snapdrag is in the background.
private struct DragSource: NSViewRepresentable {
    let capture: Capture
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView()
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        let id = capture.id
        view.capture = capture
        view.onHover = { hovering in
            isHovering = hovering
            ThumbnailStack.shared.setHovering(hovering, for: id)
        }
    }
}

private final class DragSourceView: NSView, NSDraggingSource {
    var capture: Capture?
    var onHover: (Bool) -> Void = { _ in }

    private var mouseDownPoint: CGPoint?
    private var isDragging = false
    private var isPointerInside = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
        syncHoverWithPointer()
    }

    /// macOS sends no "entered" event when a card appears under a pointer that is already there,
    /// so check where the pointer is whenever the card is placed or moved.
    private func syncHoverWithPointer() {
        guard let window else { return }
        let inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        // Deferred, because this can run while SwiftUI is still laying out the card.
        Task { [weak self] in self?.onHover(inside) }
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        onHover(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let capture, let start = mouseDownPoint else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
        isDragging = true
        ThumbnailStack.shared.beginDrag(capture.id)

        // Offer the file itself (for Finder, Slack, Mail, browsers) and the raw image (for image editors).
        let item = NSPasteboardItem()
        item.setString(capture.fileURL.absoluteString, forType: .fileURL)
        if capture.isImage, let data = try? Data(contentsOf: capture.fileURL) {
            item.setData(data, forType: .png)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(imageFrame(for: capture.thumbnail), contents: capture.thumbnail)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    /// The thumbnail's aspect-fit rectangle inside the card, used as the drag preview.
    private func imageFrame(for image: NSImage) -> CGRect {
        let available = bounds.insetBy(dx: 6, dy: 6)
        guard image.size.width > 0, image.size.height > 0 else { return available }
        let ratio = min(available.width / image.size.width, available.height / image.size.height)
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return CGRect(
            x: available.midX - size.width / 2, y: available.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        mouseDownPoint = nil
        // No enter/exit events arrive during a drag, so work out afresh whether the pointer is over the card.
        if let window {
            let inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
            isPointerInside = inside
            onHover(inside)
        }
        if let capture {
            ThumbnailStack.shared.endDrag(capture.id, accepted: !operation.isEmpty)
        }
    }
}
