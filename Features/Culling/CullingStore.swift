import AppKit
import Observation
import RawBoyBrowseKit
import ViewerFiles
import ViewerImaging

/// Stars, picks and rejects of the open folder, kept in XMP sidecars as RawBoy Browser keeps them: read when the folder
/// opens, written 0.4 s after each change (one write at a time, each reading the file afresh), undoable together with
/// moves to the bin and the Trash.
@MainActor
@Observable
final class CullingStore {
    private(set) var folder: URL?
    /// By photo id (its main file name).
    private(set) var ratings: [String: Rating] = [:]
    /// Orientations sidecars set (`tiff:Orientation`, EXIF 1...8), by photo id: rotations made here, or in Lightroom.
    private(set) var orientations: [String: Int] = [:]
    /// Crops (RawBoy's `cropLeft`… in `rawboy:Develop`, fractions of the turned photo), by photo id.
    private(set) var crops: [String: CropRect] = [:]
    /// Photos whose sidecars hold RawBoy's edits: their turn is kept in RawBoy's fields too.
    private var hasDevelop: Set<String> = []
    /// Photos RawBoy straightened or corrected for perspective: the viewer leaves cropping them to RawBoy.
    private(set) var straightened: Set<String> = []
    /// Each photo's own EXIF orientation, once read.
    private var fileOrientations: [String: Int] = [:]
    /// The sidecars each photo has, including ones written since the folder opened.
    private(set) var sidecars: [String: [String]] = [:]
    private(set) var canUndo = false
    private(set) var binCount = 0
    /// A short note on what just happened ("Moved 3 rejects to _bin"), for the browser to show.
    private(set) var message: String?
    /// In the viewer, rating moves on to the next photo (RawBoy Browser's default: on).
    var autoAdvance: Bool = UserDefaults.standard.object(forKey: Keys.autoAdvance) as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoAdvance, forKey: Keys.autoAdvance) }
    }
    /// Files moved (bin, Trash, undo): the browser rereads the folder.
    var onFilesChanged: (() -> Void)?
    /// A rating changed (or the folder's were read).
    var onRatingsChanged: (() -> Void)?
    /// These photos were turned: their pictures must be made again.
    var onOrientationsChanged: (([String]) -> Void)?

    private var groups: [String: PhotoGroup] = [:]
    private var undoStack: [Undo] = []
    private var writeTimers: [String: DispatchWorkItem] = [:]
    /// How many times each photo was rated, turned or cropped here, and its sidecars written: a sidecar read that
    /// started before either (it may hold what the file said before the write) mustn't be applied.
    private var localChanges: [String: Int] = [:]
    /// Sidecar writes under way, by photo id.
    private var inFlight: [String: Int] = [:]
    /// Files this app wrote or moved just now, by name: the folder watcher's events for them aren't someone else's.
    private var ownChanges: [String: Date] = [:]
    private var writes: Task<Void, Never>?
    private var generation = 0

    enum Keys {
        static let autoAdvance = "culling.autoAdvance"
        static let trashNotice = "culling.syncedTrashNoticeShown"
        /// Set by "Don't ask again" on the browser's photo-only Trash question; folders always ask.
        static let trashPhotosWithoutAsking = "culling.trashPhotosWithoutAsking"
    }

    private enum Undo {
        case ratings([(id: String, rating: Rating)])
        case orientations([(id: String, orientation: Int?)])
        case crop(id: String, crop: CropRect?, orientation: Int?)
        case moves([FileMove], what: String)
        /// Files renamed in place (old name → new name); undone together, so names can swap back.
        case renames([FileMove])
    }

    static let writeDelay = 0.4

    func rating(_ id: String) -> Rating { ratings[id] ?? .none }

    func hasSidecar(_ id: String) -> Bool { !(sidecars[id] ?? []).isEmpty }

    /// Reads the ratings of [groups] in [folder] (in the background). Pending writes of the folder before are done
    /// first; undo doesn't reach across folders.
    func load(folder: URL, groups: [PhotoGroup]) {
        let sameFolder = folder == self.folder
        if !sameFolder { flushWrites() }
        generation += 1
        let generation = generation
        self.folder = folder
        self.groups = Dictionary(groups.map { ($0.main, $0) }, uniquingKeysWith: { a, _ in a })
        sidecars = Dictionary(groups.map { ($0.main, $0.sidecars) }, uniquingKeysWith: { a, _ in a })
        if !sameFolder {
            ratings = [:]
            orientations = [:]
            crops = [:]
            hasDevelop = []
            straightened = []
            fileOrientations = [:]
            undoStack = []
            canUndo = false
            message = nil
        }
        binCount = FileMoves.binPhotoCount(of: folder)
        readSidecars(of: groups, in: folder, generation: generation)
    }

    /// Reads [groups]' ratings and orientations again: their sidecars changed outside this app.
    func refresh(_ ids: [String]) {
        guard let folder else { return }
        readSidecars(of: ids.compactMap { groups[$0] }, in: folder, generation: generation)
    }

    /// Reads the sidecars of [groups] in the background and takes what they say, except for photos rated or turned
    /// here a moment ago (their writes are still to come, and win).
    private func readSidecars(of groups: [PhotoGroup], in folder: URL, generation: Int) {
        let groups = groups.map { group in
            PhotoGroup(
                stem: group.stem, main: group.main, companions: group.companions,
                sidecars: sidecars[group.main] ?? group.sidecars)
        }
        let changesAtStart = localChanges
        let busyAtStart = Set(groups.map(\.main).filter(isBusy))
        Task.detached(priority: .userInitiated) {
            var read: [String: Rating] = [:]
            var turned: [String: Int] = [:]
            var cropped: [String: CropRect] = [:]
            var developed: [String: DevelopGeometry] = [:]
            var own: [String: Int] = [:]
            for group in groups where !group.sidecars.isEmpty {
                let rating = SidecarFiles.rating(of: group, in: folder)
                if rating.isRated { read[group.main] = rating }
                if let o = SidecarFiles.orientation(of: group, in: folder) { turned[group.main] = o }
                // RawBoy's own turn wins over tiff:Orientation: RawBoy is the editor, and it doesn't keep that field.
                if let json = SidecarFiles.develop(of: group, in: folder), let g = DevelopEdits.geometry(json) {
                    let file = ImageLoader.fileOrientation(of: folder.appendingPathComponent(group.main))
                    own[group.main] = file
                    developed[group.main] = g
                    let wanted = Orientation(exif: file).then(g.orientation).exif
                    if wanted != file || turned[group.main] != nil { turned[group.main] = wanted }
                    if !g.crop.isFull { cropped[group.main] = g.crop }
                }
            }
            await MainActor.run {
                guard generation == self.generation else { return }
                var turnedIDs: [String] = []
                var rated = false
                for group in groups
                where !busyAtStart.contains(group.main) && !self.isBusy(group.main)
                    && self.localChanges[group.main] == changesAtStart[group.main]
                {
                    let id = group.main
                    self.fileOrientations.merge(own) { _, new in new }
                    if let g = developed[id] {
                        self.hasDevelop.insert(id)
                        if g.isStraightened { self.straightened.insert(id) } else { self.straightened.remove(id) }
                    } else {
                        self.hasDevelop.remove(id)
                        self.straightened.remove(id)
                    }
                    if self.crops[id] != cropped[id] {
                        self.crops[id] = cropped[id]
                        if !turnedIDs.contains(id) { turnedIDs.append(id) }
                    }
                    if self.ratings[id] != read[id] {
                        self.ratings[id] = read[id]
                        rated = true
                    }
                    if self.orientations[id] != turned[id] {
                        self.orientations[id] = turned[id]
                        turnedIDs.append(id)
                    }
                }
                if !turnedIDs.isEmpty { self.onOrientationsChanged?(turnedIDs) }
                if rated || generation != self.lastNotified {
                    self.lastNotified = generation
                    self.onRatingsChanged?()
                }
            }
        }
    }

    private var lastNotified = -1

    /// A rating or rotation of [id] is waiting to be written, or being written.
    func isBusy(_ id: String) -> Bool { writeTimers[id] != nil || (inFlight[id] ?? 0) > 0 }

    /// This app wrote or moved [name] in the last two seconds.
    func isOwnChange(_ name: String) -> Bool {
        guard let at = ownChanges[name] else { return false }
        return Date().timeIntervalSince(at) < 2
    }

    private func noteOwnChanges(_ names: [String]) {
        let now = Date()
        ownChanges = ownChanges.filter { now.timeIntervalSince($0.value) < 10 }
        for name in names { ownChanges[name] = now }
    }

    private func noteOwnChanges(_ moves: [FileMove]) {
        noteOwnChanges(moves.flatMap { [$0.from.lastPathComponent, $0.to.lastPathComponent] })
    }

    // MARK: Rating

    // Each takes one photo or several (the grid's selection); several are rated together and undo in one step.

    func setStars(_ ids: [String], _ stars: Int) {
        rate(ids, Rating.withStars(ids.map(rating), stars))
    }

    /// Sets [flag], or clears it when the photos already have it.
    func toggleFlag(_ ids: [String], _ flag: Flag) {
        rate(ids, Rating.withFlag(ids.map(rating), flag))
    }

    func clearFlag(_ ids: [String]) {
        rate(ids, ids.map { Rating(stars: rating($0).stars, flag: nil) })
    }

    private func rate(_ ids: [String], _ new: [Rating], undoable: Bool = true) {
        let changed = zip(ids, new).filter { rating($0.0) != $0.1 }
        guard !changed.isEmpty else { return }
        if undoable { push(.ratings(changed.map { ($0.0, rating($0.0)) })) }
        for (id, value) in changed {
            ratings[id] = value
            scheduleWrite(id)
        }
        onRatingsChanged?()
    }

    // MARK: Rotating

    /// The orientation a sidecar sets for [id], or nil (the file's own applies).
    func orientation(_ id: String) -> Int? { orientations[id] }

    /// [id]'s crop, or nil for none.
    func crop(_ id: String) -> CropRect? { crops[id] }

    /// Crops [id] (nil: no crop), RawBoy's way; undoable.
    func setCrop(_ id: String, _ crop: CropRect?) {
        let crop = crop.flatMap { $0.isFull ? nil : $0 }
        guard groups[id] != nil, crops[id] != crop else { return }
        push(.crop(id: id, crop: crops[id], orientation: orientations[id]))
        crops[id] = crop
        scheduleWrite(id)
        onOrientationsChanged?([id])
    }

    private func fileOrientation(_ id: String) -> Int {
        if let known = fileOrientations[id] { return known }
        guard let folder else { return 1 }
        let o = ImageLoader.fileOrientation(of: folder.appendingPathComponent(id))
        fileOrientations[id] = o
        return o
    }

    /// RawBoy's turn and crop for [id], when they go into its sidecars: it is cropped, or already has RawBoy's edits.
    private func developGeometry(_ id: String) -> DevelopGeometry? {
        guard crops[id] != nil || hasDevelop.contains(id) else { return nil }
        let file = fileOrientation(id)
        let delta = Orienting.delta(from: file, to: orientations[id] ?? file)
        return DevelopGeometry(rotation: delta.quarterTurns, mirrored: delta.mirrored, crop: crops[id] ?? .full)
    }

    /// Turns [ids] a quarter clockwise or anticlockwise, losslessly: the orientation goes into their sidecars, the
    /// files stay as they are.
    func rotate(_ ids: [String], clockwise: Bool) {
        guard let folder else { return }
        var previous: [(String, Int?)] = []
        for id in ids {
            guard groups[id] != nil else { continue }
            _ = folder
            let current = orientations[id] ?? fileOrientation(id)
            previous.append((id, orientations[id]))
            orientations[id] = Orientation(exif: current).then(clockwise ? .clockwise : .anticlockwise).exif
            // The crop turns with the picture, as in RawBoy.
            if let crop = crops[id] { crops[id] = CropMath.rotate(crop, quarterTurns: clockwise ? 1 : -1) }
            scheduleWrite(id)
        }
        guard !previous.isEmpty else { return }
        push(.orientations(previous))
        onOrientationsChanged?(previous.map(\.0))
    }

    // MARK: Undo

    /// Undoes the last rating change or file move. Returns the photo to show when one rating was undone.
    @discardableResult
    func undo() -> String? {
        guard let last = undoStack.popLast() else { return nil }
        canUndo = !undoStack.isEmpty
        switch last {
        case .ratings(let previous):
            rate(previous.map(\.id), previous.map(\.rating), undoable: false)
            return previous.count == 1 ? previous[0].id : nil
        case .orientations(let previous):
            for (id, o) in previous {
                // A crop turned with the photo turns back.
                if let crop = crops[id], let now = orientations[id] ?? Optional(fileOrientation(id)) {
                    let back = Orientation(exif: now).inverse.then(Orientation(exif: o ?? fileOrientation(id)))
                    if !back.mirrored { crops[id] = CropMath.rotate(crop, quarterTurns: back.quarterTurns) }
                }
                orientations[id] = o
                scheduleWrite(id)
            }
            onOrientationsChanged?(previous.map(\.id))
            return previous.count == 1 ? previous[0].id : nil
        case .crop(let id, let crop, let orientation):
            crops[id] = crop
            orientations[id] = orientation
            scheduleWrite(id)
            onOrientationsChanged?([id])
            return id
        case .moves(let moves, let what):
            noteOwnChanges(moves)
            let failed = FileMoves.moveBack(moves)
            message = failed == 0 ? "\(what) undone" : "\(failed) file\(failed == 1 ? "" : "s") couldn't be moved back"
            filesChanged()
            return nil
        case .renames(let moves):
            let back = moves.map { FileMove(from: $0.to, to: $0.from) }
            noteOwnChanges(moves)
            do {
                try FileMoves.renameAll(back)
                message = "Rename undone"
            } catch {
                message = "Couldn't undo the rename: \(error.localizedDescription)"
            }
            filesChanged()
            return nil
        }
    }

    private func push(_ undo: Undo) {
        undoStack.append(undo)
        if undoStack.count > 200 { undoStack.removeFirst() }
        canUndo = true
    }

    // MARK: Writing

    private func scheduleWrite(_ id: String) {
        localChanges[id, default: 0] += 1
        writeTimers[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.write(id) }
        writeTimers[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.writeDelay, execute: work)
    }

    private func write(_ id: String) {
        writeTimers[id] = nil
        guard let folder, let group = groups[id] else { return }
        let rating = rating(id)
        let orientation = orientations[id]
        let geometry = developGeometry(id)
        let names = (sidecars[id] ?? []).isEmpty ? ["\(group.stem).xmp"] : sidecars[id]!
        let previous = writes
        inFlight[id, default: 0] += 1
        noteOwnChanges(names)
        writes = Task {
            await previous?.value
            defer {
                self.localChanges[id, default: 0] += 1
                self.inFlight[id, default: 1] -= 1
                if self.inFlight[id] == 0 { self.inFlight[id] = nil }
                self.noteOwnChanges(names)
            }
            let result = await Task.detached {
                Result {
                    try SidecarFiles.write(
                        rating, orientation: orientation, geometry: geometry, names: names, in: folder)
                }
            }
            .value
            switch result {
            case .success(let written):
                if (self.sidecars[id] ?? []).isEmpty, !written.isEmpty, self.folder == folder {
                    self.sidecars[id] = written
                }
                if geometry != nil, self.folder == folder { self.hasDevelop.insert(id) }
            case .failure(let error):
                self.message = "Couldn't save the rating of \(group.main): \(error.localizedDescription)"
            }
        }
    }

    /// Writes every pending sidecar now.
    func flushWrites() {
        for (id, timer) in writeTimers {
            timer.cancel()
            write(id)
        }
    }

    /// Writes every pending sidecar on this thread, now (quitting). A write already under way finishes on its own;
    /// both write the same rating, each atomically.
    func writePendingNow() {
        guard let folder else { return }
        for (id, timer) in writeTimers {
            timer.cancel()
            guard let group = groups[id] else { continue }
            let names = (sidecars[id] ?? []).isEmpty ? ["\(group.stem).xmp"] : sidecars[id]!
            noteOwnChanges(names)
            _ = try? SidecarFiles.write(
                rating(id), orientation: orientations[id], geometry: developGeometry(id), names: names, in: folder)
        }
        writeTimers = [:]
    }

    /// Waits until every write is on disk (before moving files).
    func finishWrites() async {
        flushWrites()
        await writes?.value
    }

    // MARK: Bin and Trash

    /// Moves every reject (its raw, companions and sidecars) into the folder's `_bin`; undoable.
    func moveRejectsToBin(_ visibleOrder: [PhotoGroup]) async {
        guard let folder else { return }
        await finishWrites()
        let rejects = visibleOrder.filter { rating($0.main).flag == .reject }
        guard !rejects.isEmpty else {
            message = "No rejects to move"
            return
        }
        var moves: [FileMove] = []
        var failed = 0
        for group in rejects {
            let current = PhotoGroup(
                stem: group.stem, main: group.main, companions: group.companions, sidecars: sidecars[group.main] ?? [])
            do { moves += try FileMoves.moveToBin(current, in: folder) } catch { failed += 1 }
            noteOwnChanges(moves)
        }
        let moved = rejects.count - failed
        if !moves.isEmpty { push(.moves(moves, what: "Move to \(FolderScanner.binFolderName)")) }
        message =
            failed == 0
            ? "Moved \(moved) reject\(moved == 1 ? "" : "s") to \(FolderScanner.binFolderName)"
            : "Moved \(moved) to \(FolderScanner.binFolderName); \(failed) couldn't be moved"
        filesChanged()
    }

    /// Moves everything in the bin back into the folder; undoable.
    func restoreBin() {
        guard let folder else { return }
        let moves = FileMoves.binContents(of: folder)
        guard !moves.isEmpty else { return }
        noteOwnChanges(moves)
        let failed = FileMoves.moveBack(moves)
        let photos = moves.filter { PhotoFileType(fileName: $0.from.lastPathComponent) != nil }.count
        message =
            failed == 0
            ? "\(photos) photo\(photos == 1 ? "" : "s") back from \(FolderScanner.binFolderName)"
            : "\(failed) file\(failed == 1 ? "" : "s") couldn't be moved back"
        filesChanged()
    }

    /// Moves [ids] (with their companions and sidecars) to the Trash; undoable. In a cloud sync folder the first time
    /// asks first, because the Trash there deletes from every device too.
    /// [syncedNoticeShown]: the caller's own question already carried the synced-folder warning.
    func moveToTrash(_ ids: [String], syncedNoticeShown: Bool = false) async {
        guard let folder, !ids.isEmpty, syncedNoticeShown || confirmTrashInSyncedFolder(folder) else { return }
        await finishWrites()
        var moves: [FileMove] = []
        var failed = 0
        for id in ids {
            guard let group = groups[id] else { continue }
            let current = PhotoGroup(
                stem: group.stem, main: group.main, companions: group.companions, sidecars: sidecars[id] ?? [])
            do { moves += try FileMoves.trash(current, in: folder) } catch { failed += 1 }
            noteOwnChanges(moves)
        }
        let moved = ids.count - failed
        if !moves.isEmpty { push(.moves(moves, what: "Move to Trash")) }
        message =
            failed == 0
            ? "Moved \(moved) photo\(moved == 1 ? "" : "s") to the Trash"
            : "Moved \(moved) to the Trash; \(failed) couldn't be moved"
        filesChanged()
    }

    /// Moves subfolders (with everything in them) to the Trash; one undo step. The caller has asked already.
    func moveFoldersToTrash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var moves: [FileMove] = []
        var failed = 0
        for url in urls {
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                if let trashed = trashed as URL? { moves.append(FileMove(from: url, to: trashed)) }
            } catch { failed += 1 }
        }
        noteOwnChanges(moves)
        if !moves.isEmpty { push(.moves(moves, what: "Move to Trash")) }
        let moved = urls.count - failed
        message =
            failed == 0
            ? "Moved \(moved) folder\(moved == 1 ? "" : "s") to the Trash"
            : "Moved \(moved) folder\(moved == 1 ? "" : "s") to the Trash; \(failed) couldn't be moved"
        filesChanged()
    }

    /// Renames the photos in [items] (each with its JPEG and sidecars, as planned); undoable as one step. Returns each
    /// renamed photo's new id by its old one; empty when nothing was renamed.
    func rename(_ items: [RenameItem]) async -> [String: String] {
        guard let folder else { return [:] }
        await finishWrites()
        let changing = items.filter { $0.status == .ok }
        let moves = changing.flatMap { item in
            item.files.filter { $0.old != $0.new }.map {
                FileMove(from: folder.appendingPathComponent($0.old), to: folder.appendingPathComponent($0.new))
            }
        }
        guard !moves.isEmpty else { return [:] }
        noteOwnChanges(moves)
        do {
            try FileMoves.renameAll(moves)
        } catch {
            message = "Couldn't rename: \(error.localizedDescription). Nothing was changed"
            return [:]
        }
        push(.renames(moves))
        message = "Renamed \(changing.count) photo\(changing.count == 1 ? "" : "s")"
        filesChanged()
        return Dictionary(changing.map { ($0.id, $0.newMain) }, uniquingKeysWith: { a, _ in a })
    }

    /// Files moved elsewhere (Move to…): undoable like the bin.
    func recordMoves(_ moves: [FileMove], what: String) {
        guard !moves.isEmpty else { return }
        noteOwnChanges(moves)
        push(.moves(moves, what: what))
        filesChanged()
    }

    /// A note for the browser's bar.
    func say(_ text: String?) { message = text }

    private func filesChanged() {
        if let folder { binCount = FileMoves.binPhotoCount(of: folder) }
        onFilesChanged?()
    }

    /// Cloud sync folders: iCloud Drive and the File Provider clients under ~/Library/CloudStorage.
    static func isSyncedFolder(_ folder: URL) -> Bool {
        let path = folder.standardizedFileURL.path
        return path.contains("/Library/CloudStorage/") || path.contains("/Library/Mobile Documents/")
    }

    private func confirmTrashInSyncedFolder(_ folder: URL) -> Bool {
        guard Self.isSyncedFolder(folder), !UserDefaults.standard.bool(forKey: Keys.trashNotice) else { return true }
        let alert = NSAlert()
        alert.messageText = "Move to the Trash in a synced folder?"
        alert.informativeText =
            "This folder syncs with the cloud: photos moved to the Trash are deleted there and on your other devices "
            + "too. Moving rejects to \(FolderScanner.binFolderName) keeps them instead."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let ok = alert.runModal() == .alertFirstButtonReturn
        if ok, alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: Keys.trashNotice) }
        return ok
    }
}
