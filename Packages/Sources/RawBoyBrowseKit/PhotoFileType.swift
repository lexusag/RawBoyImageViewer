/// Which files the viewer shows, by extension (case-insensitive).
public enum PhotoFileType: Equatable, Sendable {
    /// A camera raw. TIFF-based raws (DNG, NEF, ARW…) are raws, not TIFFs.
    case raw
    /// A file that is already a picture: JPEG, HEIC, PNG, TIFF…
    case display

    public static let rawExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "crw", "dcr", "dng", "erf", "fff", "gpr", "iiq", "kdc", "mos", "mrw",
        "nef", "nrw", "orf", "pef", "raf", "rw2", "rwl", "sr2", "srf", "srw", "x3f",
    ]

    public static let displayExtensions: Set<String> = [
        "avif", "heic", "heif", "jpeg", "jpg", "jxl", "png", "tif", "tiff", "webp",
    ]

    /// The type of a file named [fileName], or nil when the viewer doesn't show it.
    public init?(fileName: String) {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return nil }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        if Self.rawExtensions.contains(ext) {
            self = .raw
        } else if Self.displayExtensions.contains(ext) {
            self = .display
        } else {
            return nil
        }
    }
}
