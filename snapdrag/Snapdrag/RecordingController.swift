import AppKit
import SwiftUI

/// Runs a recording from the user's point of view: choosing what to record,
/// showing the stop control and area outline, and handing off the finished file.
final class RecordingController {
    static let shared = RecordingController()

    private var controlPanel: NSPanel?
    private var outlineWindow: NSWindow?
    private var isFinishing = false

    private init() {
        ScreenRecorder.shared.onUnexpectedStop = { [weak self] in
            Task { await self?.finish() }
        }
    }

    /// Starts a recording, or stops the one in progress.
    func toggle() async throws {
        if ScreenRecorder.shared.isRecording {
            await finish()
        } else {
            try await begin()
        }
    }

    private func begin() async throws {
        let shots = try await ScreenCapturer.captureDisplays(NSScreen.screens)
        let selection = await AreaSelector().select(
            from: shots,
            hint: "Drag to record an area  ·  Return to record the whole screen  ·  Esc to cancel",
            allowsFullScreen: true
        )
        guard let selection else { return }

        let screen = selection.shot.screen
        var rect: CGRect? = selection.isFullScreen ? nil : selection.rect
        if let area = rect, area.width < 64 || area.height < 64 {
            HUD.show("That area is too small to record", symbol: "exclamationmark.triangle")
            return
        }
        if let area = rect, area.size == screen.frame.size { rect = nil }

        try FileManager.default.createDirectory(at: CaptureOutput.cacheFolder, withIntermediateDirectories: true)
        let url = CaptureOutput.cacheFolder
            .appendingPathComponent(FileNaming.name(for: Date(), precise: true) + ".mp4")

        // Let the selection overlay disappear before the first frame is captured.
        try await Task.sleep(for: .milliseconds(150))
        try await ScreenRecorder.shared.start(screen: screen, rect: rect, outputURL: url)
        showControls(on: screen, area: rect)
    }

    func finish() async {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        hideControls()
        guard var url = await ScreenRecorder.shared.stop() else {
            HUD.show("The recording couldn't be saved", symbol: "exclamationmark.triangle")
            return
        }

        if AppSettings.shared.recordingFormat == .gif {
            HUD.show("Converting to GIF…", symbol: "arrow.triangle.2.circlepath")
            let gifURL = url.deletingPathExtension().appendingPathExtension("gif")
            do {
                try await VideoTools.makeGIF(from: url, to: gifURL)
                try? FileManager.default.removeItem(at: url)
                url = gifURL
            } catch {
                HUD.show("GIF conversion failed; kept the MP4", symbol: "exclamationmark.triangle")
            }
        }
        await CaptureOutput.deliverRecording(at: url)
    }

    #if DEBUG
    /// Development aid: runs the whole flow on a small area for two seconds without user input,
    /// writes down what happened, and removes the test recording again.
    func runSelfTest() async {
        var report = ""
        do {
            guard let screen = NSScreen.main else { throw CaptureError.displayNotFound }
            let area = CGRect(x: 200, y: 200, width: 400, height: 300)
            try FileManager.default.createDirectory(at: CaptureOutput.cacheFolder, withIntermediateDirectories: true)
            let url = CaptureOutput.cacheFolder
                .appendingPathComponent(FileNaming.name(for: Date(), precise: true) + ".mp4")
            try await ScreenRecorder.shared.start(screen: screen, rect: area, outputURL: url)
            showControls(on: screen, area: area)
            report += "controls shown: \(controlPanel?.isVisible == true), outline shown: \(outlineWindow?.isVisible == true)\n"
            try await Task.sleep(for: .seconds(2))
            await finish()
            report += "controls hidden: \(controlPanel == nil && outlineWindow == nil)\n"

            let card = ThumbnailStack.shared.captures.last { $0.fileURL == url }
            report += "thumbnail card: \(card != nil), duration: \(card?.duration.map { String(format: "%.1f", $0) } ?? "none")\n"
            let item = HistoryStore.shared.items.first { $0.url == url }
            report += "in history: \(item != nil)\n"
            if let item { HistoryStore.shared.delete(item) }
            report += "cleaned up: \(!FileManager.default.fileExists(atPath: url.path))\n"
        } catch {
            report += "error: \(error)\n"
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnapdragSelfTest")
        try? report.write(to: folder.appendingPathComponent("recording-flow.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    // MARK: On-screen controls

    private func showControls(on screen: NSScreen, area: CGRect?) {
        if let area {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: RecordingOutline(area: area))
            window.orderFrontRegardless()
            outlineWindow = window
        }

        let content = NSHostingView(rootView: RecordingControl())
        let size = content.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = content
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 24))
        panel.orderFrontRegardless()
        controlPanel = panel
    }

    private func hideControls() {
        controlPanel?.close()
        controlPanel = nil
        outlineWindow?.close()
        outlineWindow = nil
    }
}

/// A thin frame just outside the area being recorded. It is not part of the video.
private struct RecordingOutline: View {
    let area: CGRect

    var body: some View {
        Rectangle()
            .strokeBorder(Color.red.opacity(0.9), lineWidth: 2)
            .frame(width: area.width + 4, height: area.height + 4)
            .position(x: area.midX, y: area.midY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
    }
}

/// The floating pill with the elapsed time and a Stop button. It is not part of the video.
private struct RecordingControl: View {
    private let recorder = ScreenRecorder.shared

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(at: context.date))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .frame(minWidth: 40, alignment: .leading)
            }

            Button {
                Task { await RecordingController.shared.finish() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(.red, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .padding(10)
    }

    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(recorder.startDate ?? date)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
