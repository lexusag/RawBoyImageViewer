import AppKit

/// What "Copy Folder Name" and "Copy Folder Path" put on the clipboard (plain text, to paste anywhere).
enum FolderCopy {
    /// The folder's own name; a volume's root (`/`) keeps its Finder name.
    static func name(of url: URL) -> String {
        let name = url.standardizedFileURL.lastPathComponent
        return name.isEmpty || name == "/"
            ? (FileManager.default.displayName(atPath: url.path)) : name
    }

    /// The full absolute path, without a trailing slash.
    static func path(of url: URL) -> String { url.standardizedFileURL.path }

    @MainActor
    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}
