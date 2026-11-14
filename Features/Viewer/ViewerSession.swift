import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles
import ViewerImaging

/// One open folder in the viewer: its photos, the current one, loading and prefetching, and the commands from keys,
/// pointer and panels.
@MainActor
final class ViewerSession {
    let model: ViewerModel
    private let culling: CullingStore
    /// Each photo's main file (the raw of a RAW + JPEG pair), in name order.
    private(set) var photos: [URL] = []
    private var index: Int {
        get { model.index }
        set { model.index = newValue }
    }

    private let store = ImageStore()
    private var controller: ViewerWindowController?
    private var forward = true
    /// Bumped on every navigation: loads that finish for an older photo are dropped.
    private var generation = 0
    private var shownURL: URL?
    /// The picture on screen (preview or full resolution), for the histogram and the clipping overlay.
    private var shownImage: LoadedImage?
    private var loadingFull = false
    /// The long edge previews are decoded to, for the viewer's screen.
    private var previewPixelSize = 3840

    var isOpen: Bool { controller != nil }
    /// The viewer closed, on this photo (its main file name).
    var onClose: ((String?) -> Void)?
    /// Export, copy, move, clipboard or share for these photos: the app handles them.
    var onFileAction: ((FileAction, [String]) -> Void)?
    /// A folder in the breadcrumb was clicked: the browser shows it.
    var onBrowse: ((URL) -> Void)?

    init(culling: CullingStore) {
        self.culling = culling
        model = ViewerModel(culling: culling)
        model.send = { [weak self] command in
            self?.handle(command)
            self?.controller?.focusCanvas()
        }
        model.openFolder = { [weak self] url in self?.onBrowse?(url) }
    }

    /// Shows [groups] of [folder] (the browser's order) at [index].
    func show(folder: URL, groups: [PhotoGroup], at index: Int) {
        guard !groups.isEmpty else { return }
        model.folder = folder
        model.groups = groups
        photos = groups.map { folder.appendingPathComponent($0.main) }
        self.index = min(max(index, 0), groups.count - 1)
        forward = true
        shownURL = nil
        presentWindow()
        showCurrent()
        #if DEBUG
            autoplayIfAsked()
        #endif
    }

