import Foundation
import RawBoyBrowseKit

/// One file moved (to the bin, the Trash, or back), for undo.
public struct FileMove: Equatable, Sendable {
    public let from: URL
    public let to: URL

    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
    }
}

/// Moving photos with their companions and sidecars: into the folder's `_bin` (RawBoy Browser's bin), into the
/// Trash, and back.
public enum FileMoves {
    /// Moves [group]'s files from [folder] into its `_bin`, with one suffix for the whole photo when a name is taken
    /// there, so its sidecars keep matching it.
    public static func moveToBin(_ group: PhotoGroup, in folder: URL) throws -> [FileMove] {
        let bin = folder.appendingPathComponent(FolderScanner.binFolderName)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let names = [group.main] + group.companions + group.sidecars
        var suffix = ""
        var k = 1
        while names.contains(where: {
            FileManager.default.fileExists(
                atPath: bin.appendingPathComponent(PhotoGroups.withSuffix($0, stem: group.stem, suffix: suffix)).path)
        }) {
            suffix = "-\(k)"
            k += 1
        }
        var moves: [FileMove] = []
        for name in names {
            let move = FileMove(
                from: folder.appendingPathComponent(name),
                to: bin.appendingPathComponent(PhotoGroups.withSuffix(name, stem: group.stem, suffix: suffix)))
            try FileManager.default.moveItem(at: move.from, to: move.to)
            moves.append(move)
        }
        return moves
    }

    /// Moves [group]'s files to the Trash.
    public static func trash(_ group: PhotoGroup, in folder: URL) throws -> [FileMove] {
        var moves: [FileMove] = []
        for name in [group.main] + group.companions + group.sidecars {
            let url = folder.appendingPathComponent(name)
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            if let trashed = trashed as URL? { moves.append(FileMove(from: url, to: trashed)) }
        }
        return moves
    }

    /// Moves [names] in [folder] to the Trash, skipping missing files.
    public static func trashFiles(_ names: [String], in folder: URL) -> (moves: [FileMove], failed: Int) {
        var moves: [FileMove] = []
        var failed = 0
        for name in names {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                if let trashed = trashed as URL? { moves.append(FileMove(from: url, to: trashed)) }
            } catch {
                failed += 1
            }
        }
        return (moves, failed)
    }

    /// Moves [moves] back (`to` → `from`), under another name when `from` is taken now. Returns how many failed.
    @discardableResult
    public static func moveBack(_ moves: [FileMove]) -> Int {
        var failed = 0
        for move in moves {
            var target = move.from
            var k = 1
            while FileManager.default.fileExists(atPath: target.path) {
                let name = move.from.lastPathComponent
                target = move.from.deletingLastPathComponent().appendingPathComponent(
                    PhotoGroups.withSuffix(name, stem: PhotoGroups.stem(of: name), suffix: "-\(k)"))
                k += 1
            }
            do { try FileManager.default.moveItem(at: move.to, to: target) } catch { failed += 1 }
        }
        return failed
    }

    /// Renames files in place, all or none: every file first moves to a temporary name, then to its new one, so names
    /// can be swapped or shifted (IMG_1 → IMG_2 → IMG_3) and a case-only change works on a case-insensitive volume.
    /// A name that is taken (by anything) fails the whole batch, which is put back as it was.
    public static func renameAll(_ moves: [FileMove]) throws {
        let fm = FileManager.default
        let token = UUID().uuidString.prefix(8)
        var staged: [(temp: URL, move: FileMove)] = []
        func rollBack(_ placed: [FileMove]) {
            for move in placed.reversed() { try? fm.moveItem(at: move.to, to: move.from) }
            for item in staged.reversed() where !fm.fileExists(atPath: item.move.from.path) {
                try? fm.moveItem(at: item.temp, to: item.move.from)
            }
        }
        for (i, move) in moves.enumerated() {
            let temp = move.from.deletingLastPathComponent().appendingPathComponent(".rawboy-rename-\(token)-\(i)")
            do { try fm.moveItem(at: move.from, to: temp) } catch {
                rollBack([])
                throw error
            }
            staged.append((temp, move))
        }
        var placed: [FileMove] = []
        for item in staged {
            do {
                try fm.moveItem(at: item.temp, to: item.move.to)
                placed.append(item.move)
            } catch {
                rollBack(placed)
                throw error
            }
        }
    }

    /// Every file in [folder]'s bin, as moves back into [folder].
    public static func binContents(of folder: URL) -> [FileMove] {
        let bin = folder.appendingPathComponent(FolderScanner.binFolderName)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: bin.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.map {
            FileMove(from: folder.appendingPathComponent($0), to: bin.appendingPathComponent($0))
        }
    }

    /// How many photos are in [folder]'s bin.
    public static func binPhotoCount(of folder: URL) -> Int {
        binContents(of: folder).filter { PhotoFileType(fileName: $0.to.lastPathComponent) != nil }.count
    }
}

/// Reading and writing sidecars. Writes are atomic (a temporary file, then a rename), so a sync client never uploads
/// a half-written sidecar.
public enum SidecarFiles {
    public static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The rating of a photo: from the first of its sidecars (by name, as RawBoy reads them) that has one.
    public static func rating(of group: PhotoGroup, in folder: URL) -> Rating {
        for name in group.sidecars {
            if let text = read(folder.appendingPathComponent(name)), XmpSidecar.hasRating(text) {
                return XmpSidecar.read(text)
            }
        }
        return .none
    }

    /// The orientation a photo's sidecars set (`tiff:Orientation`, from the first that has one), or nil.
    public static func orientation(of group: PhotoGroup, in folder: URL) -> Int? {
        for name in group.sidecars {
            if let text = read(folder.appendingPathComponent(name)), let o = XmpSidecar.readOrientation(text) {
                return o
            }
        }
        return nil
    }

    /// RawBoy's edits JSON from a photo's sidecars (the first that has it), or nil.
    public static func develop(of group: PhotoGroup, in folder: URL) -> String? {
        for name in group.sidecars {
            if let text = read(folder.appendingPathComponent(name)), let json = XmpSidecar.readDevelop(text) {
                return json
            }
        }
        return nil
    }

    /// Writes [rating], [orientation] (nil: none) and, when given, RawBoy's turn and crop [geometry] into each of
    /// [names] in [folder] (RawBoy writes every sidecar a photo has), creating a new one only when there is something
    /// to keep. Returns the names written.
    public static func write(
        _ rating: Rating, orientation: Int? = nil, geometry: DevelopGeometry? = nil, names: [String], in folder: URL
    ) throws -> [String] {
        var written: [String] = []
        for name in names {
            let url = folder.appendingPathComponent(name)
            let text = read(url)
            let develop = geometry.flatMap { DevelopEdits.write(text.flatMap(XmpSidecar.readDevelop), $0) }
            if text == nil && !rating.isRated && orientation == nil && develop == nil { continue }
            var out = try XmpSidecar.writeOrientation(XmpSidecar.write(text, rating), orientation)
            if geometry != nil { out = try XmpSidecar.writeDevelop(out, develop) }
            try Data(out.utf8).write(to: url, options: .atomic)
            written.append(name)
        }
        return written
    }
}
