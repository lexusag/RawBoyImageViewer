/// A least-recently-used cache limited by the total cost of its values (bytes, for images).
/// Not thread-safe: own it from one actor.
public struct LRUCache<Key: Hashable, Value> {
    public let budget: Int
    public private(set) var totalCost = 0
    private var entries: [Key: (value: Value, cost: Int)] = [:]
    /// Least recent first.
    private var order: [Key] = []

    public init(budget: Int) {
        self.budget = budget
    }

    public var count: Int { entries.count }

    /// The value for [key], now the most recent.
    public mutating func value(for key: Key) -> Value? {
        guard let entry = entries[key] else { return nil }
        touch(key)
        return entry.value
    }

    /// The value for [key] without changing the order.
    public func peek(_ key: Key) -> Value? { entries[key]?.value }

    public func contains(_ key: Key) -> Bool { entries[key] != nil }

    /// Stores [value] as the most recent, then drops the least recent until the total is within the budget.
    /// The value just stored is kept even when it alone is over the budget.
    public mutating func insert(_ value: Value, for key: Key, cost: Int) {
        if let old = entries[key] {
            totalCost -= old.cost
        }
        entries[key] = (value, cost)
        totalCost += cost
        touch(key)
        while totalCost > budget, order.count > 1 {
            remove(order[0])
        }
    }

    public mutating func remove(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        totalCost -= entry.cost
        order.removeAll { $0 == key }
    }

    public mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
