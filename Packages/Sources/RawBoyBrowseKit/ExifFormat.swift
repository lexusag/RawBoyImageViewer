import Foundation

/// EXIF values as the details panel writes them: plain, short, the way photographers say them.
public enum ExifFormat {
    /// "1/240 s", "1/8 s", "2 s", "1.3 s".
    public static func shutter(_ seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        if seconds >= 1 { return "\(trim(seconds)) s" }
        let denominator = 1 / seconds
        // 1/3 s and 0.4 s cameras store as 0.3 and 0.4: keep those as decimals when 1/x isn't near a whole number.
        if seconds >= 0.3, abs(denominator - denominator.rounded()) > 0.05 { return "\(trim(seconds)) s" }
        return "1/\(Int(denominator.rounded())) s"
    }

    /// "f/2.8", "f/11".
    public static func aperture(_ f: Double) -> String? { f > 0 ? "f/\(trim(f))" : nil }

    /// "ISO 100".
    public static func iso(_ value: Int) -> String? { value > 0 ? "ISO \(value)" : nil }

    /// "0 EV", "+0.3 EV", "−1.7 EV" (a real minus sign).
    public static func bias(_ ev: Double) -> String {
        let rounded = (ev * 10).rounded() / 10
        if rounded == 0 { return "0 EV" }
        return "\(rounded > 0 ? "+" : "−")\(trim(abs(rounded))) EV"
    }

    /// "63 mm", "63 mm (50 mm in 35 mm terms)".
    public static func focalLength(_ mm: Double?, equivalent35: Double?) -> String? {
        guard let mm, mm > 0 else { return nil }
        let base = "\(trim(mm)) mm"
        guard let eq = equivalent35, eq > 0, abs(eq - mm) >= 1 else { return base }
        return "\(base) (\(trim(eq)) mm in 35 mm terms)"
    }

    /// EXIF ExposureProgram.
    public static func program(_ value: Int) -> String? {
        [
            1: "Manual", 2: "Program", 3: "Aperture priority", 4: "Shutter priority", 5: "Creative", 6: "Action",
            7: "Portrait", 8: "Landscape",
        ][value]
    }

    /// EXIF MeteringMode.
    public static func metering(_ value: Int) -> String? {
        [1: "Average", 2: "Centre-weighted", 3: "Spot", 4: "Multi-spot", 5: "Multi-segment", 6: "Partial"][value]
    }

    /// EXIF Flash: whether it fired, and forced off / auto when it says so.
    public static func flash(_ value: Int) -> String {
        let fired = value & 1 != 0
        switch (value >> 3) & 3 {
        case 2: return fired ? "Fired" : "Off"
        case 3: return fired ? "Fired (auto)" : "Did not fire (auto)"
        default: return fired ? "Fired" : "Did not fire"
        }
    }

    /// EXIF WhiteBalance.
    public static func whiteBalance(_ value: Int) -> String? { [0: "Auto", 1: "Manual"][value] }

    /// "50.4501° N, 30.5234° E".
    public static func coordinates(latitude: Double, latitudeRef: String?, longitude: Double, longitudeRef: String?)
        -> String
    {
        let lat = String(format: "%.4f", abs(latitude))
        let lon = String(format: "%.4f", abs(longitude))
        let ns = latitudeRef ?? (latitude < 0 ? "S" : "N")
        let ew = longitudeRef ?? (longitude < 0 ? "W" : "E")
        return "\(lat)° \(ns), \(lon)° \(ew)"
    }

    /// The make and model as one name, without the make twice ("FUJIFILM" + "GFX 50R" → "FUJIFILM GFX 50R",
    /// "Canon" + "Canon EOS R5" → "Canon EOS R5").
    public static func camera(make: String?, model: String?) -> String? {
        let make = make?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let model = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let model else { return make }
        guard let make, !model.lowercased().hasPrefix(make.lowercased().split(separator: " ").first ?? "") else {
            return model
        }
        return "\(make) \(model)"
    }

    /// An EXIF date ("2026:03:01 12:23:15") as a Date in the current time zone.
    public static func date(_ exif: String?) -> Date? {
        guard let text = PhotoOrder.validDate(exif) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: text)
    }

    /// Up to two decimals, without trailing zeros.
    static func trim(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
