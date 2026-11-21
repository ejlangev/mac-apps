import AppKit
import SwiftUI

/// A brief message in the middle of the screen that fades out by itself.
enum HUD {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ text: String, symbol: String) {
        dismissTask?.cancel()
        panel?.close()

        let content = NSHostingView(rootView: HUDView(text: text, symbol: symbol))
        let size = content.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.close()
            if self.panel === panel { self.panel = nil }
        }
    }
}

private struct HUDView: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.title3.weight(.medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .padding(12)
    }
}
