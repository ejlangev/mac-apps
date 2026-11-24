// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HomeUpdater",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HomeUpdater", targets: ["HomeUpdater"]),
    ],
    targets: [
        .target(name: "HomeUpdater"),
    ]
)
