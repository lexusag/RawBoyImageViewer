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

    /// The photo to show when [previous] (at [index], [current]) becomes [remaining]: [current] when it is still
    /// there, else the first photo from [index] onwards in [previous] that remains, else the last one before [index].
    public static func nextAfterRemoval(
        previous: [String], remaining: [String], current: String?, index: Int
    ) -> String? {
        guard !remaining.isEmpty else { return nil }
        let kept = Set(remaining)
        if let current, kept.contains(current) { return current }
        if previous.indices.contains(index) {
            if let next = previous[index...].first(where: { kept.contains($0) }) { return next }
            if let before = previous[..<index].last(where: { kept.contains($0) }) { return before }
        }
        return remaining[min(max(index, 0), remaining.count - 1)]
    }

    /// The browser's selection and anchor after the folder or filter changes: what remains of [selection], or, when
    /// all of it was removed, the next photo (or item) after where the selection stood.
    public static func selectionAfterRemoval(
        previousPhotos: [String],
        remainingPhotos: [String],
        previousItems: [String] = [],
        remainingItems: [String] = [],
        selection: Set<String>,
        anchor: String?
    ) -> (selection: Set<String>, anchor: String?) {
        let prevItems = previousItems.isEmpty ? previousPhotos : previousItems
        let remItems = remainingItems.isEmpty ? remainingPhotos : remainingItems
        let keptItems = Set(remItems)
        let keptPhotos = Set(remainingPhotos)

        if !selection.isEmpty {
            let surviving = selection.intersection(keptItems)
            if !surviving.isEmpty {
                let newAnchor =
                    anchor.flatMap { surviving.contains($0) ? $0 : nil }
                    ?? remItems.first { surviving.contains($0) }
                return (surviving, newAnchor)
            }
            let photoStart =
                anchor.flatMap { previousPhotos.firstIndex(of: $0) }
                ?? previousPhotos.firstIndex { selection.contains($0) }
            if let photoStart {
                if let next = previousPhotos[photoStart...].first(where: { keptPhotos.contains($0) })
                    ?? previousPhotos[..<photoStart].last(where: { keptPhotos.contains($0) })
                    ?? remainingPhotos.first
                {
                    return ([next], next)
                }
                return ([], remItems.first)
            }
            let itemStart =
                anchor.flatMap { prevItems.firstIndex(of: $0) }
                ?? prevItems.firstIndex { selection.contains($0) }
            if let itemStart,
                let next = prevItems[itemStart...].first(where: { keptItems.contains($0) })
                    ?? prevItems[..<itemStart].last(where: { keptItems.contains($0) })
            {
                return ([next], next)
            }
            return ([], remainingPhotos.first ?? remItems.first)
        }

        if let anchor {
            if keptItems.contains(anchor) {
                return ([], anchor)
            }
            if let photoStart = previousPhotos.firstIndex(of: anchor),
                let next = previousPhotos[photoStart...].first(where: { keptPhotos.contains($0) })
                    ?? previousPhotos[..<photoStart].last(where: { keptPhotos.contains($0) })
            {
                return ([], next)
            }
        }
        return ([], remainingPhotos.first ?? remItems.first)
    }
}

