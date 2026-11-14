// swift-tools-version: 6.0
import PackageDescription

// RawBoyBrowseKit is pure Swift (no AppKit) so RawBoy desktop and the Windows port can use it later.
// ViewerImaging and ViewerFiles are Apple-only.
// Pixel loops (histogram, clipping overlay, parsers) are ~10x slower unoptimised, and Debug is what runs day to day:
// the packages are always optimised, as RawBoy's iOS engine is.
let optimised: [SwiftSetting] = [.unsafeFlags(["-O"])]

let package = Package(
    name: "RawBoyViewerPackages",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RawBoyBrowseKit", targets: ["RawBoyBrowseKit"]),
        .library(name: "ViewerImaging", targets: ["ViewerImaging"]),
        .library(name: "ViewerFiles", targets: ["ViewerFiles"]),
    ],
    targets: [
        .target(name: "RawBoyBrowseKit", swiftSettings: optimised),
        .target(name: "ViewerImaging", dependencies: ["RawBoyBrowseKit"], swiftSettings: optimised),
        .target(name: "ViewerFiles", dependencies: ["RawBoyBrowseKit"], swiftSettings: optimised),
        .testTarget(name: "RawBoyBrowseKitTests", dependencies: ["RawBoyBrowseKit"]),
        .testTarget(name: "ViewerImagingTests", dependencies: ["ViewerImaging"]),
        .testTarget(name: "ViewerFilesTests", dependencies: ["ViewerFiles"]),
    ]
)
