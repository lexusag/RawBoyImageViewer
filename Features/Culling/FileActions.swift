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
        static let recentDestinations = "files.recentDestinations"
    }

    /// The photos an action applies to: the one on screen in the viewer, else the browser's selection.
    var actionTargets: [String] {
        if viewer.isOpen, NSApp.keyWindow is ViewerWindow, let id = viewer.model.current?.main { return [id] }
        return browser.ratingTargets
    }

    func perform(_ action: FileAction, _ ids: [String]? = nil) {
        let ids = ids ?? actionTargets
        guard !ids.isEmpty, let folder = browser.folder else { return }
        switch action {
        case .export: showExportSheet(ids, folder)
        case .copyTo: copyOrMove(ids, folder, move: false, to: nil)
        case .moveTo: copyOrMove(ids, folder, move: true, to: nil)
        case .clipboard: copyToClipboard(ids, folder)
        case .share: share(ids, folder)
        case .sendTo(let path): send(ids.map { folder.appendingPathComponent($0) }, to: URL(fileURLWithPath: path))
        }
    }

    /// Says what happened in the browser's bar, and over the photo when the viewer is in front.
    func say(_ text: String) {
        culling.say(text)
        if viewer.isOpen, NSApp.keyWindow is ViewerWindow { viewer.flash(text) }
    }

    private func groups(_ ids: [String]) -> [PhotoGroup] {
        let wanted = Set(ids)
        return browser.photos.filter { wanted.contains($0.id) }.map(\.group)
    }

    // MARK: Export

    static var exportOptions: ExportOptions {
        get {
            UserDefaults.standard.data(forKey: FileKeys.exportOptions)
                .flatMap { try? JSONDecoder().decode(ExportOptions.self, from: $0) } ?? ExportOptions()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: FileKeys.exportOptions) }
    }

    static var exportFolder: URL {
        get {
            UserDefaults.standard.string(forKey: FileKeys.exportFolder).map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/RawBoy Export")
        }
        set { UserDefaults.standard.set(newValue.path, forKey: FileKeys.exportFolder) }
    }

    private func showExportSheet(_ ids: [String], _ folder: URL) {
        guard let parent = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360), styleMask: [.titled],
            backing: .buffered, defer: false)
        let view = ExportSheet(
            count: ids.count, options: Self.exportOptions, folder: Self.exportFolder,
            onCancel: { parent.endSheet(sheet) },
            onExport: { [weak self] options, destination in
                parent.endSheet(sheet)
                Self.exportOptions = options
                Self.exportFolder = destination
                self?.export(ids, from: folder, to: destination, options: options)
            })
        sheet.contentViewController = NSHostingController(rootView: view.preferredColorScheme(.dark))
        parent.beginSheet(sheet)
    }

    private func export(_ ids: [String], from folder: URL, to destination: URL, options: ExportOptions) {
        let items = ids.map { (folder.appendingPathComponent($0), culling.orientation($0), culling.crop($0)) }
        say("Exporting \(items.count) photo\(items.count == 1 ? "" : "s")…")
        Task.detached(priority: .userInitiated) {
            var done = 0
            var failed: [String] = []
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                await MainActor.run { self.say("Can't create \(destination.lastPathComponent)") }
                return
            }
            for (url, orientation, crop) in items {
                do {
                    _ = try Exporter.export(
                        url, orientation: orientation, crop: crop, to: destination, options: options)
                    done += 1
                } catch {
                    failed.append(url.lastPathComponent)
                }
            }
            let summary =
                failed.isEmpty
                ? "Exported \(done) photo\(done == 1 ? "" : "s") to \(destination.lastPathComponent)"
                : "Exported \(done); couldn't export \(failed.joined(separator: ", "))"
            await MainActor.run { self.say(summary) }
        }
    }

    // MARK: Copy to, Move to

    /// Recently used destinations, newest first.
    var recentDestinations: [URL] {
        (UserDefaults.standard.stringArray(forKey: FileKeys.recentDestinations) ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func remember(destination: URL) {
        let list = [destination] + recentDestinations.filter { $0 != destination }.prefix(4)
        UserDefaults.standard.set(list.map(\.path), forKey: FileKeys.recentDestinations)
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
        if move { culling.recordMoves(moves, what: "Move to \(destination.lastPathComponent)") }
    }

    // MARK: Drag to Places

    /// What the grid or list is dragging: set when a drag starts, so a drop knows it was ours.
    struct DragSet {
        var ids: [String] = []
        var folders: [URL] = []
        var lead: URL?
    }

    /// Starts dragging [entry]: the whole selection when it is part of it, else just that entry. The pasteboard
    /// carries the entry's own file URL, so Finder accepts the drop too.
    func beginDrag(_ entry: GridEntry) -> NSItemProvider? {
        guard let folder = browser.folder else { return nil }
        var entries = [entry]
        if browser.selection.contains(entry.id) {
            entries = browser.items.filter { browser.selection.contains($0.id) }
        } else {
            browser.click(entry.id, command: false, shift: false)
        }
        var set = DragSet()
        for e in entries {
            switch e {
            case .photo(let photo): set.ids.append(photo.id)
            case .folder(let url): set.folders.append(url)
            case .parent: break
            }
        }
        guard !set.ids.isEmpty || !set.folders.isEmpty else { return nil }
        switch entry {
        case .photo(let photo): set.lead = folder.appendingPathComponent(photo.id)
        case .folder(let url): set.lead = url
        case .parent: return nil
        }
        drag = set
        return set.lead.map { NSItemProvider(object: $0 as NSURL) }
    }

    /// A drop on a folder in Places. Moves on the same volume, copies across volumes or with Option held (as Finder).
    /// Returns false for drops that aren't from the grid.
    func dropOnPlace(_ urls: [URL], _ destination: URL) -> Bool {
        guard let set = drag, let folder = browser.folder, let lead = set.lead,
            urls.contains(where: { $0.standardizedFileURL == lead.standardizedFileURL })
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
        SendToApps.send(urls, to: app) { [weak self] error in
            if error != nil {
                self?.say("Couldn't open in \(name)")
            } else {
                let what = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) photos"
                self?.say("Sent \(what) to \(name)")
            }
        }
    }

    private func share(_ ids: [String], _ folder: URL) {
        let urls = ids.map { folder.appendingPathComponent($0) }
        let picker = NSSharingServicePicker(items: urls)
        if viewer.isOpen, NSApp.keyWindow is ViewerWindow, let view = viewer.canvasView {
            picker.show(
                relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view,
                preferredEdge: .minY)
        } else if let view = NSApp.keyWindow?.contentView {
            picker.show(
                relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1),
                of: view, preferredEdge: .minY)
        }
    }
}

