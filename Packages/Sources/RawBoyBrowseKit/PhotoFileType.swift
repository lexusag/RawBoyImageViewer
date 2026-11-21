/// Which files the viewer shows, by extension (case-insensitive).
public enum PhotoFileType: Equatable, Sendable {
    /// A camera raw. TIFF-based raws (DNG, NEF, ARW…) are raws, not TIFFs.
    case raw
    /// A file that is already a picture: JPEG, HEIC, PNG, TIFF…
    case display
    /// A video: shown in the browser with a still as its thumbnail, opened in the default player (the viewer
    /// itself shows only pictures).
    case video

    /// RawBoy's list (`RAW_ACCEPT` in RawBoy's web/src/ui/common/files.ts): keep them the same.
    public static let rawExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "crw", "dcr", "dng", "erf", "fff", "iiq", "kdc", "mos", "mrw", "nef", "nrw",
        "orf", "pef", "raf", "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f",
    ]

    /// RawBoy Browser's image types, plus AVIF, WebP and JPEG XL, which ImageIO opens.
    public static let displayExtensions: Set<String> = [
        "avif", "heic", "heif", "jpeg", "jpg", "jxl", "png", "tif", "tiff", "webp",
    ]

    /// Common video containers, which AVFoundation can take a still from.
    public static let videoExtensions: Set<String> = ["avi", "m4v", "mkv", "mov", "mp4", "mts", "m2ts", "webm"]

    /// The type of a file named [fileName], or nil when the viewer doesn't show it.
    public init?(fileName: String) {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return nil }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        if Self.rawExtensions.contains(ext) {
            self = .raw
        } else if Self.displayExtensions.contains(ext) {
            self = .display
        } else if Self.videoExtensions.contains(ext) {
            self = .video
        } else {
            return nil
        }
    }
}
