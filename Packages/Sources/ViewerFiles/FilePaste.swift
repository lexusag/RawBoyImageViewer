import Foundation
import RawBoyBrowseKit

/// Pasting files into a folder: copies, never overwriting.
///
/// A photo's files (the raw, its JPEG, its sidecars) share one suffix when the name is taken, so they still match:
/// IMG_1.CR2 + IMG_1.xmp → "IMG_1 2.CR2" + "IMG_1 2.xmp". A folder becomes "Name 2".
public enum FilePaste {
    /// What a paste made.
    public struct Result: Equatable, Sendable {
        /// Every file or folder made.
        public var created: [URL] = []
        /// Photos (and other files) pasted, a photo's files counted once.
        public var files = 0
        public var folders = 0
        /// Items that couldn't be copied.
        public var failed = 0
    }

    /// Source → target pairs for [sources] pasted into [destination]. Nothing is copied. A folder pasted into itself
    /// or into its own subfolder is left out (it would never end).
    public static func plan(_ sources: [URL], into destination: URL) -> (units: [[FileMove]], folders: [FileMove]) {
        let fm = FileManager.default
        var taken = Set<String>()
        func exists(_ url: URL) -> Bool {
            taken.contains(url.lastPathComponent.lowercased()) || fm.fileExists(atPath: url.path)
        }

        var directories: [URL] = []
        var byParent: [URL: [URL]] = [:]
        var order: [URL] = []
        for source in sources {
            var isDirectory: ObjCBool = false
            guard !source.lastPathComponent.hasPrefix("."),
                fm.fileExists(atPath: source.path, isDirectory: &isDirectory)
            else { continue }
            if isDirectory.boolValue {
                directories.append(source)
            } else {
                let parent = source.deletingLastPathComponent().standardizedFileURL
                if byParent[parent] == nil { order.append(parent) }
                if !(byParent[parent] ?? []).contains(source) { byParent[parent, default: []].append(source) }
            }
        }

        var units: [[FileMove]] = []
        for parent in order {
            let urls = byParent[parent] ?? []
            let byName = Dictionary(urls.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
            let names = urls.map(\.lastPathComponent)
            // A photo's files go together; anything else is its own unit.
            var found: [(stem: String, names: [String])] = []
            var grouped = Set<String>()
            for group in PhotoGroups.group(names) {
                let members = [group.main] + group.companions + group.sidecars
                found.append((group.stem, members))
                grouped.formUnion(members)
            }
            for name in names where !grouped.contains(name) {
                found.append((PhotoGroups.stem(of: name), [name]))
            }
            for unit in found {
                var suffix = ""
                var k = 2
                func target(_ name: String) -> URL {
                    destination.appendingPathComponent(PhotoGroups.withSuffix(name, stem: unit.stem, suffix: suffix))
                }
                while unit.names.contains(where: { exists(target($0)) }) {
                    suffix = " \(k)"
                    k += 1
                }
                var moves: [FileMove] = []
                for name in unit.names {
                    guard let from = byName[name] else { continue }
                    let to = target(name)
                    taken.insert(to.lastPathComponent.lowercased())
                    moves.append(FileMove(from: from, to: to))
                }
                units.append(moves)
            }
        }

        var folders: [FileMove] = []
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        for source in directories {
            let path = source.standardizedFileURL.resolvingSymlinksInPath().path
            if destinationPath.hasPrefix(path + "/") { continue }
            var to = destination.appendingPathComponent(source.lastPathComponent)
            var k = 2
            while exists(to) {
                to = destination.appendingPathComponent("\(source.lastPathComponent) \(k)")
                k += 1
            }
            taken.insert(to.lastPathComponent.lowercased())
            folders.append(FileMove(from: source, to: to))
        }
        return (units, folders)
    }

    /// Copies [sources] into [destination] as [plan] says.
    @discardableResult
    public static func paste(_ sources: [URL], into destination: URL) -> Result {
        let (units, folders) = plan(sources, into: destination)
        var result = Result()
        let fm = FileManager.default
        for source in sources {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue,
                !folders.contains(where: { $0.from == source })
            {
                result.failed += 1
            }
        }
        for unit in units {
            var copied = false
            for move in unit {
                do {
                    try fm.copyItem(at: move.from, to: move.to)
                    result.created.append(move.to)
                    copied = true
                } catch {
                    result.failed += 1
                }
            }
            if copied { result.files += 1 }
        }
        for move in folders {
            do {
                try FileManager.default.copyItem(at: move.from, to: move.to)
                result.created.append(move.to)
                result.folders += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }
}
