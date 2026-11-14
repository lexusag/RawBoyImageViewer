import Foundation
import RawBoyBrowseKit

/// One photo file found in a folder.
public struct PhotoFile: Equatable, Sendable {
    public let url: URL
    public let type: PhotoFileType

    public init(url: URL, type: PhotoFileType) {
        self.url = url
        self.type = type
    }
}

/// Lists a folder's photos (not its subfolders).
///
/// Reads directory entries only, never file contents, so online-only files in a cloud sync folder aren't downloaded.
public enum FolderScanner {
    /// The bin subfolder rejects are moved into, as RawBoy Browser does. Never shown as photos.
    public static let binFolderName = "_bin"

    /// The photos in [folder], sorted by file name. Hidden files are skipped.
    public static func photos(in folder: URL) throws -> [PhotoFile] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return urls.compactMap { url -> PhotoFile? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                let type = PhotoFileType(fileName: url.lastPathComponent)
            else { return nil }
            return PhotoFile(url: url, type: type)
        }
        .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }
}
