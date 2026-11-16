import Foundation

/// The sidebar's Recent list: pinned folders first (in the order they were pinned), then the latest others.
/// Pinned folders are kept apart from the recents, so the recents limit never drops them.
public enum RecentFolders {
    /// How many unpinned recents are kept.
    public static let keep = 8
    /// How many unpinned recents are shown.
    public static let shown = 6

    /// [folder] first, the rest as they were, at most [keep].
    public static func remembering(_ folder: URL, in recent: [URL]) -> [URL] {
        let folder = folder.standardizedFileURL
        return Array(([folder] + recent.filter { $0.standardizedFileURL != folder }).prefix(keep))
    }

    /// [folder] pinned (added last) or unpinned.
    public static func toggling(_ folder: URL, in pinned: [URL]) -> [URL] {
        let folder = folder.standardizedFileURL
        if pinned.contains(where: { $0.standardizedFileURL == folder }) {
            return pinned.filter { $0.standardizedFileURL != folder }
        }
        return pinned + [folder]
    }

    /// What the sidebar lists: every pinned folder, then up to [shown] recents that are not pinned.
    public static func listed(recent: [URL], pinned: [URL]) -> [URL] {
        let fixed = Set(pinned.map(\.standardizedFileURL))
        let others = recent.filter { !fixed.contains($0.standardizedFileURL) }
        return pinned + others.prefix(shown)
    }
}
