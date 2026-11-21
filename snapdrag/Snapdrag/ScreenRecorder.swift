import AVFoundation
import ImageIO
import Observation
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Records a display, or part of one, to an MP4 file with ScreenCaptureKit.
@Observable
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    static let shared = ScreenRecorder()

    private(set) var isRecording = false
    private(set) var startDate: Date?

    /// Called if the system ends the recording by itself, for example from the menu bar's sharing control.
    @ObservationIgnored var onUnexpectedStop: (() -> Void)?

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: SCRecordingOutput?
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var didFinishWriting = false
    @ObservationIgnored private var finishContinuation: CheckedContinuation<Void, Never>?

    private override init() {}

    /// Starts recording. `rect` is in points from the display's top-left corner; nil records the whole display.
    func start(screen: NSScreen, rect: CGRect?, outputURL: URL) async throws {
        guard !isRecording else { return }
        let settings = AppSettings.shared

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        // Snapdrag's own windows (the stop control, the area outline, thumbnails) stay out of the video.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let scale = CGFloat(filter.pointPixelScale)
        let source = rect ?? CGRect(origin: .zero, size: screen.frame.size)
        // H.264 hardware encoding tops out at 4096 × 2304, and needs even dimensions.
        let fit = min(1, 4096 / (source.width * scale), 2304 / (source.height * scale))
        func even(_ value: CGFloat) -> Int { max(2, Int(value * scale * fit) / 2 * 2) }

        let config = SCStreamConfiguration()
        if rect != nil { config.sourceRect = source }
        config.width = even(source.width)
        config.height = even(source.height)
        config.showsCursor = settings.recordCursor
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.recordFrameRate))
        config.queueDepth = 6
        config.capturesAudio = settings.recordSystemAudio
        config.excludesCurrentProcessAudio = true
        if settings.recordMicrophone, await AVCaptureDevice.requestAccess(for: .audio) {
            config.captureMicrophone = true
        }

        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = outputURL
        outputConfig.videoCodecType = .h264
        outputConfig.outputFileType = .mp4

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        self.outputURL = outputURL
        didFinishWriting = false
        startDate = Date()
        isRecording = true
    }

    /// Stops recording and returns the finished file once it has been fully written.
    func stop() async -> URL? {
        guard isRecording, let stream, let url = outputURL else { return nil }
        isRecording = false
        try? await stream.stopCapture()
        await waitUntilWritten()
        reset()
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func waitUntilWritten() async {
        guard !didFinishWriting else { return }
        // Don't wait forever if the finish callback never arrives.
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            markWritten()
        }
        await withCheckedContinuation { finishContinuation = $0 }
        timeout.cancel()
    }

    private func markWritten() {
        didFinishWriting = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    private func reset() {
        stream = nil
        output = nil
        outputURL = nil
        startDate = nil
    }

    // MARK: Callbacks (these arrive on a background queue)

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.markWritten() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in self.markWritten() }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            guard self.isRecording else { return }
            self.onUnexpectedStop?()
        }
    }
}

/// Helpers for working with finished recordings.
enum VideoTools {
    static func duration(of url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite ? seconds : nil
    }

    /// The first frame, for use as a thumbnail.
    static func poster(for url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        return try? await generator.image(at: .zero).image
    }

    /// Converts a video to an endlessly looping GIF. GIFs get large quickly, so frames are sampled and scaled down.
    static func makeGIF(from source: URL, to destination: URL, framesPerSecond: Double = 12, maxSide: CGFloat = 960) async throws {
        let asset = AVURLAsset(url: source)
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)

        let frameCount = max(1, Int((seconds * framesPerSecond).rounded()))
        guard let file = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else { throw CocoaError(.fileWriteUnknown) }

        let loopForever: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(file, loopForever as CFDictionary)
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / framesPerSecond],
        ]

        var written = 0
        for index in 0..<frameCount {
            let time = CMTime(seconds: Double(index) / framesPerSecond, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(file, frame, frameProperties as CFDictionary)
            written += 1
        }
        guard written > 0, CGImageDestinationFinalize(file) else { throw CocoaError(.fileWriteUnknown) }
    }
}
