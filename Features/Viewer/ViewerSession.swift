import AppKit
import RawBoyBrowseKit
import ViewerFiles
import ViewerImaging

/// One open folder in the viewer: its photos, the current one, loading and prefetching.
@MainActor
final class ViewerSession {
    private(set) var folder: URL?
    /// Each photo's main file (the raw of a RAW + JPEG pair), in name order.
    private(set) var photos: [URL] = []
    private(set) var index = 0

    private let store = ImageStore()
    private var controller: ViewerWindowController?
    private var forward = true
    /// Bumped on every navigation: loads that finish for an older photo are dropped.
    private var generation = 0
    private var shownURL: URL?
    private var loadingFull = false
    /// The long edge previews are decoded to, for the viewer's screen.
    private var previewPixelSize = 3840

    var isOpen: Bool { controller != nil }
    var onClose: (() -> Void)?

    enum OpenError: LocalizedError {
        case noPhotos(String)

        var errorDescription: String? {
            switch self {
            case .noPhotos(let name): "No photos in \(name)."
            }
        }
    }

    /// Opens [folder] at [fileName] (its first photo when nil or not a photo there).
    func open(folder: URL, at fileName: String? = nil) throws {
        let names = try FolderScanner.photos(in: folder).map(\.url.lastPathComponent)
        let groups = PhotoGroups.group(names)
        guard !groups.isEmpty else { throw OpenError.noPhotos(folder.lastPathComponent) }
        self.folder = folder
        photos = groups.map { folder.appendingPathComponent($0.main) }
        let wanted = fileName.map { PhotoGroups.stem(of: $0).lowercased() }
        index = groups.firstIndex { $0.stem.lowercased() == wanted } ?? 0
        forward = true
        shownURL = nil
        presentWindow()
        showCurrent()
        #if DEBUG
            autoplayIfAsked()
        #endif
    }

    #if DEBUG
        /// RAWBOY_AUTOPLAY=N (debug builds): step through N photos, zoom the last to 1:1, report and quit. For timing
        /// and smoke tests without a person at the keyboard (`tools/smoke.sh`).
        private func autoplayIfAsked() {
            guard let steps = ProcessInfo.processInfo.environment["RAWBOY_AUTOPLAY"].flatMap(Int.init) else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                for _ in 0..<steps {
                    handle(.next)
                    try? await Task.sleep(for: .milliseconds(700))
                }
                handle(.toggleZoom)
                try? await Task.sleep(for: .seconds(4))
                Trace.log("autoplay done at photo \(index + 1) of \(photos.count)")
                NSApp.terminate(nil)
            }
        }
    #endif

    /// Opens what Finder (or the command line) handed over: a folder, or a photo in its folder.
    func open(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            try open(folder: url)
        } else {
            try open(folder: url.deletingLastPathComponent(), at: url.lastPathComponent)
        }
    }

    func close() {
        controller?.close()
    }

    private func presentWindow() {
        if controller == nil {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
            let controller = ViewerWindowController(screen: screen)
            controller.canvas.onCommand = { [weak self] in self?.handle($0) }
            controller.canvas.onNeedsFullResolution = { [weak self] in self?.loadFullResolution() }
            controller.onClose = { [weak self] in
                self?.controller = nil
                self?.onClose?()
            }
            self.controller = controller
            previewPixelSize = Self.previewPixelSize(for: screen)
        }
        controller?.present()
    }

    /// The long edge previews are decoded to: the screen's long edge in pixels, so a photo of either orientation is
    /// sharp at fit.
    private static func previewPixelSize(for screen: NSScreen) -> Int {
        Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor)
    }

    func handle(_ command: ViewerCommand) {
        switch command {
        case .next: go(to: index + 1)
        case .previous: go(to: index - 1)
        case .first: go(to: 0)
        case .last: go(to: photos.count - 1)
        case .toggleZoom: controller?.canvas.toggleZoom()
        case .close: close()
        case .toggleFullScreen: controller?.toggleScreenFilling()
        }
    }

    private func go(to newIndex: Int) {
        let clamped = min(max(newIndex, 0), photos.count - 1)
        guard clamped != index else { return }
        forward = clamped > index
        index = clamped
        showCurrent()
    }

    private func showCurrent() {
        guard photos.indices.contains(index), let controller else { return }
        let url = photos[index]
        generation += 1
        let generation = generation
        loadingFull = false
        controller.setTitle("\(url.lastPathComponent)  ·  \(index + 1) / \(photos.count)")

        let previewPixelSize = previewPixelSize
        Task {
            let started = Date()
            // In this task, before any load, so a size change can't drop previews prefetched for the new size.
            await store.setPreviewPixelSize(previewPixelSize)
            var image = await store.cached(url, .preview)
            if image == nil {
                // While a key is held, photos fly past: only decode the one the keys stop on.
                try? await Task.sleep(for: .milliseconds(40))
                guard generation == self.generation else { return }
                let spinner = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled, generation == self.generation { controller.canvas.setLoading(true) }
                }
                image = await store.image(url, .preview)
                spinner.cancel()
            }
            guard generation == self.generation else { return }
            if let image {
                controller.canvas.show(image, samePhoto: shownURL == url)
                shownURL = url
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                Trace.log(
                    "shown \(url.lastPathComponent) in \(ms) ms (\(image.cgImage.width)×\(image.cgImage.height)"
                        + "\(image.isFullResolution ? ", full" : ""))")
            } else {
                controller.canvas.showMessage("Can't open \(url.lastPathComponent).")
                shownURL = nil
            }
            let order = PrefetchPlan.order(current: index, count: photos.count, forward: forward)
            await store.prefetch(order.map { photos[$0] })
        }
    }

    private func loadFullResolution() {
        guard !loadingFull, photos.indices.contains(index), let controller else { return }
        loadingFull = true
        let url = photos[index]
        let generation = generation
        Task {
            let started = Date()
            controller.canvas.setLoading(true)
            let image = await store.image(url, .full)
            guard generation == self.generation else { return }
            controller.canvas.setLoading(false)
            if let image {
                controller.canvas.show(image, samePhoto: true)
                Trace.log(
                    "full \(url.lastPathComponent) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            }
        }
    }
}
