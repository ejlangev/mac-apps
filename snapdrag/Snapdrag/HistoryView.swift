import AppKit
import QuickLookThumbnailing
import SwiftUI

/// A grid of past captures. Each one can be dragged out, copied, saved or deleted.
struct HistoryView: View {
    private let store = HistoryStore.shared

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)]

    var body: some View {
        Group {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "No Captures Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Screenshots you take appear here, even if you never saved them.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(store.items) { item in
                            HistoryCell(item: item)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 760, minHeight: 320, idealHeight: 520)
        .onAppear { store.prune() }
    }
}

private struct HistoryCell: View {
    let item: HistoryItem

    @State private var preview: NSImage?
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                shape.fill(.quaternary)

                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                }

                if !item.isImage {
                    Label(item.url.pathExtension.uppercased(), systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if isHovering {
                    Color.black.opacity(0.45)
                        .allowsHitTesting(false)
                    HStack(spacing: 8) {
                        if item.isImage {
                            iconButton("pencil", help: "Annotate") { open() }
                        } else {
                            iconButton("play.fill", help: "Play") { open() }
                        }
                        iconButton("doc.on.doc", help: "Copy") { copy() }
                        if item.isImage {
                            iconButton("text.viewfinder", help: "Copy Text") { copyText() }
                        }
                        iconButton("square.and.arrow.down", help: "Save") { save() }
                        iconButton("trash", help: "Delete") { HistoryStore.shared.delete(item) }
                    }
                }
            }
            .frame(height: 130)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.separator))
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            .onTapGesture(count: 2) { open() }

            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            if item.isImage {
                Button("Annotate") { open() }
                Button("Copy") { copy() }
                Button("Copy Text") { copyText() }
            } else {
                Button("Play") { open() }
                Button("Copy") { copy() }
            }
            Button("Save") { save() }
            Button("Open in Default App") { NSWorkspace.shared.open(item.url) }
            Divider()
            Button("Delete", role: .destructive) { HistoryStore.shared.delete(item) }
        }
        .task(id: item.url) {
            let url = item.url
            if item.isImage {
                let image = await Task.detached(priority: .userInitiated) {
                    HistoryThumbnailer.load(url)
                }.value
                if let image {
                    preview = NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
                }
            } else {
                // Quick Look makes the preview frame for recordings.
                let request = QLThumbnailGenerator.Request(
                    fileAt: url, size: CGSize(width: 260, height: 180), scale: 2, representationTypes: .thumbnail
                )
                preview = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 30)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Screenshots open in the annotation editor; recordings open in the default player.
    private func open() {
        if item.isImage {
            AnnotationEditor.open(fileURL: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func copy() {
        if item.isImage {
            Clipboard.copyImage(at: item.url)
        } else {
            Clipboard.copyFile(at: item.url)
        }
        HUD.show("Copied to clipboard", symbol: "doc.on.clipboard")
    }

    private func copyText() {
        let url = item.url
        Task { await TextRecognizer.copyText(fromFileAt: url) }
    }

    private func save() {
        do {
            let url = try CaptureOutput.save(fileURL: item.url, date: item.date)
            HUD.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "checkmark.circle")
        } catch {
            HUD.show("Couldn't save: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }
}
