#if DEBUG
import AppKit
import AVFoundation

/// Development aid: records a small corner of the screen for two seconds, converts it to a GIF,
/// writes down what came out, and deletes both files again.
enum RecordingSelfTest {
    static func run() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnapdragSelfTest")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let movie = folder.appendingPathComponent("test.mp4")
        let gif = folder.appendingPathComponent("test.gif")
        try? FileManager.default.removeItem(at: movie)
        try? FileManager.default.removeItem(at: gif)

        var report = ""
        do {
            guard let screen = NSScreen.main else { throw CaptureError.displayNotFound }
            try await ScreenRecorder.shared.start(
                screen: screen, rect: CGRect(x: 0, y: 0, width: 400, height: 300), outputURL: movie
            )
            try await Task.sleep(for: .seconds(2))
            guard let url = await ScreenRecorder.shared.stop() else { throw CocoaError(.fileNoSuchFile) }

            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.load(.tracks)
            var size = CGSize.zero
            if let video = tracks.first(where: { $0.mediaType == .video }) {
                size = try await video.load(.naturalSize)
            }
            report += "mp4: \(Int(size.width))x\(Int(size.height)), \(String(format: "%.1f", duration))s, "
            report += "\(tracks.filter { $0.mediaType == .audio }.count) audio tracks\n"

            try await VideoTools.makeGIF(from: url, to: gif)
            let frames = CGImageSourceCreateWithURL(gif as CFURL, nil).map(CGImageSourceGetCount) ?? 0
            let bytes = (try? gif.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            report += "gif: \(frames) frames, \(bytes / 1024) KB\n"
        } catch {
            report += "error: \(error)\n"
        }
        try? FileManager.default.removeItem(at: movie)
        try? FileManager.default.removeItem(at: gif)
        try? report.write(to: folder.appendingPathComponent("recording.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
