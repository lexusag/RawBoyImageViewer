import Darwin
import Foundation
import RawBoyBrowseKit

/// One photo file found in a folder, with what the directory entry says about it (never its contents).
public struct PhotoFile: Equatable, Sendable {
    public let url: URL
    public let type: PhotoFileType
    public let size: Int64?
    public let modified: Date?
    /// Only a placeholder is on this Mac (a cloud sync folder): reading it would download it.
    public let isOnlineOnly: Bool

    public init(url: URL, type: PhotoFileType, size: Int64? = nil, modified: Date? = nil, isOnlineOnly: Bool = false) {
        self.url = url
        self.type = type
        self.size = size
        self.modified = modified
        self.isOnlineOnly = isOnlineOnly
    }
}

/// Lists a folder's photos and sidecars (not its subfolders).
///
/// Reads directory entries only, never file contents, so online-only files in a cloud sync folder aren't downloaded.
public enum FolderScanner {
    /// The bin subfolder rejects are moved into, as RawBoy Browser does. Never shown as photos.
    public static let binFolderName = "_bin"

    static let keys: [URLResourceKey] = [
        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// The photos in [folder], sorted by file name. Hidden files are skipped.
    public static func photos(in folder: URL) throws -> [PhotoFile] {
        try entries(in: folder).compactMap { url -> PhotoFile? in
            guard let type = PhotoFileType(fileName: url.lastPathComponent) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return nil }
            return PhotoFile(
                url: url, type: type, size: values?.fileSize.map(Int64.init), modified: values?.contentModificationDate,
                isOnlineOnly: CloudStatus.isOnlineOnly(url, values: values))
        }
        .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    /// The names of [folder]'s XMP sidecars.
    public static func sidecarNames(in folder: URL) throws -> [String] {
        try entries(in: folder).map(\.lastPathComponent).filter { $0.lowercased().hasSuffix(".xmp") }
    }

    /// [folder]'s visible subfolders (packages and the bin left out), by name.
    public static func subfolders(of folder: URL) -> [URL] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true && url.lastPathComponent != binFolderName
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Whether [folder] has any visible subfolder. Stops at the first one, so it is cheaper than `subfolders(of:)` on
    /// big folders; run it off the main thread (network volumes can be slow).
    public static func hasSubfolders(in folder: URL) -> Bool {
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        else { return false }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true && values?.isPackage != true && url.lastPathComponent != binFolderName {
                return true
            }
        }
        return false
    }

    private static func entries(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
    }
}

/// Cloud sync folders (iCloud Drive and the File Provider clients: Dropbox, Google Drive, Synology Drive...) keep
/// files as dataless placeholders until read. Telling them apart reads metadata only.
public enum CloudStatus {
    /// `SF_DATALESS` from sys/stat.h: the file's data isn't on this Mac.
    static let datalessFlag: UInt32 = 0x4000_0000

    public static func isOnlineOnly(_ url: URL, values: URLResourceValues? = nil) -> Bool {
        let values = values ?? (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))
        if let status = values?.ubiquitousItemDownloadingStatus, status == .notDownloaded { return true }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & datalessFlag != 0
    }
}
