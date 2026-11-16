// swift-tools-version: 6.0
import PackageDescription

// The same libraries as Packages/Package.swift (the Viewer app's own package, which `swift test --package-path Packages`
// and the Xcode project use), declared again at the repository root because SwiftPM needs a Package.swift at the root
// of a git dependency: RawBoy Desktop depends on `https://github.com/lexusag/RawBoyImageViewer` from a tag. The sources
// are the ones under Packages/ (`path:`); nothing is copied. `tools/check-root-package.sh` (CI) fails when the two
// manifests stop declaring the same targets, products, dependencies and platforms. Change both together.
//
// Optimisation: Packages/Package.swift builds the libraries with `-O` even in Debug (pixel loops are ~10x slower
// otherwise). SwiftPM forbids `unsafeFlags` in a dependency fetched from git, so a checkout (`.build/checkouts`,
// SourcePackages/checkouts) gets none: the consuming project sets SWIFT_OPTIMIZATION_LEVEL itself (RawBoy's project.yml
// does). A local `.package(path:)` dependency, as in development, keeps the flag.
let isCheckout = Context.packageDirectory.contains("/checkouts/")
let optimised: [SwiftSetting] = isCheckout ? [] : [.unsafeFlags(["-O"])]

let package = Package(
    name: "RawBoyViewerPackages",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .library(name: "RawBoyBrowseKit", targets: ["RawBoyBrowseKit"]),
        .library(name: "ViewerImaging", targets: ["ViewerImaging"]),
        .library(name: "ViewerFiles", targets: ["ViewerFiles"]),
        .library(name: "ViewerUI", targets: ["ViewerUI"]),
    ],
    targets: [
        .target(name: "RawBoyBrowseKit", path: "Packages/Sources/RawBoyBrowseKit", swiftSettings: optimised),
        .target(
            name: "ViewerImaging", dependencies: ["RawBoyBrowseKit"], path: "Packages/Sources/ViewerImaging",
            swiftSettings: optimised),
        .target(
            name: "ViewerFiles", dependencies: ["RawBoyBrowseKit"], path: "Packages/Sources/ViewerFiles",
            swiftSettings: optimised),
        // The browser, viewer, compare and culling screens (SwiftUI/AppKit), without the app shell: no engine code.
        .target(
            name: "ViewerUI", dependencies: ["RawBoyBrowseKit", "ViewerFiles", "ViewerImaging"],
            path: "Packages/Sources/ViewerUI", swiftSettings: optimised),
        // Fixtures/Xmp is read from the source tree (shared with RawBoy's engine tests), not bundled.
        .testTarget(
            name: "RawBoyBrowseKitTests", dependencies: ["RawBoyBrowseKit"],
            path: "Packages/Tests/RawBoyBrowseKitTests",
            exclude: ["Fixtures"]),
        .testTarget(name: "ViewerUITests", dependencies: ["ViewerUI"], path: "Packages/Tests/ViewerUITests"),
        .testTarget(
            name: "ViewerImagingTests", dependencies: ["ViewerImaging"], path: "Packages/Tests/ViewerImagingTests"),
        .testTarget(name: "ViewerFilesTests", dependencies: ["ViewerFiles"], path: "Packages/Tests/ViewerFilesTests"),
    ]
)
