// swift-tools-version: 6.0
import PackageDescription

// RawBoyBrowseKit is pure Swift (no AppKit) so RawBoy desktop and the Windows port can use it later.
// ViewerImaging and ViewerFiles are Apple-only.
let package = Package(
    name: "RawBoyViewerPackages",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RawBoyBrowseKit", targets: ["RawBoyBrowseKit"]),
        .library(name: "ViewerImaging", targets: ["ViewerImaging"]),
        .library(name: "ViewerFiles", targets: ["ViewerFiles"]),
    ],
    targets: [
        .target(name: "RawBoyBrowseKit"),
        .target(name: "ViewerImaging", dependencies: ["RawBoyBrowseKit"]),
        .target(name: "ViewerFiles", dependencies: ["RawBoyBrowseKit"]),
        .testTarget(name: "RawBoyBrowseKitTests", dependencies: ["RawBoyBrowseKit"]),
        .testTarget(name: "ViewerImagingTests", dependencies: ["ViewerImaging"]),
        .testTarget(name: "ViewerFilesTests", dependencies: ["ViewerFiles"]),
    ]
)
