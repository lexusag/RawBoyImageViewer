import Foundation

/// The running app's name, version and build, as its bundle declares them (a release's tag and build number; a local
/// build says 0.1 (1)).
enum AppVersion {
    static var text: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var name: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "RawBoy Viewer"
    }

    /// "RawBoy Viewer 1.2.3 (45)".
    static var line: String { "\(name) \(text)" }
}
