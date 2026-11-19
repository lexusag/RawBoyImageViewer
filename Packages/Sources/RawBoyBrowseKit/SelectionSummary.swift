import Foundation

/// The browser's selection counter: "3 files, 1 folder selected · 2.5 MB". Folders are only named when some are
/// selected, and the total size is shown when at least one file is selected.
public enum SelectionSummary {
    public static func text(files: Int, folders: Int, bytes: Int64? = nil) -> String {
        var parts: [String] = []
        if files > 0 || folders == 0 { parts.append("\(files) \(files == 1 ? "file" : "files")") }
        if folders > 0 { parts.append("\(folders) \(folders == 1 ? "folder" : "folders")") }
        let summary = parts.joined(separator: ", ") + " selected"
        guard files > 0, let bytes else { return summary }
        return "\(summary) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}
