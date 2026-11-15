import AppKit
import Observation
import RawBoyBrowseKit
import ViewerFiles
import ViewerImaging

/// One photo in the browser: a RAW + JPEG pair is one, shown from its main file (the raw).
struct BrowsePhoto: Identifiable, Equatable {
    let group: PhotoGroup
    let url: URL
    let isRaw: Bool
    let size: Int64?
    let modified: Date?
    /// A cloud placeholder: no thumbnail until it is downloaded (opening it does that).
    let isOnlineOnly: Bool
    /// When it was shot (EXIF), else the file's date, as an EXIF date; nil until read.
    var date: String?

    var id: String { group.main }
    var name: String { group.main }
}

enum BrowserViewMode: String { case grid, list }

/// One tile of the grid: the parent folder, a subfolder (both only when folders are shown), or a photo.
enum GridEntry: Identifiable, Equatable {
    case parent(URL)
    case folder(URL)
    case photo(BrowsePhoto)

    var id: String {
        switch self {
        case .parent: ".."
        case .folder(let url): Self.folderID(url)
        case .photo(let photo): photo.id
        }
    }

    static func folderID(_ url: URL) -> String { "folder:" + url.standardizedFileURL.path }
}

/// The browser's state: the folder, its photos in order, the filter, the selection.
@MainActor
@Observable
final class BrowserModel {
    private(set) var folder: URL?
    private(set) var photos: [BrowsePhoto] = []
    private(set) var loadError: String?
    private(set) var isLoading = false

