import AppKit
import Observation
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles

/// App-wide state shared by the browser and the viewer.
@MainActor
@Observable
final class AppModel {
    /// The grid items being dragged to a folder in Places (see `beginDrag`).
    var drag: DragSet?
    static let shared = AppModel()

    let culling = CullingStore()
    let browser: BrowserModel
    let viewer: ViewerSession
    let compare: CompareSession
    @ObservationIgnored private var watcher: FolderWatcher?

    init() {
        browser = BrowserModel(culling: culling)
        viewer = ViewerSession(culling: culling)
        compare = CompareSession(culling: culling)
        compare.onClose = { [weak self] chosen in
            if let chosen { self?.browser.select(chosen) }
            NSApp.windows.first { !($0 is ViewerWindow) && $0.isVisible }?.makeKeyAndOrderFront(nil)
        }
        viewer.onCompare = { [weak self] ids in self?.openCompare(ids) }
        culling.onRatingsChanged = { [weak self] in
            self?.browser.ratingsChanged()
            self?.viewer.ratingsChanged()
            self?.compare.ratingsChanged()
        }
        culling.onOrientationsChanged = { [weak self] ids in
            self?.viewer.orientationsChanged(ids)
            self?.compare.orientationsChanged(ids)
        }
        viewer.onFileAction = { [weak self] action, ids in self?.perform(action, ids) }
        culling.onFilesChanged = { [weak self] in self?.folderContentsChanged() }
        browser.onLoad = { [weak self] folder in self?.watch(folder) }
        viewer.onClose = { [weak self] current in
            // Back in the browser on the photo the viewer showed last.
            if let current { self?.browser.select(current) }
            NSApp.windows.first { !($0 is ViewerWindow) && $0.isVisible }?.makeKeyAndOrderFront(nil)
        }
        viewer.onBrowse = { [weak self] folder in self?.browse(folder) }
    }