    #if DEBUG
        /// RAWBOY_AUTOPLAY=N (debug builds): step through N photos, open each edge panel, zoom the last photo to 1:1,
        /// report and quit. For timing and smoke tests without a person at the keyboard (`tools/smoke.sh`).
        private func autoplayIfAsked() {
            guard let steps = ProcessInfo.processInfo.environment["RAWBOY_AUTOPLAY"].flatMap(Int.init) else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                for _ in 0..<steps {
                    handle(.next)
                    try? await Task.sleep(for: .milliseconds(700))
                }
                if ProcessInfo.processInfo.environment["RAWBOY_CULL"] != nil { await cullTest() }
                for edge in PanelEdge.allCases {
                    handle(.togglePanel(edge))
                    try? await Task.sleep(for: .milliseconds(500))
                    Trace.log("panel \(edge.rawValue) shown: \(controller?.root.panels[edge]?.isHidden == false)")
                    snapshot(edge)
                }
                handle(.toggleClipping)
                try? await Task.sleep(for: .milliseconds(800))
                if let h = model.histogram {
                    Trace.log(
                        "histogram: highlights \(Histogram.percent(h.highlights)), shadows \(Histogram.percent(h.shadows))"
                    )
                }
                Trace.log("clip overlay on screen: \(controller?.canvas.hasClipOverlay == true)")
                handle(.dismiss)
                handle(.toggleZoom)
                try? await Task.sleep(for: .seconds(4))
                Trace.log("autoplay done at photo \(index + 1) of \(photos.count)")
                NSApp.terminate(nil)
            }
        }

        /// RAWBOY_CULL=1: rates the photo on screen and the next two (3 stars, pick, reject, auto-advancing), prints
        /// the sidecars written, moves the reject to the bin and undoes that. Only for copies of photos.
        private func cullTest() async {
            let start = index
            handle(.setStars(3))
            try? await Task.sleep(for: .milliseconds(300))
            handle(.toggleFlag(.pick))
            try? await Task.sleep(for: .milliseconds(300))
            handle(.toggleFlag(.reject))
            await culling.finishWrites()
            Trace.log("cull: advanced from \(start + 1) to \(index + 1)")
            for group in model.groups[start..<min(start + 3, model.groups.count)] {
                let names = culling.sidecars[group.main] ?? []
                let text = names.first.flatMap { SidecarFiles.read(model.folder!.appendingPathComponent($0)) } ?? ""
                let fields = text.split(separator: "\n").filter {
                    $0.contains("xmp:Rating") || $0.contains("rawboy:Pick") || $0.contains("crs:")
                }
                Trace.log("cull: \(group.main) → \(names) \(fields.map { $0.trimmingCharacters(in: .whitespaces) })")
            }
            await culling.moveRejectsToBin(model.groups)
            try? await Task.sleep(for: .milliseconds(300))
            Trace.log("cull: \(culling.message ?? "") · bin \(culling.binCount) · viewer has \(photos.count)")
            handle(.undo)
            try? await Task.sleep(for: .milliseconds(300))
            Trace.log("cull: \(culling.message ?? "") · bin \(culling.binCount) · viewer has \(photos.count)")

            // M6: turn the photo on screen, export it, move it away and back.
            go(to: 0)
            try? await Task.sleep(for: .milliseconds(500))
            let before = model.fullSize
            handle(.rotate(clockwise: true))
            try? await Task.sleep(for: .milliseconds(800))
            await culling.finishWrites()
            let id = model.current!.main
            let sidecar = (culling.sidecars[id] ?? []).first.flatMap {
                SidecarFiles.read(model.folder!.appendingPathComponent($0))
            }
            Trace.log(
                "rotate: \(id) \(before.map { "\(Int($0.width))×\(Int($0.height))" } ?? "?") → "
                    + "\(model.fullSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? "?"), sidecar orientation "
                    + "\(sidecar.flatMap(XmpSidecar.readOrientation).map(String.init) ?? "none")")
            let exportFolder = model.folder!.appendingPathComponent("export-test")
            try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
            if let out = try? Exporter.export(
                model.folder!.appendingPathComponent(id), orientation: culling.orientation(id), to: exportFolder,
                options: ExportOptions(longEdge: 1080))
            {
                let size = ImageLoader.fullSize(of: out)
                Trace.log(
                    "export: \(out.lastPathComponent) \(size.map { "\(Int($0.width))×\(Int($0.height))" } ?? "?")")
            }
            handle(.rotate(clockwise: false))
            try? await Task.sleep(for: .milliseconds(300))
            await culling.finishWrites()
        }

        private func snapshot(_ edge: PanelEdge) {
            guard let frame = controller?.root.frame(for: edge) else { return }
            let view: AnyView =
                switch edge {
                case .left: AnyView(ActionMenu(model: model))
                case .right: AnyView(InfoPanel(model: model))
                case .top: AnyView(BrowserStrip(model: model))
                }
            Snapshot.write(view.padding(16), size: frame.size, name: "panel-\(edge.rawValue)")
        }
    #endif

    /// A short note over the photo.
    func flash(_ text: String) {
        controller?.canvas.flash(text)
    }

    /// The window to put sheets on, and the view to anchor the share menu to.
    var window: NSWindow? { controller?.window }
    var canvasView: NSView? { controller?.canvas }

    func close() {
        controller?.close()
    }

    private func presentWindow() {
        if controller == nil {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
            let controller = ViewerWindowController(screen: screen, model: model)
            controller.canvas.onCommand = { [weak self] in self?.handle($0) }
            controller.canvas.onNeedsFullResolution = { [weak self] in self?.loadFullResolution() }
            controller.canvas.onFitChanged = { [weak self] in self?.model.isFit = $0 }
            controller.onClose = { [weak self] in
                guard let self else { return }
                self.controller = nil
                self.onClose?(model.current?.main)
            }
            self.controller = controller
            model.isScreenFilling = controller.isScreenFilling
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
        case .go(let target): go(to: target)
        case .toggleZoom: controller?.canvas.toggleZoom()
        case .dismiss: if controller?.closePanels() == false { close() }
        case .close: close()
        case .toggleFullScreen: controller?.toggleScreenFilling()
        case .togglePanel(let edge): controller?.togglePanel(edge)
        case .togglePin(let edge): controller?.togglePin(edge)
        case .toggleChrome: controller?.toggleChrome()
        case .toggleClipping:
            model.showClipping.toggle()
            updateClipOverlay()
        case .setStars(let n): rateCurrent { self.culling.setStars($0, n) }
        case .toggleFlag(let flag): rateCurrent { self.culling.toggleFlag($0, flag) }
        case .unflag: rateCurrent { self.culling.clearFlag($0) }
        case .rotate(let clockwise):
            guard let id = model.current?.main else { return }
            culling.rotate([id], clockwise: clockwise)
        case .undo:
            if let id = culling.undo(), let i = model.groups.firstIndex(where: { $0.main == id }) {
                go(to: i)
                controller?.canvas.flash("Undone")
            }
            updateRatingBadge()
        case .moveToTrash:
            guard let id = model.current?.main else { return }
            Task { await culling.moveToTrash([id]) }
        case .file(let action):
            guard let id = model.current?.main else { return }
            onFileAction?(action, [id])
        case .revealFile:
            if let url = model.currentURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .openInEditor:
            openInEditor()
        }
    }

    /// Rates the photo on screen, says so, and goes on to the next one when auto-advance is on (RawBoy Browser does).
    private func rateCurrent(_ rate: ([String]) -> Void) {
        guard let id = model.current?.main else { return }
        rate([id])
        let label = Self.ratingText(culling.rating(id))
        controller?.canvas.flash(label.isEmpty ? "Not rated" : label)
        updateRatingBadge()
        if culling.autoAdvance, index < photos.count - 1 { go(to: index + 1) }
    }

    /// "★★★", "★★ · Pick", "Rejected", or "" when unrated.
    static func ratingText(_ rating: Rating) -> String {
        if rating.flag == .reject { return "Rejected" }
        let stars = String(repeating: "★", count: rating.stars)
        let pick = rating.flag == .pick ? "Pick" : ""
        return [stars, pick].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// These photos were turned: the one on screen is shown again, turned.
    func orientationsChanged(_ ids: [String]) {
        guard let id = model.current?.main, ids.contains(id) else { return }
        shownURL = nil
        showCurrent()
    }

    /// Ratings changed (another photo's, or the folder's were read).
    func ratingsChanged() {
        updateRatingBadge()
    }

    private func updateRatingBadge() {
        let text = Self.ratingText(model.rating)
        controller?.canvas.ratingText = text
        controller?.canvas.counterText = "\(index + 1) / \(photos.count)" + (text.isEmpty ? "" : "  ·  \(text)")
    }

    /// The photos changed on disk (moved to the bin or the Trash, or back): goes on with [groups], on the same photo
    /// when it is still there, else the one now in its place.
    func replace(groups: [PhotoGroup]) {
        guard let folder = model.folder else { return }
        guard !groups.isEmpty else {
            close()
            return
        }
        let current = model.current?.main
        model.groups = groups
        photos = groups.map { folder.appendingPathComponent($0.main) }
        index = groups.firstIndex { $0.main == current } ?? min(index, groups.count - 1)
        shownURL = nil
        showCurrent()
    }

    private func openInEditor() {
        guard let url = model.currentURL else { return }
        if let app = model.editor.url {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func go(to newIndex: Int) {
        guard !photos.isEmpty else { return }
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
        updateRatingBadge()
        // Metadata only: never reads the file, so an online-only file in a cloud folder isn't downloaded.
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        model.fileSize = values?.fileSize.map(Int64.init)
        model.modified = values?.contentModificationDate
        model.fullSize = nil
        model.metadata = nil
        model.histogram = nil
        Task.detached(priority: .userInitiated) {
            let metadata = PhotoMetadata.read(url)
            await MainActor.run {
                if generation == self.generation { self.model.metadata = metadata }
            }
        }

        let previewPixelSize = previewPixelSize
        let orientation = culling.orientation(url.lastPathComponent)
        Task {
            let started = Date()
            // In this task, before any load, so a size change can't drop previews prefetched for the new size.
            await store.setPreviewPixelSize(previewPixelSize)
            var image = await store.cached(url, .preview, orientation: orientation)
            if image == nil {
                // While a key is held, photos fly past: only decode the one the keys stop on.
                try? await Task.sleep(for: .milliseconds(40))
                guard generation == self.generation else { return }
                let spinner = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled, generation == self.generation { controller.canvas.setLoading(true) }
                }
                image = await store.image(url, .preview, orientation: orientation)
                spinner.cancel()
            }
            guard generation == self.generation else { return }
            if let image {
                controller.canvas.show(image, samePhoto: shownURL == url)
                shownURL = url
                shown(image, generation)
                model.fullSize = image.fullSize
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                Trace.log(
                    "shown \(url.lastPathComponent) in \(ms) ms (\(image.cgImage.width)×\(image.cgImage.height)"
                        + "\(image.isFullResolution ? ", full" : ""))")
            } else {
                controller.canvas.showMessage("Can't open \(url.lastPathComponent).")
                shownURL = nil
            }
            // Neighbours further than the next one are only loaded when they are on this Mac: prefetching must not
            // download a cloud folder.
            let index = index
            let order = PrefetchPlan.order(current: index, count: photos.count, forward: forward).filter {
                abs($0 - index) == 1 || !CloudStatus.isOnlineOnly(photos[$0])
            }
            await store.prefetch(order.map { (photos[$0], culling.orientation(photos[$0].lastPathComponent)) })
        }
    }

    /// A new photo is on screen: count its levels, and redo the clipping warning when it is on.
    private func shown(_ image: LoadedImage, _ generation: Int) {
        shownImage = image
        controller?.canvas.setClipOverlay(nil)
        updateClipOverlay()
        Task.detached(priority: .userInitiated) {
            let histogram = ImageAnalysis.histogram(of: image.cgImage)
            await MainActor.run {
                if generation == self.generation { self.model.histogram = histogram }
            }
        }
    }

    /// The clipping warning for the picture on screen, made in the background; cleared when it is off.
    private func updateClipOverlay() {
        guard model.showClipping, let image = shownImage else {
            controller?.canvas.setClipOverlay(nil)
            return
        }
        let generation = generation
        Task.detached(priority: .userInitiated) {
            let overlay = ImageAnalysis.clipOverlay(of: image.cgImage)
            await MainActor.run {
                guard generation == self.generation, self.model.showClipping,
                    self.shownImage?.cgImage === image.cgImage
                else { return }
                self.controller?.canvas.setClipOverlay(overlay)
                #if DEBUG
                    if let overlay { Snapshot.writeImage(overlay, name: "clip-overlay") }
                #endif
            }
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
            let image = await store.image(url, .full, orientation: culling.orientation(url.lastPathComponent))
            guard generation == self.generation else { return }
            controller.canvas.setLoading(false)
            if let image {
                controller.canvas.show(image, samePhoto: true)
                shownImage = image
                updateClipOverlay()
                Trace.log("full \(url.lastPathComponent) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            }
        }
    }
}
