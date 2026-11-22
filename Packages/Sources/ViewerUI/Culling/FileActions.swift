import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles
import ViewerImaging

/// Export, Copy to / Move to, the clipboard and Share, for the photo in the viewer or the browser's selection.
extension AppModel {
    enum FileKeys {
        static let exportOptions = "export.options"
        static let exportFolder = "export.folder"
        static let exportDestination = "export.destination"
        static let exportPresets = "export.presets"
        static let recentDestinations = "files.recentDestinations"
    }

    /// The photos an action applies to: the one on screen in the viewer, else the browser's selection.
    var actionTargets: [String] {
        if viewer.isOpen, viewerIsKey, let id = viewer.model.current?.main { return [id] }
        return browser.ratingTargets
    }

    func perform(_ action: FileAction, _ ids: [String]? = nil) {
        var ids = ids ?? actionTargets
        // A collage wants several photos: from the viewer, which acts on one, take the browser's selection.
        if action == .collage, ids.count < 2, browser.ratingTargets.count > 1 { ids = browser.ratingTargets }
        guard !ids.isEmpty, let folder = browser.folder else { return }
        switch action {
        case .collage: showCollage(ids, folder)
        case .export: showExportSheet(ids, folder)
        case .copyTo: copyOrMove(ids, folder, move: false, to: nil)
        case .moveTo: copyOrMove(ids, folder, move: true, to: nil)
        case .clipboard: copyToClipboard(ids, folder)
        case .share: share(ids, folder)
        case .sendToAuto(let how): sendToAuto(ids.map { folder.appendingPathComponent($0) }, as: how)
        case .sendTo(let path): send(ids.map { folder.appendingPathComponent($0) }, to: URL(fileURLWithPath: path))
        }
    }

    /// Says what happened in the browser's bar, and over the photo when the viewer is in front.
    func say(_ text: String) {
        culling.say(text)
        if viewer.isOpen, viewerIsKey { viewer.flash(text) }
    }

    private func groups(_ ids: [String]) -> [PhotoGroup] {
        let wanted = Set(ids)
        return browser.photos.filter { wanted.contains($0.id) }.map(\.group)
    }

    // MARK: Export

    static var exportOptions: ExportOptions {
        get {
            ViewerSettings.current.data(forKey: FileKeys.exportOptions)
                .flatMap { try? JSONDecoder().decode(ExportOptions.self, from: $0) } ?? ExportOptions()
        }
        set { ViewerSettings.current.set(try? JSONEncoder().encode(newValue), forKey: FileKeys.exportOptions) }
    }

    static var exportFolder: URL {
        get {
            ViewerSettings.current.string(forKey: FileKeys.exportFolder).map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/RawBoy Export")
        }
        set { ViewerSettings.current.set(newValue.path, forKey: FileKeys.exportFolder) }
    }

    /// The last export destination: the folder itself, a subfolder of whichever folder is open (by name), or a path.
    /// Older versions stored only a path.
    static var exportDestination: ExportDestination {
        get {
            ViewerSettings.current.string(forKey: FileKeys.exportDestination).flatMap(ExportDestination.init(stored:))
                ?? .path(exportFolder)
        }
        set {
            ViewerSettings.current.set(newValue.stored, forKey: FileKeys.exportDestination)
            if case .path(let url) = newValue { exportFolder = url }
        }
    }

    static var exportPresets: [ExportPreset] {
        get {
            ViewerSettings.current.data(forKey: FileKeys.exportPresets)
                .flatMap { try? JSONDecoder().decode([ExportPreset].self, from: $0) } ?? []
        }
        set { ViewerSettings.current.set(try? JSONEncoder().encode(newValue), forKey: FileKeys.exportPresets) }
    }

