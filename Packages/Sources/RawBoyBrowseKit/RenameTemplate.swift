import Foundation

/// What a rename template can use about one photo.
public struct RenameContext: Equatable, Sendable {
    /// The photo's main file name, with or without extension.
    public var fileName: String
    public var camera: String?
    public var lens: String?
    public var iso: Int?
    /// "YYYY:MM:DD HH:MM:SS" (EXIF), or nil if unknown.
    public var date: String?
    /// The name of the folder the photo is in.
    public var folder: String?
    /// The photo's number in this rename, for `#`.
    public var index: Int
    /// What `{name}` gives, when it isn't the file's own stem (a find and replace applied to the original name).
    public var originalStem: String?

    public init(
        fileName: String, camera: String? = nil, lens: String? = nil, iso: Int? = nil, date: String? = nil,
        folder: String? = nil, index: Int = 1
    ) {
        self.fileName = fileName
        self.camera = camera
        self.lens = lens
        self.iso = iso
        self.date = date
        self.folder = folder
        self.index = index
    }
}

/// File name templates for renaming photos: RawBoy Auto's export template (`NameTemplate.ts`: keep the two in step)
/// without its look keyword, plus `{folder}`. Text with `{keywords}` and `#` counters, e.g. `{date}_###` →
/// "2026-11-11_001". Keywords are case-insensitive:
///
///     {name} original name without extension   {camera} camera make and model   {lens} lens name
///     {iso}  ISO speed                         {folder} the folder's name
///     {date} 2026-11-11   {time} 14-30-05   {year} {yy} {month} {day} {hour} {minute} {second}  (shoot date)
///     #, ##, ###…  the photo's number: # = 1, ## = 01, ### = 001 (a run of #s sets the width)
///
/// Anything else is kept as typed, and a keyword with no value for a photo (no lens name…) is left out. Characters file
/// systems refuse (`/ \ : * ? " < > |` and control characters) become "_". The extension is kept by the caller.
public enum RenameTemplate {
    /// What the dialog starts with: the original name, so nothing changes until the user edits it.
    public static let defaultTemplate = "{name}"

    /// The keywords, for the dialog's buttons and the help.
    public static let keywords: [(token: String, text: String)] = [
        ("{name}", "original name"),
        ("{date}", "2026-11-11"),
        ("{time}", "14-30-05"),
        ("{camera}", "camera"),
        ("{lens}", "lens"),
        ("{iso}", "ISO"),
        ("{folder}", "folder name"),
        ("{year}", "year"),
        ("{month}", "month"),
        ("{day}", "day"),
        ("{hour}", "hour"),
        ("{minute}", "minute"),
        ("{second}", "second"),
        ("###", "number: ### = 001"),
    ]

    private static let dateKeys: Set<String> = [
        "year", "yy", "month", "day", "hour", "minute", "second", "date", "time",
    ]
    private static let maxStem = 150
    private static let reserved: Set<String> = Set(
        ["con", "prn", "aux", "nul"] + (1...9).flatMap { ["com\($0)", "lpt\($0)"] })

