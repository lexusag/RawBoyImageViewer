import Foundation

/// How the browser orders photos: by when they were shot, or by file name. Remembered.
/// The same as RawBoy's `PhotoSort` (`PhotoOrder.kt`, `.swift`, `.ts`).
public enum PhotoSort: String, CaseIterable, Sendable {
    case date, name
}

/// Photo order for `PhotoSort`. A port of RawBoy's `PhotoOrder.swift`: keep the two in step.
public enum PhotoOrder {
    /// [text] as an EXIF date "YYYY:MM:DD HH:MM:SS" (sorts as text) if it is one, else nil (blank or zero clocks).
    public static func validDate(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))),
            t.range(of: #"^\d{4}:\d\d:\d\d \d\d:\d\d:\d\d"#, options: .regularExpression) != nil,
            !t.hasPrefix("0000")
        else { return nil }
        return String(t.prefix(19))
    }

    /// A file's modified date as an EXIF date in local time: the date of photos with no capture date.
    public static func fileDate(_ date: Date?, timeZone: TimeZone = .current) -> String? {
        guard let date, date.timeIntervalSince1970 > 0 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.string(from: date)
    }

    /// File names as people read them: case-insensitive, runs of digits by value ("IMG_9" before "IMG_10").
    public static func compareNames(_ a: String, _ b: String) -> ComparisonResult {
        let r = a.compare(b, options: [.caseInsensitive, .numeric])
        return r != .orderedSame ? r : a.compare(b)
    }

    /// Whether [a] goes before [b] for [sort]: `.date` by date (oldest first; those without one after the rest, by
    /// name), then name; `.name` by name, then date.
    public static func inOrder(
        _ sort: PhotoSort, _ a: (date: String?, name: String), _ b: (date: String?, name: String)
    ) -> Bool {
        let byDate: ComparisonResult =
            switch (a.date, b.date) {
            case (let x?, let y?): x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
            case (nil, nil): .orderedSame
            case (nil, _): .orderedDescending
            case (_, nil): .orderedAscending
            }
        let byName = compareNames(a.name, b.name)
        let first = sort == .date ? byDate : byName
        return (first != .orderedSame ? first : (sort == .date ? byName : byDate)) == .orderedAscending
    }
}
