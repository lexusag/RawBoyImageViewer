import AppKit
import RawBoyBrowseKit
import ViewerImaging

/// Photos side by side, zoomed and panned together.
///
/// Two photos: the chosen one (amber frame) and a challenger. Clicking a photo chooses it and the next photo of the
/// folder takes the other place; ← → step the challenger through the folder; rating keys rate the chosen one.
/// Three or four photos: clicking (or ← →) chooses one, and rating keys rate it. Esc, G or Return go back to the
/// browser on the chosen photo.
@MainActor
final class CompareSession {
    private let culling: CullingStore
    private var controller: CompareWindowController?
    private let store = ImageStore(budget: 800_000_000)
    private var folder: URL?
    /// The browser's photos, for the challengers.
    private var order: [PhotoGroup] = []
    /// What each pane shows (photo ids).
    private var panes: [String] = []
    private var chosen = 0
    private var shared = SharedZoom.fit

    /// Closed, on the chosen photo.
    var onClose: ((String?) -> Void)?

    init(culling: CullingStore) {
        self.culling = culling
    }

    var isOpen: Bool { controller != nil }

    /// Compares [ids] (2–4) of [folder]; [order] is the browser's, for the next challengers.
    func show(folder: URL, ids: [String], order: [PhotoGroup]) {
        let ids = Array(ids.prefix(4))
        guard ids.count >= 2 else { return }
        self.folder = folder
        self.order = order
        panes = ids
        chosen = 0
        shared = .fit
        controller?.close()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let controller = CompareWindowController(screen: screen, count: ids.count)
        self.controller = controller
        Task {
            let columns = ids.count == 4 ? 2 : ids.count
            await store.setPreviewPixelSize(
                Int(max(screen.frame.width / Double(columns), screen.frame.height) * screen.backingScaleFactor))
        }
        for (i, canvas) in controller.canvases.enumerated() {
            canvas.navigationEnabled = false
            canvas.onCommand = { [weak self] in self?.handle($0, from: i) }
            canvas.onZoomChanged = { [weak self] in self?.zoomed($0, from: i) }
            canvas.onClick = { [weak self] in self?.choose(i) }
            canvas.onNeedsFullResolution = { [weak self] in self?.loadFull(i) }
        }
        controller.onClose = { [weak self] in
            guard let self else { return }
            self.controller = nil
            onClose?(panes.indices.contains(chosen) ? panes[chosen] : nil)
        }
        controller.present()
        for i in panes.indices { load(i) }
        updateBadges()
        controller.canvases.first?.flash(
            ids.count == 2
                ? "Click the better one: the next photo takes the other place · ← → change it"
                : "Click a photo to rate it · Esc to go back")
    }

    func close() { controller?.close() }

    // MARK: Panes

    private func load(_ i: Int, full: Bool = false) {
        guard let folder, let controller, panes.indices.contains(i) else { return }
        let id = panes[i]
        let url = folder.appendingPathComponent(id)
        let raw = PhotoFileType(fileName: id) == .raw && UserDefaults.standard.bool(forKey: "viewer.realPreview")
        let kind: ImageStore.Kind = raw ? (full ? .developedFull : .developed) : (full ? .full : .preview)
        let orientation = culling.orientation(id)
        let canvas = controller.canvases[i]
        canvas.captionText = id
        if !full { canvas.setLoading(true) }
        Task {
            let image = await store.image(url, kind, orientation: orientation)
            guard self.panes.indices.contains(i), self.panes[i] == id else { return }
            canvas.setLoading(false)
            if let image {
                canvas.show(image, samePhoto: full)
                // A photo coming in takes on the zoom the others have.
                if !full { canvas.applyShared(shared) }
            } else {
                canvas.showMessage("Can't open \(id).")
            }
        }
    }

    private func loadFull(_ i: Int) { load(i, full: true) }

    private func zoomed(_ zoom: SharedZoom, from i: Int) {
        shared = zoom
        for (j, canvas) in (controller?.canvases ?? []).enumerated() where j != i { canvas.applyShared(zoom) }
    }

    /// Clicking a pane chooses it; with two, the next photo takes the other place.
    private func choose(_ i: Int) {
        guard panes.indices.contains(i) else { return }
        chosen = i
        updateBadges()
        guard panes.count == 2 else { return }
        let other = 1 - i
        if let next = nextChallenger(after: panes.max { index(of: $0) < index(of: $1) }) {
            panes[other] = next
            load(other)
            updateBadges()
        } else {
            controller?.canvases[other].flash("That was the last photo")
        }
    }

    private func index(of id: String) -> Int { order.firstIndex { $0.main == id } ?? -1 }

    /// The next photo in the browser's order after [id] that isn't on screen.
    private func nextChallenger(after id: String?) -> String? {
        let start = id.map(index(of:)) ?? -1
        return order[(start + 1)...].first { !panes.contains($0.main) }?.main
    }

    /// ← → with two photos: the challenger steps through the folder; with more, the choice moves.
    private func step(_ forward: Bool) {
        guard panes.count == 2 else {
            chosen = (chosen + (forward ? 1 : panes.count - 1)) % panes.count
            updateBadges()
            return
        }
        let other = 1 - chosen
        var i = index(of: panes[other])
        repeat { i += forward ? 1 : -1 } while order.indices.contains(i) && order[i].main == panes[chosen]
        guard order.indices.contains(i) else {
            controller?.canvases[other].flash(forward ? "That was the last photo" : "That was the first photo")
            return
        }
        panes[other] = order[i].main
        load(other)
        updateBadges()
    }

    #if DEBUG
        var debugState: String { "panes \(panes), chosen \(chosen), shared factor \(shared.factor)" }
        func debugChoose(_ i: Int) { choose(i) }
        func debugStep(_ forward: Bool) { step(forward) }
        func debugKey(_ command: ViewerCommand) { handle(command, from: chosen) }
        /// Zooms the first pane to 1:1 at a point right of its centre; returns every pane's shared zoom.
        func debugZoomFirst() -> [SharedZoom] {
            controller?.canvases.first?.toggleZoom(at: Point2D(x: 200, y: 0))
            return controller?.canvases.map(\.sharedZoom) ?? []
        }
    #endif

    // MARK: Keys and ratings

    private func handle(_ command: ViewerCommand, from pane: Int) {
        guard panes.indices.contains(chosen) else { return }
        let id = panes[chosen]
        switch command {
        case .next: step(true)
        case .previous: step(false)
        case .setStars(let n): culling.setStars([id], n)
        case .toggleFlag(let flag): culling.toggleFlag([id], flag)
        case .unflag: culling.clearFlag([id])
        case .rotate(let clockwise): culling.rotate([id], clockwise: clockwise)
        case .undo: culling.undo()
        case .dismiss, .close: close()
        case .toggleFullScreen: controller?.toggleScreenFilling()
        default: break
        }
    }

    /// Ratings changed: the badges follow.
    func ratingsChanged() { updateBadges() }

    /// Photos were turned: the ones on screen are loaded again.
    func orientationsChanged(_ ids: [String]) {
        for (i, id) in panes.enumerated() where ids.contains(id) { load(i) }
    }

    private func updateBadges() {
        for (i, canvas) in (controller?.canvases ?? []).enumerated() where panes.indices.contains(i) {
            canvas.isHighlighted = i == chosen
            canvas.ratingText = ViewerSession.ratingText(culling.rating(panes[i]))
        }
    }
}
