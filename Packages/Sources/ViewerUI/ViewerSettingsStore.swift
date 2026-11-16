import Foundation

/// Where the screens keep their personal choices (sort, sizes, favourites, the last folder, export options...). The
/// standalone viewer uses `UserDefaults` as it is; RawBoy Desktop gives its own prefix (or another store).
public protocol ViewerSettingsStore: Sendable {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func stringArray(forKey key: String) -> [String]?
    func data(forKey key: String) -> Data?
    func bool(forKey key: String) -> Bool
    func double(forKey key: String) -> Double
    func set(_ value: Any?, forKey key: String)
    /// The key as it is stored. `@AppStorage` (SwiftUI) reads `UserDefaults` itself, so it goes through this too.
    func key(_ name: String) -> String
}

/// `UserDefaults` with [prefix] in front of every key ("" for the standalone viewer: keys stay `browser.sort`...).
public struct UserDefaultsSettings: ViewerSettingsStore, @unchecked Sendable {
    public let defaults: UserDefaults
    public let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func key(_ name: String) -> String { prefix + name }
    public func object(forKey key: String) -> Any? { defaults.object(forKey: self.key(key)) }
    public func string(forKey key: String) -> String? { defaults.string(forKey: self.key(key)) }
    public func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: self.key(key)) }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: self.key(key)) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: self.key(key)) }
    public func double(forKey key: String) -> Double { defaults.double(forKey: self.key(key)) }
    public func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: self.key(key)) }
}

/// The settings the screens use. Set once at launch, before the first `AppModel` is made.
public enum ViewerSettings {
    nonisolated(unsafe) public static var store: any ViewerSettingsStore = UserDefaultsSettings()

    /// [name] as `@AppStorage` must spell it.
    public static func key(_ name: String) -> String { store.key(name) }
}
