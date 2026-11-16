import Foundation
import SwiftUI

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
}

/// `UserDefaults` with [prefix] in front of every key ("" for the standalone viewer: keys stay `browser.sort`...).
public struct UserDefaultsSettings: ViewerSettingsStore, @unchecked Sendable {
    public let defaults: UserDefaults
    public let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "") {
        self.defaults = defaults
        self.prefix = prefix
    }

    private func stored(_ name: String) -> String { prefix + name }
    public func object(forKey key: String) -> Any? { defaults.object(forKey: stored(key)) }
    public func string(forKey key: String) -> String? { defaults.string(forKey: stored(key)) }
    public func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: stored(key)) }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: stored(key)) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: stored(key)) }
    public func double(forKey key: String) -> Double { defaults.double(forKey: stored(key)) }
    public func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: stored(key)) }
}

/// The settings the screens use. Set once at launch, before the first `AppModel` is made.
public enum ViewerSettings {
    nonisolated(unsafe) public static var store: any ViewerSettingsStore = UserDefaultsSettings()
}

/// Tells the views that a setting changed (what `@AppStorage` does for UserDefaults).
final class SettingChanges: ObservableObject, @unchecked Sendable {
    static let shared = SettingChanges()

    func didChange() {
        DispatchQueue.main.async { [self] in objectWillChange.send() }
    }
}

/// The store the screens write through: [ViewerSettings.store], and the views hear about every change.
struct NotifyingSettings: ViewerSettingsStore {
    let base: any ViewerSettingsStore

    func object(forKey key: String) -> Any? { base.object(forKey: key) }
    func string(forKey key: String) -> String? { base.string(forKey: key) }
    func stringArray(forKey key: String) -> [String]? { base.stringArray(forKey: key) }
    func data(forKey key: String) -> Data? { base.data(forKey: key) }
    func bool(forKey key: String) -> Bool { base.bool(forKey: key) }
    func double(forKey key: String) -> Double { base.double(forKey: key) }

    func set(_ value: Any?, forKey key: String) {
        base.set(value, forKey: key)
        SettingChanges.shared.didChange()
    }
}

extension ViewerSettings {
    /// What the screens use: [store], with change notices.
    static var current: any ViewerSettingsStore { NotifyingSettings(base: store) }
}

/// A value a setting can hold.
protocol ViewerSettingValue {
    static func read(_ store: any ViewerSettingsStore, _ key: String) -> Self?
}

extension Bool: ViewerSettingValue {
    static func read(_ store: any ViewerSettingsStore, _ key: String) -> Bool? { store.object(forKey: key) as? Bool }
}

extension Double: ViewerSettingValue {
    static func read(_ store: any ViewerSettingsStore, _ key: String) -> Double? {
        store.object(forKey: key) as? Double
    }
}

extension String: ViewerSettingValue {
    static func read(_ store: any ViewerSettingsStore, _ key: String) -> String? { store.string(forKey: key) }
}

/// `@AppStorage` for the settings store: reads and writes [ViewerSettings.store] (not `UserDefaults` itself), and the
/// view updates when any screen changes a setting.
@propertyWrapper
struct ViewerSetting<Value: ViewerSettingValue>: DynamicProperty {
    private let name: String
    private let fallback: Value
    @ObservedObject private var changes = SettingChanges.shared

    init(wrappedValue: Value, _ name: String) {
        self.name = name
        fallback = wrappedValue
        _changes = ObservedObject(wrappedValue: SettingChanges.shared)
    }

    var wrappedValue: Value {
        get {
            _ = changes
            return Value.read(ViewerSettings.store, name) ?? fallback
        }
        nonmutating set { ViewerSettings.current.set(newValue, forKey: name) }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