    var sort: PhotoSort = PhotoSort(rawValue: UserDefaults.standard.string(forKey: Keys.sort) ?? "") ?? .date {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Keys.sort)
            reorder()
        }
    }
    var filter = "" {
        didSet { reorder() }
    }
    /// Picks, unflagged or rejects only (RawBoy Browser's filter).
    var flagFilter: FlagFilter = .all {
        didSet { reorder() }
    }
    /// At least this many stars.
    var minStars = 0 {
        didSet { reorder() }
    }
    var isRatingFiltered: Bool { flagFilter != .all || minStars > 0 }
    let culling: CullingStore
    /// Subfolders (and the parent) as tiles before the photos. Off by default.
    var showFolders: Bool = UserDefaults.standard.bool(forKey: Keys.showFolders) {
        didSet {
            UserDefaults.standard.set(showFolders, forKey: Keys.showFolders)
            reorder()
        }
    }
    /// Photos as thumbnails or as a list with columns.
    var viewMode: BrowserViewMode =
        BrowserViewMode(rawValue: UserDefaults.standard.string(forKey: Keys.viewMode) ?? "") ?? .grid
    {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Keys.viewMode) }
    }
    /// A pane on the right with the selected photo, large. Off by default.
    var showPreview: Bool = UserDefaults.standard.bool(forKey: Keys.showPreview) {
        didSet { UserDefaults.standard.set(showPreview, forKey: Keys.showPreview) }
    }
    /// Pane and column widths, set by dragging their edges.
    var sidebarWidth = BrowserModel.stored(Keys.sidebarWidth, 248) {
        didSet { UserDefaults.standard.set(sidebarWidth, forKey: Keys.sidebarWidth) }
    }
    var previewWidth = BrowserModel.stored(Keys.previewWidth, 360) {
        didSet { UserDefaults.standard.set(previewWidth, forKey: Keys.previewWidth) }
    }
    var dateColumn = BrowserModel.stored(Keys.dateColumn, 130) {
        didSet { UserDefaults.standard.set(dateColumn, forKey: Keys.dateColumn) }
    }
    var kindColumn = BrowserModel.stored(Keys.kindColumn, 84) {
        didSet { UserDefaults.standard.set(kindColumn, forKey: Keys.kindColumn) }
    }
    var sizeColumn = BrowserModel.stored(Keys.sizeColumn, 76) {
        didSet { UserDefaults.standard.set(sizeColumn, forKey: Keys.sizeColumn) }
    }
    private(set) var favourites: [URL] = (UserDefaults.standard.stringArray(forKey: Keys.favourites) ?? []).map {
        URL(fileURLWithPath: $0)
    }
    var thumbnailSize: Double = UserDefaults.standard.object(forKey: Keys.size) as? Double ?? 168 {
        didSet { UserDefaults.standard.set(thumbnailSize, forKey: Keys.size) }
    }
    var selection: Set<String> = []
    /// Where Shift-click ranges and arrow keys start.
    var anchor: String?
    /// Bumped to scroll the grid to [anchor].
    private(set) var scrollRequest = 0
    /// Bumped when folders were made or removed here: the sidebar's tree reads its rows again.
    private(set) var treeChange = 0
    /// The folder made last (its parent's row opens to show it).
    private(set) var createdFolder: URL?
    private(set) var recent: [URL] = (UserDefaults.standard.stringArray(forKey: Keys.recent) ?? []).map {
        URL(fileURLWithPath: $0)
    }

    /// The photos matching the filter, in order: what the viewer steps through.
    private(set) var visible: [BrowsePhoto] = []
    /// The folder's subfolders, by name.
    private(set) var subfolders: [URL] = []
    /// What the grid shows: folders (when shown), then the visible photos.
    private(set) var items: [GridEntry] = []

    let thumbnails = ThumbnailStore(pixelSize: 480)
    private var generation = 0

    init(culling: CullingStore) {
        self.culling = culling
    }

    /// Ratings changed: a rating filter may show other photos now.
    func ratingsChanged() {
        if isRatingFiltered { reorder() }
    }

    /// The photos a rating key acts on: the selected ones in grid order, else the one at the anchor.
    var ratingTargets: [String] {
        let photos = visible.map(\.id)
        let selected = photos.filter { selection.contains($0) }
        if !selected.isEmpty { return selected }
        return anchor.flatMap { a in photos.contains(a) ? [a] : nil } ?? []
    }

    /// The selected subfolders, in grid order.
    var selectedFolders: [URL] {
        items.compactMap { entry in
            if case .folder(let url) = entry, selection.contains(entry.id) { return url }
            return nil
        }
    }

    enum Keys {
        static let sort = "browser.sort"
        static let size = "browser.thumbnailSize"
        static let recent = "browser.recentFolders"
        static let last = "browser.lastFolder"
        static let showFolders = "browser.showFolders"
        static let favourites = "browser.favourites"
        static let viewMode = "browser.viewMode"
        static let showPreview = "browser.showPreview"
        static let sidebarWidth = "browser.sidebarWidth"
        static let previewWidth = "browser.previewWidth"
        static let dateColumn = "browser.dateColumn"
        static let kindColumn = "browser.kindColumn"
        static let sizeColumn = "browser.sizeColumn"
    }

    nonisolated static func stored(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    static var lastFolder: URL? {
        UserDefaults.standard.string(forKey: Keys.last).map { URL(fileURLWithPath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// Shows [folder]: its photos at once in name order, reordered once their dates are read. [select] is a file name
    /// to select (and scroll to), [selectID] a grid entry's id.
    func load(_ folder: URL, select: String? = nil, selectID: String? = nil) {
        let folder = folder.standardizedFileURL
        generation += 1
        let generation = generation
        self.folder = folder
        loadError = nil
        do {
            let files = try FolderScanner.photos(in: folder)
            let sidecars = (try? FolderScanner.sidecarNames(in: folder)) ?? []
            let byName = Dictionary(files.map { ($0.url.lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
            photos = PhotoGroups.group(files.map(\.url.lastPathComponent) + sidecars).compactMap { group in
                guard let file = byName[group.main] else { return nil }
                return BrowsePhoto(
                    group: group, url: file.url, isRaw: file.type == .raw, size: file.size, modified: file.modified,
                    isOnlineOnly: file.isOnlineOnly, date: nil)
            }
        } catch {
            photos = []
            loadError = "Can't read \(folder.lastPathComponent): \(error.localizedDescription)"
        }
        subfolders = FolderScanner.subfolders(of: folder)
        let wanted = select.map { PhotoGroups.stem(of: $0).lowercased() }
        let selected = selectID ?? wanted.flatMap { w in photos.first { $0.group.stem.lowercased() == w }?.id }
        selection = selected.map { [$0] } ?? []
        anchor = selected ?? photos.first?.id
        culling.load(folder: folder, groups: photos.map(\.group))
        reorder()
        scrollRequest += 1
        remember(folder)
        onLoad?(folder)
        readDates(generation)
    }

    /// Reads the folder again, keeping the selection (what is still there of it) and the scroll position's photo.
    func reload() {
        guard let folder else { return }
        let kept = selection
        load(folder, selectID: anchor)
        let ids = Set(items.map(\.id))
        selection = kept.intersection(ids).isEmpty ? selection : kept.intersection(ids)
    }

    /// Folders were added or removed: the Places tree rereads. [created] opens its parent and is selected in the grid.
    func foldersChanged(created: URL? = nil) {
        createdFolder = created
        treeChange += 1
        guard let created, folder?.standardizedFileURL == created.deletingLastPathComponent().standardizedFileURL
        else { return }
        reload()
        let id = GridEntry.folderID(created)
        if items.contains(where: { $0.id == id }) { select(id) }
    }

    /// A folder was loaded (the app watches it).
    var onLoad: ((URL) -> Void)?

    private func remember(_ folder: URL) {
        UserDefaults.standard.set(folder.path, forKey: Keys.last)
        recent = [folder] + recent.filter { $0 != folder }.prefix(7)
        UserDefaults.standard.set(recent.map(\.path), forKey: Keys.recent)
    }

    /// Capture dates, read in the background (headers only; online-only files get their file date, since reading them
    /// would download them), then one reorder.
    private func readDates(_ generation: Int) {
        let items = photos.map { ($0.id, $0.url, $0.isOnlineOnly, $0.modified) }
        guard !items.isEmpty else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let dates = await withTaskGroup(of: (String, String?).self) { group in
                var out: [String: String] = [:]
                var next = 0
                func add(_ g: inout TaskGroup<(String, String?)>) {
                    let (id, url, online, modified) = items[next]
                    next += 1
                    g.addTask {
                        let exif = online ? nil : FileSource(url: url).flatMap { CaptureDate.find(in: $0) }
                        return (id, exif ?? PhotoOrder.fileDate(modified))
                    }
                }
                for _ in 0..<min(8, items.count) { add(&group) }
                for await (id, date) in group {
                    if let date { out[id] = date }
                    if next < items.count { add(&group) }
                }
                return out
            }
            await MainActor.run {
                guard generation == self.generation else { return }
                for i in self.photos.indices { self.photos[i].date = dates[self.photos[i].id] }
                self.isLoading = false
                self.reorder()
            }
        }
    }

    private func reorder() {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let culling = culling
        let (flagFilter, minStars) = (flagFilter, minStars)
        let matching = photos.filter {
            (needle.isEmpty || $0.name.lowercased().contains(needle))
                && flagFilter.passes(culling.rating($0.id), minStars: minStars)
        }
        let sort = sort
        visible = matching.sorted { PhotoOrder.inOrder(sort, ($0.date, $0.name), ($1.date, $1.name)) }
        var entries: [GridEntry] = []
        if showFolders, let folder {
            let parent = folder.deletingLastPathComponent()
            if parent.path != folder.path { entries.append(.parent(parent)) }
            let folders =
                needle.isEmpty
                ? subfolders : subfolders.filter { $0.lastPathComponent.lowercased().contains(needle) }
            entries += folders.map(GridEntry.folder)
        }
        items = entries + visible.map(GridEntry.photo)
    }

    // MARK: Folders

    /// Up to the parent folder, with the folder just left selected.
    func goUp() {
        guard let folder else { return }
        let parent = folder.deletingLastPathComponent()
        guard parent.path != folder.path else { return }
        load(parent, selectID: GridEntry.folderID(folder))
    }

    /// Opens a folder tile; false for a photo (the viewer opens those).
    func activate(_ id: String) -> Bool {
        switch items.first(where: { $0.id == id }) {
        case .parent: goUp()
        case .folder(let url): load(url)
        default: return false
        }
        return true
    }

    func isFavourite(_ url: URL) -> Bool { favourites.contains(url.standardizedFileURL) }

    func toggleFavourite(_ url: URL) {
        let url = url.standardizedFileURL
        if let i = favourites.firstIndex(of: url) {
            favourites.remove(at: i)
        } else {
            favourites.append(url)
        }
        UserDefaults.standard.set(favourites.map(\.path), forKey: Keys.favourites)
    }

    // MARK: Selection

    func click(_ id: String, command: Bool, shift: Bool) {
        if shift, let anchor, let a = items.firstIndex(where: { $0.id == anchor }),
            let b = items.firstIndex(where: { $0.id == id })
        {
            selection.formUnion(items[min(a, b)...max(a, b)].map(\.id))
        } else if command {
            if selection.remove(id) == nil { selection.insert(id) }
            anchor = id
        } else {
            selection = [id]
            anchor = id
        }
    }

    /// Every folder and photo shown, never the "Up a folder" tile.
    func selectAll() {
        selection = Set(
            items.compactMap { entry -> String? in
                if case .parent = entry { return nil }
                return entry.id
            })
    }

    func clearSelection() { selection = [] }

    /// Moves the selection by [step] places (±1 along a row, ±columns between rows).
    func move(by step: Int) {
        guard !items.isEmpty else { return }
        let current = anchor.flatMap { a in items.firstIndex { $0.id == a } }
        let target = current.map { min(max($0 + step, 0), items.count - 1) } ?? 0
        select(items[target].id)
    }

    /// Selects only [id] and scrolls to it.
    func select(_ id: String) {
        selection = [id]
        anchor = id
        scrollRequest += 1
    }

    var anchorIndex: Int? { anchor.flatMap { a in items.firstIndex { $0.id == a } } }
}