    /// Opens what Finder, a drop or the Open dialog handed over: a folder in the browser, a photo in the viewer (with
    /// its folder in the browser behind it).
    func open(_ url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            browse(url)
            #if DEBUG
                autoplayBrowserIfAsked()
            #endif
        } else {
            browser.load(url.deletingLastPathComponent(), select: url.lastPathComponent)
            if let id = browser.anchor, browser.selection.contains(id) { openViewer(at: id) }
        }
    }

    /// Shows [folder] in the browser (closing the viewer when it is open).
    func browse(_ folder: URL) {
        if viewer.isOpen { viewer.close() }
        browser.load(folder)
    }

    /// Opens the viewer on the browser's photos, in the browser's order, at [id].
    func openViewer(at id: String) {
        guard let folder = browser.folder, let index = browser.visible.firstIndex(where: { $0.id == id }) else {
            return
        }
        viewer.show(folder: folder, groups: browser.visible.map(\.group), at: index)
    }

    // MARK: Watching the folder

    /// Files appeared, went, or were moved: the browser reads the folder again and the viewer goes on with what is
    /// left (or is back).
    func folderContentsChanged() {
        browser.reload()
        if viewer.isOpen { viewer.replace(groups: browser.visible.map(\.group)) }
    }

    /// Watches the open folder, so changes made elsewhere (new photos, darktable or RawBoy Web rating) show up here.
    private func watch(_ folder: URL) {
        guard watcher?.folder != folder.standardizedFileURL else { return }
        watcher = FolderWatcher(folder: folder) { [weak self] change in self?.folderChanged(change) }
    }

    private func folderChanged(_ change: FolderWatcher.Change) {
        // Only photos, sidecars and folders matter: atomic writes' temporary files ("NAME.xmp.sb-…") don't. Our own
        // sidecar writes and moves come back as events too: they are already accounted for.
        guard let folder = browser.folder else { return }
        func relevant(_ name: String) -> Bool {
            if PhotoFileType(fileName: name) != nil || name.lowercased().hasSuffix(".xmp") { return true }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(name).path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        let structural = change.structural.filter { relevant($0) && !culling.isOwnChange($0) }
        let modified = change.modified.filter { !culling.isOwnChange($0) }
        let photos = modified.filter { PhotoFileType(fileName: $0) != nil }
        if !photos.isEmpty { viewer.forget(photos) }
        if !structural.isEmpty || !photos.isEmpty {
            Trace.log("folder changed: \(structural.union(photos).sorted().joined(separator: ", "))")
            folderContentsChanged()
            return
        }
        let sidecars = modified.filter { $0.lowercased().hasSuffix(".xmp") }
        guard !sidecars.isEmpty else { return }
        let ids = browser.photos.filter { photo in
            (culling.sidecars[photo.id] ?? photo.group.sidecars).contains { sidecars.contains($0) }
        }.map(\.id)
        Trace.log("sidecars changed: \(sidecars.sorted().joined(separator: ", "))")
        culling.refresh(ids)
    }

    // MARK: Culling (menus and keys, wherever the focus is)

    /// The viewer (or Compare) when it is the key window, else the browser.
    private var viewerIsKey: Bool { (viewer.isOpen || compare.isOpen) && NSApp.keyWindow is ViewerWindow }

    /// Compare [ids] (2–4); one photo is compared with the one after it in the browser.
    func openCompare(_ ids: [String]) {
        guard let folder = browser.folder else { return }
        var ids = ids
        if ids.count == 1, let i = browser.visible.firstIndex(where: { $0.id == ids[0] }),
            browser.visible.indices.contains(i + 1)
        {
            ids.append(browser.visible[i + 1].id)
        }
        guard ids.count >= 2 else { return }
        if viewer.isOpen { viewer.close() }
        compare.show(folder: folder, ids: ids, order: browser.visible.map(\.group))
    }

    /// ⌘Z: text editing in a text field, else the last rating or file move.
    func undo() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            return
        }
        if viewerIsKey {
            viewer.handle(.undo)
        } else if let id = culling.undo() {
            browser.select(id)
        }
    }

    /// ⌘[ / ⌘]: the photo in the viewer, else the browser's selection.
    func rotate(clockwise: Bool) {
        if viewerIsKey {
            viewer.handle(.rotate(clockwise: clockwise))
        } else {
            culling.rotate(browser.ratingTargets, clockwise: clockwise)
        }
    }

    /// ⌘⌫ and ⌦: the photo in the viewer, else the browser's selection.
    func moveToTrash() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
            return
        }
        if viewerIsKey {
            viewer.handle(.moveToTrash)
        } else {
            // Only what is selected: with nothing selected, the anchor isn't something to delete.
            guard !browser.selection.isEmpty else { return }
            let ids = browser.ratingTargets
            Task { await culling.moveToTrash(ids) }
        }
    }

    /// The browser's rating keys (by physical key, as the viewer's): 1–5, 0, P, X, U on the selection.
    func browserKey(_ event: NSEvent) -> Bool {
        // ⌦ (Fn-⌫ on a laptop) trashes the selection; plain ⌫ goes up a folder. Here rather than in the views, so it
        // works whichever view (grid, list, preview) has the focus. ⌘⌫ is the menu's.
        if !viewerIsKey, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
            event.keyCode == 51 || event.keyCode == 117, !(NSApp.keyWindow is NSPanel),
            !(NSApp.keyWindow?.firstResponder is NSTextView), browser.folder != nil
        {
            if event.keyCode == 51 { browser.goUp() } else { moveToTrash() }
            return true
        }
        // ⌘A by physical key: SwiftUI's key presses are characters, "ф" on a Ukrainian layout.
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if !viewerIsKey, event.keyCode == 0, mods == .command, !(NSApp.keyWindow is NSPanel),
            !(NSApp.keyWindow?.firstResponder is NSTextView), browser.folder != nil
        {
            browser.selectAll()
            return true
        }
        guard !viewerIsKey, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            !(NSApp.keyWindow?.firstResponder is NSTextView), let command = ViewerKeys.command(for: event)
        else { return false }
        let ids = browser.ratingTargets
        guard !ids.isEmpty else { return false }
        switch command {
        case .setStars(let n): culling.setStars(ids, n)
        case .toggleFlag(let flag): culling.toggleFlag(ids, flag)
        case .unflag: culling.clearFlag(ids)
        case .rotate(let clockwise): culling.rotate(ids, clockwise: clockwise)
        case .compare: openCompare(ids)
        case .toggleSlideshow:
            openViewer(at: ids[0])
            viewer.startSlideshow()
        default: return false
        }
        return true
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of photos, or one photo in it."
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }
}

#if DEBUG
    extension AppModel {
        /// tools/smoke.sh opens a folder and wants the viewer: snapshots of the browser and real cells first.
        fileprivate func autoplayBrowserIfAsked() {
            if ProcessInfo.processInfo.environment["RAWBOY_AUTOPLAY"] != nil {
                Task {
                    // Dates first, so the grid is in its final order.
                    try? await Task.sleep(for: .milliseconds(300))
                    Snapshot.write(BrowserView(app: self), size: CGSize(width: 1280, height: 820), name: "browser")
                    Snapshot.write(HelpView(), size: CGSize(width: 640, height: 1500), name: "help")
                    // Real cells with their thumbnails (the grid's load after the snapshot).
                    var cells: [(BrowsePhoto, CGImage?)] = []
                    for photo in browser.visible.prefix(4) {
                        let thumb = await browser.thumbnails.thumbnail(
                            photo.url, size: photo.size, modified: photo.modified)
                        cells.append((photo, thumb?.cgImage))
                    }
                    let size = browser.thumbnailSize
                    let store = browser.thumbnails
                    let culling = culling
                    Snapshot.write(
                        HStack(spacing: 10) {
                            ForEach(cells, id: \.0.id) { photo, image in
                                PhotoCell(
                                    photo: photo, size: size, isSelected: false, rating: culling.rating(photo.id),
                                    hasSidecar: culling.hasSidecar(photo.id), store: store,
                                    image: image)
                            }
                        }.padding(10),
                        size: CGSize(width: 4 * (size + 10) + 20, height: size * 0.75 + 50), name: "cells")
                    Trace.log("browser: \(browser.items.map(\.id).joined(separator: ", "))")
                    if let first = browser.visible.first {
                        openViewer(at: first.id)
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
#endif