/// Export settings for the photos chosen: size, format, quality, location, where to.
struct ExportSheet: View {
    let count: Int
    @State var options: ExportOptions
    @State var folder: URL
    let onCancel: () -> Void
    let onExport: (ExportOptions, URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Export \(count) photo\(count == 1 ? "" : "s")")
                .font(Theme.title)
                .foregroundStyle(Theme.paperWhite)
            row("Long edge") {
                Segmented(
                    options: ExportOptions.sizes.map { ($0, $0.map { "\($0) px" } ?? "Full size") },
                    selection: $options.longEdge)
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
            row("Save to") {
                HStack {
                    Text((folder.path as NSString).abbreviatingWithTildeInPath)
                        .font(Theme.body)
                        .foregroundStyle(Theme.paperWhite)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.directoryURL = folder
                        if panel.runModal() == .OK, let url = panel.url { folder = url }
                    }
                    .buttonStyle(.rawBoy)
                }
            }
            Text(
                "Raws are developed by macOS as shot. For RawBoy's look, export them from RawBoy. Files with the same "
                    + "name aren't replaced: the new one gets a number."
            )
            .font(Theme.label)
            .foregroundStyle(Theme.ashMuted)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.rawBoy)
                    .keyboardShortcut(.cancelAction)
                Button("Export") { onExport(options, folder) }
                    .buttonStyle(.rawBoyPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 520)
        .background(Theme.graphiteSurface)
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
