import Foundation
import Observation

/// Checks the home app server for a newer build of this app.
///
/// Reads `HomeUpdaterHost` (the server's ts.net name) and the bundle ID from Info.plist,
/// fetches `https://<host>/<bundle-id>/version.json`, and compares its `build` with this
/// app's `CFBundleVersion`. Every failure (no host, Tailscale off, server down, bad JSON)
/// is silent: the app just doesn't show a banner.
@MainActor
@Observable
public final class HomeUpdater {
    public struct Update: Equatable, Sendable {
        public let build: Int
        public let version: String
        public let installURL: URL
    }

    /// Set when the server has a newer build than the one running.
    public private(set) var availableUpdate: Update?

    private let versionURL: URL?
    private let currentBuild: Int
    private var lastCheck: Date?

    public init(bundle: Bundle = .main) {
        let host = (bundle.object(forInfoDictionaryKey: "HomeUpdaterHost") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let bundleID = bundle.bundleIdentifier ?? ""
        if !host.isEmpty, !bundleID.isEmpty {
            versionURL = URL(string: "https://\(host)/\(bundleID)/version.json")
        } else {
            versionURL = nil
        }
        currentBuild = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// Checks at most once every `minimumInterval` seconds (launch and each foreground call this).
    public func check(minimumInterval: TimeInterval = 60) async {
        guard let versionURL else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < minimumInterval { return }
        lastCheck = Date()

        var request = URLRequest(url: versionURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard
            let result = try? await URLSession.shared.data(for: request),
            (result.1 as? HTTPURLResponse)?.statusCode == 200,
            let info = try? JSONDecoder().decode(VersionInfo.self, from: result.0),
            let build = Int(info.build),
            let url = URL(string: info.install),
            url.scheme == "itms-services"
        else { return }

        availableUpdate = build > currentBuild
            ? Update(build: build, version: info.version, installURL: url)
            : nil
    }
}

private struct VersionInfo: Decodable {
    let build: String
    let version: String
    let install: String
}
