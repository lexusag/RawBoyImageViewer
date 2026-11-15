import Foundation

/// The browser's selection counter: "3 files, 1 folder selected". Folders are only named when some are selected.
public enum SelectionSummary {
    public static func text(files: Int, folders: Int) -> String {
        var parts: [String] = []
        if files > 0 || folders == 0 { parts.append("\(files) \(files == 1 ? "file" : "files")") }
        if folders > 0 { parts.append("\(folders) \(folders == 1 ? "folder" : "folders")") }
        return parts.joined(separator: ", ") + " selected"
    }
}