    /// [text] with characters file systems refuse replaced, the ends trimmed (Windows drops trailing dots and spaces)
    /// and the length capped.
    public static func sanitize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7f || "/\\:*?\"<>|".unicodeScalars.contains(scalar) {
                scalars.append("_")
            } else {
                scalars.append(scalar)
            }
        }
        var s = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "."))
        s = s.trimmingCharacters(in: trim)
        if s.count > maxStem {
            s = String(s.prefix(maxStem)).trimmingCharacters(in: trim)
        }
        if reserved.contains(s.lowercased()) { s = "_" + s }
        return s
    }

    /// The date parts of an EXIF date, or nil if it isn't one.
    static func dateParts(_ date: String?) -> [String: String]? {
        guard let date else { return nil }
        let c = Array(date.utf8)
        // "YYYY:MM:DD HH:MM:SS", the date and time separated by a space or a T.
        guard c.count >= 19, c[4] == 0x3a, c[7] == 0x3a, c[10] == 0x20 || c[10] == 0x54, c[13] == 0x3a,
            c[16] == 0x3a
        else { return nil }
        func part(_ r: Range<Int>) -> String? {
            let s = String(decoding: c[r], as: UTF8.self)
            return s.allSatisfy({ $0.isASCII && $0.isNumber }) ? s : nil
        }
        guard let y = part(0..<4), let mo = part(5..<7), let d = part(8..<10), let h = part(11..<13),
            let mi = part(14..<16), let s = part(17..<19)
        else { return nil }
        return [
            "year": y, "yy": String(y.suffix(2)), "month": mo, "day": d, "hour": h, "minute": mi, "second": s,
            "date": "\(y)-\(mo)-\(d)", "time": "\(h)-\(mi)-\(s)",
        ]
    }

    /// [name] without its extension.
    static func stemOf(_ name: String) -> String { PhotoGroups.stem(of: name) }

    /// The name (without extension) [template] gives [context], or [template] itself when [literal]. Empty when it gives nothing.
    public static func apply(_ template: String, _ context: RenameContext, literal: Bool = false) -> String {
        // A typed name, not a template: `#` and braces mean themselves.
        if literal { return sanitize(template) }
        let dates = dateParts(context.date)
        var values: [String: String] = [
            "name": context.originalStem ?? stemOf(context.fileName),
            "camera": context.camera ?? "",
            "lens": context.lens ?? "",
            "iso": (context.iso ?? 0) > 0 ? String(context.iso ?? 0) : "",
            "folder": context.folder ?? "",
        ]
        for (key, value) in dates ?? [:] { values[key] = value }
        let text = template.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTemplate : template

        var out = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "#" {
                var j = i
                while j < chars.count, chars[j] == "#" { j += 1 }
                let digits = String(max(0, context.index))
                out += String(repeating: "0", count: max(0, (j - i) - digits.count)) + digits
                i = j
            } else if ch == "{", let close = chars[i...].firstIndex(of: "}"),
                chars[(i + 1)..<close].allSatisfy({ $0.isASCII && $0.isLetter })
            {
                let key = String(chars[(i + 1)..<close]).lowercased()
                if values[key] != nil || dateKeys.contains(key) {
                    out += values[key] ?? ""
                } else {
                    // Unknown words stay as typed, so a typo shows in the preview.
                    out += String(chars[i...close])
                }
                i = close + 1
            } else {
                out.append(ch)
                i += 1
            }
        }
        return sanitize(out)
    }
}

/// Find and replace on a name: plain text or a regular expression, applied to the original name (before the
/// template) or to the name the template gives.
public struct RenameReplace: Equatable, Codable, Sendable {
    public enum Target: String, Codable, Sendable {
        /// The photo's own name: `{name}` in the template then gives the replaced name.
        case original
        /// The name the template gives.
        case result
    }

    public var find: String
    public var replace: String
    public var regex: Bool
    public var caseSensitive: Bool
    public var target: Target

    public init(
        find: String = "", replace: String = "", regex: Bool = false, caseSensitive: Bool = false,
        target: Target = .result
    ) {
        self.find = find
        self.replace = replace
        self.regex = regex
        self.caseSensitive = caseSensitive
        self.target = target
    }

    /// Whether anything is to be replaced.
    public var isActive: Bool { !find.isEmpty }

    private func expression() throws -> NSRegularExpression {
        try NSRegularExpression(pattern: find, options: caseSensitive ? [] : [.caseInsensitive])
    }

    /// Why the regular expression can't be used, or nil when it can (or when it isn't one).
    public var error: String? {
        guard isActive, regex else { return nil }
        do {
            _ = try expression()
            return nil
        } catch {
            return "Not a valid regular expression"
        }
    }

    /// [text] with every match of [find] replaced. `$1`… and `$0` give a regex's groups (`\$` a dollar sign). An
    /// invalid regex changes nothing.
    public func apply(_ text: String) -> String {
        guard isActive else { return text }
        if regex {
            guard let expression = try? expression() else { return text }
            return expression.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replace)
        }
        return text.replacingOccurrences(
            of: find, with: replace, options: caseSensitive ? [.literal] : [.literal, .caseInsensitive])
    }
}

