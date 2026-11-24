import SwiftUI

public extension View {
    /// Shows an "Update available" banner at the top of this view when the home server
    /// has a newer build. Checks on launch and whenever the app comes to the foreground.
    func homeUpdater() -> some View {
        modifier(HomeUpdaterModifier())
    }
}

struct HomeUpdaterModifier: ViewModifier {
    @State private var updater = HomeUpdater()
    @State private var dismissedBuild: Int?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            // Fill the screen so the inset pins to the top even when the app's root view is small.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let update = updater.availableUpdate, update.build != dismissedBuild {
                    UpdateBanner(
                        update: update,
                        install: { openURL(update.installURL) },
                        dismiss: { dismissedBuild = update.build }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: updater.availableUpdate)
            .task { await updater.check(minimumInterval: 0) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await updater.check() }
                }
            }
    }
}

struct UpdateBanner: View {
    let update: HomeUpdater.Update
    let install: () -> Void
    let dismiss: () -> Void

    /// deploy.sh stamps builds as YYYYMMDDHHMM; show that as a date when it parses.
    private var detail: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmm"
        if let date = f.date(from: String(update.build)) {
            return "Version \(update.version) · \(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
        }
        return "Version \(update.version) (\(update.build))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 1) {
                Text("Update available")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .opacity(0.85)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: install) {
                Text("Update")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: install)
        .background {
            // Fill up under the status bar so the bar reads as part of the screen edge.
            Rectangle()
                .fill(Color.accentColor.gradient)
                .ignoresSafeArea(edges: .top)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityElement(children: .contain)
    }
}
