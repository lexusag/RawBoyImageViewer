import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// The folder's photos as rows: thumbnail, name, shoot date, kind, size, rating. Drag the lines between the column
/// titles to resize them. Selection and keys as in the grid (up / down move one row).
struct PhotoList: View {
    let app: AppModel
    @FocusState private var focused: Bool
    @State private var marquee = Marquee()
    @Environment(\.isSnapshot) private var isSnapshot

    static let rowHeight = 36.0
    static let ratingWidth = 84.0

    var body: some View {
        let browser = app.browser
        VStack(spacing: 0) {
            header(browser)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                PanelScroll(marquee: marquee) {
                    LazyVStack(spacing: 2) {
                        ForEach(browser.items) { entry in
                            ListRow(entry: entry, app: app)
                                .id(entry.id)
                                .modifier(MarqueeCell(id: entry.id, enabled: !entry.isParent))
                                .onDrag { app.beginDrag(entry) ?? NSItemProvider() }
                                .gesture(
                                    TapGesture(count: 2).onEnded { open(entry.id) }
                                        .exclusively(
                                            before: TapGesture().onEnded {
                                                let flags = NSEvent.modifierFlags
                                                browser.click(
                                                    entry.id, command: flags.contains(.command),
                                                    shift: flags.contains(.shift))
                                                focused = true
                                            }))
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .marqueeSurface(marquee, browser: browser) { focused = true }
                }
                .onChange(of: browser.scrollRequest) {
                    if let anchor = browser.anchor { proxy.scrollTo(anchor) }
                }
                .onAppear {
                    if !isSnapshot, let anchor = browser.anchor { proxy.scrollTo(anchor, anchor: .center) }
                }
            }
        }
        .contextMenu { NewFolderMenu(app: app) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .space, .escape]) { press in
            switch press.key {
            case .upArrow: browser.move(by: -1)
            case .downArrow: browser.move(by: 1)
            case .escape: browser.clearSelection()
            default:
                if let anchor = browser.anchor { open(anchor) }
            }
            return .handled
        }
    }

    private func open(_ id: String) {
        if !app.browser.activate(id) { app.openViewer(at: id) }
    }

    private func header(_ browser: BrowserModel) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)  // thumbnail
            title("Name").frame(maxWidth: .infinity, alignment: .leading)
            column("Shot", Bindable(browser).dateColumn)
            column("Kind", Bindable(browser).kindColumn)
            column("Size", Bindable(browser).sizeColumn, trailing: true)
            ZStack(alignment: .leading) {
                Color.clear.frame(width: 1)
                title("Rating")
            }
            .frame(width: Self.ratingWidth, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: 26)
        .background(Theme.graphiteSurface)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(Theme.label).foregroundStyle(Theme.ashMuted).lineLimit(1)
    }

    /// A fixed-width column whose left edge is dragged.
    private func column(_ text: String, _ width: Binding<Double>, trailing: Bool = false) -> some View {
        HStack(spacing: 0) {
            ResizeHandle(width: width, range: 48...320, growsRight: false)
                .frame(height: 14)
            title(text)
                .padding(.horizontal, 8)
                .frame(width: max(width.wrappedValue - 1, 0), alignment: trailing ? .trailing : .leading)
        }
    }

    static func dateText(_ date: String?) -> String {
        guard let date else { return "…" }
        var chars = Array(date.prefix(16))  // 2024:05:01 12:30
        for i in [4, 7] where i < chars.count && chars[i] == ":" { chars[i] = "-" }
        return String(chars)
    }

    static func kindText(_ photo: BrowsePhoto) -> String {
        if photo.isRaw { return photo.group.companions.isEmpty ? "RAW" : "RAW + JPEG" }
        let ext = photo.url.pathExtension.uppercased()
        return ext.isEmpty ? "Photo" : ext
    }
}

private struct ListRow: View {
    let entry: GridEntry
    let app: AppModel
    @State private var hovered = false

    var body: some View {
        let browser = app.browser
        let isSelected = browser.selection.contains(entry.id)
        HStack(spacing: 0) {
            switch entry {
            case .photo(let photo):
                RowThumbnail(photo: photo, app: app).frame(width: 48)
                Text(photo.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                cell(PhotoList.dateText(photo.date), browser.dateColumn)
                cell(PhotoList.kindText(photo), browser.kindColumn)
                cell(
                    photo.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "",
                    browser.sizeColumn, trailing: true)
                RatingBadge(rating: browser.culling.rating(photo.id))
                    .frame(width: PhotoList.ratingWidth, alignment: .leading)
            case .folder(let url):
                icon("folder.fill")
                Text(url.lastPathComponent).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                cell("Folder", rest(browser))
            case .parent:
                icon("arrow.turn.left.up")
                Text("Up a folder").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: rest(browser))
            }
        }
        .font(Theme.body)
        .foregroundStyle(isSelected ? Theme.paperWhite : Theme.ashMuted)
        .padding(.horizontal, 0)
        .frame(height: PhotoList.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .fill(isSelected || hovered ? Theme.graphiteRaised : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                .strokeBorder(isSelected ? Theme.amber : .clear, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            switch entry {
            case .photo(let photo): ListPhotoMenu(id: photo.id, url: photo.url, app: app)
            case .folder(let url):
                FolderMenu(url: url, browser: browser, trash: { app.trashFolder(url, entryID: entry.id) })
            case .parent: EmptyView()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The width of every column after the name.
    private func rest(_ browser: BrowserModel) -> Double {
        browser.dateColumn + browser.kindColumn + browser.sizeColumn + PhotoList.ratingWidth
    }

    private var label: String {
        switch entry {
        case .photo(let photo): photo.name
        case .folder(let url): "Folder \(url.lastPathComponent)"
        case .parent: "Up a folder"
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).foregroundStyle(Theme.ashMuted).frame(width: 48)
    }

    private func cell(_ text: String, _ width: Double, trailing: Bool = false) -> some View {
        Text(text)
            .font(Theme.label)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
    }
}

/// A small thumbnail from the grid's store.
private struct RowThumbnail: View {
    let photo: BrowsePhoto
    let app: AppModel
    @State private var image: CGImage?

    var body: some View {
        let culling = app.culling
        let orientation = culling.orientation(photo.id)
        let crop = culling.crop(photo.id)
        ZStack {
            if let image {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
            } else if photo.isOnlineOnly {
                Image(systemName: "icloud.and.arrow.down").font(.system(size: 11)).foregroundStyle(Theme.ashMuted)
            }
        }
        .frame(width: 40, height: 28)
        .task(
            id:
                "\(photo.id)|\(orientation ?? 0)|\(photo.modified?.timeIntervalSince1970 ?? 0)|\(String(describing: crop))"
        ) {
            guard !photo.isOnlineOnly else { return }
            image =
                await app.browser.thumbnails.thumbnail(
                    photo.url, size: photo.size, modified: photo.modified, orientation: orientation, crop: crop)?
                .cgImage
        }
    }
}

/// The photo's right-click menu in a list row: the same as the grid's.
private struct ListPhotoMenu: View {
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
        Button("Rename…") { app.rename(ids) }
        Button("Export…") { app.perform(.export, ids) }
        Button("Copy to Folder…") { app.perform(.copyTo, ids) }
        Button("Move to Folder…") { app.perform(.moveTo, ids) }
        Button("Copy Photo") { app.perform(.clipboard, ids) }
        Button("Share…") { app.perform(.share, ids) }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Move to Trash…") {
            app.trash(photos: ids, folders: app.browser.selection.contains(id) ? app.browser.selectedFolders : [])
        }
    }
}
