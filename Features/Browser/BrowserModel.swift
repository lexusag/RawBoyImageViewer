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
    var thumbnailSize: Double = UserDefaults.standard.object(forKey: Keys.size) as? Double ?? 168 {
        didSet { UserDefaults.standard.set(thumbnailSize, forKey: Keys.size) }
    }
    var selection: Set<String> = []
    /// Where Shift-click ranges and arrow keys start.
    var anchor: String?
    /// Bumped to scroll the grid to [anchor].
    private(set) var scrollRequest = 0
    private(set) var recent: [URL] = (UserDefaults.standard.stringArray(forKey: Keys.recent) ?? []).map {
        URL(fileURLWithPath: $0)
    }

    /// What the grid shows: the photos matching the filter, in order.
    private(set) var visible: [BrowsePhoto] = []

    let thumbnails = ThumbnailStore(pixelSize: 480)
    private var generation = 0

    enum Keys {
        static let sort = "browser.sort"
        static let size = "browser.thumbnailSize"
        static let recent = "browser.recentFolders"
        static let last = "browser.lastFolder"
    }

    static var lastFolder: URL? {
        UserDefaults.standard.string(forKey: Keys.last).map { URL(fileURLWithPath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// Shows [folder]: its photos at once in name order, reordered once their dates are read. [select] is a file name
    /// to select (and scroll to).
    func load(_ folder: URL, select: String? = nil) {
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
        let wanted = select.map { PhotoGroups.stem(of: $0).lowercased() }
        let selected = wanted.flatMap { w in photos.first { $0.group.stem.lowercased() == w }?.id }
        selection = selected.map { [$0] } ?? []
        anchor = selected ?? photos.first?.id
        reorder()
        scrollRequest += 1
        remember(folder)
        readDates(generation)
    }

    func reload() {
        if let folder { load(folder, select: anchor) }
    }

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
        let matching = needle.isEmpty ? photos : photos.filter { $0.name.lowercased().contains(needle) }
        let sort = sort
        visible = matching.sorted { PhotoOrder.inOrder(sort, ($0.date, $0.name), ($1.date, $1.name)) }
    }

    // MARK: Selection

    func click(_ id: String, command: Bool, shift: Bool) {
        if shift, let anchor, let a = visible.firstIndex(where: { $0.id == anchor }),
            let b = visible.firstIndex(where: { $0.id == id })
        {
            selection.formUnion(visible[min(a, b)...max(a, b)].map(\.id))
        } else if command {
            if selection.remove(id) == nil { selection.insert(id) }
            anchor = id
        } else {
            selection = [id]
            anchor = id
        }
    }

    func selectAll() { selection = Set(visible.map(\.id)) }

    func clearSelection() { selection = [] }

    /// Moves the selection by [step] places (±1 along a row, ±columns between rows).
    func move(by step: Int) {
        guard !visible.isEmpty else { return }
        let current = anchor.flatMap { a in visible.firstIndex { $0.id == a } }
        let target = current.map { min(max($0 + step, 0), visible.count - 1) } ?? 0
        select(visible[target].id)
    }

    /// Selects only [id] and scrolls to it.
    func select(_ id: String) {
        selection = [id]
        anchor = id
        scrollRequest += 1
    }

    var anchorIndex: Int? { anchor.flatMap { a in visible.firstIndex { $0.id == a } } }
}
