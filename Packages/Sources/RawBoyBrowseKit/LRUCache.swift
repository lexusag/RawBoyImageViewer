/// A least-recently-used cache limited by the total cost of its values (bytes, for images).
/// Not thread-safe: own it from one actor.
///
/// Every use is O(1) amortised: recency is a stamp on the entry, and `order` is a queue of (key, stamp) that may hold
/// stale pairs (the key was used again since), skipped when they reach the front. A plain array of keys made every
/// lookup and eviction O(entries), which showed in thumbnail caches of hundreds of entries.
public struct LRUCache<Key: Hashable, Value> {
    public let budget: Int
    public private(set) var totalCost = 0
    private var entries: [Key: (value: Value, cost: Int, stamp: Int)] = [:]
    /// Least recent first, from `head`; pairs whose stamp isn't the entry's current one are stale.
    private var order: [(key: Key, stamp: Int)] = []
    private var head = 0
    private var clock = 0

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
        entries[key] = (value, cost, 0)
        totalCost += cost
        touch(key)
        while totalCost > budget, entries.count > 1, let oldest = popOldest() {
            remove(oldest)
        }
    }

    public mutating func remove(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        totalCost -= entry.cost
        // Its pairs in `order` are stale now (no entry), and go when they reach the front or at the next compaction.
    }

    public mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        head = 0
        totalCost = 0
    }

    private mutating func touch(_ key: Key) {
        clock += 1
        entries[key]?.stamp = clock
        order.append((key, clock))
        compactIfSparse()
    }

    /// The least recent live key, taken off the queue.
    private mutating func popOldest() -> Key? {
        while head < order.count {
            let (key, stamp) = order[head]
            head += 1
            if entries[key]?.stamp == stamp { return key }
        }
        return nil
    }

    /// Drops stale pairs once they outnumber the live ones, so the queue stays proportional to the entries.
    private mutating func compactIfSparse() {
        guard order.count - head > 4 * entries.count + 32 || (head > 1024 && head * 2 > order.count) else { return }
        order = order[head...].filter { entries[$0.key]?.stamp == $0.stamp }
        head = 0
    }
}
