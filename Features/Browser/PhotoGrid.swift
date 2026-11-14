import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerFiles
import ViewerImaging

/// The folder's photos as thumbnails, after its subfolders when those are shown. Click selects, ⌘-click adds,
/// Shift-click selects a range, double-click (or Enter / Space) opens the viewer or the folder; arrows move, ⌘A
/// selects all, Esc clears (RawBoy Browser's keys), ⌘↑ goes up a folder (so does ⌫, and ⌦ trashes the selection: both in `AppModel.browserKey`).
struct PhotoGrid: View {
    let app: AppModel
    @FocusState private var focused: Bool
    @State private var columns = 1
    @Environment(\.isSnapshot) private var isSnapshot

    static let spacing = 10.0

    var body: some View {
        let browser = app.browser
        let cell = browser.thumbnailSize
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                PanelScroll {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: Self.spacing)],
                        spacing: Self.spacing
                    ) {
                        ForEach(browser.items) { entry in
                            Group {
                                switch entry {
                                case .photo(let photo):
                                    PhotoCell(
                                        photo: photo, size: cell, isSelected: browser.selection.contains(entry.id),
                                        rating: browser.culling.rating(photo.id),
                                        orientation: browser.culling.orientation(photo.id),
                                        crop: browser.culling.crop(photo.id),
                                        hasSidecar: browser.culling.hasSidecar(photo.id), store: browser.thumbnails
                                    )
                                    .contextMenu {
                                        PhotoMenu(id: photo.id, url: photo.url, app: app)
                                    }
                                case .folder(let url):
                                    FolderCell(
                                        title: url.lastPathComponent, icon: "folder.fill", size: cell,
                                        isSelected: browser.selection.contains(entry.id),
                                        url: url, store: browser.thumbnails
                                    )
                                    .contextMenu { FolderMenu(url: url, browser: browser) }
                                case .parent:
                                    FolderCell(
                                        title: "Up a folder", icon: "arrow.turn.left.up", size: cell,
                                        isSelected: browser.selection.contains(entry.id))
                                }
                            }
                            .id(entry.id)
                            .onDrag { app.beginDrag(entry) ?? NSItemProvider() }
                            // Both gestures run together: waiting to tell a single click from a double one
                            // (`exclusively`) delayed every selection by the double-click interval.
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    let flags = NSEvent.modifierFlags
                                    browser.click(
                                        entry.id, command: flags.contains(.command), shift: flags.contains(.shift))
                                    focused = true
                                }
                            )
                            .simultaneousGesture(TapGesture(count: 2).onEnded { open(entry.id) })
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }
                .onChange(of: browser.scrollRequest) {
                    if let anchor = browser.anchor { proxy.scrollTo(anchor) }
                }
                .onAppear {
                    if !isSnapshot, let anchor = browser.anchor { proxy.scrollTo(anchor, anchor: .center) }
                }
            }
            .onAppear { columns = Self.columns(geometry.size.width, cell) }
            .onChange(of: geometry.size.width) { _, width in columns = Self.columns(width, cell) }
            .onChange(of: cell) { _, size in columns = Self.columns(geometry.size.width, size) }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space, .escape]) { press in
            switch press.key {
            case .leftArrow: browser.move(by: -1)
            case .rightArrow: browser.move(by: 1)
            case .upArrow: browser.move(by: -columns)
            case .downArrow: browser.move(by: columns)
            case .escape: browser.clearSelection()
            default:
                if let anchor = browser.anchor { open(anchor) }
            }
            return .handled
        }
        .onKeyPress(characters: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            browser.selectAll()
            return .handled
        }
    }

    /// A folder tile opens the folder, a photo the viewer.
    private func open(_ id: String) {
        if !app.browser.activate(id) { app.openViewer(at: id) }
    }

    /// How many cells fit across [width] (the adaptive grid's own arithmetic), for the up/down keys.
    static func columns(_ width: Double, _ cell: Double) -> Int {
        max(Int((width - 2 * DesignTokens.Spacing.md + spacing) / (cell + spacing)), 1)
    }
}

struct PhotoCell: View {
    let photo: BrowsePhoto
    let size: Double
    let isSelected: Bool
    var rating: Rating = .none
    var hasSidecar = false
    var orientation: Int?
    var crop: CropRect?
    let store: ThumbnailStore
    @State private var image: CGImage?

