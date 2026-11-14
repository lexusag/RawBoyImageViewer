import AppKit
import Observation
import SwiftUI
import ViewerFiles

/// App-wide state shared by the browser and the viewer.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let culling = CullingStore()
    let browser: BrowserModel
    let viewer: ViewerSession

    init() {
        browser = BrowserModel(culling: culling)
        viewer = ViewerSession(culling: culling)
        culling.onRatingsChanged = { [weak self] in
            self?.browser.ratingsChanged()
            self?.viewer.ratingsChanged()
        }
        culling.onFilesChanged = { [weak self] in
            guard let self else { return }
            browser.reload()
            // The viewer keeps going on the photos that are left (or are back).
            if viewer.isOpen { viewer.replace(groups: browser.visible.map(\.group)) }
        }
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

    // MARK: Culling (menus and keys, wherever the focus is)

    /// The viewer when it is the key window, else the browser.
    private var viewerIsKey: Bool { viewer.isOpen && NSApp.keyWindow is ViewerWindow }

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

    /// ⌘⌫: the photo in the viewer, else the browser's selection.
    func moveToTrash() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
            return
        }
        if viewerIsKey {
            viewer.handle(.moveToTrash)
        } else {
            let ids = browser.ratingTargets
            Task { await culling.moveToTrash(ids) }
        }
    }

    /// The browser's rating keys (by physical key, as the viewer's): 1–5, 0, P, X, U on the selection.
    func browserKey(_ event: NSEvent) -> Bool {
        guard !viewerIsKey, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            !(NSApp.keyWindow?.firstResponder is NSTextView), let command = ViewerKeys.command(for: event)
        else { return false }
        let ids = browser.ratingTargets
        guard !ids.isEmpty else { return false }
        switch command {
        case .setStars(let n): culling.setStars(ids, n)
        case .toggleFlag(let flag): culling.toggleFlag(ids, flag)
        case .unflag: culling.clearFlag(ids)
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
