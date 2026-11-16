import AppKit
import Observation
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles

/// App-wide state shared by the browser and the viewer.
@MainActor
@Observable
public final class AppModel {
    /// The grid items being dragged to a folder in Places (see `beginDrag`).
    var drag: DragSet?
    /// The export running now, or the last one until it is dismissed.
    var exportJob: ExportJob?

    let culling = CullingStore()
    let browser: BrowserModel
    let viewer: ViewerSession
    let compare: CompareSession
    @ObservationIgnored private var watcher: FolderWatcher?

    private let optionsBox: ViewerOptionsBox
    /// How the next viewer or Compare opens (changeable: a host's setting for an in-window or a full-screen viewer).
    public var options: ViewerOptions {
        get { optionsBox.value }
        set { optionsBox.value = newValue }
    }
    /// Compare is open as a view in the host's window (observed: a host that places `CompareView` shows it then); not
    /// when it is a window of its own.
    public private(set) var compareOpen = false
    /// The window the browser view is in (set by `BrowserRoot`): where the key monitor and "back to the browser" go.
    @ObservationIgnored public private(set) weak var browserWindow: NSWindow?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var shownViews = 0

    public init(options: ViewerOptions = ViewerOptions()) {
        let box = ViewerOptionsBox(options)
        optionsBox = box
        browser = BrowserModel(culling: culling)
        viewer = ViewerSession(culling: culling, options: box)
        compare = CompareSession(culling: culling, options: box)
        viewer.app = self
        compare.app = self
        compare.onClose = { [weak self] chosen in
            self?.compareOpen = false
            if let chosen { self?.browser.select(chosen) }
            self?.browserWindow?.makeKeyAndOrderFront(nil)
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
        culling.onFilesChanged = { [weak self] in
            self?.folderContentsChanged()
            self?.browser.foldersChanged()
        }
        browser.onLoad = { [weak self] folder in self?.watch(folder) }
        browser.onOrderChanged = { [weak self] in
            guard let self else { return }
            if viewer.isOpen { viewer.replace(groups: browser.visible.map(\.group)) }
            if compare.isOpen { compare.replace(order: browser.visible.map(\.group)) }
        }
        viewer.onClose = { [weak self] current in
            // Back in the browser on the photo the viewer showed last.
            if let current { self?.browser.select(current) }
            self?.browserWindow?.makeKeyAndOrderFront(nil)
        }
        viewer.onBrowse = { [weak self] folder in self?.browse(folder) }
    }

    /// Opens what Finder, a drop or the Open dialog handed over: a folder in the browser, a photo in the viewer (with
    /// its folder in the browser behind it).
    public func open(_ url: URL) {
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
        if viewer.isOpen {
            viewer.replace(groups: browser.visible.map(\.group))
            if let current = viewer.model.current?.main { browser.select(current) }
        }
        if compare.isOpen {
            compare.replace(order: browser.visible.map(\.group))
            if let current = compare.chosenID { browser.select(current) }
        }
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
            browser.refreshTree()
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
    var viewerIsKey: Bool { viewer.isKey || compare.isKey }

    /// Compare [ids] (2–4); one photo is compared with the one after it in the browser.
    public func openCompare(_ ids: [String]) {
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
        compareOpen = compare.isOpen && compare.isEmbedded
    }

    /// Opens the viewer on the browser's selection (or first photo). [inHostWindow] overrides `options` for this one
    /// opening: true in the host's window, false in the screen-filling window of its own; nil follows `options`.
    public func openSelectedInViewer(inHostWindow: Bool? = nil) {
        guard let id = browser.ratingTargets.first ?? browser.visible.first?.id else { return }
        let saved = options
        if let inHostWindow { options.viewerInHostWindow = inHostWindow }
        openViewer(at: id)
        options = saved
    }

    /// Closes the viewer and Compare when they are windows of their own (the host leaves Browse mode: nothing of
    /// ours may stay over its windows). Their presentation options are restored by their windows closing.
    public func closeOwnWindows() {
        if viewer.isOpen, !viewer.isEmbedded { viewer.close() }
        if compare.isOpen, !compare.isEmbedded { compare.close() }
    }

    /// ⌘Z: text editing in a text field, else the last rating or file move.
    public func undo() {
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
    public func rotate(clockwise: Bool) {
        if viewerIsKey {
            viewer.handle(.rotate(clockwise: clockwise))
        } else {
            culling.rotate(browser.ratingTargets, clockwise: clockwise)
        }
    }

    /// ⌘⌫ and ⌦: the photo in the viewer, else the browser's selection.
    public func moveToTrash() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
            return
        }
        if viewerIsKey {
            if viewer.isOpen { viewer.handle(.moveToTrash) } else { compare.handle(.moveToTrash) }
        } else {
            // Only what is selected: with nothing selected, the anchor isn't something to delete.
            guard !browser.selection.isEmpty else { return }
            trash(photos: browser.ratingTargets, folders: browser.selectedFolders)
        }
    }

    /// New Folder… in [parent]: asks for a name (empty names and names already taken are refused, with the reason),
    /// makes it, shows it in the grid and the Places tree. ⌘Z removes it while it is empty.
    func newFolder(in parent: URL) {
        let fm = FileManager.default
        func taken(_ name: String) -> Bool {
            ((try? fm.contentsOfDirectory(atPath: parent.path)) ?? []).contains { $0.lowercased() == name.lowercased() }
        }
        var name = "untitled folder"
        var n = 2
        while taken(name) {
            name = "untitled folder \(n)"
            n += 1
        }
        var problem: String?
        while true {
            let alert = NSAlert()
            alert.messageText = "New folder in “\(parent.lastPathComponent)”"
            alert.informativeText = problem ?? "Name the new folder."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.stringValue = name
            alert.accessoryView = field
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                problem = "The name can't be empty."
            } else if name.contains("/") || name.contains(":") {
                problem = "A folder name can't contain “/” or “:”."
            } else if name == "." || name == ".." {
                problem = "“\(name)” isn't a usable name."
            } else if taken(name) {
                problem = "“\(name)” already exists here. Pick another name."
            } else {
                break
            }
        }
        let url = parent.appendingPathComponent(name, isDirectory: true)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't create “\(name)”"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        culling.recordCreatedFolder(url)
        browser.foldersChanged(created: url)
    }

