// swift-tools-version: 5.10
//
// QDVC Progress for macOS — a native app for keeping track of your projects
// and the work you put into them, day by day, in one spreadsheet-like grid.
// The workspace is a folder of plain YAML and CSV files (see
// docs/FILE_FORMAT.md), designed to be tracked with Git.
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed .app, no Apple account needed)

import PackageDescription

var products: [Product] = [
    .library(name: "ProgressCore", targets: ["ProgressCore"]),
]
var targets: [Target] = [
    // Pure model layer: Foundation (+ Yams) only, no AppKit/SwiftUI,
    // unit-testable.
    .target(
        name: "ProgressCore",
        dependencies: [.product(name: "Yams", package: "Yams")]
    ),
    .testTarget(
        name: "ProgressCoreTests",
        dependencies: ["ProgressCore"]
    ),
]

#if os(macOS)
// The SwiftUI/AppKit front-end. Declared on macOS only, so the core and its
// tests also build with a Linux Swift toolchain (docs/MAINTENANCE.md).
products.insert(.executable(name: "QDVCProgress", targets: ["QDVCProgress"]), at: 0)
targets.insert(.executableTarget(name: "QDVCProgress", dependencies: ["ProgressCore"]), at: 1)
#endif

let package = Package(
    name: "QDVCProgress",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: targets
)
