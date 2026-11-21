import AppKit
import SwiftUI

/// Opens annotation editor windows and keeps them alive while they are on screen.
enum AnnotationEditor {
    private static var windows: [NSWindow] = []
    private static let closeObserver = CloseObserver()

    static let toolbarHeight: CGFloat = 52
    static let minimumSize = CGSize(width: 1040, height: 560)

    /// Opens an editor for a cached capture.
    static func open(fileURL: URL, prepare: ((AnnotationDocument) -> Void)? = nil) {
        guard let (image, scale) = try? ImageEncoder.load(fileURL) else {
            HUD.show("That capture can't be opened", symbol: "exclamationmark.triangle")
            return
        }
        let document = AnnotationDocument(image: image, scale: scale)
        prepare?(document)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Annotate"
        window.isReleasedWhenClosed = false
        window.delegate = closeObserver
        window.contentViewController = NSHostingController(
            rootView: AnnotationEditorView(document: document) { [weak window] in window?.close() }
        )

        // Fit the screenshot at full size where the screen allows it.
        let screen = (NSScreen.underMouse ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let wanted = CGSize(
            width: document.fullRect.width + 48,
            height: document.fullRect.height + 48 + toolbarHeight
        )
        window.contentMinSize = minimumSize
        window.setContentSize(CGSize(
            width: min(max(wanted.width, minimumSize.width), screen.width * 0.9),
            height: min(max(wanted.height, minimumSize.height), screen.height * 0.9)
        ))
        window.center()

        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private final class CloseObserver: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            AnnotationEditor.windows.removeAll { $0 === window }
        }
    }
}

struct AnnotationEditorView: View {
    @Bindable var document: AnnotationDocument
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .frame(height: AnnotationEditor.toolbarHeight)
                .background(.bar)
            Divider()
            CanvasRepresentable(document: document)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button {
                        document.tool = tool
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 30, height: 28)
                            .background(
                                document.tool == tool ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(tool.title) (\(String(tool.key).uppercased()))")
                }
            }

            Divider().frame(height: 24)

            HStack(spacing: 6) {
                ForEach(AnnotationDocument.palette, id: \.self) { color in
                    Button {
                        document.color = color
                    } label: {
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                            .padding(3)
                            .overlay(
                                Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                    .opacity(document.color == color ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Size", selection: $document.lineWidth) {
                Text("S").tag(CGFloat(2))
                Text("M").tag(CGFloat(4))
                Text("L").tag(CGFloat(8))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 100)
            .help("Stroke and text size")

            Spacer(minLength: 12)

            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.canUndo)
                .help("Undo (⌘Z)")
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.canRedo)
                .help("Redo (⇧⌘Z)")

            Divider().frame(height: 24)

            Button("Copy") { copy() }
                .help("Copy the annotated image to the clipboard")
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save the annotated image to your save folder (⌘S)")
            Button("Done") { done() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Finish: show the annotated image as a new thumbnail (⌘↩)")
        }
        .padding(.horizontal, 12)
    }

    // MARK: Actions

    private func rendered() -> CGImage? {
        guard let image = AnnotationRenderer.render(document) else {
            HUD.show("Couldn't render the image", symbol: "exclamationmark.triangle")
            return nil
        }
        return image
    }

    private func copy() {
        guard let image = rendered(),
              let data = try? ImageEncoder.data(for: image, scale: document.scale, format: .png)
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        HUD.show("Copied to clipboard", symbol: "doc.on.clipboard")
    }

    private func save() {
        guard let image = rendered() else { return }
        do {
            let url = try CaptureOutput.save(image: image, scale: document.scale, date: Date())
            HUD.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "checkmark.circle")
        } catch {
            HUD.show("Couldn't save: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    /// The annotated image becomes a new capture: in the history, on the clipboard and as a thumbnail.
    private func done() {
        guard let image = rendered() else { return }
        do {
            try CaptureOutput.deliver(image, scale: document.scale)
            close()
        } catch {
            HUD.show("Couldn't finish: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let document: AnnotationDocument

    func makeNSView(context: Context) -> AnnotationCanvasView {
        AnnotationCanvasView(document: document)
    }

    func updateNSView(_ view: AnnotationCanvasView, context: Context) {}
}
