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
    private var slideshow: Task<Void, Never>?
    /// Seconds per photo in a slideshow (Settings).
    static var slideshowSeconds: Double { SettingsKeys.slideshow }
    /// Compare [ids] (2–4), in the browser's order: the app opens the compare view.
    var onCompare: (([String]) -> Void)?
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
                if ProcessInfo.processInfo.environment["RAWBOY_CROP"] != nil {
                    await cropTest()
                    NSApp.terminate(nil)
                    return
                }
                if ProcessInfo.processInfo.environment["RAWBOY_WATCH"] != nil {
                    await watchTest()
                    NSApp.terminate(nil)
                    return
                }
                if ProcessInfo.processInfo.environment["RAWBOY_M7"] != nil {
                    await m7Test()
                    NSApp.terminate(nil)
                    return
                }
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

        /// RAWBOY_CROP=1 (on copies): crops the photo on screen through the tool, prints the sidecar's RawBoy edits,
        /// renders the canvas next to a Core Graphics crop of the same picture, turns it, exports it, undoes.
        private func cropTest() async {
            guard let controller, let folder = model.folder, let id = model.current?.main else { return }
            let sidecarName = (culling.sidecars[id] ?? []).first ?? PhotoGroups.stem(of: id) + ".xmp"
            func develop() -> String {
                XmpSidecar.readDevelop(SidecarFiles.read(folder.appendingPathComponent(sidecarName)) ?? "") ?? "none"
            }
            handle(.crop)
            try? await Task.sleep(for: .milliseconds(500))
            guard let state = controller.debugCropState else {
                Trace.log("crop: the tool didn't open")
                return
            }
            let wanted = CropRect(left: 0.1, top: 0.05, right: 0.6, bottom: 0.65)
            state.crop = wanted
            state.aspect = .threeTwo
            try? await Task.sleep(for: .milliseconds(300))
            // The tool as drawn: the overlay (AppKit drawing) over the canvas's layers.
            if let window = controller.window, let content = window.contentView,
                let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
            {
                content.cacheDisplay(in: content.bounds, to: rep)
                if let overlayImage = rep.cgImage,
                    let ctx = CGContext(
                        data: nil, width: overlayImage.width, height: overlayImage.height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                {
                    let scale = Double(overlayImage.width) / content.bounds.width
                    ctx.scaleBy(x: scale, y: scale)
                    controller.canvas.layer?.render(in: ctx)
                    ctx.resetClip()
                    ctx.scaleBy(x: 1 / scale, y: 1 / scale)
                    ctx.draw(
                        overlayImage, in: CGRect(x: 0, y: 0, width: overlayImage.width, height: overlayImage.height))
                    if let both = ctx.makeImage() { Snapshot.writeImage(both, name: "crop-tool") }
                }
            }
            Trace.log(
                "crop: 3:2 gives \(String(format: "%.3f", state.crop.width * state.frameSize.width / (state.crop.height * state.frameSize.height)))"
            )
            state.onDone(state.crop)
            await culling.finishWrites()
            try? await Task.sleep(for: .milliseconds(800))
            Trace.log("crop: tool closed \(!controller.isCropping), canvas crop \(controller.canvas.crop == wanted)")
            Trace.log("crop: rawboy:Develop \(develop())")
            // The canvas as drawn, and the same crop by Core Graphics, to compare.
            if let layer = controller.canvas.layer, let image = controller.canvas.image {
                let frame = controller.canvas.imageFrame
                let scale = 1.0
                if let ctx = CGContext(
                    data: nil, width: Int(frame.width * scale), height: Int(frame.height * scale), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                {
                    ctx.translateBy(x: -frame.minX, y: -frame.minY)
                    layer.render(in: ctx)
                    if let shown = ctx.makeImage() { Snapshot.writeImage(shown, name: "crop-canvas") }
                }
                Snapshot.writeImage(Orienting.crop(image.cgImage, wanted), name: "crop-expected")
            }
            handle(.rotate(clockwise: true))
            await culling.finishWrites()
            try? await Task.sleep(for: .milliseconds(800))
            Trace.log("crop: turned, crop \(String(describing: culling.crop(id))), rawboy:Develop \(develop())")
            let out = folder.appendingPathComponent("export-crop")
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            if let file = try? Exporter.export(
                folder.appendingPathComponent(id), orientation: culling.orientation(id), crop: culling.crop(id),
                to: out,
                options: ExportOptions(longEdge: 1000))
            {
                Trace.log(
                    "crop: export \(ImageLoader.fullSize(of: file).map { "\(Int($0.width))×\(Int($0.height))" } ?? "?")"
                )
            }
            handle(.undo)
            handle(.undo)
            await culling.finishWrites()
            try? await Task.sleep(for: .milliseconds(500))
            Trace.log(
                "crop: after two undos: crop \(String(describing: culling.crop(id))), rawboy:Develop \(develop())")
        }

        /// RAWBOY_WATCH=1 (on copies): a rating made here causes no reload; a sidecar written from outside is read
        /// again; a photo copied in, then removed, shows up and goes.
        private func watchTest() async {
            guard let folder = model.folder, model.groups.count >= 2 else { return }
            let own = model.groups[0].main
            let other = model.groups[1]
            culling.autoAdvance = false
            handle(.setStars(2))
            await culling.finishWrites()
            try? await Task.sleep(for: .seconds(1.5))
            Trace.log("watch: rated \(own) here (no reload expected above)")
            let sidecar = folder.appendingPathComponent(other.stem + ".xmp")
            let text = SidecarFiles.read(sidecar)
            // Written in place (as some apps do), or created when the photo had no sidecar.
            let stars = XmpSidecar.read(text ?? "").stars == 5 ? 4 : 5
            let outside = try? XmpSidecar.write(text, Rating(stars: stars))
            await Task.detached { try? Data((outside ?? "").utf8).write(to: sidecar) }.value
            try? await Task.sleep(for: .seconds(1.5))
            Trace.log("watch: \(other.main) after an outside write: \(culling.rating(other.main).stars) stars")
            let copy = folder.appendingPathComponent("ZZ_copy.dng")
            try? FileManager.default.copyItem(at: folder.appendingPathComponent(own), to: copy)
            try? await Task.sleep(for: .seconds(1.5))
            Trace.log(
                "watch: after copying a photo in: browser \(AppModel.shared.browser.photos.count), viewer \(photos.count)"
            )
            try? FileManager.default.removeItem(at: copy)
            try? await Task.sleep(for: .seconds(1.5))
            Trace.log(
                "watch: after removing it: browser \(AppModel.shared.browser.photos.count), viewer \(photos.count)")
            culling.autoAdvance = true
        }

        /// RAWBOY_M7=1: real preview on and off, one slide of a slideshow, and Compare (choose, step, rate, close).
        private func m7Test() async {
            let wasReal = model.realPreview
            if !wasReal { handle(.toggleRealPreview) }
            try? await Task.sleep(for: .milliseconds(1500))
            Trace.log("real preview: \(model.realPreview), \(model.current?.main ?? "")")
            if !wasReal { handle(.toggleRealPreview) }
            try? await Task.sleep(for: .milliseconds(500))
            let start = index
            handle(.toggleSlideshow)
            try? await Task.sleep(for: .seconds(Self.slideshowSeconds + 1))
            Trace.log("slideshow: \(start + 1) → \(index + 1), running \(model.isSlideshow)")
            handle(.toggleSlideshow)
            handle(.compare)
            try? await Task.sleep(for: .milliseconds(1500))
            let compare = AppModel.shared.compare
            Trace.log("compare open \(compare.isOpen), viewer open \(isOpen): \(compare.debugState)")
            compare.debugChoose(1)
            try? await Task.sleep(for: .milliseconds(800))
            Trace.log("compare after choosing the right one: \(compare.debugState)")
            compare.debugStep(true)
            try? await Task.sleep(for: .milliseconds(800))
            Trace.log("compare after →: \(compare.debugState)")
            let zooms = compare.debugZoomFirst()
            Trace.log(
                "compare zoom: "
                    + zooms.map { "×\(String(format: "%.2f", $0.factor)) at \(String(format: "%.3f", $0.centre.x))" }
                    .joined(separator: " | "))
            compare.debugKey(.setStars(4))
            try? await Task.sleep(for: .milliseconds(300))
            Trace.log("compare rated: \(compare.debugState)")
            compare.debugKey(.setStars(4))
            await culling.finishWrites()
            compare.close()
            try? await Task.sleep(for: .milliseconds(500))
            Trace.log("compare closed \(!compare.isOpen); browser selection \(AppModel.shared.browser.anchor ?? "")")
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
        stopSlideshow()
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
        case .dismiss:
            if model.isSlideshow {
                stopSlideshow()
            } else if controller?.closePanels() == false {
                close()
            }
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
        case .crop: startCrop()
        case .toggleRealPreview:
            model.realPreview.toggle()
            controller?.canvas.flash(model.realPreview ? "Raws developed by macOS (R)" : "Camera previews (R)")
            shownURL = nil
            showCurrent()
        case .toggleSlideshow:
            model.isSlideshow ? stopSlideshow() : startSlideshow()
        case .compare:
            // The photo on screen and the next ones, up to four.
            let ids = model.groups[index..<min(index + 2, model.groups.count)].map(\.main)
            if ids.count >= 2 {
                onCompare?(ids)
            } else {
                controller?.canvas.flash("Nothing after this photo to compare")
            }
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

    // MARK: Crop

    /// The crop tool on the photo on screen. RawBoy's straightened photos are left to RawBoy: the viewer can't draw
    /// the frame their crop is measured in.
    func startCrop() {
        guard let controller, let id = model.current?.main, let image = controller.canvas.image else { return }
        if culling.straightened.contains(id) {
            controller.canvas.flash("Straightened in RawBoy: crop it there")
            return
        }
        stopSlideshow()
        let state = CropToolState(crop: culling.crop(id) ?? .full, frameSize: image.fullSize)
        state.onDone = { [weak self] crop in
            guard let self else { return }
            controller.endCrop()
            controller.canvas.navigationEnabled = true
            culling.setCrop(id, crop)
            controller.canvas.crop = culling.crop(id)
            controller.canvas.flash(crop.isFull ? "Not cropped" : "Cropped (RawBoy reads it too)")
        }
        /// Applies the crop and writes the cropped photo (the last export format and quality, full size).
        func saveCopy(_ crop: CropRect, to destination: URL, stem: String?, suffix: String) {
            guard let folder = model.folder else { return }
            controller.endCrop()
            controller.canvas.navigationEnabled = true
            culling.setCrop(id, crop)
            controller.canvas.crop = culling.crop(id)
            let source = folder.appendingPathComponent(id)
            let orientation = culling.orientation(id)
            var options = AppModel.exportOptions
            options.longEdge = nil
            options.shortEdge = nil
            options.crop = nil
            controller.canvas.flash("Saving cropped copy…")
            Task.detached(priority: .userInitiated) {
                let result = Result {
                    try Exporter.export(
                        source, orientation: orientation, crop: crop.isFull ? nil : crop, to: destination,
                        options: options, stem: stem, suffix: suffix)
                }
                await MainActor.run {
                    switch result {
                    case .success(let url):
                        controller.canvas.flash("Saved \(url.lastPathComponent) in \(destination.lastPathComponent)")
                    case .failure:
                        controller.canvas.flash("Couldn't save the copy")
                    }
                }
            }
        }
        // Next to the original, with _crop added to its name.
        state.onSaveCopy = { [weak self] crop in
            guard let folder = self?.model.folder else { return }
            saveCopy(crop, to: folder, stem: nil, suffix: "_crop")
        }
        // A name and folder of the person's choosing; the crop tool stays open if they cancel.
        state.onSaveCopyAs = { [weak self] crop in
            guard let folder = self?.model.folder else { return }
            let format = AppModel.exportOptions.format
            let panel = NSSavePanel()
            panel.allowedContentTypes = [format == .jpeg ? .jpeg : .heic]
            panel.canCreateDirectories = true
            panel.directoryURL = folder
            panel.nameFieldStringValue = "\(PhotoGroups.stem(of: id))_crop.\(format.fileExtension)"
            panel.message = "Save the cropped photo as:"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            saveCopy(
                crop, to: url.deletingLastPathComponent(), stem: url.deletingPathExtension().lastPathComponent,
                suffix: "")
        }
        state.onCancel = { [weak self] in
            guard let self else { return }
            controller.endCrop()
            controller.canvas.navigationEnabled = true
            controller.canvas.crop = culling.crop(id)
        }
        controller.canvas.navigationEnabled = false
        controller.canvas.crop = nil
        controller.beginCrop(state)
    }

    // MARK: Slideshow

    /// From the photo on screen, one every [slideshowSeconds], crossfading, panels hidden; stops at the end, on S or
    /// Esc. Moving by hand starts the wait again.
    func startSlideshow() {
        guard controller != nil, photos.count > 1 else { return }
        model.isSlideshow = true
        _ = controller?.closePanels()
        controller?.canvas.flash("Slideshow · S or Esc to stop")
        scheduleSlide()
    }

    func stopSlideshow() {
        slideshow?.cancel()
        slideshow = nil
        guard model.isSlideshow else { return }
        model.isSlideshow = false
        controller?.canvas.flash("Slideshow stopped")
    }

    private func scheduleSlide() {
        slideshow?.cancel()
        slideshow = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.slideshowSeconds))
            guard let self, !Task.isCancelled, model.isSlideshow else { return }
            if index < photos.count - 1 {
                go(to: index + 1)
            } else {
                stopSlideshow()
                controller?.canvas.flash("End of the slideshow")
            }
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

    /// [ratingText] as VoiceOver should say it ("3 stars, Pick").
    static func spoken(_ text: String) -> String {
        let stars = text.filter { $0 == "★" }.count
        let rest = text.replacingOccurrences(of: "★", with: "").replacingOccurrences(of: " · ", with: "")
            .trimmingCharacters(in: .whitespaces)
        return [stars > 0 ? "\(stars) star\(stars == 1 ? "" : "s")" : nil, rest.isEmpty ? nil : rest]
            .compactMap { $0 }.joined(separator: ", ")
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
        if let name = model.current?.main {
            controller?.canvas.setAccessibilityLabel(
                "\(name), \(index + 1) of \(photos.count)" + (text.isEmpty ? "" : ", \(Self.spoken(text))"))
        }
        controller?.canvas.ratingText = text
        controller?.canvas.counterText = "\(index + 1) / \(photos.count)" + (text.isEmpty ? "" : "  ·  \(text)")
    }

    /// These files changed in place (edited elsewhere): their pictures are made again.
    func forget(_ names: Set<String>) {
        guard let folder = model.folder else { return }
        Task {
            for name in names { await store.forget(folder.appendingPathComponent(name)) }
        }
    }

    /// The photos changed on disk (moved to the bin or the Trash, or back): goes on with [groups], on the same photo
    /// when it is still there, else the one now in its place.
    func replace(groups: [PhotoGroup]) {
        guard let folder = model.folder else { return }
        guard !groups.isEmpty else {
            model.groups = []
            photos = []
            close()
            return
        }
        // Nothing changed (a date read that kept the order): no reload, no flicker.
        if groups == model.groups { return }
        let current = model.current?.main
        let target = PhotoOrder.nextAfterRemoval(
            previous: model.groups.map(\.main), remaining: groups.map(\.main), current: current, index: index)
        model.groups = groups
        photos = groups.map { folder.appendingPathComponent($0.main) }
        index = target.flatMap { id in groups.firstIndex { $0.main == id } } ?? min(index, groups.count - 1)
        shownURL = nil
        showCurrent()
    }

    private func openInEditor() {
        guard let url = model.currentURL else { return }
        let app = model.editor.url
        // The editor reads the sidecar when it opens the photo: a rating, turn or crop made a moment ago goes first.
        Task {
            await culling.finishWrites()
            if let app {
                // The async variant, not a completion handler: a closure written here is @MainActor, and
                // LaunchServices calls handlers on its own queue, where Swift's isolation check traps (macOS 27).
                _ = try? await NSWorkspace.shared.open(
                    [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func go(to newIndex: Int) {
        guard !photos.isEmpty else { return }
        let clamped = min(max(newIndex, 0), photos.count - 1)
        guard clamped != index else { return }
        forward = clamped > index
        index = clamped
        showCurrent()
        if model.isSlideshow { scheduleSlide() }
    }

    /// Which picture to load for [url]: a raw developed by macOS when real preview is on, else the camera's.
    private func kind(_ url: URL, full: Bool) -> ImageStore.Kind {
        let developed = model.realPreview && PhotoFileType(fileName: url.lastPathComponent) == .raw
        return developed ? (full ? .developedFull : .developed) : (full ? .full : .preview)
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
            let kind = kind(url, full: false)
            var image = await store.cached(url, kind, orientation: orientation)
            if image == nil {
                // While a key is held, photos fly past: only decode the one the keys stop on.
                try? await Task.sleep(for: .milliseconds(40))
                guard generation == self.generation else { return }
                let spinner = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled, generation == self.generation { controller.canvas.setLoading(true) }
                }
                image = await store.image(url, kind, orientation: orientation)
                spinner.cancel()
            }
            guard generation == self.generation else { return }
            if let image {
                controller.canvas.crop = culling.crop(url.lastPathComponent)
                controller.canvas.show(image, samePhoto: shownURL == url, fade: model.isSlideshow)
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
            await store.prefetch(
                order.map { (photos[$0], culling.orientation(photos[$0].lastPathComponent)) }, kind: kind)
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
            let image = await store.image(
                url, kind(url, full: true), orientation: culling.orientation(url.lastPathComponent))
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