    /// Right-click on a folder tile: the whole selection when the tile is in it, else that folder alone.
    func trashFolder(_ url: URL, entryID: String) {
        if browser.selection.contains(entryID) {
            trash(photos: browser.ratingTargets, folders: browser.selectedFolders)
        } else {
            trash(photos: [], folders: [url])
        }
    }

    /// The browser's way to the Trash (keys, toolbar, right-click): asks first, then moves photos (with their JPEGs and
    /// sidecars) and folders (with everything in them). Always the Trash, never a permanent delete; ⌘Z puts them back.
    func trash(photos ids: [String], folders: [URL]) {
        guard !ids.isEmpty || !folders.isEmpty, let current = browser.folder else { return }
        let defaults = ViewerSettings.current
        let synced = CullingStore.isSyncedFolder(current) && !defaults.bool(forKey: CullingStore.Keys.trashNotice)
        let skip = folders.isEmpty && defaults.bool(forKey: CullingStore.Keys.trashPhotosWithoutAsking)
        if !skip {
            let alert = NSAlert()
            let photoText = "\(ids.count) photo\(ids.count == 1 ? "" : "s")"
            let folderText =
                folders.count == 1 ? "the folder “\(folders[0].lastPathComponent)”" : "\(folders.count) folders"
            alert.messageText =
                "Move "
                + [ids.isEmpty ? nil : photoText, folders.isEmpty ? nil : folderText].compactMap { $0 }.joined(
                    separator: " and ") + " to the Trash?"
            var lines: [String] = []
            if !ids.isEmpty { lines.append("A photo's JPEG and sidecars go with it.") }
            if !folders.isEmpty {
                lines.append("Everything inside \(folders.count == 1 ? "the folder" : "the folders") goes too.")
            }
            lines.append("⌘Z puts \(ids.count + folders.count == 1 ? "it" : "them") back.")
            if synced {
                lines.append("This folder syncs with the cloud: the Trash deletes there and on your other devices too.")
            }
            alert.informativeText = lines.joined(separator: " ")
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            if folders.isEmpty {
                alert.showsSuppressionButton = true
                alert.suppressionButton?.title = "Don't ask again for photos"
            }
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on {
                defaults.set(true, forKey: CullingStore.Keys.trashPhotosWithoutAsking)
            }
        }
        let trashedIDs = Set(ids + folders.map(GridEntry.folderID))
        if browser.selection.isDisjoint(with: trashedIDs),
            let first = ids.first ?? folders.first.map(GridEntry.folderID)
        {
            browser.selection = trashedIDs
            browser.anchor = first
        }
        Task {
            await culling.moveToTrash(ids, syncedNoticeShown: !skip)
            culling.moveFoldersToTrash(folders)
        }
    }