    init(
        photo: BrowsePhoto, size: Double, isSelected: Bool, rating: Rating = .none, orientation: Int? = nil,
        crop: CropRect? = nil, hasSidecar: Bool = false, store: ThumbnailStore, image: CGImage? = nil
    ) {
        self.photo = photo
        self.size = size
        self.isSelected = isSelected
        self.rating = rating
        self.hasSidecar = hasSidecar
        self.orientation = orientation
        self.crop = crop
        self.store = store
        _image = State(initialValue: image)
    }
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(isSelected || hovered ? Theme.graphiteRaised : Theme.graphiteSurface)
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                        // Centred: the stack aligns its badges bottom-right, and a portrait picture is narrower than the cell.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Rejects fade, as in Lightroom.
                        .opacity(rating.flag == .reject ? 0.4 : 1)
                } else if photo.isOnlineOnly {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.ashMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .help("Only in the cloud: opening it downloads it")
                }
                RatingBadge(rating: rating)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                HStack(spacing: 3) {
                    if hasSidecar { Badge(text: "XMP") }
                    if photo.isRaw { Badge(text: photo.group.companions.isEmpty ? "RAW" : "RAW+") }
                }
                .padding(6)
            }
            .frame(width: size, height: size * 0.75)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .strokeBorder(isSelected ? Theme.amber : Theme.hairline, lineWidth: isSelected ? 2 : 1))
            Text(photo.name)
                .font(Theme.label)
                .foregroundStyle(isSelected ? Theme.paperWhite : Theme.ashMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [photo.name, ViewerSession.spoken(ViewerSession.ratingText(rating))].filter { !$0.isEmpty }
                .joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected, .isImage] : .isImage)
        // Made again when the file changes (its modified date) or is turned.
        .task(
            id:
                "\(photo.id)|\(orientation ?? 0)|\(photo.modified?.timeIntervalSince1970 ?? 0)|\(String(describing: crop))"
        ) {
            guard !photo.isOnlineOnly else { return }
            image =
                await store.thumbnail(
                    photo.url, size: photo.size, modified: photo.modified, orientation: orientation, crop: crop)?
                .cgImage
        }
    }
}

/// A folder (or the way up) as a tile the size of a photo's.
private struct FolderCell: View {
    let title: String
    let icon: String
    let size: Double
    let isSelected: Bool
    /// The folder itself and a store for the pictures inside it (the "show what is inside" setting); nil for "up".
    var url: URL?
    var store: ThumbnailStore?
    @AppStorage(SettingsKeys.folderContents) private var showContents = false
    @State private var hovered = false
    @State private var inside: [CGImage] = []

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(isSelected || hovered ? Theme.graphiteRaised : Theme.graphiteSurface)
                if showContents, !inside.isEmpty {
                    contents
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.paperWhite)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.graphiteSurface.opacity(0.92)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(6)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.22))
                        .foregroundStyle(Theme.ashMuted)
                }
            }
            .frame(width: size, height: size * 0.75)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .strokeBorder(isSelected ? Theme.amber : Theme.hairline, lineWidth: isSelected ? 2 : 1))
            Text(title)
                .font(Theme.label)
                .foregroundStyle(isSelected ? Theme.paperWhite : Theme.ashMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folder \(title)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .task(id: "\(url?.path ?? "")|\(showContents)") {
            guard showContents, let url, let store else {
                inside = []
                return
            }
            inside = await Self.pictures(in: url, store: store)
        }
    }

    /// Up to four of the folder's pictures, two by two.
    private var contents: some View {
        let gap = 3.0
        let width = (size - 12 - gap) / 2
        let height = (size * 0.75 - 12 - gap) / 2
        let shown = Array(inside.prefix(4))
        return VStack(spacing: gap) {
            ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(row..<min(row + 2, shown.count), id: \.self) { i in
                        Image(decorative: shown[i], scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }
    }

    /// Reads the directory entries, then the thumbnails of the first four photos (never cloud placeholders).
    static func pictures(in folder: URL, store: ThumbnailStore) async -> [CGImage] {
        let files = await Task.detached(priority: .utility) { () -> [PhotoFile] in
            var seen = Set<String>()
            return ((try? FolderScanner.photos(in: folder)) ?? [])
                .filter { !$0.isOnlineOnly }
                .sorted {
                    $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
                }
                .filter { seen.insert($0.url.deletingPathExtension().lastPathComponent.lowercased()).inserted }
                .prefix(4).map { $0 }
        }.value
        var out: [CGImage] = []
        for file in files {
            if Task.isCancelled { return [] }
            if let image = await store.thumbnail(file.url, size: file.size, modified: file.modified)?.cgImage {
                out.append(image)
            }
        }
        return out
    }
}

/// Right-click on a photo: acts on the selection when the photo is in it, else on that photo alone.
private struct PhotoMenu: View {
    let id: String
    let url: URL
    let app: AppModel

    var body: some View {
        let ids = app.browser.selection.contains(id) ? app.browser.ratingTargets : [id]
        Button("Open") { app.openViewer(at: id) }
        Divider()
        Button("Rotate Left") { app.culling.rotate(ids, clockwise: false) }
        Button("Rotate Right") { app.culling.rotate(ids, clockwise: true) }
        Divider()
        Button("Export…") { app.perform(.export, ids) }
        Button("Copy to Folder…") { app.perform(.copyTo, ids) }
        Button("Move to Folder…") { app.perform(.moveTo, ids) }
        Button("Copy Photo") { app.perform(.clipboard, ids) }
        Button("Share…") { app.perform(.share, ids) }
        SendToMenu(app: app, ids: ids)
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Move to Trash") { Task { await app.culling.moveToTrash(ids) } }
    }
}

/// Right-click on a folder, in the grid or the sidebar.
struct FolderMenu: View {
    let url: URL
    let browser: BrowserModel

    var body: some View {
        Button(browser.isFavourite(url) ? "Remove from Favourites" : "Add to Favourites") {
            browser.toggleFavourite(url)
        }
        SendToMenu(app: AppModel.shared, folder: url)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.ashMuted)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.graphiteSurface.opacity(0.92)))
    }
}