    private func showExportSheet(_ ids: [String], _ folder: URL) {
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 430), styleMask: [.titled],
            backing: .buffered, defer: false)
        let view = ExportSheet(
            count: ids.count, options: Self.exportOptions, current: folder,
            subfolders: FolderScanner.subfolders(of: folder), destination: Self.exportDestination,
            onCancel: { parent.endSheet(sheet) },
            onExport: { [weak self] options, destination in
                parent.endSheet(sheet)
                // The crop is chosen per export (or by a preset), never carried into the next one.
                var remembered = options
                remembered.crop = nil
                Self.exportOptions = remembered
                Self.exportDestination = destination
                self?.export(ids, from: folder, to: destination.url(in: folder), options: options)
            })
        sheet.contentViewController = NSHostingController(rootView: view.preferredColorScheme(.dark))
        parent.beginSheet(sheet)
    }

    private func export(_ ids: [String], from folder: URL, to destination: URL, options: ExportOptions) {
        guard exportJob?.isRunning != true else {
            say("An export is still running")
            return
        }
        let items = ids.map { (folder.appendingPathComponent($0), culling.orientation($0), culling.crop($0)) }
        let job = ExportJob(total: items.count, destination: destination)
        job.onChange = { [weak self, weak job] in
            // The bar shows the result; over the viewer, which has no bar, say it on the photo.
            if let job, let self, self.viewer.isOpen, viewerIsKey { self.viewer.flash(job.summary) }
        }
        exportJob = job
        job.start(items: items, options: options)
    }

    // MARK: Copy to, Move to

    /// Recently used destinations, newest first.
    var recentDestinations: [URL] {
        (ViewerSettings.current.stringArray(forKey: FileKeys.recentDestinations) ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func remember(destination: URL) {
        let list = [destination] + recentDestinations.filter { $0 != destination }.prefix(4)
        ViewerSettings.current.set(list.map(\.path), forKey: FileKeys.recentDestinations)
    }

    /// Copies or moves [ids] (with their JPEGs and sidecars) into [to], or a folder chosen now. Moves are undoable.
    func copyOrMove(_ ids: [String], _ folder: URL, move: Bool, to: URL?, folders: [URL] = []) {
        guard let destination = to ?? chooseDestination(move: move) else { return }
        guard destination.standardizedFileURL != folder.standardizedFileURL else {
            say("That is this folder")
            return
        }
        remember(destination: destination)
        var moves: [FileMove] = []
        var failed = 0
        for group in groups(ids) {
            let names = [group.main] + group.companions + (culling.sidecars[group.main] ?? group.sidecars)
            for name in names {
                let from = folder.appendingPathComponent(name)
                let target = Exporter.freeURL(
                    in: destination, stem: PhotoGroups.stem(of: name),
                    extension: String(name.split(separator: ".").last ?? ""))
                do {
                    if move {
                        try FileManager.default.moveItem(at: from, to: target)
                        moves.append(FileMove(from: from, to: target))
                    } else {
                        try FileManager.default.copyItem(at: from, to: target)
                    }
                } catch {
                    failed += 1
                }
            }
        }
        // Whole folders (dragged from the grid): never into themselves, named freely when the name is taken.
        let destinationPath = destination.standardizedFileURL.path + "/"
        var folderCount = 0
        for source in folders {
            let path = source.standardizedFileURL.path
            if destinationPath.hasPrefix(path + "/") { failed += 1; continue }
            var target = destination.appendingPathComponent(source.lastPathComponent)
            var k = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = destination.appendingPathComponent("\(source.lastPathComponent) \(k)")
                k += 1
            }
            do {
                if move {
                    try FileManager.default.moveItem(at: source, to: target)
                    moves.append(FileMove(from: source, to: target))
                } else {
                    try FileManager.default.copyItem(at: source, to: target)
                }
                folderCount += 1
            } catch {
                failed += 1
            }
        }
        let count = ids.count
        let verb = move ? "Moved" : "Copied"
        let what =
            [
                count > 0 ? "\(count) photo\(count == 1 ? "" : "s")" : nil,
                folderCount > 0 ? "\(folderCount) folder\(folderCount == 1 ? "" : "s")" : nil,
            ].compactMap { $0 }.joined(separator: " and ")
        say(
            failed == 0
                ? "\(verb) \(what) to \(destination.lastPathComponent)"
                : "\(verb) to \(destination.lastPathComponent); \(failed) file\(failed == 1 ? "" : "s") failed")
        if move {
            culling.recordMoves(moves, what: "Move to \(destination.lastPathComponent)")
        }
    }

    // MARK: ⌘C, ⌘V

    /// ⌘C in the browser: the selected photos (each with its JPEG and sidecars) and folders, as file URLs, so Finder
    /// and other apps can paste them. Returns false when nothing is selected.
    func copySelectionToPasteboard() -> Bool {
        guard let folder = browser.folder, !browser.selection.isEmpty else { return false }
        let wanted = Set(browser.ratingTargets)
        var urls: [URL] = []
        var photos = 0
        for group in groups(browser.ratingTargets) where wanted.contains(group.main) {
            let names = [group.main] + group.companions + (culling.sidecars[group.main] ?? group.sidecars)
            urls += names.map { folder.appendingPathComponent($0) }
            photos += 1
        }
        let folders = browser.selectedFolders
        urls += folders
        guard !urls.isEmpty else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(urls as [NSURL])
        let what =
            [
                photos > 0 ? "\(photos) photo\(photos == 1 ? "" : "s")" : nil,
                folders.isEmpty ? nil : "\(folders.count) folder\(folders.count == 1 ? "" : "s")",
            ].compactMap { $0 }.joined(separator: " and ")
        say("Copied \(what)")
        return true
    }

    /// ⌘V in the browser: copies the files and folders on the pasteboard (from Finder or from here) into the open
    /// folder. Names already taken get a number ("IMG_1 2.CR2"), a photo's files together; nothing is overwritten.
    /// ⌘Z puts the copies in the Trash. Returns false when the pasteboard holds no files.
    func pasteFromPasteboard() -> Bool {
        guard let folder = browser.folder,
            let urls = NSPasteboard.general.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
        else { return false }
        return copyIn(urls, into: folder, verb: "Pasted")
    }

    private func copyIn(_ urls: [URL], into folder: URL, verb: String) -> Bool {
        let result = FilePaste.paste(urls, into: folder)
        guard !result.created.isEmpty || result.failed > 0 else { return false }
        let what =
            [
                result.files > 0 ? "\(result.files) file\(result.files == 1 ? "" : "s")" : nil,
                result.folders > 0 ? "\(result.folders) folder\(result.folders == 1 ? "" : "s")" : nil,
            ].compactMap { $0 }.joined(separator: " and ")
        culling.recordPasted(result.created)
        if what.isEmpty {
            say("Couldn't copy \(result.failed) item\(result.failed == 1 ? "" : "s")")
        } else {
            say(
                result.failed == 0
                    ? "\(verb) \(what)" : "\(verb) \(what); \(result.failed) couldn't be copied")
        }
        return true
    }

    // MARK: Drag to Places

    /// What the grid or list is dragging: set when a drag starts, so a drop knows it was ours.
    struct DragSet {
        var ids: [String] = []
        var folders: [URL] = []
        var lead: URL?
    }

    /// Starts dragging [entry]: the whole selection when it is part of it, else just that entry. Returns every
    /// dragged file or folder URL (in display order) for the AppKit dragging session, so Finder and other apps
    /// receive the whole selection.
    func beginDrag(_ entry: GridEntry) -> [URL] {
        guard let folder = browser.folder else { return [] }
        var entries = [entry]
        if browser.selection.contains(entry.id) {
            entries = browser.items.filter { browser.selection.contains($0.id) }
        } else {
            browser.click(entry.id, command: false, shift: false)
        }
        var set = DragSet()
        var urls: [URL] = []
        for e in entries {
            switch e {
            case .photo(let photo):
                set.ids.append(photo.id)
                urls.append(folder.appendingPathComponent(photo.id))
            case .folder(let url):
                set.folders.append(url)
                urls.append(url)
            case .parent: break
            }
        }
        guard !urls.isEmpty else { return [] }
        switch entry {
        case .photo(let photo): set.lead = folder.appendingPathComponent(photo.id)
        case .folder(let url): set.lead = url
        case .parent: return []
        }
        drag = set
        return urls
    }

    /// Clears the active drag once the dragging session ends (if a drop on Places hasn't already).
    func endDrag() {
        drag = nil
    }

    /// Whether [urls] is the drag this app started (so dropping it on the grid again does nothing).
    func isOwnDrag(_ urls: [URL]) -> Bool {
        guard let lead = drag?.lead else { return false }
        return urls.contains { Self.sameItem($0, lead) }
    }

    /// Whether a dropped URL is the dragged lead. The path alone isn't enough: since the drag also offers the file's
    /// contents, a drop target may be handed another URL for it (a file reference, a resolved symlink, a temporary
    /// in-place copy). The name within the shown folder is what identifies it, so the whole selection still moves.
    static func sameItem(_ dropped: URL, _ lead: URL) -> Bool {
        if dropped.standardizedFileURL == lead.standardizedFileURL { return true }
        if dropped.resolvingSymlinksInPath() == lead.resolvingSymlinksInPath() { return true }
        return dropped.lastPathComponent == lead.lastPathComponent
    }

    /// Files or folders dropped from Finder or another app on the browser: copied into the open folder (never
    /// overwriting; ⌘Z puts the copies in the Trash). When no folder is open, opens a dropped folder or the dropped
    /// file's folder.
    func dropOnBrowser(_ urls: [URL]) -> Bool {
        guard !isOwnDrag(urls) else { return false }
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }
        if let folder = browser.folder {
            return copyIn(fileURLs, into: folder, verb: "Copied")
        }
        let fm = FileManager.default
        let isDir = { (u: URL) in
            var d: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
        }
        guard let url = fileURLs.first(where: isDir) ?? fileURLs.first(where: { fm.fileExists(atPath: $0.path) })
        else {
            return false
        }
        open(url)
        return true
    }

    /// Folders dropped from elsewhere on Favourites are added to them. Returns false for our own drags.
    func dropOnFavourites(_ urls: [URL]) -> Bool {
        guard !isOwnDrag(urls) else { return false }
        var added = false
        for url in urls {
            var d: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &d), d.boolValue,
                !browser.isFavourite(url)
            else { continue }
            browser.toggleFavourite(url)
            added = true
        }
        return added
    }

    /// A drop on a folder in Places. Moves on the same volume, copies across volumes or with Option held (as Finder).
    /// Returns false for drops that aren't from the grid.
    func dropOnPlace(_ urls: [URL], _ destination: URL) -> Bool {
        guard let set = drag, let folder = browser.folder, let lead = set.lead,
            urls.isEmpty || urls.contains(where: { Self.sameItem($0, lead) })
        else { return false }
        drag = nil
        let copy = NSEvent.modifierFlags.contains(.option) || !Self.sameVolume(folder, destination)
        copyOrMove(set.ids, folder, move: !copy, to: destination, folders: set.folders)
        return true
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        guard let x = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
            let y = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject
        else { return false }
        return x.isEqual(y)
    }

    private func chooseDestination(move: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = move ? "Move Here" : "Copy Here"
        panel.message = move ? "Move the photos, with their JPEGs and sidecars, to:" : "Copy the photos to:"
        panel.directoryURL = recentDestinations.first
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: Clipboard, Share

    private func copyToClipboard(_ ids: [String], _ folder: URL) {
        let urls = ids.map { folder.appendingPathComponent($0) as NSURL }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(urls)
        say(ids.count == 1 ? "Copied \(ids[0])" : "Copied \(ids.count) photos")
    }

    /// Opens photos, or a folder, in another app (Reblum, say) chosen from the Send to menu.
    func send(_ urls: [URL], to app: URL) {
        guard !urls.isEmpty else { return }
        let name = SendToApps.name(of: app)
        let count = SendToApps.expandingFolders(urls).count
        if count == 0 {
            say("No photos in the folder to send")
            return
        }
        SendToApps.send(urls, to: app) { [weak self] error in
            if error != nil {
                self?.say("Couldn't open in \(name)")
            } else {
                let what = count == 1 ? SendToApps.expandingFolders(urls)[0].lastPathComponent : "\(count) photos"
                self?.say("Sent \(what) to \(name)")
            }
        }
    }

    /// "Send to RawBoy Pro" in the browser's right-click menu: the first of [ids] opens in the editor (one photo at a
    /// time; the others stay in the browser). Pending ratings and turns are written first, as the editor reads sidecars.
    func openInEditor(_ ids: [String]) {
        guard let id = ids.first, let folder = browser.folder else { return }
        let url = folder.appendingPathComponent(id)
        let editor = viewer.model.editor.url
        if ids.count > 1 { say("Opening \(id) only: the editor takes one photo at a time") }
        Task { @MainActor in
            await culling.finishWrites()
            if await ViewerHost.handOff.openInEditor(url) { return }
            if let editor {
                _ = try? await NSWorkspace.shared.open(
                    [url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Adds photos to RawBoy Desktop's Auto batch as Looks, Film or As is ([how]; nil asks, the last choice first).
    /// Pending ratings and turns are written first, as Auto reads sidecars.
    func sendToAuto(_ urls: [URL], as how: AutoImport? = nil) {
        guard !urls.isEmpty else { return }
        guard ViewerHost.handOff.canSendToAuto else {
            say("RawBoy Desktop isn't installed")
            return
        }
        guard let how = how ?? askAutoImport(count: urls.count) else { return }
        SendToApps.lastAutoImport = how
        Task { @MainActor in
            await culling.finishWrites()
            do {
                try await ViewerHost.handOff.sendToAuto(urls, as: how)
                let what = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) photos"
                say("Sent \(what) to RawBoy Auto as \(how.label)")
            } catch {
                say("Couldn't open RawBoy Desktop")
            }
        }
    }

    /// ⇧⌘A and the panel's button: Looks, Film or As is, the last one chosen as the default button.
    private func askAutoImport(count: Int) -> AutoImport? {
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Send 1 photo to RawBoy Auto" : "Send \(count) photos to RawBoy Auto"
        alert.informativeText =
            "Looks: developed automatically with a film look. Film: developed as film. "
            + "As is: no automatic edits (raws get only their measured denoise)."
        let last = SendToApps.lastAutoImport
        let order = [last] + AutoImport.allCases.filter { $0 != last }
        for how in order { alert.addButton(withTitle: how.label) }
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return order.indices.contains(index) ? order[index] : nil
    }

    private func share(_ ids: [String], _ folder: URL) {
        let urls = ids.map { folder.appendingPathComponent($0) }
        let picker = NSSharingServicePicker(items: urls)
        if viewer.isOpen, viewerIsKey, let view = viewer.canvasView {
            picker.show(
                relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view,
                preferredEdge: .minY)
        } else if let view = (browserWindow ?? NSApp.keyWindow)?.contentView {
            picker.show(
                relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1),
                of: view, preferredEdge: .minY)
        }
    }
}

/// A named export: size, format, quality, location and where it goes (a subfolder is kept by name).
struct ExportPreset: Codable, Equatable, Identifiable {
    var name: String
    var options: ExportOptions
    var destination: String

    var id: String { name }
}

/// Where an export goes: the open folder, a subfolder of it (made on export if it isn't there), or any folder.
enum ExportDestination: Equatable {
    case same
    case subfolder(String)
    case path(URL)

    init?(stored: String) {
        if stored == "same" {
            self = .same
        } else if stored.hasPrefix("sub:"), let name = Self.cleaned(String(stored.dropFirst(4))) {
            self = .subfolder(name)
        } else if stored.hasPrefix("path:") {
            self = .path(URL(fileURLWithPath: String(stored.dropFirst(5))))
        } else {
            return nil
        }
    }

    var stored: String {
        switch self {
        case .same: "same"
        case .subfolder(let name): "sub:\(name)"
        case .path(let url): "path:\(url.path)"
        }
    }

    func url(in folder: URL) -> URL {
        switch self {
        case .same: folder
        case .subfolder(let name): folder.appendingPathComponent(name, isDirectory: true)
        case .path(let url): url
        }
    }

    /// A folder name that can't climb out of the open folder: no slashes or colons, not empty, not hidden dots only.
    static func cleaned(_ name: String) -> String? {
        let name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.allSatisfy({ $0 == "." }) ? nil : name
    }
}

/// Export settings for the photos chosen: size, format, quality, location, where to.
struct ExportSheet: View {
    let count: Int
    @State var options: ExportOptions
    /// The folder the photos are in, and its subfolders.
    let current: URL
    let subfolders: [URL]
    @State var destination: ExportDestination
    @State private var presets = AppModel.exportPresets
    @State private var namingPreset = false
    @State private var presetName = ""
    @State private var makingNew = false
    @State private var newName = ""
    /// What is typed in the custom long edge field; empty while a preset size is chosen.
    @State private var customLongEdge = ""
    let onCancel: () -> Void
    let onExport: (ExportOptions, ExportDestination) -> Void

    private var customLongEdgeInvalid: Bool {
        !customLongEdge.isEmpty && ExportOptions.parseLongEdge(customLongEdge) == nil
    }

    /// A valid typed size becomes the long edge; an invalid one leaves the last good size and shows the range.
    private func applyCustomLongEdge() {
        if let n = ExportOptions.parseLongEdge(customLongEdge) { options.longEdge = n }
    }

    private var chosen: ExportDestination? {
        makingNew ? ExportDestination.cleaned(newName).map { .subfolder($0) } : destination
    }

    private var label: String {
        if makingNew { return "New subfolder…" }
        switch destination {
        case .same: return "Same folder"
        case .subfolder(let name): return name
        case .path(let url): return (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Export \(count) photo\(count == 1 ? "" : "s")")
                .font(Theme.title)
                .foregroundStyle(Theme.paperWhite)
            row("Preset") {
                HStack {
                    Menu {
                        ForEach(presets) { preset in
                            Button(preset.name) { apply(preset) }
                        }
                        if !presets.isEmpty { Divider() }
                        Button("Save these settings as preset…") { namingPreset = true }
                        if !presets.isEmpty {
                            Menu("Delete preset") {
                                ForEach(presets) { preset in
                                    Button(preset.name) { delete(preset) }
                                }
                            }
                        }
                    } label: {
                        Text(currentPreset?.name ?? "None")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.rawBoy)
                    .fixedSize()
                    if namingPreset {
                        TextField("Preset name", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .onSubmit(savePreset)
                        Button("Save", action: savePreset)
                            .buttonStyle(.rawBoy)
                            .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            row("Long edge") {
                Segmented(
                    options: ExportOptions.sizes.map { ($0, $0.map { "\($0) px" } ?? "Full size") },
                    selection: Binding(
                        get: { options.longEdge },
                        set: { options.longEdge = $0; customLongEdge = "" }))
                HStack(spacing: DesignTokens.Spacing.sm) {
                    TextField("Custom", text: $customLongEdge)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit(applyCustomLongEdge)
                        .onChange(of: customLongEdge) { _, _ in applyCustomLongEdge() }
                    Text("px")
                        .font(Theme.label)
                        .foregroundStyle(Theme.ashMuted)
                    if customLongEdgeInvalid {
                        Text("\(ExportOptions.customLongEdgeRange.lowerBound)–\(ExportOptions.customLongEdgeRange.upperBound)")
                            .font(Theme.label)
                            .foregroundStyle(Theme.amber)
                    }
                }
            }
            row("Short edge") {
                HStack {
                    Segmented(
                        options: [(Int?.none, "Free"), (.some(ExportOptions.instagramShortEdge), "1440 px")],
                        selection: $options.shortEdge)
                    Button("Instagram") { options = .instagram(from: options); customLongEdge = "" }
                        .buttonStyle(.rawBoy)
                        .help("3:4 crop, 1440 px short edge, sRGB JPEG, no enlarging")
                }
            }
            row("Crop") {
                Segmented(
                    options: [(ExportOptions.Crop?.none, "Free")]
                        + ExportOptions.Crop.allCases.map { (.some($0), $0.rawValue) },
                    selection: $options.crop)
            }
            row("Colour") {
                Toggle("Convert to sRGB", isOn: $options.convertToSRGB)
                    .toggleStyle(.checkbox)
                    .font(Theme.body)
            }
            row("Format") {
                Segmented(options: [(ExportOptions.Format.jpeg, "JPEG"), (.heic, "HEIC")], selection: $options.format)
            }
            row("Quality") {
                HStack {
                    Slider(value: $options.quality, in: 0.6...1).tint(Theme.amber).frame(width: 160)
                    Text("\(Int((options.quality * 100).rounded()))")
                        .font(Theme.label.monospacedDigit())
                        .foregroundStyle(Theme.ashMuted)
                }
            }
            row("Location") {
                Toggle("Leave the GPS position out", isOn: $options.removeLocation)
                    .toggleStyle(.checkbox)
                    .font(Theme.body)
            }
            row("Same name") {
                Toggle("Replace existing files", isOn: $options.replaceExisting)
                    .toggleStyle(.checkbox)
                    .font(Theme.body)
            }
            row("Save to") {
                HStack {
                    Menu {
                        Button("Same folder (\(current.lastPathComponent))") { pick(.same) }
                        if !subfolders.isEmpty { Divider() }
                        ForEach(subfolders, id: \.self) { url in
                            Button(url.lastPathComponent) { pick(.subfolder(url.lastPathComponent)) }
                        }
                        Divider()
                        Button("New subfolder…") { makingNew = true }
                        Button("Choose…") { choose() }
                    } label: {
                        Text(label).lineLimit(1).truncationMode(.middle)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.rawBoy)
                    .fixedSize()
                    if makingNew {
                        TextField("Folder name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                }
            }
            if !makingNew, chosen != .same {
                Text(((chosen?.url(in: current).path ?? "") as NSString).abbreviatingWithTildeInPath)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ashMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(
                "Raws are developed by macOS as shot. For RawBoy's look, export them from RawBoy. Files with the same "
                    + "name get a number, or with Replace existing files go to the Trash and are replaced (never in "
                    + "the photo's own folder)."
            )
            .font(Theme.label)
            .foregroundStyle(Theme.ashMuted)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.rawBoy)
                    .keyboardShortcut(.cancelAction)
                Button("Export") { if let chosen { onExport(options, chosen) } }
                    .buttonStyle(.rawBoyPrimary)
                    .disabled(chosen == nil || customLongEdgeInvalid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 520)
        .background(Theme.graphiteSurface)
    }

    /// The preset whose settings and destination are what the sheet shows now.
    private var currentPreset: ExportPreset? {
        guard let chosen else { return nil }
        return presets.first { $0.options == options && $0.destination == chosen.stored }
    }

    private func apply(_ preset: ExportPreset) {
        options = preset.options
        pick(ExportDestination(stored: preset.destination) ?? .same)
        namingPreset = false
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let chosen else { return }
        let preset = ExportPreset(name: name, options: options, destination: chosen.stored)
        if let i = presets.firstIndex(where: { $0.name == name }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
        AppModel.exportPresets = presets
        presetName = ""
        namingPreset = false
    }

    private func delete(_ preset: ExportPreset) {
        presets.removeAll { $0.name == preset.name }
        AppModel.exportPresets = presets
    }

    private func pick(_ choice: ExportDestination) {
        makingNew = false
        destination = choice
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination.url(in: current)
        if panel.runModal() == .OK, let url = panel.url { pick(url == current ? .same : .path(url)) }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            Text(label)
                .font(Theme.label)
                .foregroundStyle(Theme.ashMuted)
                .frame(width: 80, alignment: .leading)
            content()
        }
    }
}
