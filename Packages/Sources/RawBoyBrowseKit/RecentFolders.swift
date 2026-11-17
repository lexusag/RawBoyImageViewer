import Foundation

/// The sidebar's Recent list: pinned folders first (in the order they were pinned), then the latest others.
/// Pinned folders are kept apart from the recents, so the recents limit never drops them.
/// Folders are compared by path: a URL rebuilt from a stored path may differ from the original in its trailing slash.
public enum RecentFolders {
    public static func same(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL.path == b.standardizedFileURL.path }

    /// How many unpinned recents are kept.
    public static let keep = 8
    /// How many unpinned recents are shown.
    public static let shown = 6

    /// [folder] first, the rest as they were, at most [keep].
    public static func remembering(_ folder: URL, in recent: [URL]) -> [URL] {
        let folder = folder.standardizedFileURL
        return Array(([folder] + recent.filter { !same($0, folder) }).prefix(keep))
    }

    /// [folder] pinned (added last) or unpinned.
    public static func toggling(_ folder: URL, in pinned: [URL]) -> [URL] {
        let folder = folder.standardizedFileURL
        if pinned.contains(where: { same($0, folder) }) {
            return pinned.filter { !same($0, folder) }
        }
        return pinned + [folder]
    }

    /// What the sidebar lists: every pinned folder, then up to [shown] recents that are not pinned.
    public static func listed(recent: [URL], pinned: [URL]) -> [URL] {
        let others = recent.filter { r in !pinned.contains { same($0, r) } }
        return pinned + others.prefix(shown)
    }
}
