#if DEBUG
    import AppKit
    import SwiftUI

    /// RAWBOY_SNAPSHOT=<folder> (debug builds): views drawn into PNGs with `ImageRenderer`, to look at without a
    /// screen recording permission. Scrolling parts lay out flat (`isSnapshot`); async thumbnails stay empty.
    @MainActor
    enum Snapshot {
        static let folder = ProcessInfo.processInfo.environment["RAWBOY_SNAPSHOT"].map { URL(fileURLWithPath: $0) }

        static func write<V: View>(_ view: V, size: CGSize, name: String) {
            guard let folder else { return }
            let renderer = ImageRenderer(
                content: view.frame(width: size.width, height: size.height)
                    .background(Theme.inkBlack).environment(\.colorScheme, .dark).environment(\.isSnapshot, true))
            renderer.scale = 2
            guard let image = renderer.cgImage else {
                Trace.log("snapshot \(name): nothing rendered")
                return
            }
            guard
                let dest = CGImageDestinationCreateWithURL(
                    folder.appendingPathComponent("\(name).png") as CFURL, "public.png" as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }
#endif