/// One photo in a rename: the files it has now and what each becomes.
public struct RenameItem: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case ok
        /// The template gives the name it has.
        case unchanged
        case conflict(String)
    }

    /// The photo's id in the browser (its main file's old name).
    public let id: String
    public let oldStem: String
    public let newStem: String
    /// Every file of the photo (main, JPEG companions, sidecars) as (old name, new name).
    public let files: [(old: String, new: String)]
    public var status: Status

    /// The main file's new name.
    public var newMain: String { files.first?.new ?? id }

    public static func == (a: RenameItem, b: RenameItem) -> Bool {
        a.id == b.id && a.oldStem == b.oldStem && a.newStem == b.newStem && a.status == b.status
            && a.files.map(\.old) == b.files.map(\.old) && a.files.map(\.new) == b.files.map(\.new)
    }
}

/// What a rename would do, worked out before anything is touched.
public enum RenamePlan {
    /// Plans renaming [photos] (each with its context and sidecars as they are now) by [template], numbering from
    /// [start] in the order given. [existing] is every file name in the folder. A new name that is taken by a file
    /// outside the rename, or given to two photos, is a conflict: nothing is renamed over anything.
    public static func make(
        photos: [(group: PhotoGroup, context: RenameContext)], template: String, start: Int, existing: [String],
        literal: Bool = false, replace: RenameReplace = RenameReplace()
    ) -> [RenameItem] {
        // A bad regex replaces nothing; the dialog shows why and blocks the rename.
        let replace = replace.error == nil ? replace : RenameReplace()
        var items: [RenameItem] = []
        for (n, photo) in photos.enumerated() {
            var context = photo.context
            context.index = start + n
            // A typed name has no `{name}`, so the replace goes on what was typed.
            let beforeTemplate = replace.target == .original && !literal
            if beforeTemplate { context.originalStem = replace.apply(RenameTemplate.stemOf(context.fileName)) }
            var newStem = RenameTemplate.apply(template, context, literal: literal)
            if !beforeTemplate { newStem = RenameTemplate.sanitize(replace.apply(newStem)) }
            let group = photo.group
            let names = [group.main] + group.companions + group.sidecars
            var files: [(old: String, new: String)] = []
            for name in names {
                files.append((name, renamed(name, oldStem: group.stem, newStem: newStem) ?? name))
            }
            let status: RenameItem.Status =
                newStem.isEmpty
                ? .conflict("Empty name") : files.allSatisfy { $0.old == $0.new } ? .unchanged : .ok
            items.append(
                RenameItem(
                    id: group.main, oldStem: group.stem, newStem: newStem, files: files, status: status))
        }

        // Names the rename frees: what the photos that change have now. The rest of the folder stays in the way.
        let changing = items.filter { $0.status == .ok }
        let freed = Set(changing.flatMap { $0.files.map { $0.old.lowercased() } })
        let blocked = Set(existing.map { $0.lowercased() }).subtracting(freed)

        var users: [String: Int] = [:]
        for item in items {
            for file in item.files { users[file.new.lowercased(), default: 0] += 1 }
        }
        for i in items.indices where items[i].status == .ok {
            for file in items[i].files {
                let key = file.new.lowercased()
                if users[key, default: 0] > 1 {
                    items[i].status = .conflict("Same name as another photo")
                    break
                }
                if blocked.contains(key) {
                    items[i].status = .conflict("\(file.new) already exists")
                    break
                }
            }
        }
        return items
    }

    /// [name] with the photo's [oldStem] (case-insensitively) replaced by [newStem], so "IMG_1.CR2.xmp" → "B.CR2.xmp";
    /// nil when [name] doesn't start with it.
    public static func renamed(_ name: String, oldStem: String, newStem: String) -> String? {
        guard name.lowercased().hasPrefix(oldStem.lowercased()) else { return nil }
        return newStem + String(name.dropFirst(oldStem.count))
    }

    /// Whether the rename can go ahead: something changes and nothing conflicts.
    public static func canApply(_ items: [RenameItem]) -> Bool {
        var changes = false
        for item in items {
            switch item.status {
            case .conflict: return false
            case .ok: changes = true
            case .unchanged: break
            }
        }
        return changes
    }
}
