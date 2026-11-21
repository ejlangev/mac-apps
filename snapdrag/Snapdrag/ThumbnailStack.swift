import AppKit
import Observation
import SwiftUI

/// The floating stack of recent captures in a corner of the screen.
@Observable
final class ThumbnailStack {
    static let shared = ThumbnailStack()

    static let cardSize = CGSize(width: 220, height: 140)
    static let spacing: CGFloat = 10
    /// Room around the cards for their shadows.
    static let padding: CGFloat = 16
    static let maximumCards = 5

    /// Oldest first; the newest card sits at the bottom of the stack.
    private(set) var captures: [Capture] = []

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var screen: NSScreen?
    @ObservationIgnored private var closeTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var shrinkTask: Task<Void, Never>?
    /// Cards the pointer is over, cards being dragged, and cards that have been dragged at least once.
    @ObservationIgnored private var hovering: Set<UUID> = []
    @ObservationIgnored private var dragging: Set<UUID> = []
    @ObservationIgnored private var dragged: Set<UUID> = []
    @ObservationIgnored private var playing: Set<UUID> = []

    /// How long a card stays once it has been dragged and released, so a drop in the wrong place can be redone.
    static let afterDragSeconds = 3

    private init() {}

    func add(_ capture: Capture) {
        screen = NSScreen.underMouse ?? NSScreen.main
        var updated = captures + [capture]
        while updated.count > Self.maximumCards {
            forget(updated.removeFirst().id)
        }

        // Grow the panel first so the new card has room to animate in.
        layoutPanel(cardCount: max(updated.count, captures.count))
        withAnimation(.spring(duration: 0.35)) { captures = updated }
        scheduleClose(for: capture.id)
    }

    func remove(_ id: UUID) {
        forget(id)
        guard captures.contains(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: 0.2)) { captures.removeAll { $0.id == id } }

        // Shrink the panel once the card has finished animating out.
        shrinkTask?.cancel()
        shrinkTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            layoutPanel(cardCount: captures.count)
        }
    }

    func remove(fileURL: URL) {
        for capture in captures where capture.fileURL == fileURL { remove(capture.id) }
    }

    func removeAll() {
        for capture in captures { remove(capture.id) }
    }

    /// Stops the countdown while the pointer is over a card; it starts again when the pointer leaves.
    func setHovering(_ isHovering: Bool, for id: UUID) {
        if isHovering {
            hovering.insert(id)
            closeTasks.removeValue(forKey: id)?.cancel()
        } else {
            hovering.remove(id)
            scheduleClose(for: id)
        }
    }

    /// Stops the countdown while a recording plays inside its card.
    func setPlaying(_ isPlaying: Bool, for id: UUID) {
        if isPlaying {
            playing.insert(id)
            closeTasks.removeValue(forKey: id)?.cancel()
        } else if playing.remove(id) != nil {
            scheduleClose(for: id)
        }
    }

    /// Stops the countdown for as long as the card is being dragged.
    func beginDrag(_ id: UUID) {
        dragging.insert(id)
        closeTasks.removeValue(forKey: id)?.cancel()
    }

    /// After a drag is released the card closes in a few seconds rather than at once.
    /// With the timer set to Never, a drop that nothing accepted leaves the card in place.
    func endDrag(_ id: UUID, accepted: Bool) {
        dragging.remove(id)
        if accepted || AppSettings.shared.thumbnailAutoClose > 0 { dragged.insert(id) }
        scheduleClose(for: id)
    }

    private func forget(_ id: UUID) {
        closeTasks.removeValue(forKey: id)?.cancel()
        hovering.remove(id)
        dragging.remove(id)
        dragged.remove(id)
        playing.remove(id)
    }

    private func scheduleClose(for id: UUID) {
        closeTasks.removeValue(forKey: id)?.cancel()
        guard !hovering.contains(id), !dragging.contains(id), !playing.contains(id) else { return }
        let seconds = dragged.contains(id) ? Self.afterDragSeconds : AppSettings.shared.thumbnailAutoClose
        guard seconds > 0, captures.contains(where: { $0.id == id }) else { return }
        closeTasks[id] = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            remove(id)
        }
    }

    // MARK: Panel

    private func layoutPanel(cardCount: Int) {
        guard cardCount > 0, let screen = screen ?? NSScreen.main else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let count = CGFloat(cardCount)
        let size = CGSize(
            width: Self.cardSize.width + Self.padding * 2,
            height: count * Self.cardSize.height + (count - 1) * Self.spacing + Self.padding * 2
        )
        let area = screen.visibleFrame
        let margin: CGFloat = 4
        let x = AppSettings.shared.thumbnailCorner == .bottomLeft
            ? area.minX + margin
            : area.maxX - size.width - margin
        panel.setFrame(CGRect(origin: CGPoint(x: x, y: area.minY + margin), size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .statusBar // set after isFloatingPanel, which would otherwise lower it
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = FirstMouseHostingView(rootView: ThumbnailStackView())
        return panel
    }
}

/// Lets buttons in the panel respond to the first click, without Snapdrag needing to be the active app.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ThumbnailStackView: View {
    private let stack = ThumbnailStack.shared

    var body: some View {
        let leading = AppSettings.shared.thumbnailCorner == .bottomLeft
        VStack(spacing: ThumbnailStack.spacing) {
            ForEach(stack.captures) { capture in
                ThumbnailCard(capture: capture)
                    .transition(.move(edge: leading ? .leading : .trailing).combined(with: .opacity))
            }
        }
        .padding(ThumbnailStack.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