    /// Asks first, then moves [ids]' XMP sidecar files to the Trash and clears their ratings, rotations and crops.
    /// ⌘Z puts the sidecar files back.
    func resetSidecars(_ ids: [String]) {
        let targets = ids.filter { culling.hasSidecar($0) || culling.isBusy($0) }
        guard !targets.isEmpty, let current = browser.folder else { return }
        let sidecarCount = targets.reduce(0) { $0 + (culling.sidecars[$1]?.count ?? 0) }
        let synced =
            CullingStore.isSyncedFolder(current)
            && !ViewerSettings.current.bool(forKey: CullingStore.Keys.trashNotice)
        let alert = NSAlert()
        alert.messageText =
            targets.count == 1
            ? "Reset sidecar for 1 photo?"
            : "Reset sidecars for \(targets.count) photos?"
        var lines: [String] = []
        if sidecarCount > 0 {
            lines.append(
                "Ratings, rotations and crops will be cleared, and "
                    + "\(sidecarCount == 1 ? "its XMP sidecar" : "\(sidecarCount) XMP sidecars") moved to the Trash."
            )
            lines.append("⌘Z puts \(sidecarCount == 1 ? "it" : "them") back.")
            if synced {
                lines.append("This folder syncs with the cloud: the Trash deletes there and on your other devices too.")
            }
        } else {
            lines.append("Pending ratings, rotations and crops will be cleared.")
        }
        alert.informativeText = lines.joined(separator: " ")
        alert.addButton(withTitle: "Reset Sidecars")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await culling.resetSidecars(targets) }
    }

    /// The browser's rating keys (by physical key, as the viewer's): 1–5, 0, P, X, U on the selection.
    func browserKey(_ event: NSEvent) -> Bool {
        // ⌦ (Fn-⌫ on a laptop) trashes the selection; plain ⌫ goes up a folder. Here rather than in the views, so it
        // works whichever view (grid, list, preview) has the focus. ⌘⌫ is the menu's.
        if !viewerIsKey, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
            event.keyCode == 51 || event.keyCode == 117, !(event.window is NSPanel),
            !(event.window?.firstResponder is NSTextView), browser.folder != nil
        {
            if event.keyCode == 51 { browser.goUp() } else { moveToTrash() }
            return true
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // F2 renames the selection (any layout: key code 120).
        if !viewerIsKey, event.keyCode == 120, mods.isEmpty, !(event.window is NSPanel),
            event.window?.sheetParent == nil,
            !(event.window?.firstResponder is NSTextView), browser.folder != nil, !browser.selection.isEmpty
        {
            rename()
            return true
        }
        // ⌘A by physical key: SwiftUI's key presses are characters, "ф" on a Ukrainian layout.
        if !viewerIsKey, event.keyCode == 0, mods == .command, !(event.window is NSPanel),
            !(event.window?.firstResponder is NSTextView), browser.folder != nil
        {
            browser.selectAll()
            return true
        }
        // ⌘C / ⌘V by physical key: the selection's files to and from the pasteboard (Finder's too). Text fields, sheets
        // and panels keep their own copy and paste.
        if !viewerIsKey, mods == .command, event.keyCode == 8 || event.keyCode == 9, !(event.window is NSPanel),
            event.window?.sheetParent == nil, !(event.window?.firstResponder is NSTextView),
            browser.folder != nil
        {
            return event.keyCode == 8 ? copySelectionToPasteboard() : pasteFromPasteboard()
        }
        guard !viewerIsKey, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            !(event.window?.firstResponder is NSTextView), let command = ViewerKeys.command(for: event)
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

    /// Back in the folder the last session left, when Settings say so and nothing else was opened.
    public func openLastFolderIfWanted() {
        if SettingsKeys.opensLastFolder, browser.folder == nil, let last = BrowserModel.lastFolder {
            browser.load(last)
        }
    }

    /// Ratings still waiting to be written go to disk now (quitting).
    public func writePendingNow() { culling.writePendingNow() }

    /// The folder the browser shows, for a host's window title.
    public var folder: URL? { browser.folder }

    /// The viewer is open as a view in the host's window (observed: a host places `ViewerView` while this is true). A
    /// viewer in a window of its own (`ViewerOptions.viewerInHostWindow` off) is not: its view stays in that window.
    public var isViewerOpen: Bool { viewer.model.isPresented && viewer.isEmbedded }

    #if DEBUG
        /// Debug probes only (never a synthetic key event: those go through the system's keyboard handling, which can
        /// reach other apps): the browser's select-all, a rating of the selection, and the viewer's E key, called directly.
        public func debugSelectAll() { browser.selectAll() }
        public func debugRateSelection(stars: Int) { culling.setStars(browser.ratingTargets, stars) }
        public func debugPressEditorKey() { viewer.handle(.openInEditor) }
        public var debugViewerFirstResponder: String {
            viewer.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
        }
    #endif

    /// Whether the browser's window is the key window.
    public var browserWindowIsKey: Bool {
        guard let window = browserWindow else { return false }
        return window.isKeyWindow && window.isVisible
    }

    // MARK: Keys

    /// The browser (or a viewer) is on screen in [window]: its keys are handled until `viewDisappeared`.
    func viewAppeared(browserIn window: NSWindow?) {
        if let window { browserWindow = window }
        shownViews += 1
        installKeyMonitor()
    }

    func viewDisappeared() {
        shownViews = max(0, shownViews - 1)
        if shownViews == 0 { removeKeyMonitor() }
    }

    /// The browser's rating keys, by physical key (SwiftUI's key presses are characters, Cyrillic on a Ukrainian
    /// layout), and ? for Help: only in this model's windows (the browser's, the viewer's, Compare's), and only while
    /// one of its views is shown.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyDown(event) ?? false } ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func ownsWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === browserWindow || window === viewer.window || window === compare.window
            || HelpWindow.isHelp(window)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard ownsWindow(event.window) else { return false }
        // ? (Shift + the / key) anywhere but a text field: the keys.
        if event.keyCode == 44, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            event.modifierFlags.contains(.shift), !(event.window?.firstResponder is NSTextView)
        {
            HelpWindow.toggle()
            return true
        }
        return browserKey(event)
    }

    public func openFolderPanel() {
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
                    Snapshot.write(HelpView(), size: CGSize(width: 640, height: 1800), name: "help")
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
