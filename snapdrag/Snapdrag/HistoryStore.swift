import AppKit
import ImageIO
import Observation

/// One past capture, backed by its file in the app's cache folder.
struct HistoryItem: Identifiable, Hashable {
    let url: URL
    let date: Date
    let bytes: Int

    var id: URL { url }
    /// Screenshots are PNGs; MP4 and GIF files are recordings.
    var isImage: Bool { url.pathExtension.lowercased() == "png" }
}

/// The list of past captures. The cache folder is the single source of truth:
/// every screenshot and recording in it is a history item, so nothing else needs to be kept in sync.
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    /// Newest first.
    private(set) var items: [HistoryItem] = []

    var totalBytes: Int { items.reduce(0) { $0 + $1.bytes } }

    private init() {}

    /// Re-reads the cache folder.
    func reload() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: CaptureOutput.cacheFolder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        )) ?? []

        items = urls
            .filter { ["png", "mp4", "gif"].contains($0.pathExtension.lowercased()) }
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys),
                      let date = values.contentModificationDate
                else { return nil }
                return HistoryItem(url: url, date: date, bytes: values.fileSize ?? 0)
            }
            .sorted { $0.date > $1.date }
    }

    /// Deletes captures older than the retention setting, then refreshes the list.
    func prune() {
        reload()
        let days = AppSettings.shared.historyRetentionDays
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let expired = items.filter { $0.date < cutoff }
        guard !expired.isEmpty else { return }
        for item in expired { try? FileManager.default.removeItem(at: item.url) }
        reload()
    }

    func delete(_ item: HistoryItem) {
        try? FileManager.default.removeItem(at: item.url)
        // A floating thumbnail for the same capture would now point at a missing file.
        ThumbnailStack.shared.remove(fileURL: item.url)
        reload()
    }

    func clear() {
        for item in items {
            try? FileManager.default.removeItem(at: item.url)
            ThumbnailStack.shared.remove(fileURL: item.url)
        }
        reload()
    }
}

/// Decodes small previews off the main thread, so scrolling the history stays smooth.
nonisolated enum HistoryThumbnailer {
    static func load(_ url: URL, maxPixelSize: Int = 480) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
