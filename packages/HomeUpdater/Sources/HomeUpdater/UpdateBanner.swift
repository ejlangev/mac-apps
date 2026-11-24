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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(.headline)
                Text("Version \(update.version) (\(String(update.build)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Install", action: install)
                .buttonStyle(.borderedProminent)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 4)
    }
}
